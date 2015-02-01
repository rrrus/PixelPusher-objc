/****************************************************************************
 *
 * "PPCard.m" implements the PPCard{} class.
 *
 * Originally Created by Rus Maxham on 5/31/13.
 * Copyright (c) 2013 rrrus. All rights reserved.
 *
 * Modified extensively by Christopher Schardt in November of 2014
 * The modifications largeley consisted of:
 *	- adding support for pusher commands
 *	- adding the DO_PACKET_POOL compiler switch to remove overly-complicated code
 *	- code made easier to read by adding blank lines, separating declarations, etc...
 *	- many private properties converted to IVARs
 *
 ****************************************************************************/

#import <UIKit/UIKit.h>
#import "GCDAsyncUdpSocket.h"
#import "HLDeferredList.h"
#import "NSData+Utils.h"
#import "PPCard.h"
#import "PPDeviceRegistry.h"
#import "PPPixelPusher.h"
#import "PPStrip.h"
#import "PPPusherCommand.h"


INIT_LOG_LEVEL_INFO


/////////////////////////////////////////////////
#pragma mark - SWICHES:

/*
Rrrus' version of this code does some very complicated things:
- It maintains a set of NSMutableData "packets" (_packetPool) into which packet data is copied.
- Every time a packet is to be sent, a "packet" is retrieved from the pool.
- After the packet is sent, the "packet" is returned to the pool by the GDAsyncUDPSocketDelegate methods.
- A dictionary (_packetsInFlight) keeps track of every packet that is currently being used,
  so that if transmission is cancelled, the packet may be returned to the pool.
Turning off this switch causes packets to be sent in a much simpler way:
- An NSData is allocated for each packet.
- After the packet is sent, the NSData is forgotten by this library.
- It's up to GDAsyncUDPSocket to release it.
*/
#define DO_PACKET_POOL		FALSE

/*
Rrrus' code does complicated stuff with "promises" too.  These are HLDeferred objects
that are used to let [PPScene frameTask] know when all of the packets have been presented
to the GCDAsyncUdpSocket.  The purpose is to prevent [PPScene frameTask] from processing the next frame
until this has occurred.
- A dictionary of promises is used.
- All that really should be necessary is a single promise [self flushPromise] that has [takeResult:]
  called when all packets have been sent to the socket.  A simple counter can accomplish this.
*/
#define DO_PACKET_PROMISE_DICT	FALSE

/*
Turning off both of these switches reduced the amount of time to prepare a single packet
from 16-36usec to 6-13usec.  It also eliminated some occasional very long times - approx 300usec.

All timings were measured on an iPad with optimized code.  What these results say is that on iOS:
A) Memory allocation/deallocation is quick.
B) Adding/retrieving from an NSMutableDictionary is not always quick.
*/


/////////////////////////////////////////////////
#pragma mark - PRIVATE STUFF:

@interface PPCard () <GCDAsyncUdpSocketDelegate>
{
	uint32_t			_maxPacketLength;
	uint32_t			_packetNumber;
	int32_t				_unsentPacketCount;
	CFTimeInterval		_lastSendTime;
	CFTimeInterval		_lastFrameTime;
}

@property (nonatomic, strong) PPPixelPusher *pusher;
@property (nonatomic, strong) GCDAsyncUdpSocket* udpsocket;
@property (nonatomic, strong) NSOutputStream* writeStream;
#if DO_PACKET_POOL
@property (nonatomic, strong) NSMutableSet *packetPool;
@property (nonatomic, strong) NSMutableDictionary *packetsInFlight;
#endif
#if DO_PACKET_PROMISE_DICT
@property (nonatomic, strong) NSMutableDictionary *packetPromises;
#endif
@property (nonatomic, strong) HLDeferred *flushPromise;

@end


@implementation PPCard


/////////////////////////////////////////////////
#pragma mark - EXISTENCE:

- (id)initWithPusher:(PPPixelPusher*)pusher
{
	self = [self init];
	if (self)
	{
		_pusher = pusher;
		_maxPacketLength = 4 + ((1 + 3 * pusher.pixelsPerStrip) * pusher.maxStripsPerPacket);

		NSError*		error;

		_udpsocket = [GCDAsyncUdpSocket.alloc initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
		[_udpsocket setIPv6Enabled:NO];
		if (![_udpsocket connectToHost:pusher.ipAddress onPort:pusher.port error:&error])
		{
			assert(NO);
//			[NSException raise:NSGenericException format:@"error connecting to pusher (%@): %@", pusher.ipAddress, error];
			return nil;
		}
		
#if DO_PACKET_POOL
		self.packetPool = NSMutableSet.new;
		self.packetsInFlight = NSMutableDictionary.new;
#endif
#if DO_PACKET_PROMISE_DICT
		self.packetPromises = [NSMutableDictionary.alloc initWithCapacity:pusher.stripCount];
#endif
		_flushPromise = [HLDeferred deferredWithResult:nil];

//		_packetNumber = 0;
	}
	return self;
}

- (void)dealloc
{
	// This is probably not necessary since [udpSocketDidClose:withError:] will call it,
	// but what the heck...
	[self cancelPackets];
	
	[_udpsocket close];
}


/////////////////////////////////////////////////
#pragma mark - PROPERTIES:

- (void)setRecord:(BOOL)record
{
	if (record)
	{
		[self createWriteStream];
	}
	else
	{
		[self closeWriteStream];
	}
}
- (BOOL)record
{
	return _writeStream ? YES : NO;
}

- (uint64_t)bandwidthEstimate
{
	return 0;
}

- (BOOL)controls:(PPPixelPusher*)pusher
{
	return [pusher isEqualToPusher:_pusher];
}


/////////////////////////////////////////////////
#pragma mark - OPERATIONS:

- (void)shutDown
{
}
- (void)start
{
}
- (void)cancel
{
}

- (HLDeferred*)flush
{
	if (!_udpsocket.isConnected || _udpsocket.isClosed)
	{
		//??? This is a bit hacky since _flushPromise contains either the fulfilled
		//??? promise set in [init] or one from a previous call to flush.
		//??? The latter should be fulfilled, but will hang PPScene if it isn't.
		if (!_flushPromise.isCalled)
		{
			assert(FALSE);	// previous code could hang
			_flushPromise = [HLDeferred deferredWithResult:nil];
		}
		return _flushPromise;
	}
	
	// Due to the complex, promise-based architecture, this method is called from a block
	// within this method via [PPScene frameTask].  This means that we have to be very careful about
	// setting instance variables.  eg:  We must not set _flushPromise until the end.
	// In fact, it would be nice to not have flushPromise be stored in an instance variable
	// at all.  We only do so so that we can fulfill it inside [cancelPackets].
#if !DO_PACKET_PROMISE_DICT
	HLDeferred*		flushPromise;
	
	flushPromise = nil;
#endif

	assert(_unsentPacketCount == 0);
	_unsentPacketCount = 0;			// just in case

	NSUInteger		const stripCount = _pusher.strips.count;
	NSUInteger		const maxStripsPerPacket = MIN(_pusher.maxStripsPerPacket, (uint32_t)stripCount);
	NSTimeInterval	threadSleep;

	if (_pusher.updatePeriod > 0.1)
	{
		// Handle errant delay calculation in the firmware.
		threadSleep = 0.016 / (stripCount / maxStripsPerPacket);
	}
	else if (_pusher.updatePeriod > 0.0001)
	{
		threadSleep = _pusher.updatePeriod + 0.001;
	}
	else
	{
		// Shoot for the framelimit.
		threadSleep = (1.0 / PPDeviceRegistry.sharedRegistry.frameRateLimit) /
						   (stripCount / maxStripsPerPacket);
	}
	
	CFTimeInterval		const totalDelay = threadSleep + _extraDelay + _pusher.extraDelay;
	CFTimeInterval		const frameTime = CACurrentMediaTime();
	CFTimeInterval		packetTime;
	
	packetTime = frameTime;
	_lastFrameTime = frameTime;

	float				const powerScale = PPDeviceRegistry.sharedRegistry.powerScale;
	NSUInteger			stripIndex;

	stripIndex = 0;
	while (stripIndex < stripCount)
	{
//		CFTimeInterval	const startTime = CACurrentMediaTime();		// for NSLog() below
#if DO_PACKET_POOL
		NSMutableData*	const packet = self.packetFromPool;
#else
		NSMutableData*	const packet = [NSMutableData.alloc initWithLength:_maxPacketLength];
#endif
		uint8_t*		const pStart = packet.mutableBytes;
		uint8_t*		const pEnd = pStart + _maxPacketLength;
		uint8_t*		p;

		p = pStart;
		*(UInt32*)p = NSSwapHostIntToLittle(_packetNumber);
		p += sizeof(UInt32);

		NSMutableArray*	const pusherCommandQueue = _pusher.pusherCommandQueue;
		BOOL			sendPacket;

		sendPacket = NO;
		if (pusherCommandQueue.count > 0)
		{
			PPPusherCommand*	const command = pusherCommandQueue[0];
			NSData*				const data = command.data;
			
			memcpy(p, data.bytes, data.length);
			if (_pusher.pusherFlags & PFLAG_FIXEDSIZE)
			{
				// We need fixed size datagrams for the Photon, because the cc3000 sucks.
				p = pEnd;
			}
			else
			{
				p += data.length;
			}
			[pusherCommandQueue removeObjectAtIndex:0];		// causes command & data to be released
			sendPacket = YES;
		}
		else
		{
			NSUInteger		stripInPacketIndex;
			
			stripInPacketIndex = 0;
			while ((stripInPacketIndex < maxStripsPerPacket) && (stripIndex < stripCount))
			{
				PPStrip*		const strip = _pusher.strips[stripIndex++];
				
				// output the strip if is touched, or if this is a fixed packet size pusher.
				if (strip.touched || (_pusher.pusherFlags & PFLAG_FIXEDSIZE) || _writeStream)
				{
					strip.powerScale = powerScale;		//??? This should be done when powerScale is calculated
					*p++ = (uint8_t)strip.stripNumber;
					
					uint32_t		const stripPacketSize = [strip serialize:p size:pEnd - p];
					
					if (_writeStream)
					{
						// TODO: update to canfile format 2
						
						// we need to make the pusher wait on playback the same length of time between strips as we wait between packets
						// this number is in microseconds.
						uint32_t		delay;
						
						if (stripInPacketIndex == 0 && _lastSendTime != 0)
						{
							// only write the delay in the first strip in a datagram.
							delay = NSSwapHostIntToLittle((uint32_t)((packetTime - _lastSendTime) * 1000000));
						}
						else
						{
							delay = 0;
						}
						[_writeStream write:(uint8_t*)&delay maxLength:sizeof(delay)];
						[_writeStream write:p - 1 maxLength:stripPacketSize + 1];
					}
					
					p += stripPacketSize;
					assert(p <= pEnd);		// packet buffer overrun
					stripInPacketIndex++;
					sendPacket = YES;
				}
			}
		}
		
		if (sendPacket)
		{
			NSUInteger		const packetLength = p - pStart;
#if DO_PACKET_POOL || DO_PACKET_PROMISE_DICT
			id				const key = @(_packetNumber);
#endif		
#if DO_PACKET_PROMISE_DICT
			HLDeferred*		const packetPromise = HLDeferred.new;
			
			self.packetPromises[key] = packetPromise;
#endif
#if DO_PACKET_POOL
			self.packetsInFlight[key] = packet;
			
			// make a new NSData object with the actual number of bytes packaged
			NSData*			const outGoing = [NSData dataWithBytesNoCopy:packet.mutableBytes
																	length:packetLength
																	freeWhenDone:NO];
#else
			NSData*			const outGoing = packet;
			
			if (packetLength != _maxPacketLength)
			{
				assert(packetLength < _maxPacketLength);
				[packet setLength:packetLength];
			}
#endif
//			NSLog(@"[PPCard flush] - packet prepared in %1.3fms", (CACurrentMediaTime() - startTime) * 1000);

			// calculate the send time of the packet
			CFTimeInterval	const now = CACurrentMediaTime();
			CFTimeInterval	const lastInterval = now - _lastSendTime;
			CFTimeInterval	const delay = (totalDelay > lastInterval) ? totalDelay - lastInterval : 0;

			_lastSendTime = now + delay;

			uint32_t		const packetNumber = _packetNumber;		// saved here for block

			_packetNumber++;
			packetTime += totalDelay;
			_unsentPacketCount++;
#if !DO_PACKET_PROMISE_DICT
			if (_unsentPacketCount == 1)
			{
				// This is the first packet, allocate an un-called promise:
				flushPromise = [HLDeferred.alloc init];
			}
#endif
			// We need to do this in a concurrent queue so that the MOMENT the dispatch time is up, 
			// the packet can be sent as quickly as possible.
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
							dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
				^{
					[_udpsocket sendData:outGoing withTimeout:1 tag:packetNumber];
					
					dispatch_async(dispatch_get_main_queue(),
						^{
							_unsentPacketCount--;
#if !DO_PACKET_PROMISE_DICT
							if (_unsentPacketCount <= 0)
							{
								assert(_unsentPacketCount == 0);
								if (!flushPromise.isCalled)		// otherwise [takeResult:] will throw exception
								{
									// Due to the complex, promised-based architecture, this can cause a
									// recursive call to [PPCard flush].  This means that _unsentPacketCount,
									// _flushPromise, and other instance variables may be changed.
									// This is why we don't set _flushPromise until the end of this method.
									// (When we DID call [_flushPromise takeResult:], _flushPromise was released
									// before return.  Then ARC would call objc_retainAutoreleasedReturnValue()
									// and objc_release() and crash.  I hate ARC.)
									[flushPromise takeResult:nil];
									// _unsentPacketCount is probably now >0
									// _flushPromise probably != flushPromise
								}
							}
#else
							[self.packetPromises removeObjectForKey:key];
							[packetPromise takeResult:nil];
#endif
						}
					);
				}
			);
		}
#if DO_PACKET_POOL
		else
		{
			[self returnPacketToPool:packet];
		}
#endif
	}

	if (_unsentPacketCount > 0)
	{
#if DO_PACKET_PROMISE_DICT
		// if we actually sent a packet, generate a new flush promise from all of the
		// packet promises.
		// if flush is called before a previous flush completes, the returned promise
		// will wait for all uncompleted packet promises to complete.
		_flushPromise = [HLDeferredList.alloc initWithDeferreds:[self.packetPromises allValues]];
#else
		_flushPromise = flushPromise;
#endif
	}
	return _flushPromise;
}

- (void)cancelPackets
{
#if DO_PACKET_POOL
	NSMutableData*	packet;
	
	for (packet in self.packetsInFlight)
	{
		[self returnPacketToPool:packet];
	}
	[self.packetsInFlight removeAllObjects];
#endif

#if DO_PACKET_PROMISE_DICT
	NSDictionary*	const promises = self.packetPromises.copy;
	HLDeferred*		promise;
	
	[self.packetPromises removeAllObjects];
	//??? Why does this need to be done after [removeAllObjects]?
	for (promise in promises)
	{
		[promise takeResult:nil];
	}
#else
	if (!_flushPromise.isCalled)		// otherwise [takeResult:] will throw exception
	{
		[_flushPromise takeResult:nil];
	}
#endif
}


/////////////////////////////////////////////////
#pragma mark - WRITE-TO-FILE OPERATIONS:

- (void)createWriteStream
{
	if (!_writeStream)
	{
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString *appDocsDir = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;

		// write map to file
		NSDateFormatter *dateFormatter = NSDateFormatter.alloc.init;
		[dateFormatter setDateFormat:@"yyyy-MM-dd-HH-mm"];
		NSString *mapfilename = [NSString stringWithFormat:@"canfile.%d.%d.%@.ppshow",
								 _pusher.groupOrdinal,
								 _pusher.controllerOrdinal,
								 [dateFormatter stringFromDate:NSDate.date]];
		NSString *mapfilepath = [appDocsDir stringByAppendingPathComponent:mapfilename];
		_writeStream = [NSOutputStream outputStreamToFileAtPath:mapfilepath append:NO];
		[_writeStream open];
/*
		// This should be done if the app will stop pushing data in the background,
		// but not if it runs in the background.
		// This state should probably be passed-in somehow.
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(closeWriteStream)
												   name:UIApplicationDidEnterBackgroundNotification
												 object:nil];
*/
	}
}

- (void)closeWriteStream
{
	if (_writeStream)
	{
		[_writeStream close];
		_writeStream = nil;
	}
}


/////////////////////////////////////////////////
#pragma mark - PACKET POOL OPERATIONS:

#if DO_PACKET_POOL

- (NSMutableData*)packetFromPool {
	NSMutableData *aPacket = self.packetPool.anyObject;
	if (!aPacket) {
		aPacket = NSMutableData.new;
		aPacket.length = _maxPacketLength;
	} else {
		[self.packetPool removeObject:aPacket];
	}
	return aPacket;
}
- (void)returnPacketToPool:(NSMutableData*)packet
{
	if (packet)
	{
		[self.packetPool addObject:packet];
	}
}

#endif


/////////////////////////////////////////////////
#pragma mark - GCDAsyncUdpSocketDelegate RESPONDERS:

#if DO_PACKET_POOL

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
	NSNumber*			const key = @(tag);
	NSMutableData*		const packet = self.packetsInFlight[key];
	
	[self returnPacketToPool:packet];
	[self.packetsInFlight removeObjectForKey:key];
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError*)error
{
	[self udpSocket:sock didSendDataWithTag:tag];
}

#endif

- (void)udpSocketDidClose:(GCDAsyncUdpSocket*)sock withError:(NSError*)error
{
	[self cancelPackets];
//	[_udpsocket close];			//??? This is redundant, unless GCDAsyncUdpSocket isn't working.

	[PPDeviceRegistry.sharedRegistry expireDevice:_pusher.macAddress];
}


@end

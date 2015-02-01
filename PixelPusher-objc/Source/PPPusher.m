//
//  PPPusher.m
//  PixelPusher-objc
//
//	PPPusher is an Objective-C class that handles communication with a single PixelPusher LED controller.
//	 * contains parameters received from broadcast packets
//	 * contains parameters that affect how data is transmitted
//	 * when [flush] is called, calls [serializeIntoBuffer:] for each PPStrip to get pixel data and
//	   assembles packets from the data, which are sent at precisely calculated times.
//	 * enqueues PPPusherCommands and sends them at appropriate times
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//  Modified extensively by Christopher Schardt in 2014/2015
//	 * added pusher command code
//	 * fixed offset error in reading strips_flags and all subsequent header fields
//	 * converted all private properties to ivars
//	 * changed name from PPPixelPusher to PPPusher
//	 * no longer subclassing from PPDevice (which has been deleted)
//	 * greatly simplified the updatePeriod, delta_sequence stuff
//	 * brought in all the functionality of PPCard, enabling much code simplification
//	 * moved pusher list changed to the beginning of [frameTask]
//	 * updated writeStream logic from Java library
//

#import "GCDAsyncUdpSocket.h"
#import "PPRegistry.h"
#import "PPPusher.h"
#import "PPStrip.h"

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
B) Adding/retrieving to/from an NSMutableDictionary is not always quick.
*/


/////////////////////////////////////////////////
#pragma mark - CONSTANTS:

static const int32_t kDefaultPusherPort = 9897;


/////////////////////////////////////////////////
#pragma mark - TYPES:

typedef struct __attribute__((packed)) PPPusherData
{
    uint8_t		strips_attached;
    uint8_t		max_strips_per_packet;
    uint16_t	pixels_per_strip;	// uint16_t used to make alignment work
    uint32_t	update_period;		// in microseconds
    uint32_t	power_total;		// in PWM units
    uint32_t	delta_sequence;		// difference between received and expected sequence numbers
    int32_t		controller_ordinal; // ordering number for this controller.
    int32_t		group_ordinal;      // group number for this controller.
    uint16_t	artnet_universe;	// configured artnet starting point for this controller
    uint16_t	artnet_channel;
    uint16_t	my_port;
    uint16_t	padding1;
    uint8_t		strip_flags[8];		// flags for each strip, for up to eight strips
    uint16_t	padding2;
    uint32_t	pusher_flags;		// flags for the whole pusher
    uint32_t	segments;			// number of segments in each strip
    uint32_t	power_domain;		// power domain of this pusher
    uint8_t		last_driven_ip[4];	// last host to drive this pusher
    uint16_t	last_driven_port;	// source port of last update
} PPPusherData;
#define	StripFlagsOffset	32


/////////////////////////////////////////////////
#pragma mark - PRIVATE STUFF:

@interface PPPusher () <GCDAsyncUdpSocketDelegate>
{
	NSMutableArray* 		_pusherCommandQueue;
	NSTimeInterval			_delayForPacketLoss;

	GCDAsyncUdpSocket*		_socket;
	NSOutputStream*			_writeStream;
	uint32_t				_maxPacketLength;
	uint32_t				_packetIndex;
	int32_t					_unsentPacketCount;
	CFTimeInterval			_prevPacketSendTime;
	HLDeferred*				_flushPromise;
#if DO_PACKET_POOL
	NSMutableSet *packetPool;
	NSMutableDictionary*	_packetsInFlight;
#endif
#if DO_PACKET_PROMISE_DICT
	NSMutableDictionary*	_packetPromises;
#endif
}

@end


@implementation PPPusher


/////////////////////////////////////////////////
#pragma mark - EXISTENCE:

- (id)initWithHeader:(PPDeviceHeader*)header
{
	self = [super init];
//	NSLog(@"[PPPusher initWithHeader:] IP - %@ MAC - %@", header.ipAddress, header.macAddress);
	
	int32_t				const softwareRevision = header.swRevision;
	PPPusherData const*	const data = (PPPusherData const*)header.packetRemainder;
	NSUInteger			const dataLength = header.packetRemainderLength;
	NSUInteger			stripCount;
	
	if (dataLength < 28)
	{
		assert(NO);
		self = nil;		//??? Will self be released by ARC?
		return nil;
	}

	// These fields don't change until controller reboots:	
	stripCount = data->strips_attached;
	_maxStripsPerPacket = data->max_strips_per_packet;
	_pixelsPerStrip = NSSwapLittleShortToHost(data->pixels_per_strip);
	_maxPacketLength = 4 + ((1 + 3 * _pixelsPerStrip) * _maxStripsPerPacket);
	_controllerOrdinal = NSSwapLittleIntToHost(data->controller_ordinal);
	_groupOrdinal = NSSwapLittleIntToHost(data->group_ordinal);
	_artnetUniverse = NSSwapLittleShortToHost(data->artnet_universe);
	_artnetChannel = NSSwapLittleShortToHost(data->artnet_channel);
	_port = (dataLength >= 30) && (softwareRevision > 100) ? NSSwapLittleShortToHost(data->my_port)
														   : kDefaultPusherPort;
	// These fields can be different every packet:
	_updatePeriodUsec = NSSwapLittleIntToHost(data->update_period);
	_powerTotal = NSSwapLittleIntToHost(data->power_total);
	_deltaSequence = NSSwapLittleIntToHost(data->delta_sequence);
	
	// If _stripsAttached is less than 8, we still must read 8 bytes for the strip_flags.
	// If it is more, then the structure becomes variable-length.
	uint32_t			const stripFlagsSize = MAX(stripCount, (uint32_t)8);
	uint8_t				zeroStripFlags[256];
	uint8_t const*		stripFlags;
	
	assert((uint8_t*)data + StripFlagsOffset == data->strip_flags);
	if ((dataLength >= StripFlagsOffset + stripFlagsSize) && (softwareRevision > 108))
	{
		stripFlags = data->strip_flags;
	}
	else
	{
		stripFlags = zeroStripFlags;
		memset(zeroStripFlags, 0, 256);
	}

	// If _stripsAttached is greater than 8, the strips_flags array is larger than 8
	// bytes and the header structure becomes variable-length:
	// The +2 offset acutally makes _pusherFlags misaligned for uint32s, but it's necessary because
	// a former compiler bug caused early pushers to insert it erroneously.
	// Jas decided it was best to keep it in for universal compatibility.
	uint32_t			const postStripFlagsOffset = StripFlagsOffset + stripFlagsSize + 2;
	uint32_t const*		const postStripFlagsData = (uint32_t const*)
													((uint8_t const*)data + postStripFlagsOffset);
	
	if ((dataLength >= postStripFlagsOffset + 4 * 3) && (softwareRevision > 116))
	{
		_pusherFlags = NSSwapLittleIntToHost(((uint32_t*)postStripFlagsData)[0]);
//		_segments = NSSwapLittleIntToHost(((uint32_t*)postStripFlagsData)[1]);
//		_powerDomain = NSSwapLittleIntToHost(((uint32_t*)postStripFlagsData)[2]);
	}

	[self initializeStrips:stripCount stripFlags:stripFlags];
	_header = header;
	[header releasePacketRemainder];
	
	if (![self initializeFlushStuff])
	{
		self = nil;		//??? Will self be released by ARC?
	}
	return self;
}

- (void)initializeStrips:(NSUInteger)stripCount stripFlags:(uint8_t const*)stripFlags
{
	NSMutableArray*		const stripArray = [NSMutableArray.alloc initWithCapacity:stripCount];
	NSUInteger			index;
	
	_strips = stripArray;
	for (index = 0; index < stripCount; index++)
	{
		PPStrip*			const strip = [PPStrip.alloc initWithStripNumber:index
																	pixelCount:_pixelsPerStrip
																	flags:*stripFlags];
		stripFlags++;
		[strip setBrightnessScale:_brightnessScale];
		[stripArray addObject:strip];
	}
}
- (BOOL)initializeFlushStuff
{
	NSError*		error;

	_socket = [GCDAsyncUdpSocket.alloc initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
	[_socket setIPv6Enabled:NO];
	if ([_socket connectToHost:_header.ipAddress onPort:_port error:&error])
	{
		// We only know here that the parameters for connection were reasonable.
		// We won't know about connection un-success until [udpSocket:didNotConnect:]
	}
	else
	{
		assert(NO);
		return NO;
	}
	
#if DO_PACKET_POOL
	self.packetPool = NSMutableSet.new;
	self.packetsInFlight = NSMutableDictionary.new;
#endif
#if DO_PACKET_PROMISE_DICT
	self.packetPromises = [NSMutableDictionary.alloc initWithCapacity:pusher.stripCount];
#endif
	_flushPromise = [HLDeferred deferredWithResult:nil];
	return YES;
}


/////////////////////////////////////////////////
#pragma mark - PROPERTIES:

+ (NSComparator)sortComparator
{
	return ^NSComparisonResult(PPPusher *obj1, PPPusher *obj2)
	{
		int32_t			const group0 = obj1->_groupOrdinal;
		int32_t			const group1 = obj2->_groupOrdinal;
		
		if (group0 != group1)
		{
			return (group0 < group1) ? NSOrderedAscending
									 : NSOrderedDescending;
		}
		
		int32_t			const ord1 = obj1->_controllerOrdinal;
		int32_t			const ord2 = obj2->_controllerOrdinal;
		
		if (ord1 != ord2)
		{
			return (ord1 < ord2) ? NSOrderedAscending
								 : NSOrderedDescending;
		}
		
		return [obj1->_header.macAddress compare:obj2->_header.macAddress];
	};
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@ (%@:%d, controller %d, group %d, flags %03x)",
									super.description, self.header.ipAddress, self.port,
									self.controllerOrdinal, self.groupOrdinal, self.pusherFlags];
}

/*
- (uint64_t)bandwidthEstimate
{
	return 0;
}
*/

- (void)setIsRecordingToFile:(BOOL)doRecord
{
	if (doRecord)
	{
		[self createWriteStream];
	}
	else
	{
		[self closeWriteStream];
	}
}
- (BOOL)isRecordingToFile
{
	return _writeStream ? YES : NO;
}

- (CFTimeInterval)packetDelay
{
	NSUInteger		const stripCount = _strips.count;
	NSUInteger		const packetsPerFrame = (stripCount >= _maxStripsPerPacket)
												? (stripCount + _maxStripsPerPacket - 1) / _maxStripsPerPacket
												: 1;
	NSTimeInterval	threadSleep;

	if (_updatePeriodUsec > 100000)
	{
		// Handle errant delay calculation in the firmware.
		threadSleep = 0.016 / packetsPerFrame;
	}
	else if (_updatePeriodUsec > 1000)
	{
		threadSleep = _updatePeriodUsec * 0.000001 + 0.001;
	}
	else
	{
		// Shoot for the framelimit.
		threadSleep = (1.0 / PPRegistry.the.frameRateLimit) / packetsPerFrame;
	}
	
	return threadSleep + _extraDelay + _delayForPacketLoss;
}


/////////////////////////////////////////////////
#pragma mark - BRIGHTNESS PROPERTIES:

- (void)setBrightnessScale:(PPFloatPixel)brightnessScale
{
	if (!PPFloatPixelEqual(_brightnessScale, brightnessScale))
	{
		_brightnessScale = brightnessScale;
		
		PPStrip*		strip;
		
		for (strip in _strips)
		{
			strip.brightnessScale = brightnessScale;
		}
	}
}
- (float)averageBrightness
{
	float			total;
	PPStrip*		strip;
	
	total = 0;
	for (strip in _strips)
	{
		total += strip.averageBrightness;
	}
	return total / _strips.count;
}
// This property/method wouldn't be necessary if PFLAG_GLOBALBRIGHTNESS meant
// that any strip actually supports brightnessScale.  Too bad.
- (BOOL)doesAnyStripSupportHardwareBrightnessScaling
{
	PPStrip*		strip;
	
	for (strip in _strips)
	{
		if (strip.flags & SFLAG_BRIGHTNESS)
		{
			return YES;
		}
	}
	return NO;
}


/////////////////////////////////////////////////
#pragma mark - OPERATIONS:

// Must be called before releasing self.
// This stuff can't happen in [dealloc] because that is sometimes called quite late,
// which causes re-allocated PPPusher{}s to fail.
- (void)close
{
//	NSLog(@"[PPPusher close] IP - %@ MAC - %@", _header.ipAddress, _header.macAddress);

	[self cancelPackets];
	[_socket setDelegate:nil];		// allows self to be deallocated sooner, since _socket retains self
	[_socket close];
	_socket = nil;					// releases _socket
}

// Returns whether any update merits considering the pusher to be significantly changed,
// which only determines whether or not to send an NSNotification about it.
- (void)updateWithHeader:(PPDeviceHeader*)header
{
	if (header.packetRemainderLength < 28)
	{
		assert(NO);
	}

/* according to Jas:
	Controller and group ordinals, strip per packets, and art net variables cannot change
	during runtime.  They are only read from the config file when a pusher boots.
	(This is by design-  it makes the pusher stateless, and therefore robust against
	being switched out or power-switched externally).  Only power total, update period,
	and delta sequence change at runtime, and delta sequence is handled by the device
	registry directly.
*/
	PPPusherData const*	const data = (PPPusherData const*)header.packetRemainder;
	uint32_t			updatePeriodUsec;
	
	_powerTotal = NSSwapLittleIntToHost(data->power_total);
	_deltaSequence = NSSwapLittleIntToHost(data->delta_sequence);
	updatePeriodUsec = NSSwapLittleIntToHost(data->update_period);
    if (ABS(updatePeriodUsec - _updatePeriodUsec) > 500)
	{
		_updatePeriodUsec = updatePeriodUsec;
	}
	else
	{
		if (_doAdjustForDroppedPackets)
		{
			// if we dropped more than occasional packets, slow down a little
			if (_deltaSequence > 3)
			{
				_delayForPacketLoss += 0.002;
//				NSLog(@"for IP - %@, _deltaSequence=%d, extraDelay = %f", \
//						_header.ipAddress, _deltaSequence, _delayForPacketLoss);
			}
			else if (_deltaSequence < 1)
			{
				_delayForPacketLoss -= 0.001;
				_delayForPacketLoss = MAX(_delayForPacketLoss, 0.0);
//				NSLog(@"for IP - %@, _deltaSequence=%d, extraDelay = %f", \
//						_header.ipAddress, _deltaSequence, _delayForPacketLoss);
			}
		}
	}
}


/////////////////////////////////////////////////
#pragma mark - BRIGHTNESS OPERATIONS:

- (void)resetHardwareBrightness
{
	NSInteger			stripIndex;
	
	stripIndex = _strips.count;
	while(--stripIndex >= 0)
	{
		[self enqueuePusherCommand:[PPPusherCommand brightnessCommand:0xFFFF forStrip:stripIndex]];
	}
	[self enqueuePusherCommand:[PPPusherCommand globalBrightnessCommand:0xFFFF]];
}

- (void)enqueuePusherCommand:(PPPusherCommand*)command
{
	// [PPPusherCommand wifiConfigureCommandForSSID...] can fail, so test:
	if (command)
	{
		switch (command.type)
		{
		case PPPusherCommandReset :
		case PPPusherCommandGlobalBrightness :
		case PPPusherCommandStripBrightness :
			// The app is taking control of brightnessScale.
			// Cancel the automatic discovery brightnessScale resetting, since
			// it might come AFTER the app has set brightnessScale:
			[NSObject cancelPreviousPerformRequestsWithTarget:self
														selector:@selector(resetHardwareBrightness)
														object:nil];
		default :
			break;
		}
		
		if (!_pusherCommandQueue)
		{
			_pusherCommandQueue = [NSMutableArray.alloc initWithCapacity:1];
		}
		[_pusherCommandQueue addObject:command];
	}
}

// [setBrightnessScale:] sets factors that are always applied to pixel values.
// This method instead scales, just once, the pixels values that are currently in each strip.
- (void)scaleAverageBrightness:(float)scale
{
	scale = MIN(scale, 1);		// just in case
	
	for (PPStrip* strip in _strips)
	{
		[strip scaleAverageBrightness:scale];
	}
}


/////////////////////////////////////////////////
#pragma mark - FLUSH OPERATIONS:

// Sends packets as needed:
//	* one for each PPPusherCommand enqueued in PPPusher
//	* calls [serializeIntoBuffer:] for each PPStrip, gathering the data into as few packets as possible
//	* sets up a block for each packet on a concurrent queue to execute at the right time for synchrony
//	* fulfills a promise being waited upon by the NEXT frame (very tricky stuff)
- (HLDeferred*)flush
{
	if (!_socket.isConnected || _socket.isClosed)
	{
		//??? This is a bit hacky since _flushPromise contains either the fulfilled
		//??? promise set in [init] or one from a previous call to flush.
		//??? The latter should be fulfilled, but will hang PPScene if it isn't.
		if (!_flushPromise.isCalled)
		{
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

	_unsentPacketCount = 0;			// just in case

	float				const powerScale = PPRegistry.the.powerScale;
	NSUInteger			const stripCount = _strips.count;
	NSUInteger			const maxStripsPerPacket = MIN(_maxStripsPerPacket, stripCount);
	CFTimeInterval		const timeBetweenPackets = self.packetDelay;
	CFTimeInterval		packetSendTime;
	NSUInteger			stripIndex;
	
	packetSendTime = (_prevPacketSendTime == 0) ? CACurrentMediaTime()
												: _prevPacketSendTime + timeBetweenPackets;
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
		*(uint32_t*)p = NSSwapHostIntToLittle(_packetIndex);
		p += sizeof(uint32_t);

		NSMutableArray*	const pusherCommandQueue = _pusherCommandQueue;
		BOOL			doSendPacket;

		doSendPacket = NO;
		if (pusherCommandQueue.count > 0)
		{
			PPPusherCommand*	const command = pusherCommandQueue[0];
			NSData*				const data = command.data;
			
			memcpy(p, data.bytes, data.length);
			if (_writeStream && (_pusherFlags & PFLAG_FIXEDSIZE))
			{
				[self writeStripBuffer:p
								length:data.length
								stripInPacketIndex:0
								packetSendTime:packetSendTime];
			}
			p += data.length;
			[pusherCommandQueue removeObjectAtIndex:0];		// causes command & data to be released
			doSendPacket = YES;
		}
		else
		{
			NSUInteger		stripInPacketIndex;
			
			stripInPacketIndex = 0;
			while ((stripInPacketIndex < maxStripsPerPacket) && (stripIndex < stripCount))
			{
				PPStrip*		const strip = _strips[stripIndex++];
				
				// output the strip if is touched, or if this is a fixed packet size pusher.
				if (strip.touched || (_pusherFlags & PFLAG_FIXEDSIZE) || _writeStream)
				{
					strip.powerScale = powerScale;		//??? This should be done when powerScale is calculated
					*p++ = (uint8_t)strip.stripNumber;
					
					uint32_t		const stripPacketSize = [strip serializeIntoBuffer:p bufferLength:pEnd - p];
					
					if (_writeStream)
					{
						[self writeStripBuffer:p - 1
										length:stripPacketSize + 1
										stripInPacketIndex:stripInPacketIndex
										packetSendTime:packetSendTime];
					}
					p += stripPacketSize;
					assert(p <= pEnd);		// packet buffer overrun
					stripInPacketIndex++;
					doSendPacket = YES;
				}
			}
		}
		
		if (doSendPacket)
		{
			// We need fixed size datagrams for the Photon, because the cc3000 sucks.
			NSUInteger		const packetLength = (_pusherFlags & PFLAG_FIXEDSIZE) ? _maxPacketLength
																				  : p - pStart;
#if DO_PACKET_POOL || DO_PACKET_PROMISE_DICT
			id				const key = @(_packetIndex);
#endif		
#if DO_PACKET_PROMISE_DICT
			HLDeferred*		const packetPromise = HLDeferred.new;
			
			self.packetPromises[key] = packetPromise;
#endif
#if DO_PACKET_POOL
			self.packetsInFlight[key] = packet;
			
			// make a new NSData object with the actual number of bytes packaged
			NSData*			const outGoing = [NSData dataWithBytesNoCopy:pStart
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
//			NSLog(@"[PPPusher flush] - packet prepared in %1.3fms", (CACurrentMediaTime() - startTime) * 1000);

			uint32_t		const packetIndex = _packetIndex;		// saved here for block
			CFTimeInterval	const now = CACurrentMediaTime();
			CFTimeInterval	const delay = MAX(packetSendTime - now, 0);

			_prevPacketSendTime = now + delay;
			packetSendTime = _prevPacketSendTime + timeBetweenPackets;
			_packetIndex++;
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
//			NSLog(@"enqueued packet %u with delay = %f", _packetIndex, delay);
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
							dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
				^{
					[_socket sendData:outGoing withTimeout:1 tag:packetIndex];
					
					dispatch_async(dispatch_get_main_queue(),
						^{
							_unsentPacketCount--;
#if !DO_PACKET_PROMISE_DICT
							if (_unsentPacketCount <= 0)
							{
//								assert(_unsentPacketCount == 0);
								if (!flushPromise.isCalled)		// otherwise [takeResult:] will throw exception
								{
									// Due to the complex, promised-based architecture, this can cause a
									// recursive call to [PPPusher flush].  This means that _unsentPacketCount,
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

- (void)writeStripBuffer:(uint8_t const*)buffer
					length:(uint32_t)length
					stripInPacketIndex:(uint32_t)stripInPacketIndex
					packetSendTime:(CFTimeInterval)packetSendTime
{
	// we need to make the pusher wait on playback the same length of time between strips as we wait between packets
	// this number is in microseconds.
	uint32_t		delay;
	
	// This logic is copied from the java library.  Can't say I understand it.
	if (stripInPacketIndex == 0)
	{
		if (_prevPacketSendTime != 0)
		{
			delay = (uint32_t)((packetSendTime - _prevPacketSendTime) * 1000000);
		}
		else
		{
			delay = _updatePeriodUsec;
		}
	}
	else
	{
		if ((packetSendTime - _prevPacketSendTime) < 25 * 60 * 1000000)
		{
			delay = 0;
		}
		else
		{
			delay = 0xdeadb33f;		// timer reset magic
		}
	}
	delay = NSSwapHostIntToLittle(delay);
	[_writeStream write:(uint8_t*)&delay maxLength:sizeof(delay)];
	[_writeStream write:buffer maxLength:length];
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
								 _groupOrdinal,
								 _controllerOrdinal,
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
#pragma mark - GCDAsyncUdpSocketDelegate RESPONDERS:

#if DO_PACKET_POOL

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
	assert(sock == _socket);
	
	NSNumber*			const key = @(tag);
	NSMutableData*		const packet = self.packetsInFlight[key];
	
	[self returnPacketToPool:packet];
	[self.packetsInFlight removeObjectForKey:key];
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError*)error
{
	assert(sock == _socket);
	
	[self udpSocket:sock didSendDataWithTag:tag];
}

#endif

- (void)udpSocket:(GCDAsyncUdpSocket*)sock didNotConnect:(NSError*)error
{
	assert(sock == _socket);
//	NSLog(@"[PPPusher udpSocket:didNotConnect:] IP - %@ MAC - %@ ERROR - %@", \
//			_header.ipAddress, _header.macAddress, error.description);

	[PPRegistry.the pusherSocketFailed:self];
}
- (void)udpSocketDidClose:(GCDAsyncUdpSocket*)sock withError:(NSError*)error
{
	assert(sock == _socket);
//	NSLog(@"[PPPusher udpSocketDidClose:] IP - %@ MAC - %@ ERROR - %@", \
//			_header.ipAddress, _header.macAddress, error.description);

	// We don't want to do anything when the socket is closed by [close] - which causes error==nil
	if (error)
	{
		[PPRegistry.the pusherSocketFailed:self];
	}
}


@end

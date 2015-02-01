//
//  PPPusher.m
//  PixelPusher-objc
//
//	PPPusher is an Objective-C class that handles communication with a single PixelPusher LED controller.
//	 * contains parameters received from broadcast packets
//	 * contains parameters that affect how data is transmitted
//	 * when [sendPackets] is called, calls [fillRgbBuffer:] for each PPStrip to get pixel data and
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

#import <libkern/OSAtomic.h>
#import "GCDAsyncUdpSocket.h"
#import "PPRegistry.h"
#import "PPPusher.h"
#import "PPStrip.h"
#import "PPPrivate.h"

INIT_LOG_LEVEL_INFO


/////////////////////////////////////////////////
#pragma mark - SWICHES:


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
	NSOutputStream*			_captureStream;
	uint32_t				_maxPacketLength;
	uint32_t				_packetIndex;
	CFTimeInterval			_prevPacketSendTime;
}

@end


@implementation PPPusher


/////////////////////////////////////////////////
#pragma mark - EXISTENCE:

- (id)initWithHeader:(PPDeviceHeader*)header
{
	self = [super init];
	LOG(@"[PPPusher initWithHeader:] IP - %@ MAC - %@", header.ipAddress, header.macAddress);
	
	int32_t				const softwareRevision = header.swRevision;
	PPPusherData const*	const data = (PPPusherData const*)header.packetRemainder;
	NSUInteger			const dataLength = header.packetRemainderLength;
	NSUInteger			stripCount;
	
	if (dataLength < 28)
	{
		ASSERT(NO);
		self = nil;		//??? Will self be released by ARC?
		return nil;
	}

	// These fields don't change until controller reboots:	
	stripCount = data->strips_attached;
	_pixelsPerStrip = NSSwapLittleShortToHost(data->pixels_per_strip);
	_maxStripsPerPacket = data->max_strips_per_packet;
	_maxPacketLength = 4 + ((1 + 3 * _pixelsPerStrip) * _maxStripsPerPacket);	// bytes
	_controllerOrdinal = NSSwapLittleIntToHost(data->controller_ordinal);
	_groupOrdinal = NSSwapLittleIntToHost(data->group_ordinal);
	_artnetUniverse = NSSwapLittleShortToHost(data->artnet_universe);
	_artnetChannel = NSSwapLittleShortToHost(data->artnet_channel);
	_port = (dataLength >= 30) && (softwareRevision > 100) ? NSSwapLittleShortToHost(data->my_port)
														   : kDefaultPusherPort;
	if ((stripCount == 0) ||
		(_pixelsPerStrip == 0) ||
		(_maxStripsPerPacket == 0) ||
		(_maxStripsPerPacket > stripCount) ||
		(_port == 0))
	{
		ASSERT(NO);
		self = nil;		//??? Will self be released by ARC?
		return nil;
	}
	
	// These fields can be different every packet:
	_updatePeriodUsec = NSSwapLittleIntToHost(data->update_period);
	_powerTotal = NSSwapLittleIntToHost(data->power_total);
	_deltaSequence = NSSwapLittleIntToHost(data->delta_sequence);
	
	// If _stripsAttached is less than 8, we still must read 8 bytes for the strip_flags.
	// If it is more, then the structure becomes variable-length.
	uint32_t			const stripFlagsSize = MAX(stripCount, (uint32_t)8);
	uint8_t				zeroStripFlags[256];
	uint8_t const*		stripFlags;
	
	ASSERT((uint8_t*)data + StripFlagsOffset == data->strip_flags);
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
		return YES;
	}
	else
	{
		ASSERT(NO);
		return NO;
	}
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

- (void)setIsCapturingToFile:(BOOL)doCapture
{
	if (doCapture)
	{
		[self createCaptureStream];
	}
	else
	{
		[self closeCaptureStream];
	}
}
- (BOOL)isCapturingToFile
{
	return _captureStream ? YES : NO;
}

- (CFTimeInterval)timeBetweenPackets
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
		threadSleep = (_updatePeriodUsec + 1000) * 0.000001;
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
// We can't do it in [dealloc] because _socket is retaining self as its delegate.
// _socket WILL eventually release _self, but later than we'd like.
// Before we did this, we saw PPPushers allocated when a controller re-appeared failing
// to connect their sockets.  Not sure why, but this seems to help.
- (void)close
{
	LOG(@"[PPPusher close] IP - %@ MAC - %@", _header.ipAddress, _header.macAddress);

	// Since [close] can only be called at the start of [PPRegistry ppNextFrame],
	// there should be no time when a packet-sending block would be accessing _socket
	// while this method is.
	// However, just to be safe, we don't release _socket before setting it to nil 
	// just in case because a waiting packet-sending block is executing concurrently, for then
	// it could then try to send with a released GCDAsyncUdpSocket.
	// So create a new strong reference.  (I hate doing this the ARC way.  It's so cryptic.)
	GCDAsyncUdpSocket*	const socket = _socket;
	
	_socket = nil;				// after this no block can send a packet
	[socket setDelegate:nil];	// allows self to be deallocated sooner, since _socket retains self
	[socket close];
								// now release the rocket
}

// Returns whether any update merits considering the pusher to be significantly changed,
// which only determines whether or not to send an NSNotification about it.
- (void)updateWithHeader:(PPDeviceHeader*)header
{
	if (header.packetRemainderLength < 28)
	{
		ASSERT(NO);
	}
/*
	according to Jas:
		Controller and group ordinals, strip per packets, and art net variables cannot change
		during runtime.  They are only read from the config file when a pusher boots.
		(This is by design-  it makes the pusher stateless, and therefore robust against
		being switched out or power-switched externally).  Only power total, update period,
		and delta sequence change at runtime, and delta sequence is handled by the device
		registry directly.
	So therefore we don't consider any header fields but those that change.
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
//				LOG(@"for IP - %@, _deltaSequence=%d, extraDelay = %f", \
//						_header.ipAddress, _deltaSequence, _delayForPacketLoss);
			}
			else if (_deltaSequence < 1)
			{
				_delayForPacketLoss -= 0.001;
				_delayForPacketLoss = MAX(_delayForPacketLoss, 0.0);
//				LOG(@"for IP - %@, _deltaSequence=%d, extraDelay = %f", \
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
//	* calls [fillRgbBuffer:] for each PPStrip, gathering the data into as few packets as possible
//	* sets up a block for each packet on a concurrent queue to execute at the right time for synchrony
//	* calls [ppAllPacketsSentByPusher:] when all of its packets have been sent.
- (void)sendPackets
{
//	ASSERT(_unsentPacketCount == 0);
	_unsentPacketCount = 0;			// just in case

	if (!_socket.isConnected || _socket.isClosed)
	{
		// GCDAsyncUdpSockets can close or disconnect asynchronously,
		// even though they can't call the delegate methods until the main queue is free.
		// Therefore, we can get here.
		// Must enqueue this, else face infinite recursion.
		dispatch_async(dispatch_get_main_queue(),
			^{
				[PPRegistry.the ppAllPacketsSentByPusher:self];	// since there are no packets to send
			}
		);
		return;
	}

	float				const powerScale = PPRegistry.the.powerScale;
	NSUInteger			const stripCount = _strips.count;
	NSUInteger			const maxStripsPerPacket = MIN(_maxStripsPerPacket, stripCount);
	CFTimeInterval		const timeBetweenPackets = self.timeBetweenPackets;
	CFTimeInterval		packetSendTime;
	NSUInteger			preparedPacketCount;
	NSUInteger			stripIndex;

	packetSendTime = (_prevPacketSendTime == 0) ? CACurrentMediaTime()
												: _prevPacketSendTime + timeBetweenPackets;
	preparedPacketCount = 0;
	stripIndex = 0;
	while (stripIndex < stripCount)
	{
//		CFTimeInterval	const startTime = CACurrentMediaTime();		// for LOG() below
		NSMutableData*	const packet = [NSMutableData.alloc initWithLength:_maxPacketLength];
		uint8_t*		const dataStart = packet.mutableBytes;
		uint8_t*		const dataEnd = dataStart + _maxPacketLength;
		uint8_t*		data;

		data = dataStart;
		*(uint32_t*)data = NSSwapHostIntToLittle(_packetIndex);
		data += sizeof(uint32_t);

		NSMutableArray*	const pusherCommandQueue = _pusherCommandQueue;
		BOOL			doSendPacket;

		doSendPacket = NO;
		if (pusherCommandQueue.count > 0)
		{
			PPPusherCommand*	const command = pusherCommandQueue[0];
			NSData*				const commandData = command.data;
			NSUInteger			const commandLength = commandData.length;
			
			memcpy(data, commandData.bytes, commandLength);
			if (_captureStream && (_pusherFlags & PFLAG_FIXEDSIZE))
			{
				[self captureRgbBuffer:data
								length:commandLength
								stripInPacketIndex:0
								packetSendTime:packetSendTime];
			}
			data += commandLength;
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
				if (strip.touched || (_pusherFlags & PFLAG_FIXEDSIZE) || _captureStream)
				{
					[strip setPowerScale:powerScale];
					*data++ = (uint8_t)strip.stripNumber;
					
					uint32_t		const stripPacketSize = [strip fillRgbBuffer:data
																	bufferLength:dataEnd - data];
					if (_captureStream)
					{
						[self captureRgbBuffer:data - 1
										length:stripPacketSize + 1
										stripInPacketIndex:stripInPacketIndex
										packetSendTime:packetSendTime];
					}
					data += stripPacketSize;
					ASSERT(data <= dataEnd);		// packet buffer overrun
					stripInPacketIndex++;
					doSendPacket = YES;
				}
			}
		}
		
		if (doSendPacket)
		{
			// We need fixed size datagrams for the Photon, because the cc3000 sucks.
			NSUInteger		const packetLength = (_pusherFlags & PFLAG_FIXEDSIZE) ? _maxPacketLength
																				  : data - dataStart;
			if (packetLength != _maxPacketLength)
			{
				ASSERT(packetLength < _maxPacketLength);
				[packet setLength:packetLength];
			}
//			LOG(@"[PPPusher sendPackets] - packet prepared in %1.3fms", \
//					(CACurrentMediaTime() - startTime) * 1000);

			CFTimeInterval	const now = CACurrentMediaTime();
			CFTimeInterval	const delay = MAX(packetSendTime - now, 0);
			dispatch_time_t	const dispatchTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));

			_prevPacketSendTime = now + delay;
			packetSendTime = _prevPacketSendTime + timeBetweenPackets;
			_packetIndex++;
			_unsentPacketCount++;
//			LOG(@"PPPusher #%*d ++_unsentPacketCount = %d", _controllerOrdinal, _controllerOrdinal, _unsentPacketCount);
			preparedPacketCount++;
			
			// We need to do this in a concurrent queue so that the MOMENT the dispatch time is up, 
			// the packet can be sent as quickly as possible.
			dispatch_after(dispatchTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
				^{
					// If [close] is called while this block is waiting to run, _socket will be set to nil.
					[_socket sendData:packet withTimeout:1 tag:0];

					// We can't decrement _unsentPacketCount in this concurrent queue because it might
					// go to zero before all the packets have been prepared.				
					dispatch_async(dispatch_get_main_queue(),
						^{
							// _unsentPacketCount may be being incremented above for next packet, do decrement atomically:
							_unsentPacketCount--;
//							LOG(@"PPPusher #%*d --_unsentPacketCount = %d", _controllerOrdinal, _controllerOrdinal, _unsentPacketCount);
							if (_unsentPacketCount <= 0)
							{
								ASSERT(_unsentPacketCount == 0);
								[PPRegistry.the ppAllPacketsSentByPusher:self];
							}
						}
					);
				}
			);
		}
	}
	
	if (preparedPacketCount == 0)
	{
		// Must enqueue this, else face infinite recursion.
		dispatch_async(dispatch_get_main_queue(),
			^{
				[PPRegistry.the ppAllPacketsSentByPusher:self];	// since there are no packets to send
			}
		);
	}
}


/////////////////////////////////////////////////
#pragma mark - CAPTURE-TO-FILE OPERATIONS:

- (void)createCaptureStream
{
	if (!_captureStream)
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
		_captureStream = [NSOutputStream outputStreamToFileAtPath:mapfilepath append:NO];
		[_captureStream open];
	}
}
- (void)closeCaptureStream
{
	if (_captureStream)
	{
		[_captureStream close];
		_captureStream = nil;
	}
}

//??? The packetSendTime stuff is likely messed up.
//??? Even if it isn't, I'd like the capture files to have timing with a constant frame rate,
//??? eliminating all network/processing delays.
//??? This needs to be re-worked.
- (void)captureRgbBuffer:(uint8_t const*)buffer
					length:(uint32_t)length
					stripInPacketIndex:(uint32_t)stripInPacketIndex
					packetSendTime:(CFTimeInterval)packetSendTime
{
	// we need to make the pusher wait on playback the same length of time between strips as we wait between packets
	// this number is in microseconds.
	uint32_t		delay;
	
	// This logic is copied from the java library.  Can't say I understand it entirely.
	if (stripInPacketIndex == 0)
	{
		// first strip in packet
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
	[_captureStream write:(uint8_t*)&delay maxLength:sizeof(delay)];
	[_captureStream write:buffer maxLength:length];
}


/////////////////////////////////////////////////
#pragma mark - GCDAsyncUdpSocketDelegate RESPONDERS:

- (void)udpSocket:(GCDAsyncUdpSocket*)sock didNotConnect:(NSError*)error
{
	ASSERT(sock == _socket);
	LOG(@"[PPPusher udpSocket:didNotConnect:] IP - %@ MAC - %@ ERROR - %@", \
			_header.ipAddress, _header.macAddress, error.description);

	[PPRegistry.the pusherSocketFailed:self];
}
- (void)udpSocketDidClose:(GCDAsyncUdpSocket*)sock withError:(NSError*)error
{
	ASSERT(sock == _socket);
	LOG(@"[PPPusher udpSocketDidClose:] IP - %@ MAC - %@ ERROR - %@", \
			_header.ipAddress, _header.macAddress, error.description);

	// We don't want to do anything when the socket is closed by [close] - which causes error==nil
	if (error)
	{
		[PPRegistry.the pusherSocketFailed:self];
	}
}


@end

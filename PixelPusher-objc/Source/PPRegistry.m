//
//  PPRegistry.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//	Modified by Christopher Schardt in late 2014:
//		grouped properties, operations, responders, etc...
//		removed pusherMap, which was a duplicate of PPScene.pusherDict
//		fixed calculation of _powerScale
//		added [isRunning]
//		stripped out a lot of never-used code
//		combined with PPScene
//

//#import <UIKit/UIKit.h>
#import "GCDAsyncUdpSocket.h"
#import "HLDeferredList.h"

#import "PPDeviceHeader.h"
#import "PPRegistry.h"
#import "PPPixel.h"
#import "PPPusher.h"
#import "PPPusherGroup.h"


INIT_LOG_LEVEL_INFO


/////////////////////////////////////////////////
#pragma mark - SWITCHES:

#define DO_LOG_FRAME_TIMES	FALSE
#define PPRegistry_DO_LOCK	FALSE


/////////////////////////////////////////////////
#pragma mark - CONSTANTS:

NSString*		const PPRegistryPusherAppeared = @"PPRegistryPusherAppeared";
NSString*		const PPRegistryPusherDisappeared = @"PPRegistryPusherDisappeared";

static const int32_t kDiscoveryPort = 7331;
static const int32_t kDisconnectTimeout = 10;	// seconds
static const int64_t kExpiryTimerInterval = 1;	// seconds

static const int32_t kExpectedPusherCount = 3;


/////////////////////////////////////////////////
#pragma mark - TYPES:

typedef struct
{
	CFTimeInterval render;
	CFTimeInterval flush;
	CFTimeInterval throttle;
} FrameTimes;


/////////////////////////////////////////////////
#pragma mark - STATIC DATA:

static PPRegistry *theRegistry;

#if DO_LOG_FRAME_TIMES
static FrameTimes		sFrameTimes[85];
static uint32_t			sFrameCount = 0;
#endif


/////////////////////////////////////////////////
#pragma mark - PRIVATE STUFF:

@interface PPRegistry () <GCDAsyncUdpSocketDelegate>
{
	GCDAsyncUdpSocket*		_discoverySocket;		// detects when pushers appear or change
	NSTimer*				_expireTimer;			// detects when pushers disappear
	NSMutableDictionary*	_appearedPusherDict;	// PPPushers to be added at [frameTask], key = mac address
	NSMutableDictionary*	_disappearedPusherDict;	// PPPushers to be removed at [frameTask], key = mac address
	NSMutableArray*			_pusherArray;			// PPPushers, sorted by [PPPusher sortComparator]
	NSMutableDictionary*	_pusherDict;			// PPPushers, keyed by mac address string
	NSMutableArray*			_groupArray;			// PPPusherGroups, sorted by ordinal
	NSMutableDictionary*	_groupDict;				// PPPusherGroups, keyed by NSNumbers with ordinal
	NSMutableArray*			_sortedStripArray;		// PPStrips, only built when needed - a cache

	BOOL					_powerTotalChanged;
	HLDeferred*				_defaultFramePromise;
	HLDeferred*				_lastFrameFlush;
}

@end


@implementation PPRegistry


/////////////////////////////////////////////////
#pragma mark - EXISTENCE:

- (id)init
{
    self = [super init];

	_brightnessScale = PPFloatPixelMake(1, 1, 1);
	_frameRateLimit = 60;
	_doAdjustForDroppedPackets = YES;
	_totalPowerLimit = -1;
	_powerScale = 1.0f;
	
	_appearedPusherDict = [NSMutableDictionary.alloc initWithCapacity:kExpectedPusherCount];
	_disappearedPusherDict = [NSMutableDictionary.alloc initWithCapacity:kExpectedPusherCount];
	_pusherArray = [NSMutableArray.alloc initWithCapacity:kExpectedPusherCount];
	_pusherDict = [NSMutableDictionary.alloc initWithCapacity:kExpectedPusherCount];
	_groupArray = [NSMutableArray.alloc initWithCapacity:1];
	_groupDict = [NSMutableDictionary.alloc initWithCapacity:1];
	
	_defaultFramePromise = [HLDeferred deferredWithResult:nil];
	_lastFrameFlush = [HLDeferred deferredWithResult:nil];

    return self;
}


/////////////////////////////////////////////////
#pragma mark - PROPERTIES:

+ (PPRegistry*)the
{
	if (!theRegistry)
	{
		theRegistry = [PPRegistry.alloc init];
	}
	return theRegistry;
}

- (void)setFrameDelegate:(id<PPFrameDelegate>)frameDelegate
{
	_frameDelegate = frameDelegate;
}

- (void)setIsRunning:(BOOL)doRun
{
	if (doRun != _isRunning)
	{
		_isRunning = doRun;
		if (doRun)
		{
			[self bindDiscoverySocket];
			[self startExpireTimer];
			[self frameTask];
		}
		else
		{
			[self unbindDiscoverySocket];
			[self stopExpireTimer];
			
			if (_doKillPushersWhenNotRunning)
			{
				[self killAllPushers];
			}
			else
			{
				PPPusher*		pusher;
				
				// When we resume running, we don't want to think that a pusher disappeared
				// because its lastSeenDate is quite old.  So we clear these dates:
				for (pusher in _pusherArray)
				{
					[pusher setLastSeenDate:0];
				}
			}
		}
	}
}
- (void)setDoKillPushersWhenNotRunning:(BOOL)doKill
{
	_doKillPushersWhenNotRunning = doKill;
	if (doKill && !_isRunning)
	{
		[self killAllPushers];
	}
}

- (void)setIsRecordingToFile:(BOOL)doRecord
{
	if (doRecord != _isRecordingToFile)
	{
		_isRecordingToFile = doRecord;
		
		PPPusher*		pusher;
		
		for (pusher in _pusherArray)
		{
			[pusher setIsRecordingToFile:doRecord];
		}
	}
}

- (void)setBrightnessScale:(PPFloatPixel)brightnessScale
{
	if (!PPFloatPixelEqual(_brightnessScale, brightnessScale))
	{
		_brightnessScale = brightnessScale;
		
		PPPusher*		pusher;
		
		for (pusher in _pusherArray)
		{
			[pusher setBrightnessScale:brightnessScale];
		}
	}
}

- (void)setDoAdjustForDroppedPackets:(BOOL)doAdjustForDroppedPackets
{
	if (_doAdjustForDroppedPackets != doAdjustForDroppedPackets)
	{
		_doAdjustForDroppedPackets = doAdjustForDroppedPackets;

		PPPusher*		pusher;
		
		for (pusher in _pusherArray)
		{
			[pusher setDoAdjustForDroppedPackets:doAdjustForDroppedPackets];
		}
	}
}
- (void)setExtraDelay:(NSTimeInterval)delay
{
	_extraDelay = delay;
	
	PPPusher*		pusher;
	
	for (pusher in _pusherArray)
	{
		[pusher setExtraDelay:delay];
    }
}
/*
- (uint64_t)totalBandwidthEstimate
{
	uint64_t		totalBandwidthEstimate;
	PPPusher*		pusher;
	
	totalBandwidthEstimate = 0;
	for (pusher in _pusherArray)
	{
		totalBandwidthEstimate += pusher.bandwidthEstimate;
	}
    return totalBandwidthEstimate;
}
*/

- (NSDictionary*)groupDict
{
	return _groupDict;
}
- (NSDictionary*)pusherDict
{
	return _pusherDict;
}
- (NSArray*)groups
{
	return _groupArray;
}
- (NSArray*)pushers
{
	return _pusherArray;
}
- (NSArray*)strips
{
	if (!_sortedStripArray)
	{
		PPPusher*		pusher;
		
		_sortedStripArray = NSMutableArray.new;
		
		for (pusher in _pusherArray)
		{
			[_sortedStripArray addObjectsFromArray:pusher.strips];
		}
	}
	return _sortedStripArray;
}

- (PPPusherGroup*)groupWithOrdinal:(int32_t)groupOrdinal;	// convenience method
{
	return _groupDict[@(groupOrdinal)];
}


/////////////////////////////////////////////////
#pragma mark - OPERATIONS:

- (void)bindDiscoverySocket
{
	if (!_discoverySocket)
	{
		NSError*		error;

		// setup the discovery service
		_discoverySocket = [GCDAsyncUdpSocket.alloc initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
		[_discoverySocket setIPv6Enabled:NO];

		[_discoverySocket enableReusePort:YES error:&error];
		assert(!error);

		[_discoverySocket enableBroadcast:YES error:&error];
		assert(!error);

		[_discoverySocket bindToPort:kDiscoveryPort error:&error];
		assert(!error);

		[_discoverySocket beginReceiving:&error];
		assert(!error);
	}
}
- (void)unbindDiscoverySocket
{
	[_discoverySocket close];
	_discoverySocket = nil;
}

- (void)startExpireTimer
{
	// This timer causes a PPPusher to be removed from _pusherDict and other
	// data structures if it hasn't been heard from in a while:
	_expireTimer = [NSTimer scheduledTimerWithTimeInterval:kExpiryTimerInterval
													target:self
													selector:@selector(deviceExpireTask:)
													userInfo:nil
													repeats:YES];
}
- (void)stopExpireTimer
{
	[_expireTimer invalidate];
	_expireTimer = nil;
}

- (void)killAllPushers
{
	PPPusher*		pusher;
	
	for (pusher in _pusherArray)
	{
		// using a dictionary prevents adding a pusher more than once
		_disappearedPusherDict[pusher.header.macAddress] = pusher;
	}
}

- (void)enqueuePusherCommandInAllPushers:(PPPusherCommand*)command
{
	PPPusher*		pusher;
	
	for (pusher in _pusherArray)
	{
		[pusher enqueuePusherCommand:command];
	}
}

- (BOOL)scaleAverageBrightnessForLimit:(float)brightnessLimit	// >=1.0 for no scaling
							forEachPusher:(BOOL)forEachPusher	// compute average for each pusher
{
	if (brightnessLimit < 1.0f)
	{
		float				average;
		PPPusher*			pusher;
		
		average = 0;
		if (forEachPusher)
		{
			for (pusher in _pusherArray)
			{
				float			const a = [pusher averageBrightness];
				
				if (a > average) average = a;
			}
		}
		else
		{
			for (pusher in _pusherArray)
			{
				average += [pusher averageBrightness];
			}
			average /= _pusherDict.count;
		}
		assert(average <= 1.0f);	// brightness average shouldn't exceed 1.0
		
		float				const scale = (average > 0) ? MIN(brightnessLimit / average, 1)
														: 1;
		for (pusher in _pusherArray)
		{
			[pusher scaleAverageBrightness:scale];
		}
		
		if (scale < 1.0f)
		{
			return YES;
		}
	}
	return NO;
}


/////////////////////////////////////////////////
#pragma mark - FRAME OPERATIONS:

- (void)frameTask
{
	CFTimeInterval		const start = CACurrentMediaTime();

	// We add and remove to/from the arrays and dictionaries only here so as to not confuse client
	// code that checks the group/pusher/strips at the beginning of [pixelPusherRender] and assumes
	// they will stay the same until rendering is over (such as LED Lab).
	[self handleAppearedPushers];
	[self handleDisappearedPushers];
	if (_powerTotalChanged && (_totalPowerLimit >= 0))
	{
		[self calculatePowerScale];
		_powerTotalChanged = NO;
	}

	HLDeferred*			frameRenderPromise;
	
	assert(_frameDelegate);		// This library won't do much of anything without a delegate
	frameRenderPromise = [_frameDelegate pixelPusherRender];
	if (!frameRenderPromise)
	{
		frameRenderPromise = _defaultFramePromise;
	}
	
	[frameRenderPromise then:
		^id(id result2)
		{
#if DO_LOG_FRAME_TIMES
			uint32_t		const timesIdx = sFrameCount % _frameRateLimit;
			
			sFrameTimes[timesIdx].render = CACurrentMediaTime()	- start;
#endif			
			// We need to retain _lastFrameFlush since [then:] will likely release it, since it may call
			// call [frameTask] recursively.  ARC will actually retain and then release the return value
			// of [then:], which is the HLDeferred object, so if has been released, we will crash.
			// I hate ARC.
			HLDeferred*		const strongPrevFramePromise = _lastFrameFlush;
			
			// wait for all card tasks from last frame to finish flushing
			[strongPrevFramePromise then:
				^id(id result)
				{
					// lastFrameFlush was waiting for promises in [PPPusher flush] to be fulfilled.
					// One tricky thing about this complex, promise-based architecture is that [PPPusher flush] will
					// now cause a recursive call from a block in [PPPusher flush] to [PPPusher flush].
					// One therefore has to be very careful about instance variables in PPPusher.
#if DO_LOG_FRAME_TIMES
					sFrameTimes[timesIdx].throttle = CACurrentMediaTime() - start - sFrameTimes[timesIdx].render;
#endif
					NSMutableArray*		const promises = [NSMutableArray arrayWithCapacity:_pusherArray.count];
					PPPusher*			pusher;
					
					for (pusher in _pusherArray)
					{
						[promises addObject:[pusher flush]];
					}
					_lastFrameFlush = [HLDeferredList.alloc initWithDeferreds:promises];
					
#if DO_LOG_FRAME_TIMES
					sFrameTimes[timesIdx].flush = CACurrentMediaTime() - start - sFrameTimes[timesIdx].render - sFrameTimes[timesIdx].throttle;
					if (timesIdx == 0)
					{
						CFTimeInterval sumRender = 0;
						CFTimeInterval sumFlush = 0;
						CFTimeInterval sumThrottle = 0;
						for (uint32_t idx = 0; idx < _frameRateLimit; idx++)
						{
							sumRender += sFrameTimes[idx].render;
							sumFlush += sFrameTimes[idx].flush;
							sumThrottle += sFrameTimes[idx].throttle;
						}
						sumRender /= _frameRateLimit;
						sumThrottle /= _frameRateLimit;
						sumFlush /= _frameRateLimit;
						CFTimeInterval idle = minFrameInterval-sumThrottle-sumRender-sumFlush;
						DDLogInfo(@"avg render %1.1f%%, flush %1.1f%%, send %1.1f%%, idle %1.1f%%",
								  sumRender/minFrameInterval*100, sumFlush/minFrameInterval*100, sumSend/minFrameInterval*100, idle/minFrameInterval*100);
						DDLogInfo(@"avg render %1.2fms, flush %1.2fms, throttle %1.3fms, idle %1.2fms",
								  sumRender*1000, sumFlush*1000, sumThrottle*1000, idle*1000);
					}
#endif
					if (_isRunning)
					{
						// delay to our min frame interval if we haven't exceeded it yet
						CFTimeInterval		const minFrameInterval = 1.0 / _frameRateLimit;
						CFTimeInterval		const delayTilNextFrame = minFrameInterval - (CACurrentMediaTime() - start);
						dispatch_time_t		const popTime = dispatch_time(DISPATCH_TIME_NOW,
																			(int64_t)(MAX(0, delayTilNextFrame) * NSEC_PER_SEC));
						dispatch_after(popTime, dispatch_get_main_queue(),
							^{
								[self frameTask];
							}
						);
					}
					return nil;
				}
			];
#if DO_LOG_FRAME_TIMES
			sFrameCount++;
#endif
			return nil;
		}
	];
}

- (void)handleAppearedPushers
{
	PPPusher*		pusher;
	
	for (pusher in _appearedPusherDict.objectEnumerator)
	{
//		NSLog(@"[PPScene handleAppearedPushers] IP - %@ MAC - %@", \
//				pusher.header.ipAddress, pusher.header.macAddress);

		[pusher setBrightnessScale:_brightnessScale];
		[pusher setDoAdjustForDroppedPackets:_doAdjustForDroppedPackets];
		[pusher setIsRecordingToFile:_isRecordingToFile];
		[pusher setExtraDelay:_extraDelay];
		_pusherDict[pusher.header.macAddress] = pusher;

		NSRange			range;
		NSUInteger		insertionIndex;
		
		range.location = 0;
		range.length = _pusherArray.count;
		insertionIndex = [_pusherArray indexOfObject:pusher
										inSortedRange:range
										options:NSBinarySearchingInsertionIndex
										usingComparator:PPPusher.sortComparator];
		[_pusherArray insertObject:pusher atIndex:insertionIndex];

		_sortedStripArray = nil;		// so that it will be re-built

		PPPusherGroup*		group;
		
		group = _groupDict[@(pusher.groupOrdinal)];
		if (group)
		{
			[group addPusher:pusher];
		}
		else
		{
			group = [PPPusherGroup.alloc initWithOrdinal:pusher.groupOrdinal];
			[group addPusher:pusher];
			
			_groupDict[@(pusher.groupOrdinal)] = group;

			range.location = 0;
			range.length = _groupArray.count;
			insertionIndex = [_groupArray indexOfObject:group
											inSortedRange:range
											options:NSBinarySearchingInsertionIndex
											usingComparator:
				^NSComparisonResult(PPPusherGroup *group0, PPPusherGroup *group1)
				{
					if (group0.ordinal == group1.ordinal) return NSOrderedSame;
					if (group0.ordinal  < group1.ordinal) return NSOrderedAscending;
					return NSOrderedDescending;
				}
			];
			[_groupArray insertObject:group atIndex:insertionIndex];
		}

		// When this method is called immediately, it doesn't work.
		// Don't know why, but a delay is no problem:
		[pusher performSelector:@selector(resetHardwareBrightness) withObject:nil afterDelay:1.0];
		
		[NSNotificationCenter.defaultCenter postNotificationName:PPRegistryPusherAppeared object:pusher];
	}
	
	[_appearedPusherDict removeAllObjects];
}

- (void)handleDisappearedPushers
{
	PPPusher*		pusher;
	
	for (pusher in _disappearedPusherDict.objectEnumerator)
	{
		NSString*		const macAddress = pusher.header.macAddress;
		
//		NSLog(@"[PPScene handleDisappearedPushers] IP - %@ MAC - %@", pusher.header.ipAddress, macAddress);

		// We call [close] right away, rather than wait for [card dealloc]
		[pusher close];
		[_pusherDict removeObjectForKey:macAddress];
		[_pusherArray removeObject:pusher];
		
		PPPusherGroup*		const group = _groupDict[@(pusher.groupOrdinal)];
		
		if (group)
		{
			[group removePusher:pusher];
			if (group.pushers.count == 0)
			{
				[_groupDict removeObjectForKey:@(pusher.groupOrdinal)];
				[_groupArray removeObject:group];
			}
		}

		_sortedStripArray = nil;		// so that it will be re-built

		[NSNotificationCenter.defaultCenter postNotificationName:PPRegistryPusherDisappeared object:pusher];
	}
	
	[_disappearedPusherDict removeAllObjects];		// [PPPusher dealloc] should be called here
}

- (void)calculatePowerScale
{
	uint64_t		power;
	PPPusher*		pusher;
	
	power = 0;
	for (pusher in _pusherArray)
	{
		power += pusher.powerTotal;
	}
	_totalPower = power;
	_powerScale = ((uint64_t)_totalPowerLimit < power) ? (float)_totalPowerLimit / power
													   : 1.0f;
}


/////////////////////////////////////////////////
#pragma mark - RESPONDERS:

- (void)pusherSocketFailed:(PPPusher*)pusher
{
	// using a dictionary prevents adding a pusher more than once
	_disappearedPusherDict[pusher.header.macAddress] = pusher;
}


/////////////////////////////////////////////////
#pragma mark - GCDAsyncUdpSocketDelegate RESPONDERS:

- (void)udpSocket:(GCDAsyncUdpSocket*)socket
   didReceiveData:(NSData*)data
	  fromAddress:(NSData*)address
withFilterContext:(id)filterContext
{
	// This method can be called after the socket is released, so test:
	if (socket == _discoverySocket)
	{
		PPDeviceHeader*		const header = [PPDeviceHeader.alloc initWithPacket:data];
		
		if (header)
		{
			NSString*			const macAddress = header.macAddress;
			PPPusher*			pusher;
			
			pusher = _pusherDict[macAddress];
			if (!pusher)
			{
				pusher = [PPPusher.alloc initWithHeader:header];
				if (!pusher)
				{
					return;		// invalid data
				}
				// using a dictionary prevents adding a pusher more than once
				_appearedPusherDict[macAddress] = pusher;
//				NSLog(@"[PPScene udpSocket:didReceiveData:] APPEARED IP - %@ MAC - %@", \
//						pusher.header.ipAddress, macAddress);
			}
			else
			{
				[pusher updateWithHeader:header];
			}
			[pusher setLastSeenDate:NSDate.date.timeIntervalSinceReferenceDate];
			
			_powerTotalChanged = YES;
		}
	}
}

/*
- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError *)error
{
	DDLogError(@"updSocketDidClose: %@", error);
}
*/


/////////////////////////////////////////////////
#pragma mark - NSTimer RESPONDERS:

- (void)deviceExpireTask:(NSTimer*)timer
{
	NSTimeInterval		const now = NSDate.date.timeIntervalSinceReferenceDate;	// Get just once for efficiency
	PPPusher*			pusher;

	for (pusher in _pusherArray)
	{
		NSTimeInterval		const lastSeenDate = pusher.lastSeenDate;
		
		if (lastSeenDate != 0)
		{
			if (now - lastSeenDate > kDisconnectTimeout)
			{
				// using a dictionary prevents adding a pusher more than once
				_disappearedPusherDict[pusher.header.macAddress] = pusher;
//				NSLog(@"[PPScene deviceExpireTask] DISAPPEARED IP - %@ MAC - %@", \
//						pusher.header.ipAddress, pusher.header.macAddress);
			}
		}
	}
}


@end

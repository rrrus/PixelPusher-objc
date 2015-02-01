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

#import "PPDeviceHeader.h"
#import "PPRegistry.h"
#import "PPPixel.h"
#import "PPPusher.h"
#import "PPPusherGroup.h"
#import "PPPrivate.h"


INIT_LOG_LEVEL_INFO


/////////////////////////////////////////////////
#pragma mark - SWITCHES:

#define PPRegistry_DO_LOCK	FALSE


/////////////////////////////////////////////////
#pragma mark - CONSTANTS:

NSString*		const PPRegistryPusherAppeared = @"PPRegistryPusherAppeared";
NSString*		const PPRegistryPusherDisappeared = @"PPRegistryPusherDisappeared";

static const int32_t kDiscoveryPort = 7331;
static const int32_t kDisconnectTimeout = 100;	// seconds
static const int64_t kExpiryTimerInterval = 1;	// seconds

static const int32_t kExpectedPusherCount = 3;	// only used as initial NSMutableArray, NSMutableDictionary capacity


/////////////////////////////////////////////////
#pragma mark - TYPES:


/////////////////////////////////////////////////
#pragma mark - STATIC DATA:

static PPRegistry *theRegistry;


/////////////////////////////////////////////////
#pragma mark - PRIVATE STUFF:

@interface PPRegistry () <GCDAsyncUdpSocketDelegate>
{
	GCDAsyncUdpSocket*		_discoverySocket;		// detects when pushers appear or change
	NSTimer*				_expireTimer;			// detects when pushers disappear
	NSMutableDictionary*	_appearedPusherDict;	// PPPushers to be added at [ppNextFrame], key = mac address
	NSMutableDictionary*	_disappearedPusherDict;	// PPPushers to be removed at [ppNextFrame], key = mac address
	NSMutableArray*			_pusherArray;			// PPPushers, sorted by [PPPusher sortComparator]
	NSMutableDictionary*	_pusherDict;			// PPPushers, keyed by mac address string
	NSMutableArray*			_groupArray;			// PPPusherGroups, sorted by ordinal
	NSMutableDictionary*	_groupDict;				// PPPusherGroups, keyed by NSNumbers with ordinal
	NSMutableArray*			_sortedStripArray;		// PPStrips, only built when needed - a cache

	BOOL					_isPowerTotalChanged;
	BOOL					_isRenderingFinished;
	NSInteger				_pusherWithUnsentPacketsCount;
	NSTimeInterval			_frameStartTime;
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
			[self ppNextFrame];
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
				// because its lastSeenTime is quite old.  So we clear these dates:
				for (pusher in _pusherArray)
				{
					[pusher setLastSeenTime:0];
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

- (void)setIsCapturingToFile:(BOOL)doRecord
{
	if (doRecord != _isCapturingToFile)
	{
		_isCapturingToFile = doRecord;
		
		PPPusher*		pusher;
		
		for (pusher in _pusherArray)
		{
			[pusher setIsCapturingToFile:doRecord];
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
- (NSArray*)groupArray
{
	return _groupArray;
}
- (NSArray*)pusherArray
{
	return _pusherArray;
}
- (NSArray*)stripArray
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
		ASSERT(!error);

		[_discoverySocket enableBroadcast:YES error:&error];
		ASSERT(!error);

		[_discoverySocket bindToPort:kDiscoveryPort error:&error];
		ASSERT(!error);

		[_discoverySocket beginReceiving:&error];
		ASSERT(!error);
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
		ASSERT(average <= 1.0f);	// brightness average shouldn't exceed 1.0
		
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
#pragma mark - FRAME RESPONDERS:

- (void)ppNextFrame
{
//	LOG(@"ppNextFrame");

	_frameStartTime = CACurrentMediaTime();

	// We add and remove to/from the arrays and dictionaries only here so as to not confuse client
	// code that checks the group/pusher/strips at the beginning of [ppRenderStart] and assumes
	// they will stay the same until rendering is over (such as LED Lab).
	[self handleAppearedPushers];
	[self handleDisappearedPushers];
	[self calculatePowerScale];

	_isRenderingFinished = NO;
	ASSERT(_frameDelegate);		// This library won't do much of anything without a delegate
	if ([_frameDelegate ppRenderStart])
	{
		// The client has finished rendering directly.
		[self ppRenderFinished];
	}
}
- (void)ppRenderFinished
{
//	LOG(@"ppRenderFinished");

	_isRenderingFinished = YES;
	if (_pusherArray.count > 0)
	{
		if (_pusherWithUnsentPacketsCount <= 0)
		{
			// The previous frame's packets have been sent.  Send!
			[self ppSendNextPackets];
		}
		else
		{
			// The previous frame's packets have not been sent.  Wait.
			// (This is quite common!)
//			LOG(@"[PPRegistry ppRenderFinished] - previous frame's packets not yet sent");
		}
	}
	else
	{
		_pusherWithUnsentPacketsCount = 0;		// for when pushers appear again
		[self ppScheduleNextFrame];
	}
}
- (void)ppAllPacketsSentByPusher:(PPPusher*)pusher
{
	_pusherWithUnsentPacketsCount--;
//	LOG(@"PPRegistry PUSHER %*d --_pusherWithUnsentPacketsCount = %d", pusher.controllerOrdinal, pusher.controllerOrdinal, _pusherWithUnsentPacketsCount);
	ASSERT(_pusherWithUnsentPacketsCount >= 0);
	if (_pusherWithUnsentPacketsCount <= 0)
	{
		// All the previous frame's packets have been sent.
		if (_isRenderingFinished)
		{
			// The rendering for the current frame is finished too.  Send!
			[self ppSendNextPackets];
		}
		else
		{
			// The rendering for the current frame is not finished.  Wait.
		}
	}
}
- (void)ppSendNextPackets
{
//	LOG(@"PPRegistry PREPARE PACKETS _pusherWithUnsentPacketsCount = %d", _pusherArray.count);
	
	_isRenderingFinished = NO;	// prevents unlikely, infinite recursion
	_pusherWithUnsentPacketsCount = _pusherArray.count;
	if (_pusherWithUnsentPacketsCount > 0)
	{
		PPPusher*			pusher;
		
		for (pusher in _pusherArray)
		{
			// [sendPackets] will create packets for pusher commands and strip data,
			// and create blocks that will send them at the right time according to
			// Jas' Metronomicon algorithm.
			// When each pusher has sent all its packets, it calls [ppAllPacketsSentByPusher:].
			[pusher sendPackets];
		}
	}
	[self ppScheduleNextFrame];
}
- (void)ppScheduleNextFrame
{
//	LOG(@"ppScheduleNextFrame");

	if (_isRunning)
	{
		CFTimeInterval		const minFrameDuration = 1.0 / _frameRateLimit;
		CFTimeInterval		const frameDuration = CACurrentMediaTime() - _frameStartTime;
		CFTimeInterval		const delayTilNextFrame = MAX(minFrameDuration - frameDuration, 0);
		dispatch_time_t		const nextFrameTime = dispatch_time(DISPATCH_TIME_NOW,
																(int64_t)(delayTilNextFrame * NSEC_PER_SEC));
		if (delayTilNextFrame > 0)
		{
//			LOG(@"ppScheduleNextFrame - duration : %1.3f, delay - %1.3f sec", frameDuration, delayTilNextFrame);
		}
		dispatch_after(nextFrameTime, dispatch_get_main_queue(),
			^{
				[self ppNextFrame];
			}
		);
	}
}


/////////////////////////////////////////////////
#pragma mark - FRAME OPERATIONS:

- (void)handleAppearedPushers
{
	PPPusher*		pusher;
	
	for (pusher in _appearedPusherDict.objectEnumerator)
	{
		NSString*		const macAddress = pusher.header.macAddress;
		
		LOG(@"[PPScene handleAppearedPushers] IP - %@ MAC - %@", pusher.header.ipAddress, macAddress);

		[pusher setBrightnessScale:_brightnessScale];
		[pusher setDoAdjustForDroppedPackets:_doAdjustForDroppedPackets];
		[pusher setIsCapturingToFile:_isCapturingToFile];
		[pusher setExtraDelay:_extraDelay];
		_pusherDict[macAddress] = pusher;

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
		
		LOG(@"[PPScene handleDisappearedPushers] IP - %@ MAC - %@", pusher.header.ipAddress, macAddress);

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
	if (_isPowerTotalChanged && (_totalPowerLimit >= 0))
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
	_isPowerTotalChanged = NO;
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
//				LOG(@"[PPScene udpSocket:didReceiveData:] APPEARED IP - %@ MAC - %@", \
//						pusher.header.ipAddress, macAddress);
			}
			else
			{
				[pusher updateWithHeader:header];
			}
			[pusher setLastSeenTime:CACurrentMediaTime()];
			
			_isPowerTotalChanged = YES;
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
	NSTimeInterval		const now = CACurrentMediaTime();	// Get just once for efficiency
	PPPusher*			pusher;

	for (pusher in _pusherArray)
	{
		NSTimeInterval		const lastSeenTime = pusher.lastSeenTime;
		
		if (lastSeenTime != 0)
		{
			if (now - lastSeenTime > kDisconnectTimeout)
			{
				// using a dictionary prevents adding a pusher more than once
				_disappearedPusherDict[pusher.header.macAddress] = pusher;
//				LOG(@"[PPScene deviceExpireTask] DISAPPEARED IP - %@ MAC - %@", \
//						pusher.header.ipAddress, pusher.header.macAddress);
			}
		}
	}
}


@end

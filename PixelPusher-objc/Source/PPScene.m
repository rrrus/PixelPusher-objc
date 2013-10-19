//
//  PPScene.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/31/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "HLDeferredList.h"
#import "PPCard.h"
#import "PPPixelPusher.h"
#import "PPScene.h"
#import <QuartzCore/QuartzCore.h>

INIT_LOG_LEVEL_INFO

static const int32_t kPusherPort = 9897;
static const int32_t kFrameRateLimit = 60;	// limit to 60fps
static const CFTimeInterval kMinFrameInterval = 1.0/kFrameRateLimit;

typedef struct {
	CFTimeInterval render;
	CFTimeInterval flush;
	CFTimeInterval throttle;
} FrameTimes;

static FrameTimes sFrameTimes[kFrameRateLimit];
static uint32_t sFrameCount = 0;

@interface PPScene ()
@property (nonatomic, strong) HLDeferred *defaultFramePromise;
@property (nonatomic, strong) NSMutableDictionary *pusherMap;
@property (nonatomic, strong) NSMutableDictionary *cardMap;
@property (nonatomic, strong) NSMutableData *packet;
@property (nonatomic, assign) int32_t packetLength;
@property (nonatomic, assign) NSTimeInterval extraDelay;
@property (nonatomic, assign) BOOL autoThrottle;
@property (nonatomic, assign) BOOL drain;
@property (nonatomic, strong) HLDeferred *lastFrameFlush;

// redeclaring readonly public interfaces for private assign access
@property (nonatomic, assign) BOOL isRunning;

@end

@implementation PPScene

- (id)init {
    self = [super init];
    if (self) {
		self.defaultFramePromise = [HLDeferred deferredWithResult:nil];
		self.pusherMap = NSMutableDictionary.new;
		self.cardMap = NSMutableDictionary.new;
		self.drain = NO;
		self.isRunning = NO;
		self.lastFrameFlush = [HLDeferred deferredWithResult:nil];

		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(registryAddedPusher:)
												   name:PPDeviceRegistryAddedPusher
												 object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(registryUpdatedPusher:)
												   name:PPDeviceRegistryUpdatedPusher
												 object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(registryRemovedPusher:)
												   name:PPDeviceRegistryRemovedPusher
												 object:nil];
    }
    return self;
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setAutoThrottle:(BOOL)autothrottle {
	_autoThrottle = autothrottle;
    //System.err.println("Setting autothrottle in SceneThread.");
	[self.pusherMap forEach:^(id key, PPPixelPusher *pusher, BOOL *stop) {
		//System.err.println("Setting card "+pusher.getControllerOrdinal()+" group "+pusher.getGroupOrdinal()+" to "+
		//      (autothrottle?"throttle":"not throttle"));
		[pusher setAutoThrottle:autothrottle];
	}];
}

- (int64_t)totalBandwidth {
	__block int64_t totalBandwidth = 0;
	[self.cardMap forEach:^(id key, PPCard* card, BOOL *stop) {
		totalBandwidth += card.bandwidthEstimate;
	}];
    return totalBandwidth;
}

- (void)setExtraDelay:(NSTimeInterval)delay {
	self.extraDelay = delay;
	[self.cardMap forEach:^(id key, PPCard* card, BOOL *stop) {
		[card setExtraDelay:delay];
    }];
}

- (void)removePusher:(PPPixelPusher*)pusher {
	[self.cardMap forEach:^(id key, PPCard* card, BOOL *stop) {
        if ([card controls:pusher]) {
			[card shutDown];
			[card cancel];
		}
	}];
    [self.cardMap removeObjectForKey:pusher.macAddress];
}

- (void)start {
    self.isRunning = YES;
    self.drain = NO;
	[self.cardMap forEach:^(id key, PPCard* card, BOOL *stop) {
		[card start];
	}];

	[self frameTask];
}

- (void)frameTask {
	CFTimeInterval start = CACurrentMediaTime();
	// call the frame delegate to render a frame
	HLDeferred *frameRenderPromise = self.defaultFramePromise;
	if (self.frameDelegate) {
		// allow frame render tasks to return nil
		HLDeferred * renderPromise = [self.frameDelegate pixelPusherRender];
		if (renderPromise) frameRenderPromise = renderPromise;
	}
	[frameRenderPromise then:^id(id result) {
		uint32_t timesIdx = sFrameCount % kFrameRateLimit;
		sFrameTimes[timesIdx].render = CACurrentMediaTime()	- start;
		// wait for all card tasks from last frame to finish flushing
		[self.lastFrameFlush then:^id(id result) {
			sFrameTimes[timesIdx].throttle = CACurrentMediaTime() - start - sFrameTimes[timesIdx].render;

			NSMutableArray *promises = [NSMutableArray arrayWithCapacity:self.cardMap.count];
			[self.cardMap forEach:^(id key, PPCard* card, BOOL *stop) {
				[promises addObject:card.flush];
			}];
			sFrameTimes[timesIdx].flush = CACurrentMediaTime() - start - sFrameTimes[timesIdx].render - sFrameTimes[timesIdx].throttle;
			self.lastFrameFlush = [HLDeferredList.alloc initWithDeferreds:promises];

			// delay to our min frame interval if we haven't exceeded it yet
			CFTimeInterval delayTilNextFrame = kMinFrameInterval - (CACurrentMediaTime()-start);
			if (delayTilNextFrame < 0) {
	//			DDLogInfo(@"frame deadline blown by %fs", -delayTilNextFrame);
			}
			CFTimeInterval delayInSeconds = MAX(0, delayTilNextFrame);
			dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
			dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
				[self frameTask];
			});
#if 0	// enable for render/flush/send stats
			if (timesIdx == 0) {
				CFTimeInterval sumRender = 0;
				CFTimeInterval sumFlush = 0;
				CFTimeInterval sumThrottle = 0;
				for (uint32_t idx = 0; idx < kFrameRateLimit; idx++) {
					sumRender += sFrameTimes[idx].render;
					sumFlush += sFrameTimes[idx].flush;
					sumThrottle += sFrameTimes[idx].throttle;
				}
				sumRender /= kFrameRateLimit;
				sumThrottle /= kFrameRateLimit;
				sumFlush /= kFrameRateLimit;
				CFTimeInterval idle = kMinFrameInterval-sumThrottle-sumRender-sumFlush;
	//			DDLogInfo(@"avg render %1.1f%%, flush %1.1f%%, send %1.1f%%, idle %1.1f%%",
	//					  sumRender/kMinFrameInterval*100, sumFlush/kMinFrameInterval*100, sumSend/kMinFrameInterval*100, idle/kMinFrameInterval*100);
				DDLogInfo(@"avg render %1.2fms, flush %1.2fms, throttle %1.2fms, idle %1.2fms",
						  sumRender*1000, sumFlush*1000, sumThrottle*1000, idle*1000);
			}
#endif
			return nil;
		}];
		sFrameCount++;
		return nil;
	}];
}

- (BOOL)cancel {
    self.drain = YES;
	[self.cardMap forEach:^(id key, PPCard* card, BOOL *stop) {
		[card cancel];
	}];
	[self.cardMap removeAllObjects];
    return YES;
}

- (void)registryAddedPusher:(NSNotification*)notif {
	PPPixelPusher *pusher = DYNAMIC_CAST(PPPixelPusher, notif.object);
	if (!self.drain && pusher) {
		PPCard *newCard = [PPCard.alloc initWithPusher:pusher port:kPusherPort];
		if (self.isRunning) {
			[newCard start];
			[newCard setExtraDelay:self.extraDelay];
			[pusher setAutoThrottle:self.autoThrottle];
		}
		self.pusherMap[pusher.macAddress] = pusher;
		self.cardMap[pusher.macAddress] = newCard;
	}
}

- (void)registryUpdatedPusher:(NSNotification*)notif {
	if (!self.drain) {
	}
}

- (void)registryRemovedPusher:(NSNotification*)notif {
	PPPixelPusher *pusher = DYNAMIC_CAST(PPPixelPusher, notif.object);
	if (!self.drain && pusher) {
		DDLogInfo(@"Killing old Card %@", pusher.macAddress);
		PPCard *card = self.cardMap[pusher.macAddress];
		if (!card) {
			DDLogWarn(@"notified of unknown pusher remove %@", pusher);
		} else {
			[card cancel];
			[self.cardMap removeObjectForKey:pusher.macAddress];
			[self.pusherMap removeObjectForKey:pusher.macAddress];
		}
	}
}

@end

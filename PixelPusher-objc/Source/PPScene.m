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

typedef struct {
	CFTimeInterval render;
	CFTimeInterval flush;
	CFTimeInterval throttle;
} FrameTimes;

static FrameTimes sFrameTimes[85];
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
		self.globalBrightness = 1.0;
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

- (void)setRecord:(BOOL)record {
	if (_record != record) {
		_record = record;
		[self.cardMap forEach:^(id key, PPCard* card, BOOL *stop) {
			card.record = record;
		}];
	}
}

- (void)setAutoThrottle:(BOOL)autothrottle {
	if (_autoThrottle != autothrottle) {
		_autoThrottle = autothrottle;
		//System.err.println("Setting autothrottle in SceneThread.");
		[self.pusherMap forEach:^(id key, PPPixelPusher *pusher, BOOL *stop) {
			//System.err.println("Setting card "+pusher.getControllerOrdinal()+" group "+pusher.getGroupOrdinal()+" to "+
			//      (autothrottle?"throttle":"not throttle"));
			pusher.autoThrottle = autothrottle;
		}];
	}
}

- (void)setGlobalBrightness:(float)globalBrightness {
	if (_globalBrightness != globalBrightness) {
		_globalBrightness = globalBrightness;
		[self.pusherMap forEach:^(id key, PPPixelPusher *pusher, BOOL *stop) {
			pusher.brightness = globalBrightness;
		}];
	}
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
	uint32_t frameRateLimit = PPDeviceRegistry.sharedRegistry.frameRateLimit;
	CFTimeInterval minFrameInterval = 1.0/frameRateLimit;

	CFTimeInterval start = CACurrentMediaTime();
	// call the frame delegate to render a frame
	HLDeferred *frameRenderPromise = self.defaultFramePromise;
	id<PPFrameDelegate> strongFrameDelegate = self.frameDelegate;
	if (strongFrameDelegate) {
		// allow frame render tasks to return nil
		HLDeferred * renderPromise = [strongFrameDelegate pixelPusherRender];
		if (renderPromise) frameRenderPromise = renderPromise;
	}
	[frameRenderPromise then:^id(id result2) {
		uint32_t timesIdx = sFrameCount % frameRateLimit;
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
			CFTimeInterval delayTilNextFrame = minFrameInterval - (CACurrentMediaTime()-start);
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
				for (uint32_t idx = 0; idx < frameRateLimit; idx++) {
					sumRender += sFrameTimes[idx].render;
					sumFlush += sFrameTimes[idx].flush;
					sumThrottle += sFrameTimes[idx].throttle;
				}
				sumRender /= frameRateLimit;
				sumThrottle /= frameRateLimit;
				sumFlush /= frameRateLimit;
				CFTimeInterval idle = minFrameInterval-sumThrottle-sumRender-sumFlush;
	//			DDLogInfo(@"avg render %1.1f%%, flush %1.1f%%, send %1.1f%%, idle %1.1f%%",
	//					  sumRender/minFrameInterval*100, sumFlush/minFrameInterval*100, sumSend/minFrameInterval*100, idle/minFrameInterval*100);
				DDLogInfo(@"avg render %1.2fms, flush %1.2fms, throttle %1.3fms, idle %1.2fms",
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
		PPCard *newCard = [PPCard.alloc initWithPusher:pusher];
		if (self.isRunning) {
			[newCard start];
			newCard.extraDelay = self.extraDelay;
			newCard.record = self.record;
			pusher.autoThrottle = self.autoThrottle;
			pusher.brightness = self.globalBrightness;
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

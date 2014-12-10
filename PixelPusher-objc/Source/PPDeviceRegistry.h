//
//  PPDeviceRegistry.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PPPixel.h"
#import "PPPusherCommand.h"

extern NSString * const PPDeviceRegistryAddedPusher;
extern NSString * const PPDeviceRegistryUpdatedPusher;
extern NSString * const PPDeviceRegistryRemovedPusher;

@class HLDeferred;

@protocol PPFrameDelegate <NSObject>
@required
- (HLDeferred*)pixelPusherRender;
@end

@interface PPDeviceRegistry : NSObject

@property (nonatomic, weak) id<PPFrameDelegate> frameDelegate;
@property (nonatomic, readonly) NSDictionary *pusherMap;
@property (nonatomic, readonly) NSDictionary *groupMap;
@property (nonatomic) uint32_t frameRateLimit;
@property (nonatomic, assign) PPFloatPixel globalBrightness;
@property (nonatomic) BOOL record;

+ (PPDeviceRegistry*)sharedRegistry;

/** set an intensity output curve function.  the function will be called repeatedly with input values
	ranging from 0-1.  the function should return output values in the range from 0-1.
	the curve function may be called at any time, from non-main threads, and multiple calls
	concurrently to recompute output curves for varying output depths.  beware to ensure
	the function is thread-safe and reentrant.
 
	@example
		// set an inverse output curve
		[PPStrip setOutputCurveFunction:^float(float input) {
			return 1.0-input;
		}];
 */

- (void)setAutoThrottle:(BOOL)autothrottle;
- (int64_t)totalPower;
- (void)setTotalPowerLimit:(int64_t)powerLimit;
- (int64_t)totalPowerLimit;
- (float)powerScale;

- (void)enqueuePusherCommandInAllPushers:(PPPusherCommand*)command;

- (BOOL)scalePixelComponentsForAverageBrightnessLimit:(float)brightnessLimit	// >=1.0 for no scaling
										forEachPusher:(BOOL)forEachPusher;		// compute average for each pusher

- (NSArray*)strips;
- (NSArray*)pushers;
- (NSArray*)groups;

- (NSArray*)pushersInGroup:(int32_t)groupNumber;
- (NSArray*)stripsInGroup:(int32_t)groupNumber;

- (void)startPushing;
- (void)stopPushing;

// PPPixelPusher interface only, do not call this method
- (void)expireDevice:(NSString*)macAddr;

@end

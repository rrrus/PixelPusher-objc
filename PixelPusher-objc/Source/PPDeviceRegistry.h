//
//  PPDeviceRegistry.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//  globalBrightnessRGB added by Christopher Schardt on 7/19/14
//  scalePixelComponents stuff added by Christopher Schardt on 8/11/14
//

#import <Foundation/Foundation.h>

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
@property (nonatomic) uint32_t frameRateLimit;
@property (nonatomic, assign) float globalBrightness;
@property (nonatomic, assign) float globalBrightnessRed;
@property (nonatomic, assign) float globalBrightnessGreen;
@property (nonatomic, assign) float globalBrightnessBlue;
//@property (nonatomic, assign) float globalBrightnessLimit;	// maybe someday
@property (nonatomic) BOOL record;

+ (PPDeviceRegistry*)sharedRegistry;

- (void)setAutoThrottle:(BOOL)autothrottle;
- (int64_t)totalPower;
- (void)setTotalPowerLimit:(int64_t)powerLimit;
- (int64_t)totalPowerLimit;
- (float)powerScale;

- (BOOL)scalePixelComponentsForAverageBrightnessLimit:(float)brightnessLimit	// >=1.0 for no scaling
										forEachPusher:(BOOL)forEachPusher;		// compute average for each pusher

- (NSArray*)strips;
- (NSArray*)pushers;

- (NSArray*)pushersInGroup:(int32_t)groupNumber;
- (NSArray*)stripsInGroup:(int32_t)groupNumber;

- (void)startPushing;
- (void)stopPushing;

@end

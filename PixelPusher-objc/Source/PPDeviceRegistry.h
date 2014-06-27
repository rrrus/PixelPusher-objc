//
//  PPDeviceRegistry.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
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
@property (nonatomic) BOOL record;

+ (PPDeviceRegistry*)sharedRegistry;

- (void)setAutoThrottle:(BOOL)autothrottle;
- (int64_t)totalPower;
- (void)setTotalPowerLimit:(int64_t)powerLimit;
- (int64_t)totalPowerLimit;
- (float)powerScale;

- (NSArray*)strips;
- (NSArray*)pushers;

- (NSArray*)pushersInGroup:(int32_t)groupNumber;
- (NSArray*)stripsInGroup:(int32_t)groupNumber;

- (void)startPushing;
- (void)stopPushing;

@end

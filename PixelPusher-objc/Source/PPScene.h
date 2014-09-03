//
//  PPScene.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/31/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//  globalBrightnessRGB added by Christopher Schardt on 7/19/14
//  scalePixelComponents stuff added by Christopher Schardt on 8/11/14
//

#import <Foundation/Foundation.h>
#import "PPDeviceRegistry.h"

@class PPPixelPusher;

@interface PPScene : NSObject

@property (nonatomic, weak) id<PPFrameDelegate> frameDelegate;
@property (nonatomic, readonly) int64_t totalBandwidth;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, assign) float globalBrightness;
@property (nonatomic, assign) float globalBrightnessRed;
@property (nonatomic, assign) float globalBrightnessGreen;
@property (nonatomic, assign) float globalBrightnessBlue;
//@property (nonatomic, assign) float globalBrightnessLimit;	// maybe someday
@property (nonatomic, assign) BOOL record;

- (id)init;

- (void)removePusher:(PPPixelPusher*)pusher;

- (void)setExtraDelay:(NSTimeInterval)delay;
- (void)setAutoThrottle:(BOOL)autothrottle;

- (void)start;
- (BOOL)cancel;

- (BOOL)scalePixelComponentsForAverageBrightnessLimit:(float)brightnessLimit	// >=1.0 for no scaling
										forEachPusher:(BOOL)forEachPusher;		// compute average for each pusher

@end

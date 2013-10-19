//
//  PPScene.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/31/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PPDeviceRegistry.h"

@class PPPixelPusher;

@interface PPScene : NSObject

@property (nonatomic, weak) id<PPFrameDelegate> frameDelegate;
@property (nonatomic, readonly) int64_t totalBandwidth;
@property (nonatomic, readonly) BOOL isRunning;

- (id)init;

- (void)removePusher:(PPPixelPusher*)pusher;

- (void)setExtraDelay:(NSTimeInterval)delay;
- (void)setAutoThrottle:(BOOL)autothrottle;

- (void)start;
- (BOOL)cancel;

@end

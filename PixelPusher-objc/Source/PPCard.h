//
//  PPCard.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/31/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HLDeferred, PPPixelPusher;

@interface PPCard : NSObject

@property (nonatomic, readonly) int64_t bandwidthEstimate;
@property (nonatomic, assign) BOOL record;

- (id)initWithPusher:(PPPixelPusher*)pusher;

- (void)setExtraDelay:(NSTimeInterval)delay;
- (BOOL)controls:(PPPixelPusher*)pusher;
- (void)shutDown;
- (void)start;
- (void)cancel;
- (HLDeferred*)flush;

@end

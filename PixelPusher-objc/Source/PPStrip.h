//
//  PPStrip.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/28/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PPPixelPusher;

@interface PPStrip : NSObject

@property (nonatomic, readonly) NSMutableArray *pixels;
@property (nonatomic, assign) BOOL touched;
@property (nonatomic, assign) int32_t stripNumber;
@property (nonatomic, assign) float powerScale;

- (id)initWithStripNumber:(int32_t)stripNum pixelCount:(int32_t)pixCount;
- (uint32_t)serialize:(uint8_t*)buffer;

@end

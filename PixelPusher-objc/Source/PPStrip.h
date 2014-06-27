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
@property (nonatomic, readonly) int32_t stripNumber;
@property (nonatomic, readonly) int32_t flags;
@property (nonatomic, readonly) BOOL isWidePixel;
@property (nonatomic, assign) BOOL touched;
@property (nonatomic, assign) float powerScale;

// `pixCount` should be the PPPixelPusher's pixelsPerStrip value.  the actual number of
// pixels for the strip will be calculated and allocated appropriately based on that
// value combined with any pixel-count re-interpreteting flags.
- (id)initWithStripNumber:(int32_t)stripNum pixelCount:(int32_t)pixCount flags:(int32_t)flags;
- (uint32_t)serialize:(uint8_t*)buffer;

@end

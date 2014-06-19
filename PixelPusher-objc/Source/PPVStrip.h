//
//  PPVStrip.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 6/20/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PPPixel.h"

typedef struct {
	NSUInteger strip;
	NSUInteger pixel;
} PixelPath;

typedef struct {
	CGFloat red, green, blue;
} VPixel;

void addToPixel(VPixel *target, PPPixel *toAdd);

PixelPath PixelPathMake(NSUInteger strip, NSUInteger pixel);

@interface PPVStrip : NSObject

- (id)initWithCount:(NSUInteger)count;
- (void)setPixel:(NSUInteger)pixIndex pixelPath:(PixelPath)pixPath;

- (NSUInteger)count;
- (VPixel*)pixelAt:(NSUInteger)index;
- (void)setTouched;

@end

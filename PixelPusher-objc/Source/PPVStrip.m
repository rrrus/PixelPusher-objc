//
//  PPVStrip.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 6/20/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "PPDeviceRegistry.h"
#import "PPStrip.h"
#import "PPVStrip.h"

PixelPath PixelPathMake(NSUInteger strip, NSUInteger pixel) {
	PixelPath p = {strip, pixel};
	return p;
}

void addToPixel(VPixel *target, PPPixel *toAdd) {
	float or,og,ob;
	or = target->red + toAdd.red;
	og = target->green + toAdd.green;
	ob = target->blue + toAdd.blue;
	target->red = MIN(1, or);
	target->green = MIN(1, og);
	target->blue = MIN(1, ob);
}

@interface PPVStrip () {
	VPixel *vpixStart;
}
@property (nonatomic, strong) NSMutableData *pixelMap;
@property (nonatomic, strong) NSMutableData *pixelStore;
@property (nonatomic, assign) NSUInteger count;
@property (nonatomic, strong) NSMutableSet *stripsReferenced;
@end

@implementation PPVStrip

- (id)initWithCount:(NSUInteger)count {
	self = [self init];
	if (self) {
		self.count = count;
		uint32_t size = sizeof(PixelPath)*count;
		self.pixelMap = [NSMutableData dataWithCapacity:size];
		self.pixelMap.length = size;
		uint32_t pxsize = sizeof(VPixel)*count;
		self.pixelStore = [NSMutableData dataWithCapacity:pxsize];
		self.pixelStore.length = pxsize;
		vpixStart = self.pixelStore.mutableBytes;
		self.stripsReferenced = NSMutableSet.set;
	}
	return self;
}

- (void)setPixel:(NSUInteger)pixIndex pixelPath:(PixelPath)pixPath {
	if (pixIndex >= self.count) return;
	PixelPath *ppath = (PixelPath*)self.pixelMap.mutableBytes;
	ppath[pixIndex] = pixPath;
	[self.stripsReferenced addObject:@(pixPath.strip)];
}

- (NSUInteger)count {
	return _count;
}

- (VPixel*)pixelAt:(NSUInteger)index {
//	if (index >= self.count) return nil;
	VPixel *ret = vpixStart + index;
	return ret;
}

- (void)setTouched {
	NSArray *strips = PPDeviceRegistry.sharedRegistry.strips;
	// copy the virtual pixel store into the actual strip pixels
	PixelPath *map = self.pixelMap.mutableBytes;
	VPixel *vpx = self.pixelStore.mutableBytes;
	for (int i=0; i<self.count; i++, map++, vpx++) {
		PPPixel *p = [strips[map->strip] pixels][map->pixel];
		p.red = vpx->red;
		p.green = vpx->green;
		p.blue = vpx->blue;
	}
	// and touch the strips
	[self.stripsReferenced forEach:^(NSNumber *refNum, BOOL *stop) {
		[strips[refNum.unsignedIntValue] setTouched:YES];
	}];
}

@end

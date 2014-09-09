//
//  RRXmas.m
//  PixelMapper
//
//  Created by Rus Maxham on 12/15/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "RRXmas.h"
#import "PPPixel.h"
#import "PPStrip.h"
#import "Animator.h"

//INIT_LOG_LEVEL_INFO

@interface Twinkle : NSObject
@property (nonatomic) uint32_t idx;
@property (nonatomic, strong) Animator *anim;
@end

@implementation Twinkle : NSObject

- (id)init
{
    self = [super init];
    if (self) {
        self.anim = Animator.new;
    }
    return self;
}
@end

@interface ColorPoint : NSObject
@property (nonatomic) float hue;
@property (nonatomic) float sat;
@property (nonatomic) float pos;
@end
@implementation ColorPoint
@end

@interface RRXmas()
@property (nonatomic, strong) PPPixel* color1;
@property (nonatomic, strong) PPPixel* color2;
@property (nonatomic, strong) Animator* colorRange;
@property (nonatomic, strong) NSMutableArray* baseStrip;
@property (nonatomic, strong) NSMutableArray* twinkles;
@property (nonatomic, strong) NSMutableSet* twinkleIdxs;
@property (nonatomic, strong) NSMutableArray* colorPoints;
@property (nonatomic, strong) Animator* colorSpeed;
@property (nonatomic) float baseLuma;
@property (nonatomic) BOOL atHold;
@end

@implementation RRXmas

- (id)init
{
    self = [super init];
    if (self) {
		self.baseStrip = NSMutableArray.array;
		self.twinkleIdxs = NSMutableSet.set;
		self.twinkles = NSMutableArray.array;
		self.baseLuma = 0.7;
		self.colorRange = Animator.new;

		self.colorPoints = NSMutableArray.array;
		self.colorSpeed = Animator.new;
		[self.colorSpeed fadeTo:GLKVector4Make(1, 0, 0, 0) duration:0];
		[self nextColorSet:YES];
    }
    return self;
}

- (uint32_t)length {
	return (uint32_t)self.baseStrip.count;
}

- (void)setLength:(uint32_t)length {
	// 50% of the pixels will twinkle
	uint32_t ntwink = (uint32_t)((float)length*1);
	BOOL changed = NO;
	while(length > self.baseStrip.count) {
		[self.baseStrip addObject:PPPixel.new];
		changed = YES;
	}
	while(length < self.baseStrip.count) {
		[self.baseStrip removeLastObject];
		changed = YES;
	}
	while(ntwink > self.twinkles.count) {
		[self.twinkles addObject:Twinkle.new];
	}
	while(ntwink < self.twinkles.count) {
		Twinkle* twnkl = self.twinkles.lastObject;
		[self.twinkleIdxs removeObject:@(twnkl.idx)];
		[self.twinkles removeLastObject];
	}
	if (changed) [self redrawBase];
}

- (void)redrawBase {
//	__block float interp = 0;
//	float interpInc = 1.0f/self.baseStrip.count;
	[self.baseStrip forEach:^(PPPixel* pix, NSUInteger idx, BOOL *stop) {
#if 0
		float interpInv = 1.0f-interp;
		pix.red = self.color1.red*interpInv + self.color2.red*interp;
		pix.green = self.color1.green*interpInv + self.color2.green*interp;
		pix.blue = self.color1.blue*interpInv + self.color2.blue*interp;

		interp += interpInc;
#else
		pix.red = 0;
		pix.green = 0;
		pix.blue = 0;
#endif
	}];

}

- (void)nextColorSet:(BOOL)now {
	float sat1 = MIN(1 ,MAX(0, randRange(-0.05, 1.05)));
	float sat2 = MIN(1 ,MAX(0, randRange(-0.05, 1.05)));
	// cube the saturation to make it tend towards more desaturated
//	sat1 = sat1*sat1*sat1;
//	sat2 = sat2*sat2*sat2;
	GLKVector4 crange = GLKVector4Make(randf(2), sat1, randf(2), sat2);
	// colors transition between 1 and 5 minutes
	CFTimeInterval dur = now ? 0 : randRange(30, 3*60);
	CFTimeInterval hold = now ? 0 : randRange(30, 3*60);
	[self.colorRange fadeTo:crange duration:dur thenHoldFor:hold];
	self.atHold = NO;
	self.color1 = [PPPixel pixelWithHue:crange.x saturation:crange.y luminance:1];
	self.color2 = [PPPixel pixelWithHue:crange.z saturation:crange.w luminance:1];
}

- (void)drawInStrip:(PPStrip*)strip {
	[self drawInStrip:strip length:strip.pixelCount];
}

- (void)drawInStrip:(PPStrip*)strip length:(uint32_t)length {
	// update our pixel count
	if (length != self.baseStrip.count) {
		self.length = length;
	}
	
	// next color set
	if (self.colorRange.state == eIdle) {
		[self nextColorSet:NO];
	}
	
	[self draw1:strip];
}

- (void)draw1:(PPStrip*)strip {
	uint32_t baseLen = (uint32_t)self.baseStrip.count;
#if 0
	// reset strip to base values
	[strip.pixels forEach:^(PPPixel* dpix, NSUInteger idx, BOOL *stop) {
		if (idx >= baseLen) {
			*stop = YES;
			return;
		}
		[dpix copy:self.baseStrip[idx]];
	}];
#endif
	[self.twinkles forEach:^(Twinkle* twnkl, NSUInteger idx, BOOL *stop) {
		if (twnkl.anim.state == eIdle) {
#if 0
			[self.twinkleIdxs removeObject:@(twnkl.idx)];
			while(YES) {
				twnkl.idx = random() % self.baseStrip.count;
				id idxobj = @(twnkl.idx);
				if (![self.twinkleIdxs containsObject:idxobj]) {
					[self.twinkleIdxs addObject:idxobj];
					break;
				}
			}
#else
			twnkl.idx = (uint32_t)idx;
#endif
			[twnkl.anim fadeTo:GLKVector4Make(-1, 0, 0, 0) duration:0];
			float dur = randf(1);
			dur = dur*30;
			[twnkl.anim fadeTo:GLKVector4Make(1, 0, 0, 0) duration:dur];
			[strip setPixelAtIndex:twnkl.idx withFloatRed:0 green:0 blue:0];
		} else {
			float interp = (float)twnkl.idx / (baseLen-1);
			float interpInv = 1.0f-interp;
			// convert -1 to 1 to 0 to 1 to 0
			float lum = (1 - fabsf(twnkl.anim.value.x));
			GLKVector4 crange = self.colorRange.value;
#if 0
			// interpolate color in HSV
			float hue = fmodf(crange.x*interpInv + crange.y*interp, 1);
			float sat = crange.z*interpInv + crange.w*interp;
			UIColor* color = [UIColor colorWithHue:hue saturation:sat brightness:lum alpha:1];
			[((PPPixel*)strip.pixels[twnkl.idx]) setColor:color];
#else
			if (self.colorRange.state == eFading || !self.atHold) {
				self.color1 = [PPPixel pixelWithHue:crange.x saturation:crange.y luminance:1];
				self.color2 = [PPPixel pixelWithHue:crange.z saturation:crange.w luminance:1];
				self.atHold = (self.colorRange.state != eFading);
			}
			
			// interpolate color in RGB
			[strip setPixelAtIndex:twnkl.idx
					  withFloatRed:(self.color1.red*interpInv + self.color2.red*interp)*lum
							 green:(self.color1.green*interpInv + self.color2.green*interp)*lum
							  blue:(self.color1.blue*interpInv + self.color2.blue*interp)*lum];
#endif
		}
	}];
}

@end


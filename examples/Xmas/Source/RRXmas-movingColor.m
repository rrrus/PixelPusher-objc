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

INIT_LOG_LEVEL_INFO

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
- (id)init
{
    self = [super init];
    if (self) {
        self.hue = randf(1);
		float sat = randf(1);
		// ^5 sat to make it tend towards less saturated
		sat = sat*sat*sat*sat*sat;
		self.sat = sat;
    }
    return self;
}
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
@property (nonatomic) float colorPos;
@property (nonatomic) CFTimeInterval lastFrame;
@property (nonatomic) float baseLuma;
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

-(uint32_t)length {
	return self.baseStrip.count;
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
	float sat1 = randf(1);
	float sat2 = randf(1);
	// ^5 the saturation to make it tend towards more desaturated
	sat1 = sat1*sat1*sat1*sat1*sat1;
	sat2 = sat2*sat2*sat2*sat2*sat2;
	GLKVector4 crange = GLKVector4Make(randf(1), sat1, randf(1), sat2);
	// colors transition between 1 and 5 minutes
	CFTimeInterval dur = now ? 0 : randRange(60, 5*60);
	CFTimeInterval hold = now ? 0 : randRange(60, 5*60);
	[self.colorRange fadeTo:crange duration:dur thenHoldFor:hold];
	self.color1 = [PPPixel pixelWithHue:crange.x saturation:crange.y luminance:self.baseLuma];
	self.color2 = [PPPixel pixelWithHue:crange.z saturation:crange.w luminance:self.baseLuma];
}

- (void)updateColorPoints {
	
	// ensure there's a color point before the beginning
	while(YES) {
		ColorPoint* cp = self.colorPoints.firstObject;
		if (!cp || cp.pos+self.colorPos > 0) {
			float oldPos = cp.pos;
			cp = ColorPoint.new;
			// color points are between 10% and 500% of strip length between each other
			cp.pos = oldPos - randRange(0.1, 5);
			[self.colorPoints insertObject:cp atIndex:0];
			DDLogInfo(@"prepending color %f %f %f", cp.hue, cp.sat, cp.pos);
		} else {
			break;
		}
	}

	// ensure there's a color point after the end
	while(YES) {
		ColorPoint* cp = self.colorPoints.lastObject;
		if (cp.pos+self.colorPos < 1) {
			float oldPos = cp.pos;
			cp = ColorPoint.new;
			// color points are between 10% and 500% of strip length between each other
			cp.pos = oldPos + randRange(0.1, 5);
			[self.colorPoints addObject:cp];
			DDLogInfo(@"appending color %f %f %f", cp.hue, cp.sat, cp.pos);
		} else {
			break;
		}
	}

	// trim dead color points from before the beginning
	while (YES) {
		ColorPoint* cp = self.colorPoints[1];
		if (cp.pos+self.colorPos < 0) {
			[self.colorPoints removeObjectAtIndex:0];
		} else {
			break;
		}
	}

	// trim dead color points from after the end
	while (YES) {
		ColorPoint* cp = self.colorPoints[self.colorPoints.count-2];
		if (cp.pos+self.colorPos < 0) {
			[self.colorPoints removeLastObject];
		} else {
			break;
		}
	}
}

- (void)drawInStrip:(PPStrip*)strip {
	[self drawInStrip:strip length:strip.pixels.count];
}

- (void)drawInStrip:(PPStrip*)strip length:(uint32_t)length {
	// update our pixel count
	if (length != self.baseStrip.count) {
		self.length = length;
	}

	// update frame time based values
	CFTimeInterval thisFrame = CACurrentMediaTime();
	float frameInterval = (float)(thisFrame - self.lastFrame);
	self.lastFrame = thisFrame;
	self.colorPos += self.colorSpeed.value.x * frameInterval;
	
	// next color set
	if (self.colorRange.state == eIdle) {
		[self nextColorSet:NO];
	}

	[self updateColorPoints];
	
	[self draw1:strip];
}

- (void)draw1:(PPStrip*)strip {
	uint32_t baseLen = self.baseStrip.count;
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
	
	__block ColorPoint* cp1 = self.colorPoints[0];
	__block ColorPoint* cp2 = self.colorPoints[1];
	__block uint32_t cpidx = 1;
	__block float cp1p = cp1.pos+self.colorPos;
	__block float cp2p = cp2.pos+self.colorPos;

	[self.twinkles forEach:^(Twinkle* twnkl, NSUInteger idx, BOOL *stop) {
		float idxp = (float)twnkl.idx/(float)(baseLen-1);
		while (idxp > cp2p) {
			cpidx++;
			cp1 = cp2;
			cp1p = cp2p;
			cp2 = self.colorPoints[cpidx];
			cp2p = cp2.pos+self.colorPos;
		}
		
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
			twnkl.idx = idx;
#endif
			[twnkl.anim fadeTo:GLKVector4Make(-1, 0, 0, 0) duration:0];
			float dur = randf(1);
			dur = dur*30;
			[twnkl.anim fadeTo:GLKVector4Make(1, 0, 0, 0) duration:dur];
			[((PPPixel*)strip.pixels[twnkl.idx]) setColor:UIColor.blackColor];
		} else {
			float interpInv = 1.0f-interp;
			GLKVector4 crange = self.colorRange.value;
			float hue = crange.x*interpInv + crange.y*interp;
			float sat = crange.z*interpInv + crange.w*interp;
#if 0
			// convert -1 to 1 to 0 to 1 to 0
			float amt = (1 - fabsf(twnkl.anim.value.x) );
			float lum = self.baseLuma + (1-self.baseLuma)*amt;
#else
			float lum = (1 - fabsf(twnkl.anim.value.x));
#endif
			UIColor* color = [UIColor colorWithHue:hue saturation:sat brightness:lum alpha:1];
			[((PPPixel*)strip.pixels[twnkl.idx]) setColor:color];
		}
	}];
}

@end


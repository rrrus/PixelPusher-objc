//
//  RRComet.m
//  PixelMapper
//
//  Created by Rus Maxham on 6/1/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "RRComet.h"
#import "PPPixel.h"
#import "PPStrip.h"

@implementation RRComet

- (id)init
{
    self = [super init];
    if (self) {
		self.startTime = CACurrentMediaTime();
		self.tailLength = (random()%20)/10.0+1;
		while (fabsf(self.speed) < 4) {
			self.speed = (random()%600-300)/10.0;
		}
		if (self.speed > 0)	self.startPosition = 0;
		else				self.startPosition = 240;
		self.speedVariance = 0.2;
		self.speedVariancePeriod = (random()%400)/10.0;
		self.color = [PPPixel pixelWithHue:(random()%200)/200.0 saturation:1 luminance:1];
    }
    return self;
}

- (float)headPosition {
	CFTimeInterval now = CACurrentMediaTime();
	float speedNow = self.speed * (1 + sin(now/self.speedVariancePeriod*M_2_PI) * self.speedVariance);
	double interval = now - self.startTime;
	return self.startPosition + speedNow*interval;
}

- (float)tailPosition {
	CFTimeInterval now = CACurrentMediaTime();
	float speedNow = self.speed * (1 + sin(now/self.speedVariancePeriod*M_2_PI) * self.speedVariance);
	double interval = now - self.startTime - self.tailLength;
	return self.startPosition + speedNow*interval;
}

- (BOOL)drawInStrip:(PPStrip*)strip {
	NSAssert(strip.bufferCompType == ePPCompTypeFloat, @"buffer must have float pixels");
	NSAssert(strip.bufferPixType == ePPPixTypeRGB, @"buffer must be RGB");
	NSAssert(strip.bufferPixStride == sizeof(PPFloatPixel), @"buffer stride must be packed float pixel");
	
	float head = self.headPosition;
	float tail = self.tailPosition;
	if (head < 0 && tail < 0) return NO;
	uint32_t pixcount = strip.pixelCount;
	if (head > pixcount && tail > pixcount) return NO;
	
	int start, end, lead;
	float leadfrac = fmodf(head, 1);
	if (self.speed > 0) {
		end = MIN(pixcount-1, floorf(head));
		start = MAX(0, ceilf(tail));
		lead = end+1;
	} else {
		end = MIN(pixcount-1, floorf(tail));
		start = MAX(0, ceilf(head));
		lead = start-1;
		leadfrac = 1-leadfrac;
	}
	float range = head-tail;
	PPFloatPixel *pixels = (PPFloatPixel*)strip.buffer;
	for (int i=start; i<=end; i++) {
		float lum = ((float)i - tail)/range;
#if 1
		float red = self.color.red * lum;
		float green = self.color.green * lum;
		float blue = self.color.blue * lum;
		addToFloatPixel(pixels+i, red, green, blue);
#else
		uint8_t red = self.color.red * lum * 255.0f;
		uint8_t green = self.color.green * lum * 255.0f;
		uint8_t blue = self.color.blue * lum * 255.0f;
		addToBytePixel(pixels+i, red, green, blue);
#endif
	}
	if (lead >= 0 && lead < pixcount) {
#if 1
		float red = self.color.red * leadfrac;
		float green = self.color.green * leadfrac;
		float blue = self.color.blue * leadfrac;
		addToFloatPixel(pixels+lead, red, green, blue);
#else
		uint8_t red = self.color.red * leadfrac * 255.0f;
		uint8_t green = self.color.green * leadfrac * 255.0f;
		uint8_t blue = self.color.blue * leadfrac * 255.0f;
		addToBytePixel(pixels+lead, red, green, blue);
#endif
	}
	return YES;
}

@end


//
//  PPStrip.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/28/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "PPPixel.h"
#import "PPPixelPusher.h"
#import "PPStrip.h"

static CurveFunction gOutputCurveFunction;
static const uint8_t * gOutputLUT8 = nil;
static uint16_t* gOutputLUT16 = nil;

const CurveFunction sCurveLinearFunction =  ^float(float input) {
	return input;
};

const CurveFunction sCurveAntilogFunction =  ^float(float input) {
	// input range 0-1, output range 0-1
	return (powf(2, 8*input)-1)/255;
};

@interface PPStrip ()
@property (nonatomic, assign) uint32_t pixelCount;
@property (nonatomic, assign) int32_t stripNumber;
@property (nonatomic, assign) int32_t flags;
@end

@implementation PPStrip

+ (void)setOutputCurveFunction:(CurveFunction)curveFunction {
	if (gOutputCurveFunction != curveFunction) {
		gOutputCurveFunction = [curveFunction copy];
		// only rebuild if they already exist
		if (gOutputLUT8) [PPStrip buildOutputCurve:8];
		if (gOutputLUT16) [PPStrip buildOutputCurve:16];
	}
}

+ (void)buildOutputCurve:(int)depth {
	if (!gOutputCurveFunction) gOutputCurveFunction = sCurveAntilogFunction;

	if (depth == 16) {
		if (gOutputLUT8) free((void*)gOutputLUT8);
		gOutputLUT8 = nil;
	} else {
		if (gOutputLUT8) free((void*)gOutputLUT8);
		gOutputLUT8 = nil;
	}
	
	// special case linear output function
	if (!gOutputCurveFunction || gOutputCurveFunction == sCurveLinearFunction) {
		// give the LUTs a non-nil value so we can check to see if they're in use
		if (depth == 16) {
			gOutputLUT16 = malloc(1);
		} else {
			gOutputLUT8 = malloc(1);
		}
		return;
	}
	
	if (depth == 16) {
		uint16_t *outputLUT16 = malloc(65536);
		gOutputLUT16 = outputLUT16;
		for (int i=0; i<65536; i++) {
			outputLUT16[i] = (uint16_t)( lroundf( 65535.0f * gOutputCurveFunction(i/65535.0f) ) );
		}
	} else {
		uint8_t *outputLUT8 = malloc(256);
		gOutputLUT8 = outputLUT8;
		for (int i=0; i<256; i++) {
			outputLUT8[i] = (uint8_t)( lroundf( 255.0f * gOutputCurveFunction(i/255.0f) ) );
		}
	}
}

- (id)initWithStripNumber:(int32_t)stripNum pixelCount:(int32_t)pixCount flags:(int32_t)flags{
	self = [self init];
	if (self) {
		self.stripNumber = stripNum;
		self.flags = flags;
		self.touched = YES;
		self.powerScale = 1.0;
		self.brightness = 1.0;

		if (self.flags & SFLAG_WIDEPIXELS) {
			pixCount = (pixCount+1)/2;
			if (!gOutputLUT16) [PPStrip buildOutputCurve:16];
		} else {
			if (!gOutputLUT8) [PPStrip buildOutputCurve:8];
		}

		self.pixelCount = pixCount;
		_pixels = [NSMutableArray arrayWithCapacity:pixCount];
		for (int i = 0; i < self.pixelCount; i++) {
			[_pixels addObject:[PPPixel pixelWithRed:0 green:0 blue:0]];
		}
	}
	return self;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@ (%d%@)", super.description, self.stripNumber, self.touched?@" dirty":@""];
}

- (BOOL)isWidePixel {
	return (self.flags & SFLAG_WIDEPIXELS);
}

- (void)setPixels:(NSArray *)pixels {
	[self.pixels setArray:pixels];
	self.touched = YES;
}

- (uint32_t)serialize:(uint8_t*)buffer {
//	BOOL phase = YES;
//	if (isRGBOW) {
//		for (Pixel pixel : pixels) {
//			if (pixel == null)
//				pixel = new Pixel();
//
//			if (phase) {
//				msg[i++] = (byte) (((double)pixel.red)   * powerScale);    // C
//				msg[i++] = (byte) (((double)pixel.green) * powerScale);
//				msg[i++] = (byte) (((double)pixel.blue)  * powerScale);
//
//				msg[i++] = (byte) (((double)pixel.orange) * powerScale);   // O
//				msg[i++] = (byte) (((double)pixel.orange) * powerScale);
//				msg[i++] = (byte) (((double)pixel.orange) * powerScale);
//
//				msg[i++] = (byte) (((double)pixel.white) * powerScale);    // W
//				msg[i++] = (byte) (((double)pixel.white) * powerScale);
//				msg[i++] = (byte) (((double)pixel.white) * powerScale);
//			} else {
//				msg[i++] = (byte) (((double)pixel.red)   * powerScale);    // C
//				msg[i++] = (byte) (((double)pixel.green) * powerScale);
//				msg[i++] = (byte) (((double)pixel.blue)  * powerScale);
//
//				msg[i++] = (byte) (((double)pixel.white) * powerScale);    // W
//				msg[i++] = (byte) (((double)pixel.white) * powerScale);
//				msg[i++] = (byte) (((double)pixel.white) * powerScale);
//
//				msg[i++] = (byte) (((double)pixel.orange) * powerScale);   // O
//				msg[i++] = (byte) (((double)pixel.orange) * powerScale);
//				msg[i++] = (byte) (((double)pixel.orange) * powerScale);
//			}
//			phase = !phase;
//		}
//	} else {

	// convert brightness plus powerScale to 16-bit binary fraction
	uint32_t iPostLutScale = (uint32_t)(self.brightness * self.powerScale * 65536);
	__block uint8_t *P = buffer;
	
	// TODO: optimization opportunity -- use a for loop and a standard C-array
	// and possibly a real pixmap for the source
	
	if (self.flags & SFLAG_WIDEPIXELS) {
		if (gOutputCurveFunction != sCurveLinearFunction) {
			[self.pixels forEach:^(PPPixel *pixel, NSUInteger idx, BOOL *stop) {
				uint16_t wide;
				wide = (uint16_t)(gOutputLUT16[(uint16_t) (pixel.red * 65535)] * iPostLutScale / 65536);
				*P = (wide & 0xf0) >> 8;
				*(P+3) = (wide & 0x0f);
				P++;
				wide = (uint16_t)(gOutputLUT16[(uint16_t) (pixel.green * 65535)] * iPostLutScale / 65536);
				*P = (wide & 0xf0) >> 8;
				*(P+3) = (wide & 0x0f);
				P++;
				wide = (uint16_t)(gOutputLUT16[(uint16_t) (pixel.blue * 65535)] * iPostLutScale / 65536);
				*P = (wide & 0xf0) >> 8;
				*(P+3) = (wide & 0x0f);
				P += 4; // skip the next 3 bytes we already filled in
			}];
		} else {
			// since we're skipping the multiply of the pixel channel's float to full range short (65535)
			// we need to adjust iPostLutScale so full scale is 65535, not 65536.
			// since it is close enough, we'll just subtract 1 if iPostLutScale > 0
			if (iPostLutScale > 0) iPostLutScale--;
			[self.pixels forEach:^(PPPixel *pixel, NSUInteger idx, BOOL *stop) {
				uint16_t wide;
				wide = (uint16_t) (pixel.red * iPostLutScale);
				*P = (wide & 0xf0) >> 8;
				*(P+3) = (wide & 0x0f);
				P++;
				wide = (uint16_t) (pixel.green * iPostLutScale);
				*P = (wide & 0xf0) >> 8;
				*(P+3) = (wide & 0x0f);
				P++;
				wide = (uint16_t) (pixel.blue * iPostLutScale);
				*P = (wide & 0xf0) >> 8;
				*(P+3) = (wide & 0x0f);
				P += 4; // skip the next 3 bytes we already filled in
			}];
		}
	} else {
		if (gOutputCurveFunction != sCurveLinearFunction) {
			[self.pixels forEach:^(PPPixel *pixel, NSUInteger idx, BOOL *stop) {
				*(P++) = (uint8_t)(gOutputLUT8[(uint8_t) (pixel.red * 255)] * iPostLutScale / 65536);
				*(P++) = (uint8_t)(gOutputLUT8[(uint8_t) (pixel.green * 255)] * iPostLutScale / 65536);
				*(P++) = (uint8_t)(gOutputLUT8[(uint8_t) (pixel.blue * 255)] * iPostLutScale / 65536);
			}];
		} else {
			// since we're skipping the multiply of the pixel channel's float to full range byte (255)
			// we need to scale iPostLutScale to the range 0-65280 (255*256) so that the final /256
			// will render values in the range 0-255 instead of 0-256
			iPostLutScale = iPostLutScale * 255 / 256;
			[self.pixels forEach:^(PPPixel *pixel, NSUInteger idx, BOOL *stop) {
				*(P++) = (uint8_t)( (uint32_t) (pixel.red * iPostLutScale) / 256);
				*(P++) = (uint8_t)( (uint32_t) (pixel.green * iPostLutScale) / 256);
				*(P++) = (uint8_t)( (uint32_t) (pixel.blue * iPostLutScale) / 256);
			}];
		}
	}
	
    self.touched = NO;
	return (uint32_t)self.pixels.count*3;
}


@end

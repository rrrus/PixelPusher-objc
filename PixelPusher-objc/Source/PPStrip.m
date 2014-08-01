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
static const uint8_t*  gOutputLUT8 = nil;
static const uint16_t* gOutputLUT10 = nil;
static const uint16_t* gOutputLUT16 = nil;
static const uint8_t* gDiv3LUT = nil;

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
		if (gOutputLUT16) free((void*)gOutputLUT16);
		gOutputLUT16 = nil;
	} else if (depth == 10) {
		if (gOutputLUT10) free((void*)gOutputLUT10);
		gOutputLUT10 = nil;
	} else {
		if (gOutputLUT8) free((void*)gOutputLUT8);
		gOutputLUT8 = nil;
	}
	
	// special case linear output function
	if (!gOutputCurveFunction || gOutputCurveFunction == sCurveLinearFunction) {
		// give the LUTs a non-nil value so we can check to see if they're in use
		if (depth == 16) {
			gOutputLUT16 = malloc(2);
		} else if (depth == 10) {
			gOutputLUT10 = malloc(2);
		} else {
			gOutputLUT8 = malloc(1);
		}
		return;
	}
	
	if (depth == 16) {
		uint16_t *outputLUT16 = malloc(65536*sizeof(uint16_t));
		gOutputLUT16 = outputLUT16;
		for (int i=0; i<65536; i++) {
			outputLUT16[i] = (uint16_t)( lroundf( 65535.0f * gOutputCurveFunction(i/65535.0f) ) );
		}
	} else if (depth == 10) {
		// actually ~9.585 bits deep or 256*3
		uint16_t *outputLUT10 = malloc(768*sizeof(uint16_t));
		gOutputLUT10 = outputLUT10;
		for (int i=0; i<768; i++) {
			outputLUT10[i] = (uint16_t)( lroundf( 767.0f * gOutputCurveFunction(i/767.0f) ) );
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
			if (!gOutputLUT16) [PPStrip buildOutputCurve:16];
			pixCount = (pixCount+1)/2;
		} else {
			if (self.isRGBOWPixel) {
				pixCount = (pixCount+2)/3;
				// need a 0-767 output curve table
				if (!gOutputLUT10) [PPStrip buildOutputCurve:10];
				// and a divide by 3 table to bring it back to 0-255
				if (!gDiv3LUT) {
					uint8_t *div3LUT = malloc(768);
					gDiv3LUT = div3LUT;
					for (int i=0; i<768; i++) div3LUT[i] = (uint8_t)(i/3);
				}
			} else {
				if (!gOutputLUT8) [PPStrip buildOutputCurve:8];
			}
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

- (BOOL)isRGBOWPixel {
	return NO;//(self.stripNumber == 0);
}

- (void)setPixels:(NSArray *)pixels {
	[self.pixels setArray:pixels];
	self.touched = YES;
}

- (uint32_t)serialize:(uint8_t*)buffer {
	
/*
 
	dumb color transformation from RGB to RGBOW:
		W = MIN(R,G,B)
		R -= W
		G -= W
		B -= W
	( orange is R = O, G = 0.5*O )
		O = MIN(2*G, R)
		R -= O
		G -= O/2

	orange and white LEDs actually have 3 LEDs in each of the same color.  we can drive all three
	at different intensities to get higher precision brightness out of them.
 
 */

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
	} else if (self.isRGBOWPixel) {
		// experimenting revealed the orange LED is about r=1, g=0.9 to achieve the same hue,
		// tho the orange LED is more saturated, which is the goal
		static const uint16_t orangeGreen = 922;
		static const uint16_t orangeGreenInv = 1138;
		if (gOutputCurveFunction != sCurveLinearFunction) {
			[self.pixels forEach:^(PPPixel *pixel, NSUInteger idx, BOOL *stop) {
				// crude extraction of white and orange from RGB
				uint16_t R = (uint16_t)(gOutputLUT10[(uint16_t) (pixel.red * 767)] * iPostLutScale / 65536);
				uint16_t G = (uint16_t)(gOutputLUT10[(uint16_t) (pixel.green * 767)] * iPostLutScale / 65536);
				uint16_t B = (uint16_t)(gOutputLUT10[(uint16_t) (pixel.blue * 767)] * iPostLutScale / 65536);
				uint16_t W = MIN( MIN(R, G), B);
				R -= W; G -= W; B -= W;
				uint16_t O = MIN( R, G*orangeGreenInv/1024 );
				R -= O;
				G -= O*orangeGreen/1024;
				
				*(P++) = gDiv3LUT[R];
				*(P++) = gDiv3LUT[G];
				*(P++) = gDiv3LUT[B];

//				uint8_t T = (uint8_t)(gOutputLUT8[(uint8_t) (O * 255)] * iPostLutScale / 65536);
				*(P++) = gDiv3LUT[O];
				if (O<767) O++;
				*(P++) = gDiv3LUT[O];
				if (O<767) O++;
				*(P++) = gDiv3LUT[O];

//				T = (uint8_t)(gOutputLUT8[(uint8_t) (W * 255)] * iPostLutScale / 65536);
				*(P++) = gDiv3LUT[W];
				if (W<767) W++;
				*(P++) = gDiv3LUT[W];
				if (W<767) W++;
				*(P++) = gDiv3LUT[W];
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
	return (uint32_t)(P-buffer);
}


@end

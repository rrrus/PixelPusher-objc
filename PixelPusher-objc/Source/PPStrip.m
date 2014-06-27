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

// linear input, exponential output to map to the eye's log sensitivity
static const uint8_t sLinearExp8[] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 11, 12, 12, 12, 13, 13, 13, 14, 14, 14, 14, 15, 15, 16, 16, 16, 17, 17, 17, 18, 18, 19, 19, 20, 20, 20, 21, 21, 22, 22, 23, 23, 24, 25, 25, 26, 26, 27, 27, 28, 29, 29, 30, 31, 31, 32, 33, 34, 34, 35, 36, 37, 38, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 54, 55, 56, 57, 59, 60, 61, 63, 64, 65, 67, 68, 70, 72, 73, 75, 76, 78, 80, 82, 83, 85, 87, 89, 91, 93, 95, 97, 99, 102, 104, 106, 109, 111, 114, 116, 119, 121, 124, 127, 129, 132, 135, 138, 141, 144, 148, 151, 154, 158, 161, 165, 168, 172, 176, 180, 184, 188, 192, 196, 201, 205, 209, 214, 219, 224, 229, 234, 239, 244, 249, 255, };

@interface PPStrip ()
@property (nonatomic, assign) uint32_t pixelCount;
@property (nonatomic, assign) int32_t stripNumber;
@property (nonatomic, assign) int32_t flags;
@end

@implementation PPStrip

- (id)initWithStripNumber:(int32_t)stripNum pixelCount:(int32_t)pixCount flags:(int32_t)flags{
	self = [self init];
	if (self) {
		self.stripNumber = stripNum;
		self.flags = flags;
		self.touched = YES;
		self.powerScale = 1.0;

		if (self.flags & SFLAG_WIDEPIXELS) pixCount = (pixCount+1)/2;

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

	__block uint8_t *P = buffer;

	// TODO: optimization opportunity -- use a for loop and a standard C-array
	// and possibly a real pixmap for the source
	if (self.flags & SFLAG_WIDEPIXELS) {
		[self.pixels forEach:^(PPPixel *pixel, NSUInteger idx, BOOL *stop) {
			// TODO: 16-bit anti log table
			uint16_t wide;
			wide = (uint16_t) (pixel.red * self.powerScale * 65535);
			*P = (wide & 0xf0) >> 8;
			*(P+3) = (wide & 0x0f);
			P++;
			wide = (uint16_t) (pixel.green * self.powerScale * 65535);
			*P = (wide & 0xf0) >> 8;
			*(P+3) = (wide & 0x0f);
			P++;
			wide = (uint16_t) (pixel.blue * self.powerScale * 65535);
			*P = (wide & 0xf0) >> 8;
			*(P+3) = (wide & 0x0f);
			P += 4; // skip the next 3 bytes we already filled in
		}];
	} else {
		[self.pixels forEach:^(PPPixel *pixel, NSUInteger idx, BOOL *stop) {
			// linearize perceived LED brightness by putting input values through
			// an inverse log LUT
			*(P++) = sLinearExp8[(uint8_t) (pixel.red * self.powerScale * 255)];
			*(P++) = sLinearExp8[(uint8_t) (pixel.green * self.powerScale * 255)];
			*(P++) = sLinearExp8[(uint8_t) (pixel.blue * self.powerScale * 255)];

			// linear:
	//		*(P++) = (uint8_t) (pixel.red * self.powerScale * 255);
	//		*(P++) = (uint8_t) (pixel.green * self.powerScale * 255);
	//		*(P++) = (uint8_t) (pixel.blue * self.powerScale * 255);
		}];
	}
	
    self.touched = NO;
	return (uint32_t)self.pixels.count*3;
}


@end

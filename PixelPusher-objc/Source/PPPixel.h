//
//  PPPixel.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <UIKit/UIKit.h>

@class UIColor;

typedef struct __attribute__((packed)) {
	uint8_t red;
	uint8_t green;
	uint8_t blue;
} PPBytePixel;

typedef struct __attribute__((packed)) {
	uint16_t red;
	uint16_t green;
	uint16_t blue;
} PPShortPixel;

typedef struct {
	float red;
	float green;
	float blue;
} PPFloatPixel;

extern PPFloatPixel PPFloatPixelMake(float red, float green, float blue);
extern BOOL PPFloatPixelEqual(PPFloatPixel a, PPFloatPixel b);

/*
void PPAddToFloatPixel(PPFloatPixel *pix, float red, float green, float blue);
void PPAddToBytePixel(PPBytePixel *pix, uint8_t red, uint8_t green, uint8_t blue);

@interface PPPixel : NSObject

@property (nonatomic, assign) CGFloat red;
@property (nonatomic, assign) CGFloat green;
@property (nonatomic, assign) CGFloat blue;

+ (PPPixel*)pixelWithHue:(CGFloat)hue saturation:(CGFloat)sat luminance:(CGFloat)lum;
+ (PPPixel*)pixelWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b;

- (PPPixel*)pixelScalingLuminance:(CGFloat)scale;
- (void)scaleLuminance:(CGFloat)scale;
- (void)addPixel:(PPPixel*)other;
- (void)copy:(PPPixel*)other;
- (void)setColor:(UIColor*)color;

@end
*/
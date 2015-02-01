//
//  PPPixel.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//


#import "PPPixel.h"
#import "PPPrivate.h"


PPFloatPixel PPFloatPixelMake(float red, float green, float blue)
{
	PPFloatPixel pix = {.red = red, .green = green, .blue = blue};
	return pix;
}
BOOL PPFloatPixelEqual(PPFloatPixel a, PPFloatPixel b)
{
	return (a.red == b.red && a.green == b.green && a.blue == b.blue);
}
	
/*

void PPAddToBytePixel(PPBytePixel *pix, uint8_t red, uint8_t green, uint8_t blue) {
	uint8_t or,og,ob;
	or = pix->red + red;
	og = pix->green + green;
	ob = pix->blue + blue;
	pix->red = (uint8_t)MIN(255, or);
	pix->green = (uint8_t)MIN(255, og);
	pix->blue = (uint8_t)MIN(255, ob);
}

void PPAddToFloatPixel(PPFloatPixel *pix, float red, float green, float blue) {
	float or,og,ob;
	or = pix->red + red;
	og = pix->green + green;
	ob = pix->blue + blue;
	pix->red = MIN(1, or);
	pix->green = MIN(1, og);
	pix->blue = MIN(1, ob);
}

@interface PPPixel ()
@end

@implementation PPPixel

+ (PPPixel*)pixelWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b {
	return [PPPixel.alloc initWithRed:r green:g blue:b];
}

+ (PPPixel*)pixelWithHue:(CGFloat)hue saturation:(CGFloat)sat luminance:(CGFloat)lum {
	UIColor *color = [UIColor colorWithHue:hue saturation:sat brightness:lum alpha:1];
	CGFloat r,g,b,a;
	[color getRed:&r green:&g blue:&b alpha:&a];
	return [PPPixel pixelWithRed:r green:g blue:b];
}

- (id)copyWithZone:(NSZone *)zone {
	PPPixel *copy = [self.class allocWithZone:zone];
	copy.red = self.red;
	copy.green = self.green;
	copy.blue = self.blue;
	return copy;
}

- (id)initWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b {
	self = [self init];
	if (self) {
		self.red = r;
		self.green = g;
		self.blue = b;
	}
	return self;
}

- (PPPixel*)pixelScalingLuminance:(CGFloat)scale {
	return [PPPixel.alloc initWithRed:self.red*scale green:self.green*scale blue:self.blue*scale];
}

- (void)scaleLuminance:(CGFloat)scale {
	_red *= scale;
	_green *= scale;
	_blue *= scale;
}

- (void)addPixel:(PPPixel*)other {
	CGFloat or,og,ob;
	or = self.red + other.red;
	og = self.green + other.green;
	ob = self.blue + other.blue;
	self.red = MIN(1, or);
	self.green = MIN(1, og);
	self.blue = MIN(1, ob);
}

- (void)copy:(PPPixel*)other {
	self.red = other.red;
	self.green = other.green;
	self.blue = other.blue;
}

-(void)setColor:(UIColor *)color {
	CGFloat a;
	[color getRed:&_red green:&_green blue:&_blue alpha:&a];
}

@end

*/
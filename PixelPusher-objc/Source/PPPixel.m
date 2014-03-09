//
//  PPPixel.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "PPPixel.h"
#import <UIKit/UIKit.h>

@interface PPPixel ()
@end

@implementation PPPixel

+ (PPPixel*)pixelWithRed:(float)r green:(float)g blue:(float)b {
	return [PPPixel.alloc initWithRed:r green:g blue:b];
}

+ (PPPixel*)pixelWithHue:(float)hue saturation:(float)sat luminance:(float)lum {
	UIColor *color = [UIColor colorWithHue:hue saturation:sat brightness:lum alpha:1];
	float r,g,b,a;
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

- (id)initWithRed:(float)r green:(float)g blue:(float)b {
	self = [self init];
	if (self) {
		self.red = r;
		self.green = g;
		self.blue = b;
	}
	return self;
}

- (PPPixel*)pixelScalingLuminance:(float)scale {
	return [PPPixel.alloc initWithRed:self.red*scale green:self.green*scale blue:self.blue*scale];
}

- (void)scaleLuminance:(float)scale {
	_red *= scale;
	_green *= scale;
	_blue *= scale;
}

- (void)addPixel:(PPPixel*)other {
	float or,og,ob;
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
	float a;
	[color getRed:&_red green:&_green blue:&_blue alpha:&a];
}

@end

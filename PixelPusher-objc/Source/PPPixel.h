//
//  PPPixel.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <UIKit/UIKit.h>

@class UIColor;

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

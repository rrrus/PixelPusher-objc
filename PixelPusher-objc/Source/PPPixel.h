//
//  PPPixel.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PPPixel : NSObject

@property (nonatomic, assign) float red;
@property (nonatomic, assign) float green;
@property (nonatomic, assign) float blue;

+ (PPPixel*)pixelWithHue:(float)hue saturation:(float)sat luminance:(float)lum;
+ (PPPixel*)pixelWithRed:(float)r green:(float)g blue:(float)b;

- (PPPixel*)pixelScalingLuminance:(float)scale;
- (void)addPixel:(PPPixel*)other;
- (void)copy:(PPPixel*)other;

@end

//
//  UIImage+RRR.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 8/18/14.
//  Copyright (c) 2014 rrrus. All rights reserved.
//

#import "UIImage+RRR.h"

@implementation UIImage (RRR)

+ (UIImage*)imageWithColor:(UIColor*)color size:(CGSize)size {
	// create a new bitmap image context
	UIGraphicsBeginImageContext(size);
	[color setFill];
	[color set];
	CGRect rc;
	rc.size = size;
	UIRectFill(rc);
	// get a UIImage from the image context- enjoy!!!
	UIImage *outputImage = UIGraphicsGetImageFromCurrentImageContext();
	// clean up drawing environment
	UIGraphicsEndImageContext();
	return outputImage;
}

+ (UIImage*)resizableImageWithColor:(UIColor *)color size:(CGSize)size capInsets:(UIEdgeInsets)insets {
	return nil;
}

@end

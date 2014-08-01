//
//  PPStrip.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/28/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef float (^CurveFunction)(float input);

/// pre-fab output linear curve function
extern const CurveFunction sCurveLinearFunction;
/// pre-fab output antilog curve function
extern const CurveFunction sCurveAntilogFunction;

@class PPPixelPusher;

@interface PPStrip : NSObject

@property (nonatomic, readonly) NSMutableArray *pixels;
@property (nonatomic, readonly) int32_t stripNumber;
@property (nonatomic, readonly) int32_t flags;
@property (nonatomic, readonly) BOOL isWidePixel;
@property (nonatomic, readonly) BOOL isRGBOWPixel;
@property (nonatomic, assign) BOOL touched;
@property (nonatomic, assign) float powerScale;
@property (nonatomic, assign) float brightness;

/** set an intensity output curve function.  the function will be called repeatedly with input values
	ranging from 0-1.  the function should return output values in the range from 0-1.
	the curve function may be called at any time, from non-main threads, and multiple calls
	concurrently to recompute output curves for varying output depths.  beware to ensure
	the function is thread-safe and reentrant.
 
	@example
		//  set an inverse output curve
		[PPStrip setOutputCurveFunction:^float(float input) {
			return 1.0-input;
		}];
*/
+ (void)setOutputCurveFunction:(CurveFunction)curveFunction;

/** `pixCount` should be the PPPixelPusher's pixelsPerStrip value.  the actual number of
	pixels for the strip will be calculated and allocated appropriately based on that
	value combined with any pixel-count re-interpreteting flags.
*/
- (id)initWithStripNumber:(int32_t)stripNum pixelCount:(int32_t)pixCount flags:(int32_t)flags;
- (uint32_t)serialize:(uint8_t*)buffer;

@end

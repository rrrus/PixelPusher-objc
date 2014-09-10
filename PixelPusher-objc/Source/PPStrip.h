//
//  PPStrip.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/28/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef float (^PPCurveBlock)(float input);

/// pre-fab output linear curve function
extern const PPCurveBlock sCurveLinearFunction;
/// pre-fab output antilog curve function
extern const PPCurveBlock sCurveAntilogFunction;

typedef enum : NSUInteger {
    ePPCompTypeByte,
    ePPCompTypeShort,
    ePPCompTypeFloat,
} PPComponentType;

typedef enum : NSUInteger {
    ePPPixTypeRGB,
    ePPPixTypeRGBOW, // not supported yet
} PPPixelType;

@class PPPixelPusher;

@interface PPStrip : NSObject

@property (nonatomic, readonly) uint32_t stripNumber;
@property (nonatomic, readonly) uint32_t pixelCount;
@property (nonatomic, readonly) uint32_t flags;
@property (nonatomic, readonly) BOOL isWidePixel;
@property (nonatomic, readonly) BOOL isRGBOWPixel;
@property (nonatomic, assign) BOOL touched;
@property (nonatomic, assign) float powerScale;
@property (nonatomic, assign) float brightness;

@property (nonatomic, readonly) void* buffer;
@property (nonatomic, readonly) size_t bufferSize;
@property (nonatomic, readonly) PPPixelType bufferPixType;
@property (nonatomic, readonly) PPComponentType bufferCompType;
@property (nonatomic, readonly) size_t bufferPixStride;
@property (nonatomic, readonly) uint32_t bufferPixCount;

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
// TODO:  This should be a property of PPPixelPusher or maybe PPDeviceRegistry or PPScene
+ (void)setOutputCurveFunction:(PPCurveBlock)curveFunction;

/** `pixCount` should be the PPPixelPusher's pixelsPerStrip value.  the actual number of
	pixels for the strip will be calculated and allocated appropriately based on that
	value combined with any pixel-count re-interpreteting flags.
*/
- (id)initWithStripNumber:(int32_t)stripNum pixelCount:(int32_t)pixCount flags:(int32_t)flags;
- (uint32_t)serialize:(uint8_t*)buffer size:(size_t)size;

/// set a pixel with bytes
- (void)setPixelAtIndex:(uint32_t)index withByteRed:(uint8_t)red green:(uint8_t)green blue:(uint8_t)blue;
/// set a pixel with shorts
- (void)setPixelAtIndex:(uint32_t)index withShortRed:(uint16_t)red green:(uint16_t)green blue:(uint16_t)blue;
/// set a pixel with floats
- (void)setPixelAtIndex:(uint32_t)index withFloatRed:(float)red green:(float)green blue:(float)blue;


/** specify an external pixel buffer
 * 
 * Buffers should be in RGB order.  Color components can be byte, short, or float.  You may use
 * an RGBA buffer by specifying a `pixelStride` of the size of your pixel in bytes, eg RGBA shorts
 * would have a pixelStride of 8.  Specifying a `pixelStride` of 0 means to use the packed size of
 * the pixel's color components.
 *
 * If `buffer` is nil, setPixelBuffer will allocate a pixel buffer with the specified
 * `pixelType`, `compType`, and `pixelStride`.
 * Use the -[setPixelAt***:] methods to set values in the internally allocated buffer or access
 * the buffer directly via the .buffer property.
 */
- (void)setPixelBuffer:(void*)buffer
				  size:(size_t)size
			 pixelType:(PPPixelType)pixType
		 componentType:(PPComponentType)compType
		   pixelStride:(size_t)stride;


@end

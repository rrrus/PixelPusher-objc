/////////////////////////////////////////////////
//
//  PPStrip.h
//  PixelPusher-objc
//
//	This class stores LED/Pixel values for one PixelPusher strip.  [serializeInBuffer:]
//	copies all of those values into a buffer for sending in a packet by PPPusher.
//
//	The original PPStrip stored these in an Objective-C array of PPPixel objects,
//	each containing a CGFloat property for each color component (red, green blue).
//	When [fillRgbBuffer:] was called, this data structure was converted into a C array
//	of bytes, to be sent in a UDP packet.
//
//	This version of PPStrip builds the C array of bytes directly, using a new set
//	of methods, each of which set the color component values for a single pixel.
//	Three [setPixelAtIndex: ...] methods are provided with different component
//	parameter types.  The client app can pass components in whatever format is
//	most convenient.  [serialze:] simply copies the C array.
//
//	This version also handles the building of the output table differently.  The
//	output table ALWAYS contains uint16_t values, allowing a single, global table
//	to send precise output even when there are active pushers with different bit
//	depths.  (8-bit pushers simply ignore the post-scaling LSB.)  The length of the
//	table is determined by which [setPixelAtIndex:] methods are used.  If only the
//	"withByte" method is used, the length is 256.  If "withWord" or "withFloat" are
//	called, the table is 65536 long.  (The longer length will work just fine with
//	subsequent "withByte" calls.)
//
//  Created by Rus Maxham on 5/28/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//	Re-structured by Christopher Schardt on 7/19/14
//  scalePixelComponents stuff added by Christopher Schardt on 8/11/14
//
/////////////////////////////////////////////////

#import <Foundation/Foundation.h>
#import "PPPixel.h"


/////////////////////////////////////////////////
#pragma mark - SWITCHES:


/////////////////////////////////////////////////
#pragma mark - TYPES:

typedef float (^PPOutputCurveBlock)(float input);

/** set an intensity output curve function.  the function will be called repeatedly with input values
	ranging from 0-1.  the function should return output values in the range from 0-1.
	the curve function may be called at any time, from non-main threads, and multiple calls
	concurrently to recompute output curves for varying output depths.  beware to ensure
	the function is thread-safe and reentrant.
 
	@example
		// set an inverse output curve
		[PPStrip setOutputCurveFunction:^float(float input) {
			return 1.0-input;
		}];
 */


/////////////////////////////////////////////////
#pragma mark - STATIC DATA:

/// pre-fab output linear curve function
extern const PPOutputCurveBlock sCurveLinearFunction;
/// pre-fab output antilog curve function
extern const PPOutputCurveBlock sCurveAntilogFunction;


/////////////////////////////////////////////////
#pragma mark - FORWARDS:

@class PPPusher;


/////////////////////////////////////////////////
#pragma mark - CLASS DEFINITION:

@interface PPStrip : NSObject
{
	uint32_t		_serializedDataBytes;
	uint8_t*		_serializedData;
	uint32_t		_brightnessScaleRed;
	uint32_t		_brightnessScaleGreen;
	uint32_t		_brightnessScaleBlue;
}

// EXISTENCE:

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
// TODO:  This should be a property of PPPusher or maybe PPRegistry or PPScene
+ (void)setOutputCurveFunction:(PPOutputCurveBlock)curveFunction;

/** `pixelCount` should be the PPPusher's pixelsPerStrip value.  the actual number of
	pixels for the strip will be calculated and allocated appropriately based on that
	value combined with any pixel-count re-interpreteting flags.
*/
- (id)initWithStripNumber:(uint32_t)stripNumber pixelCount:(uint32_t)pixelCount flags:(uint32_t)flags;

// PROPERTIES:

@property (nonatomic, readonly) BOOL touched;
@property (nonatomic, readonly) uint32_t stripNumber;
@property (nonatomic, readonly) uint32_t pixelCount;
@property (nonatomic, readonly) uint32_t flags;			// combination of SFLAG_ bits
@property (nonatomic, readonly) BOOL isWidePixel;
@property (nonatomic, assign) float powerScale;

@property (nonatomic, assign) PPFloatPixel brightnessScale;
- (void)setBrightnessScaleRed:(float)red green:(float)green blue:(float)blue;
@property (nonatomic, readonly) float averageBrightness;	// 1.0 is maximum, includes brightnessScale

// OPERATIONS:

- (void)setPixels:(NSUInteger)pixelCount withByteArray:(uint8_t const*)byteArray;
- (void)setPixelAtIndex:(uint32_t)index withByteRed:(uint8_t)red green:(uint8_t)green blue:(uint8_t)blue;
- (void)setPixelAtIndex:(uint32_t)index withWordRed:(uint16_t)red green:(uint16_t)green blue:(uint16_t)blue;
- (void)setPixelAtIndex:(uint32_t)index withFloatRed:(float)red green:(float)green blue:(float)blue;

// [setBrightnessScale:] sets factors that are always applied to pixel values.
// This method instead scales, just once, the pixels values that are currently in each strip.
- (void)scaleAverageBrightness:(float)scale;		// 1.0f for no scaling

- (NSUInteger)fillRgbBuffer:(uint8_t*)buffer bufferLength:(NSUInteger)bytes;

@end

/////////////////////////////////////////////////
//
//  PPStrip.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/28/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//	Re-structured by Christopher Schardt on 7/19/14
//  scalePixelComponents stuff added by Christopher Schardt on 8/11/14
//
/////////////////////////////////////////////////

#import "PPPusher.h"
#import "PPStrip.h"
#import "PPPrivate.h"


/////////////////////////////////////////////////
#pragma mark - CONSTANTS:

#define BRIGHTNESS_SCALE_1	0x8000


/////////////////////////////////////////////////
#pragma mark - FORWARDS:

extern void VerifyOutputCurve(uint32_t length);
extern void BuildOutputCurve(uint32_t length);
extern void FreeOutputCurve(void);


/////////////////////////////////////////////////
#pragma mark - STATIC VARIABLES:

const PPOutputCurveBlock sCurveLinearFunction = ^float(float input)
{
	return input;
};

const PPOutputCurveBlock sCurveAntilogFunction = ^float(float input)
{
	// input range 0-1, output range 0-1
	return (powf(2.0f, 8.0f * input) - 1) * (1.0f / 255);
};

PPOutputCurveBlock	gOutputCurveFunction = NULL;
uint32_t			gOutputCurveTableLength = 0;
uint16_t*			gOutputCurveTable = NULL;
uint32_t			gOutputCurveTableByteMask;		// 0xFF if table is 65536 entries long, otherwise 0


@implementation PPStrip


/////////////////////////////////////////////////
#pragma mark - CLASS METHODS, STATIC FUNCTIONS:

+ (void)setOutputCurveFunction:(PPOutputCurveBlock)curveFunction
{
	if (!curveFunction)
	{
		curveFunction = sCurveLinearFunction;
	}
	
	// This test can't work since gOutputCurveFunction points to a copy.
//	if (gOutputCurveFunction != curveFunction)
	{
		gOutputCurveFunction = [curveFunction copy];
		FreeOutputCurve();
	}
}

void VerifyOutputCurve(uint32_t length)
{
	if (gOutputCurveTableLength < length)
	{
		BuildOutputCurve(length);
	}
}
void BuildOutputCurve(uint32_t length)
{
	FreeOutputCurve();
	
	if (!gOutputCurveFunction)
	{
		gOutputCurveFunction = sCurveAntilogFunction;
	}
	gOutputCurveTableLength = length;
	gOutputCurveTableByteMask = (length == 256) ? 0 : 0xFFFF;
	gOutputCurveTable = malloc(length * sizeof(uint16_t));
	
	float			const indexScalar = 1.0f / (length - 1);
	uint32_t		index;
	
	for (index = 0; index < length; index++)
	{
		uint32_t		const value = lroundf(65535.0f * gOutputCurveFunction(index * indexScalar));
		
		ASSERT(value < 65536);
		gOutputCurveTable[index] = (uint16_t)value;
	}
}
void FreeOutputCurve()
{
	if (gOutputCurveTable)
	{
		free(gOutputCurveTable);
		gOutputCurveTable = NULL;
	}
	gOutputCurveTableLength = 0;
}


/////////////////////////////////////////////////
#pragma mark - EXISTENCE:

- (id)initWithStripNumber:(uint32_t)stripNumber pixelCount:(uint32_t)pixelCount flags:(uint32_t)flags
{
	self = [self init];

//	Setting this causes black to be sent to the strip before any data arrives.
//	This makes sense at startup but not when resuming.
//	_touched = YES;

	_stripNumber = stripNumber;
	_flags = flags;
	_powerScale = 1.0;
	_brightnessScale.red = 1.0;
	_brightnessScale.green = 1.0;
	_brightnessScale.blue = 1.0;
	_brightnessScaleRed = BRIGHTNESS_SCALE_1;
	_brightnessScaleGreen = BRIGHTNESS_SCALE_1;
	_brightnessScaleBlue = BRIGHTNESS_SCALE_1;
	
	if (flags & SFLAG_WIDEPIXELS)
	{
		ASSERT(!(pixelCount & 1));
		_pixelCount = (pixelCount + 1) / 2;
	}
	else
	{
		_pixelCount = pixelCount;
	}
	_serializedDataBytes = pixelCount * 3;
	_serializedData = calloc(pixelCount * 3, 1);

	return self;
}

- (void)dealloc
{
	if (_serializedData)
	{
		free(_serializedData);
	}
//	un-comment this if we turn off ARC
//	[super dealloc];
}


/////////////////////////////////////////////////
#pragma mark - PROPERTIES:

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@ (%d%@)", super.description, self.stripNumber, self.touched?@" dirty":@""];
}
- (BOOL)isWidePixel
{
	return (_flags & SFLAG_WIDEPIXELS) ? YES : NO;
}

- (void)setPowerScale:(float)powerScale
{
	_powerScale = powerScale;
	[self calculateBrightnessScales];
}
- (void)setBrightnessScale:(PPFloatPixel)brightness
{
	_brightnessScale = brightness;
	[self calculateBrightnessScales];
}
- (void)setBrightnessScaleRed:(float)red green:(float)green blue:(float)blue;
{
	_brightnessScale.red = red;
	_brightnessScale.green = green;
	_brightnessScale.blue = blue;
	[self calculateBrightnessScales];
}

- (float)averageBrightness
{
	uint8_t const*		const dataEnd = _serializedData + _serializedDataBytes;
	uint8_t const*		data;
	uint32_t			total;

	ASSERT(_serializedDataBytes % 3 == 0);
	data = _serializedData;
	total = 0;
	
	if (_flags & SFLAG_WIDEPIXELS)
	{
		while (data < dataEnd)
		{
			unsigned int		component;
			
			component = (unsigned int)data[0] << 8;
			component |= data[3];
			total += component;
			
			component = (unsigned int)data[1] << 8;
			component |= data[4];
			total += component;
			
			component = (unsigned int)data[2] << 8;
			component |= data[5];
			total += component;
			
			data += 6;
		}
		ASSERT(_serializedDataBytes % 6 == 0);
		return (float)total / ((_serializedDataBytes / 2) * 65535);
	}
	else
	{
		while (data < dataEnd)
		{
			total += data[0];
			data++;
		}
		return (float)total / (_serializedDataBytes * 255);
	}
}


/////////////////////////////////////////////////
#pragma mark - OPERATIONS:

- (void)calculateBrightnessScales
{
	float			const scale = _powerScale * BRIGHTNESS_SCALE_1;
	
	_brightnessScaleRed = lroundf(scale * _brightnessScale.red);
	_brightnessScaleRed = MIN(_brightnessScaleRed, (uint32_t)65536);
	_brightnessScaleGreen = lroundf(scale * _brightnessScale.green);
	_brightnessScaleGreen = MIN(_brightnessScaleGreen, (uint32_t)65536);
	_brightnessScaleBlue = lroundf(scale * _brightnessScale.blue);
	_brightnessScaleBlue = MIN(_brightnessScaleBlue, (uint32_t)65536);
}

- (void)setPixels:(NSUInteger)pixelCount withByteArray:(uint8_t const*)byteArray
{
	VerifyOutputCurve(256);
	
	if (pixelCount > _pixelCount)
	{
		ASSERT(FALSE);
		pixelCount = _pixelCount;
	}
	
	uint16_t const*		const table = gOutputCurveTable;
	uint32_t			const mask = gOutputCurveTableByteMask;
	uint32_t			const scaleRed = _brightnessScaleRed;
	uint32_t			const scaleGreen = _brightnessScaleGreen;
	uint32_t			const scaleBlue = _brightnessScaleBlue;
	uint8_t const*		const srcEnd = byteArray + pixelCount * 3;
	uint8_t const*		src;
	uint8_t*			dst;
	
	src = byteArray;
	dst = _serializedData;
	if (_flags & SFLAG_LOGARITHMIC)
	{
		while (src < srcEnd)
		{
			uint32_t			r;
			uint32_t			g;
			uint32_t			b;
			
			r = src[0];
			g = src[1];
			b = src[2];
			r |= (r << 8);
			g |= (g << 8);
			b |= (b << 8);
			r = r * scaleRed / BRIGHTNESS_SCALE_1;
			r = MIN(r, (uint32_t)65535);
			g = g * scaleGreen / BRIGHTNESS_SCALE_1;
			g = MIN(g, (uint32_t)65535);
			b = b * scaleBlue / BRIGHTNESS_SCALE_1;
			b = MIN(b, (uint32_t)65535);

			dst[0] = (uint8_t)(r >> 8);
			dst[1] = (uint8_t)(g >> 8);
			dst[2] = (uint8_t)(b >> 8);
			dst += 3;
			src += 3;
		}
	}
	else if (_flags & SFLAG_WIDEPIXELS)
	{
		while (src < srcEnd)
		{
			uint32_t			r;
			uint32_t			g;
			uint32_t			b;
			
			r = src[0];
			g = src[1];
			b = src[2];
			r |= (r << 8) & mask;
			r = table[r];
			g |= (g << 8) & mask;
			g = table[g];
			b |= (b << 8) & mask;
			b = table[b];
			r = r * scaleRed / BRIGHTNESS_SCALE_1;
			r = MIN(r, (uint32_t)65535);
			g = g * scaleGreen / BRIGHTNESS_SCALE_1;
			g = MIN(g, (uint32_t)65535);
			b = b * scaleBlue / BRIGHTNESS_SCALE_1;
			b = MIN(b, (uint32_t)65535);

			dst[0] = (uint8_t)(r >> 8);
			dst[1] = (uint8_t)(g >> 8);
			dst[2] = (uint8_t)(b >> 8);
			dst[3] = (uint8_t)r;
			dst[4] = (uint8_t)g;
			dst[5] = (uint8_t)b;
			dst += 6;
			src += 3;
		}
	}
	else if ((mask != 0) ||
			 (scaleRed > BRIGHTNESS_SCALE_1) ||
			 (scaleGreen > BRIGHTNESS_SCALE_1) ||
			 (scaleBlue > BRIGHTNESS_SCALE_1))
	{
		while (src < srcEnd)
		{
			uint32_t			r;
			uint32_t			g;
			uint32_t			b;
			
			r = src[0];
			g = src[1];
			b = src[2];
			r |= (r << 8) & mask;
			r = table[r];
			g |= (g << 8) & mask;
			g = table[g];
			b |= (b << 8) & mask;
			b = table[b];
			r = r * scaleRed / BRIGHTNESS_SCALE_1;
			r = MIN(r, (uint32_t)65535);
			g = g * scaleGreen / BRIGHTNESS_SCALE_1;
			g = MIN(g, (uint32_t)65535);
			b = b * scaleBlue / BRIGHTNESS_SCALE_1;
			b = MIN(b, (uint32_t)65535);
			dst[0] = (uint8_t)(r >> 8);
			dst[1] = (uint8_t)(g >> 8);
			dst[2] = (uint8_t)(b >> 8);
			dst += 3;
			src += 3;
		}
	}
	else if ((scaleRed != BRIGHTNESS_SCALE_1) ||
			 (scaleGreen != BRIGHTNESS_SCALE_1) ||
			 (scaleBlue != BRIGHTNESS_SCALE_1))
	{
		while (src < srcEnd)
		{
			uint32_t			r;
			uint32_t			g;
			uint32_t			b;
			
			r = table[src[0]];
			g = table[src[1]];
			b = table[src[2]];
			r = r * scaleRed / BRIGHTNESS_SCALE_1;
			g = g * scaleGreen / BRIGHTNESS_SCALE_1;
			b = b * scaleBlue / BRIGHTNESS_SCALE_1;
			dst[0] = (uint8_t)(r >> 8);
			dst[1] = (uint8_t)(g >> 8);
			dst[2] = (uint8_t)(b >> 8);
			dst += 3;
			src += 3;
		}
	}
	else
	{
		while (src < srcEnd)
		{
			dst[0] = (uint8_t)(table[src[0]] >> 8);
			dst[1] = (uint8_t)(table[src[1]] >> 8);
			dst[2] = (uint8_t)(table[src[2]] >> 8);
			dst += 3;
			src += 3;
		}
	}

	_touched = YES;
}

- (void)setPixelAtIndex:(uint32_t)index withByteRed:(uint8_t)red green:(uint8_t)green blue:(uint8_t)blue
{
	VerifyOutputCurve(256);
	
	uint32_t			r;
	uint32_t			g;
	uint32_t			b;
	uint8_t*			dst;
	
	r = red;
	g = green;
	b = blue;
	if (_flags & SFLAG_LOGARITHMIC)
	{
		r |= (r << 8);
		g |= (g << 8);
		b |= (b << 8);
	}
	else
	{
		r |= (r << 8) & gOutputCurveTableByteMask;
		r = gOutputCurveTable[r];
		g |= (g << 8) & gOutputCurveTableByteMask;
		g = gOutputCurveTable[g];
		b |= (b << 8) & gOutputCurveTableByteMask;
		b = gOutputCurveTable[b];
	}
	r = r * _brightnessScaleRed / BRIGHTNESS_SCALE_1;
	r = MIN(r, (uint32_t)65535);
	g = g * _brightnessScaleGreen / BRIGHTNESS_SCALE_1;
	g = MIN(g, (uint32_t)65535);
	b = b * _brightnessScaleBlue / BRIGHTNESS_SCALE_1;
	b = MIN(b, (uint32_t)65535);

	dst = _serializedData;
	if (_flags & SFLAG_WIDEPIXELS)
	{
		dst += index * 6;
		dst[3] = (uint8_t)r;
		dst[4] = (uint8_t)g;
		dst[5] = (uint8_t)b;
	}
	else
	{
		dst += index * 3;
	}
	dst[0] = (uint8_t)(r >> 8);
	dst[1] = (uint8_t)(g >> 8);
	dst[2] = (uint8_t)(b >> 8);

	_touched = YES;
}
- (void)setPixelAtIndex:(uint32_t)index withWordRed:(uint16_t)red green:(uint16_t)green blue:(uint16_t)blue
{
	VerifyOutputCurve(65536);
	
	uint32_t			r;
	uint32_t			g;
	uint32_t			b;
	uint8_t*			dst;
	
	r = red;
	g = green;
	b = blue;
	if (!(_flags & SFLAG_LOGARITHMIC))
	{
		r = gOutputCurveTable[r];
		g = gOutputCurveTable[g];
		b = gOutputCurveTable[b];
	}
	r = r * _brightnessScaleRed / BRIGHTNESS_SCALE_1;
	r = MIN(r, (uint32_t)65535);
	g = g * _brightnessScaleGreen / BRIGHTNESS_SCALE_1;
	g = MIN(g, (uint32_t)65535);
	b = b * _brightnessScaleBlue / BRIGHTNESS_SCALE_1;
	b = MIN(b, (uint32_t)65535);
	
	dst = _serializedData;
	if (_flags & SFLAG_WIDEPIXELS)
	{
		dst += index * 6;
		dst[3] = (uint8_t)r;
		dst[4] = (uint8_t)g;
		dst[5] = (uint8_t)b;
	}
	else
	{
		dst += index * 3;
	}
	dst[0] = (uint8_t)(r >> 8);
	dst[1] = (uint8_t)(g >> 8);
	dst[2] = (uint8_t)(b >> 8);

	_touched = YES;
}
- (void)setPixelAtIndex:(uint32_t)index withFloatRed:(float)red green:(float)green blue:(float)blue
{
	VerifyOutputCurve(65536);
	
	uint32_t			r;
	uint32_t			g;
	uint32_t			b;
	uint8_t*			dst;
	
	r = lroundf(red * 65535);
	r = MIN(r, (uint32_t)65535);
	g = lroundf(green * 65535);
	g = MIN(r, (uint32_t)65535);
	b = lroundf(blue * 65535);
	b = MIN(b, (uint32_t)65535);
	if (!(_flags & SFLAG_LOGARITHMIC))
	{
		r = gOutputCurveTable[r];
		g = gOutputCurveTable[g];
		b = gOutputCurveTable[b];
	}
	r = r * _brightnessScaleRed / BRIGHTNESS_SCALE_1;
	r = MIN(r, (uint32_t)65535);
	g = g * _brightnessScaleGreen / BRIGHTNESS_SCALE_1;
	g = MIN(g, (uint32_t)65535);
	b = b * _brightnessScaleBlue / BRIGHTNESS_SCALE_1;
	b = MIN(b, (uint32_t)65535);

	dst = _serializedData;
	if (_flags & SFLAG_WIDEPIXELS)
	{
		dst += index * 6;
		dst[3] = (uint8_t)r;
		dst[4] = (uint8_t)g;
		dst[5] = (uint8_t)b;
	}
	else
	{
		dst += index * 3;
	}
	dst[0] = (uint8_t)(r >> 8);
	dst[1] = (uint8_t)(g >> 8);
	dst[2] = (uint8_t)(b >> 8);

	_touched = YES;
}

// [setBrightnessScale:] sets factors that are always applied to pixel values.
// This method instead scales, just once, the pixels values that are currently in each strip.
- (void)scaleAverageBrightness:(float)scale;		// 1.0f for no scaling
{
	if (scale != 1.0f)
	{
		uint32_t			const iScale = (uint32_t)(scale * 65536);
		uint8_t*			const dataEnd = _serializedData + _serializedDataBytes;
		uint8_t*			data;

		data = _serializedData;
		
		if (_flags & SFLAG_WIDEPIXELS)
		{
			while (data < dataEnd)
			{
				uint32_t		component;
				
				component = (uint16_t)data[0] << 8;
				component |= data[3];
				component *= iScale;
				data[0] = (uint8_t)(component >> 24);
				data[3] = (uint8_t)(component >> 16);
				
				component = (uint16_t)data[1] << 8;
				component |= data[4];
				component *= iScale;
				data[1] = (uint8_t)(component >> 24);
				data[4] = (uint8_t)(component >> 16);
				
				component = (uint16_t)data[2] << 8;
				component |= data[5];
				component *= iScale;
				data[2] = (uint8_t)(component >> 24);
				data[5] = (uint8_t)(component >> 16);
				
				data += 6;
			}
		}
		else
		{
			while (data < dataEnd)
			{
				uint32_t		component;
				
				component = data[0];
				component *= iScale;
				data[0] = (uint8_t)(component >> 16);
				data++;
			}
		}
	}
}


/////////////////////////////////////////////////
#pragma mark - OPERATIONS CALLED ONLY BY PP LIBRARY:

- (uint32_t)fillRgbBuffer:(uint8_t*)buffer bufferLength:(NSUInteger)bytes
{
    _touched = NO;
	if (_serializedDataBytes < bytes)
	{
		bytes = _serializedDataBytes;
	}
	memcpy(buffer, _serializedData, bytes);
	return bytes;
}


@end

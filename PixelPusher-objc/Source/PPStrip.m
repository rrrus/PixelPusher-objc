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

#import "PPPixelPusher.h"
#import "PPStrip.h"


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

static PPOutputCurveBlock	gOutputCurveFunction = NULL;
static uint32_t				gOutputCurveTableLength = 0;
static uint32_t				gOutputCurveTableByteMask;
static uint16_t*			gOutputCurveTable = NULL;


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

inline void VerifyOutputCurve(uint32_t length)
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
		
		assert(value < 65536);
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

	//??? Why would NSObject ever fail to initialize?
//	if (self)
	{
		_stripNumber = stripNumber;
		_flags = flags;
		_touched = YES;
		_powerScale = 1.0;
		_brightnessRed = 1.0;
		_brightnessGreen = 1.0;
		_brightnessBlue = 1.0;
		_brightnessScaleRed = BRIGHTNESS_SCALE_1;
		_brightnessScaleGreen = BRIGHTNESS_SCALE_1;
		_brightnessScaleBlue = BRIGHTNESS_SCALE_1;
		
		if (flags & SFLAG_WIDEPIXELS)
		{
			assert(!(pixelCount & 1));
			_pixelCount = (pixelCount + 1) / 2;
		}
		else
		{
			_pixelCount = pixelCount;
		}
		_serializedDataBytes = pixelCount * 3;
		_serializedData = calloc(pixelCount * 3, 1);
	}
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
- (void)setBrightness:(float)brightness
{
	_brightnessRed = brightness;
	_brightnessGreen = brightness;
	_brightnessBlue = brightness;
	[self calculateBrightnessScales];
}
- (float)brightness
{
	return (_brightnessRed + _brightnessGreen + _brightnessBlue) / 3;
}

- (void)setBrightnessRed:(float)brightness
{
	_brightnessRed = brightness;
	[self calculateBrightnessScales];
}
- (void)setBrightnessGreen:(float)brightness
{
	_brightnessGreen = brightness;
	[self calculateBrightnessScales];
}
- (void)setBrightnessBlue:(float)brightness
{
	_brightnessBlue = brightness;
	[self calculateBrightnessScales];
}

- (float)averagePixelComponentValue
{
	uint8_t*			const dataEnd = _serializedData + _serializedDataBytes;
	uint8_t*			data;
	uint32_t			total;

	assert(_serializedDataBytes % 3 == 0);
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
		assert(_serializedDataBytes % 6 == 0);
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
	
	_brightnessScaleRed = lroundf(scale * _brightnessRed);
	_brightnessScaleRed = MIN(_brightnessScaleRed, (uint32_t)65536);
	_brightnessScaleGreen = lroundf(scale * _brightnessGreen);
	_brightnessScaleGreen = MIN(_brightnessScaleGreen, (uint32_t)65536);
	_brightnessScaleBlue = lroundf(scale * _brightnessBlue);
	_brightnessScaleBlue = MIN(_brightnessScaleBlue, (uint32_t)65536);
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

- (void)scalePixelComponentValues:(float)scale;		// 1.0f for no scaling
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

- (uint32_t)serialize:(uint8_t*)buffer
{
    _touched = NO;
	memcpy(buffer, _serializedData, _serializedDataBytes);
	return _serializedDataBytes;
}


@end

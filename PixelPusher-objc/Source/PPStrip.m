//
//  PPStrip.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/28/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "PPPixel.h"
#import "PPPixelPusher.h"
#import "PPStrip.h"

typedef void (^PPSetPixWithFloatBlock)(uint32_t index, float red, float green, float blue);
typedef void (^PPSetPixWithShortBlock)(uint32_t index, uint16_t red, uint16_t green, uint16_t blue);
typedef void (^PPSetPixWithByteBlock)(uint32_t index, uint8_t red, uint8_t green, uint8_t blue);

static PPCurveBlock gOutputCurveFunction;
static const uint8_t * gOutputLUT8 = nil;
static uint16_t* gOutputLUT16 = nil;

const PPCurveBlock sCurveLinearFunction =  ^float(float input) {
	return input;
};

const PPCurveBlock sCurveAntilogFunction =  ^float(float input) {
	// input range 0-1, output range 0-1
	return (powf(2, 8*input)-1)/255;
};

@interface PPStrip ()
@property (nonatomic, assign) uint32_t pixelCount;
@property (nonatomic, assign) uint32_t stripNumber;
@property (nonatomic, assign) uint32_t flags;
@property (nonatomic, assign) void* buffer;
@property (nonatomic, assign) size_t bufferSize;
@property (nonatomic, assign) PPPixelType bufferPixType;
@property (nonatomic, assign) PPComponentType bufferCompType;
@property (nonatomic, assign) size_t bufferPixStride;
@property (nonatomic, assign) uint32_t bufferPixCount;
@property (nonatomic, strong) NSMutableData* internallyAllocatedBuffer;

@property (nonatomic, strong) PPSetPixWithByteBlock setPixWithByte;
@property (nonatomic, strong) PPSetPixWithShortBlock setPixWithShort;
@property (nonatomic, strong) PPSetPixWithFloatBlock setPixWithFloat;
@end

@implementation PPStrip

+ (void)setOutputCurveFunction:(PPCurveBlock)curveFunction {
	if (!curveFunction) curveFunction = sCurveLinearFunction;
	
	gOutputCurveFunction = [curveFunction copy];
	// only rebuild if they already exist
	if (gOutputLUT8) [PPStrip buildOutputCurve:8];
	if (gOutputLUT16) [PPStrip buildOutputCurve:16];
}

+ (void)buildOutputCurve:(int)depth {
	if (!gOutputCurveFunction) gOutputCurveFunction = sCurveAntilogFunction;

	if (depth == 16) {
		if (gOutputLUT8) free((void*)gOutputLUT8);
		gOutputLUT8 = nil;
	} else {
		if (gOutputLUT8) free((void*)gOutputLUT8);
		gOutputLUT8 = nil;
	}
	
	// special case linear output function
	if (!gOutputCurveFunction || gOutputCurveFunction == sCurveLinearFunction) {
		// give the LUTs a non-nil value so we can check to see if they're in use
		if (depth == 16) {
			gOutputLUT16 = malloc(1);
		} else {
			gOutputLUT8 = malloc(1);
		}
		return;
	}
	
	if (depth == 16) {
		uint16_t *outputLUT16 = malloc(65536);
		gOutputLUT16 = outputLUT16;
		for (int i=0; i<65536; i++) {
			outputLUT16[i] = (uint16_t)( lroundf( 65535.0f * gOutputCurveFunction(i/65535.0f) ) );
		}
	} else {
		uint8_t *outputLUT8 = malloc(256);
		gOutputLUT8 = outputLUT8;
		for (int i=0; i<256; i++) {
			outputLUT8[i] = (uint8_t)( lroundf( 255.0f * gOutputCurveFunction(i/255.0f) ) );
		}
	}
}

- (id)initWithStripNumber:(int32_t)stripNum pixelCount:(int32_t)pixCount flags:(int32_t)flags{
	self = [self init];
	if (self) {
		self.stripNumber = stripNum;
		self.flags = flags;
		self.touched = YES;
		self.powerScale = 1.0;
		self.brightness = 1.0;

		PPComponentType compType = ePPCompTypeByte;
		if (self.flags & SFLAG_WIDEPIXELS) {
			compType = ePPCompTypeShort;
			pixCount = (pixCount+1)/2;
			if (!gOutputLUT16) [PPStrip buildOutputCurve:16];
		} else {
			if (!gOutputLUT8) [PPStrip buildOutputCurve:8];
		}

		self.pixelCount = pixCount;
		// default to high-precision float pixels
		[self setPixelBuffer:nil
						size:0
				   pixelType:ePPPixTypeRGB
			   componentType:compType
				 pixelStride:sizeof(PPFloatPixel)];
	}
	return self;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@ (%d%@)", super.description, self.stripNumber, self.touched?@" dirty":@""];
}

- (BOOL)isWidePixel {
	return (self.flags & SFLAG_WIDEPIXELS);
}

- (void)setPixelAtIndex:(uint32_t)index withByteRed:(uint8_t)red green:(uint8_t)green blue:(uint8_t)blue {
	self.setPixWithByte(index, red, green, blue);
	self.touched = YES;
}

- (void)setPixelAtIndex:(uint32_t)index withShortRed:(uint16_t)red green:(uint16_t)green blue:(uint16_t)blue {
	self.setPixWithShort(index, red, green, blue);
	self.touched = YES;
}

- (void)setPixelAtIndex:(uint32_t)index withFloatRed:(float)red green:(float)green blue:(float)blue {
	self.setPixWithFloat(index, red, green, blue);
	self.touched = YES;
}

- (void)setPixelBuffer:(void*)buffer
				  size:(size_t)size
			 pixelType:(PPPixelType)pixType
		 componentType:(PPComponentType)compType
		   pixelStride:(size_t)stride
{
	// if this is a request for a specific format of internal buffer,
	// we already have an internal buffer, and it is already of the format
	// requested, do nothing.
	if (buffer == nil
		&& self.internallyAllocatedBuffer
		&& self.bufferCompType == compType
		&& self.bufferPixType == pixType)
	{
		return;
	}
	
	if (stride == 0 || buffer == nil) {
		int nComps = (pixType == ePPPixTypeRGBOW) ? 5 : 3;
		int compSize;
		switch (compType) {
			case ePPCompTypeFloat: compSize = sizeof(float); break;
			case ePPCompTypeShort: compSize = sizeof(uint16_t); break;
			case ePPCompTypeByte:  compSize = sizeof(uint8_t); break;
			default:
				NSAssert(NO, @"unknown pixel component type specified");
		}
		stride = nComps * compSize;
	}
	
	self.bufferPixStride = stride;
	self.bufferPixType = pixType;
	self.bufferCompType = compType;
	
	if (buffer == nil) {
		// allocate buffer internally using specified pixel types
		size = self.pixelCount*stride;
		self.internallyAllocatedBuffer = [NSMutableData dataWithCapacity:size];
		buffer = self.internallyAllocatedBuffer.mutableBytes;
	} else if (self.internallyAllocatedBuffer && buffer != self.internallyAllocatedBuffer.mutableBytes) {
		// using an external buffer, don't need this anymore
		self.internallyAllocatedBuffer = nil;
	}
	
	self.bufferPixCount = (uint32_t)(size / stride);
	self.buffer = buffer;
	self.bufferSize = size;
	
	[self configureSetPix];
}

- (void)configureSetPix {
	void* stripBuffer = self.buffer;
	size_t stride = self.bufferPixStride;
	
	if (self.bufferCompType == ePPCompTypeByte) {
		// buffer has byte component pixels
		self.setPixWithByte = [^(uint32_t index, uint8_t red, uint8_t green, uint8_t blue) {
			PPBytePixel *pix = (PPBytePixel*)(stripBuffer + (index*stride));
			pix->red = red;
			pix->green = green;
			pix->blue = blue;
		} copy];
		
		self.setPixWithShort = [^(uint32_t index, uint16_t red, uint16_t green, uint16_t blue) {
			PPBytePixel *pix = (PPBytePixel*)(stripBuffer + (index*stride));
			pix->red = (uint8_t)(red >> 8);
			pix->green = (uint8_t)(green >> 8);
			pix->blue = (uint8_t)(blue >> 8);
		} copy];
		
		self.setPixWithFloat = [^(uint32_t index, float red, float green, float blue) {
			PPBytePixel *pix = (PPBytePixel*)(stripBuffer + (index*stride));
			pix->red = (uint8_t)(red * 255);
			pix->green = (uint8_t)(green * 255);
			pix->blue = (uint8_t)(blue * 255);
		} copy];
		
	} else if (self.bufferCompType == ePPCompTypeShort) {
		// buffer has short component pixels
		self.setPixWithByte = [^(uint32_t index, uint8_t red, uint8_t green, uint8_t blue) {
			PPShortPixel *pix = (PPShortPixel*)(stripBuffer + (index*stride));
			pix->red = (uint16_t)(red | (red << 8));
			pix->green = (uint16_t)(green | (green << 8));
			pix->blue = (uint16_t)(blue | (blue << 8));
		} copy];
		
		self.setPixWithShort = [^(uint32_t index, uint16_t red, uint16_t green, uint16_t blue) {
			PPShortPixel *pix = (PPShortPixel*)(stripBuffer + (index*stride));
			pix->red = red;
			pix->green = green;
			pix->blue = blue;
		} copy];
		
		self.setPixWithFloat = [^(uint32_t index, float red, float green, float blue) {
			PPShortPixel *pix = (PPShortPixel*)(stripBuffer + (index*stride));
			pix->red = (uint16_t)(red * 65535);
			pix->green = (uint16_t)(green * 65535);
			pix->blue = (uint16_t)(blue * 65535);
		} copy];
		
	} else {
		// buffer has float component pixels
		self.setPixWithByte = [^(uint32_t index, uint8_t red, uint8_t green, uint8_t blue) {
			PPFloatPixel *pix = (PPFloatPixel*)(stripBuffer + (index*stride));
			pix->red = (float)red / 255.0f;
			pix->green = (float)green / 255.0f;
			pix->blue = (float)blue / 255.0f;
		} copy];
		
		self.setPixWithShort = [^(uint32_t index, uint16_t red, uint16_t green, uint16_t blue) {
			PPFloatPixel *pix = (PPFloatPixel*)(stripBuffer + (index*stride));
			pix->red = (float)red / 65535.0f;
			pix->green = (float)green / 65535.0f;
			pix->blue = (float)blue / 65535.0f;
		} copy];
		
		self.setPixWithFloat = [^(uint32_t index, float red, float green, float blue) {
			PPFloatPixel *pix = (PPFloatPixel*)(stripBuffer + (index*stride));
			pix->red = (float)red;
			pix->green = (float)green;
			pix->blue = (float)blue;
		} copy];
		
	}
}

#define COPY_PIX_WITH_LUT(scale) \
*(P++) = (uint8_t)(gOutputLUT8[(uint8_t) ((uint16_t)(srcPix->red * scale) / 256)] * iPostLutScale / 65536); \
*(P++) = (uint8_t)(gOutputLUT8[(uint8_t) ((uint16_t)(srcPix->green * scale) / 256)] * iPostLutScale / 65536); \
*(P++) = (uint8_t)(gOutputLUT8[(uint8_t) ((uint16_t)(srcPix->blue * scale) / 256)] * iPostLutScale / 65536); \
srcP += self.bufferPixStride;

#define COPY_PIX(scale) \
*(P++) = (uint8_t)( (uint16_t)(srcPix->red * scale) * iPostLutScale / (256*65536)); \
*(P++) = (uint8_t)( (uint16_t)(srcPix->green * scale) * iPostLutScale / (256*65536)); \
*(P++) = (uint8_t)( (uint16_t)(srcPix->blue * scale) * iPostLutScale / (256*65536)); \
srcP += self.bufferPixStride;

#define COPY_PIX_WIDE_WITH_LUT(scale) \
uint16_t wide; \
wide = (uint16_t)(gOutputLUT16[(uint16_t) (srcPix->red * scale)] * iPostLutScale / 65536); \
*P = (wide & 0xff00) >> 8; \
*(P+3) = (wide & 0x00ff); \
P++; \
wide = (uint16_t)(gOutputLUT16[(uint16_t) (srcPix->green * scale)] * iPostLutScale / 65536); \
*P = (wide & 0xff00) >> 8; \
*(P+3) = (wide & 0x00ff); \
P++; \
wide = (uint16_t)(gOutputLUT16[(uint16_t) (srcPix->blue * scale)] * iPostLutScale / 65536); \
*P = (wide & 0xff00) >> 8; \
*(P+3) = (wide & 0x00ff); \
P += 4; /* skip the next 3 bytes we already filled in */ \
srcP += self.bufferPixStride;

#define COPY_PIX_WIDE(scale) \
uint16_t wide; \
wide = (uint16_t) ((uint16_t)(srcPix->red * scale) * iPostLutScale / 65536); \
*P = (wide & 0xf0) >> 8; \
*(P+3) = (wide & 0x0f); \
P++; \
wide = (uint16_t) ((uint16_t)(srcPix->green * scale) * iPostLutScale / 65536); \
*P = (wide & 0xf0) >> 8; \
*(P+3) = (wide & 0x0f); \
P++; \
wide = (uint16_t) ((uint16_t)(srcPix->blue * scale) * iPostLutScale / 65536); \
*P = (wide & 0xf0) >> 8; \
*(P+3) = (wide & 0x0f); \
P += 4; /* skip the next 3 bytes we already filled in */ \
srcP += self.bufferPixStride;


- (uint32_t)serialize:(uint8_t*)buffer size:(size_t)size {

	// convert brightness plus powerScale to 16-bit binary fraction
	uint32_t iPostLutScale = (uint32_t)(self.brightness * self.powerScale * 65536);
	__block uint8_t *P = buffer;
	uint32_t pixToCopy = MIN(self.bufferPixCount, self.pixelCount);
	uint8_t *srcP = self.buffer;
	
	if (self.flags & SFLAG_WIDEPIXELS) {
		uint8_t *endP = P + (pixToCopy*2*3);
		if (gOutputCurveFunction != sCurveLinearFunction) {
			
			if (self.bufferCompType == ePPCompTypeByte) {
				while (P < endP) {
					PPBytePixel *srcPix = (PPBytePixel*)srcP;
					COPY_PIX_WIDE_WITH_LUT(256);
				}
			} else if (self.bufferCompType == ePPCompTypeShort) {
				while (P < endP) {
					PPShortPixel *srcPix = (PPShortPixel*)srcP;
					COPY_PIX_WIDE_WITH_LUT(1);
				}
			} else {
				while (P < endP) {
					PPFloatPixel *srcPix = (PPFloatPixel*)srcP;
					COPY_PIX_WIDE_WITH_LUT(65535);
				}
			}
		} else {
			if (self.bufferCompType == ePPCompTypeByte) {
				while (P < endP) {
					PPBytePixel *srcPix = (PPBytePixel*)srcP;
					COPY_PIX_WIDE(256);
				}
			} else if (self.bufferCompType == ePPCompTypeShort) {
				while (P < endP) {
					PPShortPixel *srcPix = (PPShortPixel*)srcP;
					COPY_PIX_WIDE(1);
				}
			} else {
				while (P < endP) {
					PPFloatPixel *srcPix = (PPFloatPixel*)srcP;
					COPY_PIX_WIDE(65535);
				}
			}
		}
	} else {
		uint8_t *endP = P + (pixToCopy*3);
		if (gOutputCurveFunction != sCurveLinearFunction) {
			if (self.bufferCompType == ePPCompTypeByte) {
				while (P < endP) {
					PPBytePixel *srcPix = (PPBytePixel*)srcP;
					COPY_PIX_WITH_LUT(256);
				}
			} else if (self.bufferCompType == ePPCompTypeShort) {
				while (P < endP) {
					PPShortPixel *srcPix = (PPShortPixel*)srcP;
					COPY_PIX_WITH_LUT(1);
				}
			} else {
				while (P < endP) {
					PPFloatPixel *srcPix = (PPFloatPixel*)srcP;
					COPY_PIX_WITH_LUT(65535);
				}
			}
		} else {
			if (self.bufferCompType == ePPCompTypeByte) {
				while (P < endP) {
					PPBytePixel *srcPix = (PPBytePixel*)srcP;
					COPY_PIX(256);
				}
			} else if (self.bufferCompType == ePPCompTypeShort) {
				while (P < endP) {
					PPShortPixel *srcPix = (PPShortPixel*)srcP;
					COPY_PIX(1);
				}
			}
			if (self.bufferCompType == ePPCompTypeFloat) {
				while (P < endP) {
					PPFloatPixel *srcPix = (PPFloatPixel*)srcP;
					COPY_PIX(65535);
				}
			}
		}
	}
	
	// if the pixel buffer isn't big enough, pad it out with 0's
	if (pixToCopy < self.pixelCount) {
		uint32_t padding = self.pixelCount - pixToCopy;
		if (self.flags & SFLAG_WIDEPIXELS) padding *= 2;
		padding *= 3;
		memset(P, 0, padding);
		P += padding;
	}
	
    self.touched = NO;
	return (uint32_t)(P-buffer);
}


@end

//
//  PPPixelPusher.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PPDevice.h"

@class PPDeviceHeader;

typedef enum {
	PFLAG_PROTECTED = (1<<0),
	PFLAG_FIXEDSIZE = (1<<1)
} PPPusherFlags;

typedef enum {
	SFLAG_RGBOW = (1<<0),
	SFLAG_WIDEPIXELS = (1<<1),
	SFLAG_LOGARITHMIC = (1<<2)
} PPStripFlags;

@interface PPPixelPusher : PPDeviceImpl

@property (nonatomic, readonly) NSArray *strips;
@property (nonatomic, readonly) int32_t pixelsPerStrip;
@property (nonatomic, readonly) int32_t groupOrdinal;
@property (nonatomic, readonly) int32_t controllerOrdinal;
@property (nonatomic, readonly) NSTimeInterval updatePeriod;
@property (nonatomic, readonly) int64_t powerTotal;
@property (nonatomic, readonly) int64_t deltaSequence;
@property (nonatomic, readonly) int32_t maxStripsPerPacket;
@property (nonatomic, readonly) int16_t myPort;
@property (nonatomic, readonly) NSArray *stripFlags;
@property (nonatomic, readonly) uint32_t pusherFlags;
@property (nonatomic, readonly) uint32_t segments;
@property (nonatomic, readonly) uint32_t powerDomain;

@property (nonatomic, assign)	float	brightness;
@property (nonatomic, assign)	BOOL	autoThrottle;
@property (nonatomic, assign)	NSTimeInterval extraDelay;

- (id)initWithHeader:(PPDeviceHeader*)header;
- (void)copyHeader:(PPPixelPusher*)device;
- (BOOL)isEqualToPusher:(PPPixelPusher*)pusher;
- (void)allocateStrips;

//- (void)setStrip:(int32_t)stripNumber pixels:(NSArray*)pixels;
- (void)increaseExtraDelay:(NSTimeInterval)i;
- (void)decreaseExtraDelay:(NSTimeInterval)i;

@end

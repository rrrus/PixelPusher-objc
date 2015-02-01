//
//  PPPusher.h
//  PixelPusher-objc
//
//	PPPusher is an Objective-C class that handles communication with a single PixelPusher LED controller.
//	 * contains parameters received from broadcast packets
//	 * contains parameters that affect how data is transmitted
//	 * when [flush] is called, calls [serializeIntoBuffer:] for each PPStrip to get pixel data and
//	   assembles packets from the data, which are sent at precisely calculated times.
//	 * enqueues PPPusherCommands and sends them at appropriate times
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//  Modified extensively by Christopher Schardt in 2014/2015
//	 * added pusher command code
//	 * fixed offset error in reading strips_flags and all subsequent header fields
//	 * converted all private properties to ivars
//	 * changed name from PPPixelPusher to PPPusher
//	 * no longer subclassing from PPDevice (which has been deleted)
//	 * greatly simplified the updatePeriod, delta_sequence stuff
//	 * brought in all the functionality of PPCard, enabling much code simplification
//	 * moved pusher list changed to the beginning of [frameTask]
//	 * updated writeStream logic from Java library
//

#import <Foundation/Foundation.h>
#import "HLDeferred.h"
#import "PPDeviceHeader.h"
#import "PPPixel.h"
#import "PPPusherCommand.h"


/////////////////////////////////////////////////
#pragma mark - CONSTANTS:


/////////////////////////////////////////////////
#pragma mark - TYPES:

typedef enum
{
	PFLAG_PROTECTED = (1<<0),			// Pusher is marked as protected.
	PFLAG_FIXEDSIZE = (1<<1),			// Pusher requires fixed size datagrams.
	PFLAG_GLOBALBRIGHTNESS = (1<<2),	// Pusher supports GlobalBrightness_Set (NOT whether any strip supports hardware brightness)
	PFLAG_STRIPBRIGHTNESS = (1<<3),		// Pusher supports StripBrightness_Set (NOT whether any strip supports hardware brightness)
} PPPusherFlags;

typedef enum
{
	SFLAG_RGBOW = (1<<0),				// Strip uses COW pixel ordering
	SFLAG_WIDEPIXELS = (1<<1),			// Strip uses 48bpp as RGBrgb packing
	SFLAG_LOGARITHMIC = (1<<2),			// Strip does its own antilog correction.
	SFLAG_MOTION = (1<<3),				// Strip is actually a motion control device.
	SFLAG_NOTIDEMPOTENT = (1<<4),		// Repeated writes of same data have side effects.
	SFLAG_BRIGHTNESS = (1<<5),			// Strip configured for hardware that supports brightness
} PPStripFlags;


/////////////////////////////////////////////////
#pragma mark - CLASS DEFINITION:

@interface PPPusher : NSObject

// EXISTENCE:

- (id)initWithHeader:(PPDeviceHeader*)header;


// PROPERTIES:

@property (nonatomic, readonly) NSArray* strips;
@property (nonatomic, assign) BOOL doAdjustForDroppedPackets;
@property (nonatomic, assign) BOOL isRecordingToFile;
@property (nonatomic, assign) PPFloatPixel brightnessScale;
@property (nonatomic, readonly) BOOL doesAnyStripSupportHardwareBrightnessScaling;
@property (nonatomic, readonly) float averageBrightness;	// 0-1, in all strips

// These are read out of broadcast packets sent by the controller, and never change:
@property (nonatomic, readonly) PPDeviceHeader* header;
@property (nonatomic, readonly) NSUInteger pixelsPerStrip;
@property (nonatomic, readonly) NSUInteger maxStripsPerPacket;
@property (nonatomic, readonly) uint32_t controllerOrdinal;
@property (nonatomic, readonly) uint32_t groupOrdinal;
@property (nonatomic, readonly) uint32_t pusherFlags;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) uint16_t artnetUniverse;
@property (nonatomic, readonly) uint16_t artnetChannel;
//@property (nonatomic, readonly) uint32_t segments;	// not yet implemented in controllers
//@property (nonatomic, readonly) uint32_t powerDomain;	// not working correctly in controllers

// These are read out of broadcast packets sent by the controller, and DO change:
@property (nonatomic, readonly) uint32_t updatePeriodUsec;
@property (nonatomic, readonly) uint32_t powerTotal;
//@property (nonatomic, readonly) NSString* ipAddressOfLastClient;	// not yet implemented
//@property (nonatomic, readonly) uint16_t portOfLastClient;		// not yet implemented

// PROPERTIES TO BE USED ONLY BY PPRegistry:

+ (NSComparator)sortComparator;
@property (nonatomic, assign) NSTimeInterval extraDelay;
@property (nonatomic, assign) NSTimeInterval lastSeenDate;
//@property (nonatomic, readonly) uint64_t bandwidthEstimate;	// currently just returns zero

/* Jas sez:
delta_sequence is a leaky-bucket total of the number of packets dropped over the last second,
and is intended for use in the autothrottle's backoff.  delta_sequence should always be zero,
in a perfect world, but if it goes over 2, the pusher's extra_delay should be increased by 5 ms.
When it's zero, the extra_delay should be reduced by 1 ms.  This provides a good balance
between losing packets and losing framerate, and the hysteresis stops it from oscillating too
much.  (Engineering:  it ends up being an ID controller.  No P term.)
*/
@property (nonatomic, readonly) uint32_t deltaSequence;

// OPERATIONS:

- (void)enqueuePusherCommand:(PPPusherCommand*)command;

// [setBrightnessScale:] sets factors that are always applied to pixel values.
// This method instead scales, just once, the pixels values that are currently in each strip.
- (void)scaleAverageBrightness:(float)scale;
- (void)resetHardwareBrightness;

// OPERATIONS TO BE CALLED ONLY BY PPRegistry:

- (void)close;

// Returns whether any update merits considering the pusher to be updated.
- (void)updateWithHeader:(PPDeviceHeader*)header;

// Sends packets as needed:
//	* one for each PPPusherCommand enqueued in PPPusher
//	* calls [serialize:] for each PPStrip, gathering the data into as few packets as possible
//	* sets up a block for each packet on a concurrent queue to execute at the right time for synchrony
//	* fulfills a promise being waited upon by the NEXT frame (very tricky stuff)
- (HLDeferred*)flush;


@end

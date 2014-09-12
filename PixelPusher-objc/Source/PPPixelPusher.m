//
//  PPPixelPusher.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "NSData+Utils.h"
#import "PPDeviceHeader.h"
#import "PPPixelPusher.h"
#import "PPStrip.h"

INIT_LOG_LEVEL_INFO

static const int32_t kDefaultPusherPort = 9897;

@interface PPPixelPusher ()
@property (nonatomic, assign) uint32_t stripsAttached;
@property (nonatomic, assign) uint32_t artnetUniverse;
@property (nonatomic, assign) uint32_t artnetChannel;

// redeclaring readonly public interfaces for private assign access
@property (nonatomic, strong) NSArray *strips;
@property (nonatomic, assign) uint32_t pixelsPerStrip;
@property (nonatomic, assign) uint32_t groupOrdinal;
@property (nonatomic, assign) uint32_t controllerOrdinal;
@property (nonatomic, assign) NSTimeInterval updatePeriod;
@property (nonatomic, assign) uint64_t powerTotal;
@property (nonatomic, assign) uint64_t deltaSequence;
@property (nonatomic, assign) uint32_t maxStripsPerPacket;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSArray *stripFlags;
@property (nonatomic, assign) uint32_t pusherFlags;
@property (nonatomic, assign) uint32_t segments;
@property (nonatomic, assign) uint32_t powerDomain;
@end

@implementation PPPixelPusher

+ (NSComparator)sortComparator {
	return ^NSComparisonResult(PPPixelPusher *obj1, PPPixelPusher *obj2) {
		int32_t group0 = obj1.groupOrdinal;
		int32_t group1 = obj2.groupOrdinal;
		if (group0 != group1) {
			if (group0 < group1) return NSOrderedAscending;
			return NSOrderedDescending;
		}
		
		int32_t ord1 = obj1.controllerOrdinal;
		int32_t ord2 = obj2.controllerOrdinal;
		if (ord1 != ord2) {
			if (ord1 < ord2) return NSOrderedAscending;
			return NSOrderedDescending;
		}
		
		return [obj1.macAddress compare:obj2.macAddress];
	};
}

- (id)initWithHeader:(PPDeviceHeader*)header {
	self = [super initWithHeader:header];
	if (self) {
		self.brightness = PPFloatPixelMake(1, 1, 1);
		
		NSData *packet = header.packetRemainder;
		if (self.softwareRevision < PP_ACCEPTABLE_LOWEST_SW_REV) {
			// TODO: use the device registry delegate to relay this message
			DDLogWarn(@"WARNING!  This PixelPusher Library requires firmware revision %g", PP_ACCEPTABLE_LOWEST_SW_REV/100.0);
			DDLogWarn(@"WARNING!  This PixelPusher is using %g", self.softwareRevision/100.0);
			DDLogWarn(@"WARNING!  This is not expected to work.  Please update your PixelPusher.");
		}
		if (packet.length < 28) {
			[NSException raise:NSInvalidArgumentException format:@"expected header size %d, but got %lu", 28, (unsigned long)packet.length];
		}

		self.stripsAttached = [packet ubyteAtOffset:0];
		self.maxStripsPerPacket = [packet ubyteAtOffset:1];
		self.pixelsPerStrip = [packet ushortAtOffset:2];

		// usec to sec
		self.updatePeriod = [packet uintAtOffset:4] / 1000000.0;
		self.powerTotal = [packet uintAtOffset:8];
		self.deltaSequence = [packet uintAtOffset:12];
		self.controllerOrdinal = [packet uintAtOffset:16];
		self.groupOrdinal = [packet uintAtOffset:20];

		self.artnetUniverse = [packet ushortAtOffset:24];
		self.artnetChannel = [packet ushortAtOffset:26];
        if (packet.length >= 30 && self.softwareRevision > 100) {
            self.port = [packet ushortAtOffset:28];
        } else {
            self.port = kDefaultPusherPort;
        }
		
		// A minor complication here.  The PixelPusher firmware generates announce packets from
		// a static structure, so the size of stripFlags is always 8;  even if there are fewer
		// strips configured.  So we have a wart. - jls.

		int stripFlagSize = 8;
		if (self.stripsAttached > stripFlagSize) stripFlagSize = self.stripsAttached;
		
		NSMutableArray *theStripFlags = NSMutableArray.new;
		self.stripFlags = theStripFlags;
		if (packet.length >= (30+stripFlagSize) && self.softwareRevision > 108) {
			for (int i=0; i<stripFlagSize; i++) {
				uint8_t flag = [packet ubyteAtOffset:30+i];
				[theStripFlags addObject:@(flag)];
			}
		} else {
			for (int i=0; i<stripFlagSize; i++) [theStripFlags addObject:@(0)];
		}

		// you may be asking yourself, why the +2 on that postStripFlagOffset calculation?
		// well, the PixelPusher device uses a fixed struct with compiler enforced 4-byte
		// aligned ints for this and so requires 2-byte padding before the 4-byte int types
		// that follow the strip flags.  PixelPusher is also hard fixed at 8 strip flags, so
		// this padding requirement is fixed.  other devices that support >8 strips don't use a
		// fixed struct and insert this padding to comply with this spec, so we can safely
		// add this 2-byte padding regardless of strip count.
		int postStripFlagOffset = 30 + stripFlagSize + 2;
		if (packet.length >= (postStripFlagOffset+(4*3)) && self.softwareRevision > 116) {
			self.pusherFlags = [packet uintAtOffset:postStripFlagOffset];
			self.segments = [packet uintAtOffset:postStripFlagOffset+4];
			self.powerDomain = [packet uintAtOffset:postStripFlagOffset+8];
		}
	}
	return self;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@ (%@:%d, controller %d, group %d, deltaSeq %lld, update %f, power %lld, flags %03x, firmware v%1.2f, hardware rev %d)",
			super.description, self.ipAddress, self.port, self.controllerOrdinal, self.groupOrdinal, self.deltaSequence, self.updatePeriod,
			self.powerTotal, self.pusherFlags, self.softwareRevision/100.0f, self.hardwareRevision];
}

- (void)setBrightness:(PPFloatPixel)brightness {
	if (!PPFloatPixelEqual(_brightness, brightness)) {
		_brightness = brightness;
		if (_strips) {
			[_strips forEach:^(PPStrip* strip, NSUInteger idx, BOOL *stop) {
				strip.brightness = brightness;
			}];
		}
	}
}

- (void)allocateStrips {
	if (!_strips) {
		NSMutableArray *array = NSMutableArray.new;
		for (int i=0; i<self.stripsAttached; i++) {
			int32_t stripFlags = [self.stripFlags[i] intValue];
			PPStrip *strip = [PPStrip.alloc initWithStripNumber:i pixelCount:self.pixelsPerStrip flags:stripFlags];
			strip.brightness = self.brightness;
			[array addObject:strip];
		}
		_strips = array;
	}
}

- (void)copyHeader:(PPPixelPusher *)device {
	// reallocate strips if they got bigger
	if (self.stripsAttached < device.stripsAttached
		|| self.pixelsPerStrip < device.pixelsPerStrip)
	{
		_strips = nil;
	}
	NSMutableString *changes = NSMutableString.new;
	if (self.updatePeriod != device.updatePeriod) [changes appendFormat:@" updatePeriod: %1.2fms", device.updatePeriod*1000];
	if (self.deltaSequence != device.deltaSequence) [changes appendFormat:@" deltaSeq: %lld", device.deltaSequence];
	if (self.powerTotal != device.powerTotal) [changes appendFormat:@" power: %lld", device.powerTotal];
	if (changes.length > 0) DDLogInfo(@"update pusher %@: %@", self.ipAddress, changes);

	self.stripsAttached = device.stripsAttached;
	self.maxStripsPerPacket = device.maxStripsPerPacket;
	self.pixelsPerStrip = device.pixelsPerStrip;
	self.updatePeriod = device.updatePeriod;
	self.powerTotal = device.powerTotal;
	self.deltaSequence = device.deltaSequence;
	self.controllerOrdinal = device.controllerOrdinal;
	self.groupOrdinal = device.groupOrdinal;
	self.artnetChannel = device.artnetChannel;
	self.artnetUniverse = device.artnetUniverse;
	self.port = device.port;
	self.stripFlags = (NSArray*)device.stripFlags.copy;
	self.pusherFlags = device.pusherFlags;
	self.segments = device.segments;
	self.powerDomain = device.powerDomain;
}

- (BOOL)isEqualToPusher:(PPPixelPusher*)other {
    if (self == other)	return YES;
    if (other == nil)	return NO;

//    if (this.hasRGBOW() & !other.hasRGBOW()) {
//		if (getPixelsPerStrip() != other.getPixelsPerStrip() / 3)
//			return false;
//    }
//	if (!this.hasRGBOW() & other.hasRGBOW()) {
//		if (getPixelsPerStrip() / 3 != other.getPixelsPerStrip())
//			return false;
//    }
//    if (! (this.hasRGBOW() || other.hasRGBOW()))

	/* according to Jas:

	 Controller and group ordinals, strip per packets, and art net variables cannot change
	 during runtime.  They are only read from the config file when a pusher boots.
	 (This is by design-  it makes the pusher stateless, and therefore robust against
	 being switched out or power-switched externally).  Only power total, update period,
	 and delta sequence change at runtime, and delta sequence is handled by the device
	 registry directly.

	 We try to reduce the frequency with which we parse the squitters for anything other
	 than existence because it's computationally intensive to do so on a system that has
	 dozens of pushers, each squittering once a second.  So we return true for .equals()
	 as often as possible.  This also reduces gc load, which is important when we run on
	 dalvik since that has a notoriously capricious gc.
	 */

    // if it differs by less than half a msec, it has no effect on our timing
    if (fabs(self.updatePeriod - other.updatePeriod) > 0.0005
		|| self.stripsAttached != other.stripsAttached
		|| self.pixelsPerStrip != other.pixelsPerStrip
    	|| self.artnetChannel != other.artnetChannel
		|| self.artnetUniverse != other.artnetUniverse
		|| self.port != other.port
		|| labs(self.powerTotal - other.powerTotal) > 10000
		|| self.powerDomain != other.powerDomain
		|| self.segments != other.segments
		|| self.pusherFlags != other.pusherFlags)
	{
		return NO;
    }

    return YES;
}

- (void)setStrip:(int32_t)stripNumber pixels:(NSArray*)pixels {
//	if (stripNumber >= self.stripsAttached) return;
//	[self.strips[stripNumber] setPixels:pixels];
}

- (void)increaseExtraDelay:(NSTimeInterval)i {
	if (self.autoThrottle) {
		self.extraDelay += i;
		DDLogInfo(@"Group %d card %d extra delay now %f", self.groupOrdinal, self.controllerOrdinal, self.extraDelay);
    } else {
		DDLogVerbose(@"Group %d card %d would increase delay, but autothrottle is disabled.", self.groupOrdinal, self.controllerOrdinal);
    }
}

- (void)decreaseExtraDelay:(NSTimeInterval)i {
	if (self.autoThrottle) {
		self.extraDelay -= i;
		self.extraDelay = MAX(0, self.extraDelay);
	}
}

- (float)calcAverageBrightnessValue {
	float total = 0;

	// TODO: dispatch concurrently
	for (PPStrip* strip in _strips)	{
		total += [strip calcAverageBrightnessValue];
	}
	return total / _strips.count;

}

- (void)scaleBrightnessValues:(float)scale {
	if (scale > 1) scale = 1;
	
	for (PPStrip* strip in _strips)	{
		strip.brightnessScale = scale;
	}
}

@end

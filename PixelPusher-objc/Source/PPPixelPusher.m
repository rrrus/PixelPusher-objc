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

@interface PPPixelPusher ()
@property (nonatomic, assign) int32_t stripsAttached;
@property (nonatomic, assign) int32_t artnetUniverse;
@property (nonatomic, assign) int32_t artnetChannel;

// redeclaring readonly public interfaces for private assign access
@property (nonatomic, strong) NSArray *strips;
@property (nonatomic, assign) int32_t pixelsPerStrip;
@property (nonatomic, assign) int32_t groupOrdinal;
@property (nonatomic, assign) int32_t controllerOrdinal;
@property (nonatomic, assign) NSTimeInterval updatePeriod;
@property (nonatomic, assign) int64_t powerTotal;
@property (nonatomic, assign) int64_t deltaSequence;
@property (nonatomic, assign) int32_t maxStripsPerPacket;
@end

@implementation PPPixelPusher

- (id)initWithHeader:(PPDeviceHeader*)header {
	self = [super initWithHeader:header];
	if (self) {
		NSData *packet = header.packetRemainder;
		if (packet.length < 12) {
			[NSException raise:NSInvalidArgumentException format:@"expected header size %d, but got %d", 12, packet.length];
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
	}
	return self;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@ (%@, controller %d, group %d, deltaSeq %lld, update %f, power %lld)", super.description,
			self.ipAddress, self.controllerOrdinal, self.groupOrdinal, self.deltaSequence, self.updatePeriod, self.powerTotal];
}

- (void)allocateStrips {
	if (!_strips) {
		NSMutableArray *array = NSMutableArray.new;
		for (int i=0; i<self.stripsAttached; i++) {
			[array addObject:[PPStrip.alloc initWithStripNumber:i pixelCount:self.pixelsPerStrip]];
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
	if (self.updatePeriod != device.updatePeriod) [changes appendFormat:@" updatePeriod: %f", device.updatePeriod];
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
//		|| self.powerTotal != other.powerTotal
    	|| self.artnetChannel != other.artnetChannel
		|| self.artnetUniverse != other.artnetUniverse)
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

@end

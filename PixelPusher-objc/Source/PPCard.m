//
//  PPCard.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/31/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "GCDAsyncUdpSocket.h"
#import "HLDeferredList.h"
#import "NSData+Utils.h"
#import "PPCard.h"
#import "PPDeviceRegistry.h"
#import "PPPixelPusher.h"
#import "PPStrip.h"

INIT_LOG_LEVEL_INFO

static const uint32_t kPacketSize = 1460;

@interface PPCard () <GCDAsyncUdpSocketDelegate>
@property (nonatomic, strong) HLDeferred *flushPromise;
@property (nonatomic, strong) PPPixelPusher *pusher;

@property (nonatomic, strong) dispatch_queue_t packetQueue;
@property (nonatomic, assign) NSTimeInterval threadSleep; // = 0.004;
@property (nonatomic, assign) NSTimeInterval threadExtraDelay;
@property (nonatomic, assign) NSTimeInterval threadSendTime;
@property (nonatomic, assign) int64_t bandwidthEstimate;
@property (nonatomic, strong) NSMutableSet *packetPool;
@property (nonatomic, strong) NSMutableDictionary *packetsInFlight;
@property (nonatomic, strong) GCDAsyncUdpSocket *udpsocket;
@property (nonatomic, assign) BOOL canceled;
@property (nonatomic, assign) uint16_t pusherPort;
@property (nonatomic, assign) NSString *cardAddress;
@property (nonatomic, assign) int64_t packetNumber;

@property (nonatomic, strong) NSMutableDictionary *packetPromises;

@end

@implementation PPCard

- (id)initWithPusher:(PPPixelPusher*)pusher port:(uint16_t)port {
	self = [self init];
	if (self) {
		self.packetQueue = dispatch_queue_create("PPCard", DISPATCH_QUEUE_SERIAL);
		dispatch_set_target_queue(self.packetQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));

		self.pusher = pusher;
		self.pusherPort = port;

		self.flushPromise = [HLDeferred deferredWithResult:nil];
		self.packetPromises = NSMutableDictionary.new;

		self.udpsocket = [GCDAsyncUdpSocket.alloc initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
		NSError *error;
		[self.udpsocket connectToHost:self.pusher.ipAddress onPort:self.pusherPort error:&error];
		if (error) {
			[NSException raise:NSGenericException format:@"error connecting to pusher (%@): %@", self.pusher.ipAddress, error];
		}
		self.packetPool = NSMutableSet.new;
		self.packetsInFlight = NSMutableDictionary.new;
		self.cardAddress = self.pusher.ipAddress;
		self.packetNumber = 0;
		self.canceled = NO;
		if (self.pusher.updatePeriod > 0.0001 && self.pusher.updatePeriod < 1) {
			self.threadSleep = (self.pusher.updatePeriod) + 0.001;
		} else {
			self.threadSleep = 0.004;
		}
	}
	return self;
}

- (void)dealloc {
	[self cancelAllInFlight];
}

- (NSMutableData*)packetFromPool {
	NSMutableData *aPacket = self.packetPool.anyObject;
	if (!aPacket) {
		aPacket = NSMutableData.new;
		aPacket.length = kPacketSize;
	} else {
		[self.packetPool removeObject:aPacket];
	}
	return aPacket;
}

- (void)returnPacketToPool:(NSMutableData*)packet {
	if (packet) [self.packetPool addObject:packet];
}

- (void)setExtraDelay:(NSTimeInterval)delay {
	self.threadExtraDelay = delay;
}

- (BOOL)controls:(PPPixelPusher*)pusher {
	return [pusher isEqualToPusher:self.pusher];
}

- (void)cancelAllInFlight {
	// return all in-flight packets to the pool
	[self.packetsInFlight forEach:^(NSString *key, NSMutableData *packet, BOOL *stop) {
		[self returnPacketToPool:packet];
	}];
	[self.packetsInFlight removeAllObjects];

	// resolve all pending promises
	NSDictionary *promises = self.packetPromises.copy;
	[self.packetPromises removeAllObjects];
	[promises forEach:^(NSString* key, HLDeferred* promise, BOOL *stop) {
		[promise takeResult:nil];
	}];
}

- (void)shutDown {

}
- (void)start {

}
- (void)cancel {
	self.canceled = YES;
}

- (HLDeferred*)flush {
	int32_t totalLength = 0;
	BOOL payload;
	BOOL sentPacket = NO;
	float powerScale = PPDeviceRegistry.sharedRegistry.powerScale;

	const int32_t nStrips = self.pusher.strips.count;
	int32_t stripIdx = 0;
	const int32_t requestedStripsPerPacket = self.pusher.maxStripsPerPacket;
	const int32_t supportedStripsPerPacket = (kPacketSize - 4) / (1 + 3 * self.pusher.pixelsPerStrip);
	const int32_t stripPerPacket = MIN(requestedStripsPerPacket, supportedStripsPerPacket);

	while (stripIdx < nStrips) {
		payload = NO;
		NSMutableData *packet = self.packetFromPool;
		uint8_t *P = packet.mutableBytes;
		int32_t packetLength = 0;
		if (self.pusher.updatePeriod > 0.0001) {
			self.threadSleep = self.pusher.updatePeriod + 0.001;
		}
		packetLength += addIntToBuffer(&P, self.packetNumber);
		for (int i = 0; i < stripPerPacket;) {
			if (stripIdx >= nStrips) {
				break;
			}
			PPStrip *strip = self.pusher.strips[stripIdx];
			stripIdx++;
			if (strip.touched) {
				strip.powerScale = powerScale;
				*(P++) = strip.stripNumber;
				packetLength++;
				uint32_t stripPacketSize = [strip serialize:P];
				packetLength += stripPacketSize;
				P += stripPacketSize;

				NSAssert(packetLength < kPacketSize, @"packet buffer overrun!");
				payload = true;
				i++;
			}
		}
		if (payload) {
			// make a promise for this packet send
			HLDeferred *packetPromise = HLDeferred.new;
			id key = @(self.packetNumber);
			self.packetPromises[key] = packetPromise;
			// remember this packet
			self.packetsInFlight[key] = packet;
			// make a new NSData object with the actual number of bytes packaged
			NSData *outGoing = [NSData dataWithBytesNoCopy:packet.mutableBytes length:packetLength freeWhenDone:NO];
			// send the packet
			int64_t packetNumber = self.packetNumber;
			dispatch_async(self.packetQueue, ^{
				[self.udpsocket sendData:outGoing withTimeout:1 tag:packetNumber];
				// TODO: use dispatch_after instead of sleep
				// make sure there's a min delay between packets sent
				[NSThread sleepForTimeInterval:self.threadSleep + self.threadExtraDelay + self.pusher.extraDelay];
			});
			// bump the packet count
			self.packetNumber++;
			sentPacket = YES;
			totalLength += packetLength;
		} else {
			[self returnPacketToPool:packet];
		}
	}

	if (sentPacket) {
		// if we actually sent a packet, generate a new flush promise from all of the
		// packet promises.
		// if flush is called before a previous flush completes, the returned promise
		// will wait for all uncompleted packet promises to complete.
		NSMutableArray *promises = [NSMutableArray arrayWithCapacity:self.packetPromises.count];
		[self.packetPromises forEach:^(id key, id obj, BOOL *stop) {
			[promises addObject:obj];
		}];
		self.flushPromise = [HLDeferredList.alloc initWithDeferreds:promises];
	}

	return self.flushPromise;
}

#pragma mark - GCDAsyncUdpSocketDelegate methods

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag {
	id key = @(tag);
	// resolve packet promise
	HLDeferred *promise = self.packetPromises[key];
	[self.packetPromises removeObjectForKey:key];
	NSMutableData *packet = self.packetsInFlight[key];
	[self returnPacketToPool:packet];
	[self.packetsInFlight removeObjectForKey:key];
	[promise takeResult:nil];
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error {
	id key = @(tag);
	// resolve packet promise
	DDLogError(@"upd packet %ld send failed with error: %@", tag, error);
	HLDeferred *promise = self.packetPromises[key];
	[self.packetPromises removeObjectForKey:key];
	NSMutableData *packet = self.packetsInFlight[key];
	[self returnPacketToPool:packet];
	[self.packetsInFlight removeObjectForKey:key];
	[promise takeResult:error];
}

- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError *)error {
	DDLogError(@"card socket closed with error: %@", error);
	[self cancelAllInFlight];

	CFTimeInterval delayInSeconds = 1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		DDLogInfo(@"attempting to reconnect card socket");
		NSError *error;
		[self.udpsocket connectToHost:self.pusher.ipAddress onPort:self.pusherPort error:&error];
	});
}
@end

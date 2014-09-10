//
//  PPCard.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/31/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "GCDAsyncUdpSocket.h"
#import "HLDeferredList.h"
#import "NSData+Utils.h"
#import "PPCard.h"
#import "PPDeviceRegistry.h"
#import "PPPixelPusher.h"
#import "PPStrip.h"

INIT_LOG_LEVEL_INFO

@interface PPCard () <GCDAsyncUdpSocketDelegate>
@property (nonatomic, strong) HLDeferred *flushPromise;
@property (nonatomic, strong) PPPixelPusher *pusher;

@property (nonatomic, strong) dispatch_queue_t packetQueue;
@property (nonatomic, assign) NSTimeInterval threadSleep; // = 0.004;
@property (nonatomic, assign) NSTimeInterval threadExtraDelay;
@property (nonatomic, assign) NSTimeInterval threadSendTime;
@property (nonatomic, assign) int64_t bandwidthEstimate;
@property (nonatomic, assign) int32_t maxPacketSize;
@property (nonatomic, strong) NSMutableSet *packetPool;
@property (nonatomic, strong) NSMutableDictionary *packetsInFlight;
@property (nonatomic, strong) GCDAsyncUdpSocket *udpsocket;
@property (nonatomic, assign) BOOL canceled;
@property (nonatomic, assign) NSString *cardAddress;
@property (nonatomic, assign) int64_t packetNumber;
@property (nonatomic, strong) NSOutputStream* writeStream;
@property (nonatomic, assign) CFTimeInterval lastSendTime;
@property (nonatomic, assign) CFTimeInterval lastFrameTime;

@property (nonatomic, strong) NSMutableDictionary *packetPromises;

@end

@implementation PPCard

- (id)initWithPusher:(PPPixelPusher*)pusher {
	self = [self init];
	if (self) {
		self.packetQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

		self.pusher = pusher;

		self.flushPromise = [HLDeferred deferredWithResult:nil];
		self.packetPromises = NSMutableDictionary.new;

		self.udpsocket = [GCDAsyncUdpSocket.alloc initWithDelegate:self delegateQueue:self.packetQueue];
		[self.udpsocket setIPv6Enabled:NO];
		NSError *error;
		[self.udpsocket connectToHost:self.pusher.ipAddress onPort:self.pusher.port error:&error];
		if (error) {
			[NSException raise:NSGenericException format:@"error connecting to pusher (%@): %@", self.pusher.ipAddress, error];
		}
		self.maxPacketSize = 4 +  ((1 + 3 * pusher.pixelsPerStrip) * pusher.maxStripsPerPacket);
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
	[self.udpsocket close];
}

- (void)setRecord:(BOOL)record {
	if (record)	[self createWriteStream];
	else		[self closeWriteStream];
}

- (void)createWriteStream {
	if (!self.writeStream) {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString *appDocsDir = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;

		// write map to file
		NSDateFormatter *dateFormatter = NSDateFormatter.alloc.init;
		[dateFormatter setDateFormat:@"yyyy-MM-dd-HH-mm"];
		NSString *mapfilename = [NSString stringWithFormat:@"canfile.%d.%d.%@.ppshow",
								 self.pusher.groupOrdinal,
								 self.pusher.controllerOrdinal,
								 [dateFormatter stringFromDate:NSDate.date]];
		NSString *mapfilepath = [appDocsDir stringByAppendingPathComponent:mapfilename];
		self.writeStream = [NSOutputStream outputStreamToFileAtPath:mapfilepath append:NO];
		[self.writeStream open];
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(appWillBackground)
												   name:UIApplicationDidEnterBackgroundNotification
												 object:nil];
		_record = YES;
	}
}

- (void)closeWriteStream {
	if (self.writeStream) {
		[self.writeStream close];
		self.writeStream = nil;
		_record = NO;
	}
}

- (void)appWillBackground {
//	[self closeWriteStream];
}

- (NSMutableData*)packetFromPool {
	NSMutableData *aPacket = self.packetPool.anyObject;
	if (!aPacket) {
		aPacket = NSMutableData.new;
		aPacket.length = self.maxPacketSize;
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
	if (!self.udpsocket.isConnected || self.udpsocket.isClosed) {
		return self.flushPromise;
	}
	int32_t totalLength = 0;
	BOOL payload;
	BOOL sentPacket = NO;
	float powerScale = PPDeviceRegistry.sharedRegistry.powerScale;

	const NSUInteger nStrips = self.pusher.strips.count;
	int32_t stripIdx = 0;
	const int32_t requestedStripsPerPacket = self.pusher.maxStripsPerPacket;
	const int32_t stripPerPacket = MIN(requestedStripsPerPacket, (int32_t)nStrips);

	if (self.pusher.updatePeriod > 0.0001) {
		self.threadSleep = self.pusher.updatePeriod + 0.001;
	} else {
		// Shoot for the framelimit.
		self.threadSleep = ((1.0/PPDeviceRegistry.sharedRegistry.frameRateLimit) / (nStrips / stripPerPacket));
	}
	
	// Handle errant delay calculation in the firmware.
	if (self.pusher.updatePeriod > 0.1) {
		self.threadSleep = (0.016 / (nStrips / stripPerPacket));
	}
	
	CFTimeInterval totalDelay = self.threadSleep + self.threadExtraDelay + self.pusher.extraDelay;

	CFTimeInterval frameTime = CACurrentMediaTime();
	self.lastFrameTime = frameTime;
	CFTimeInterval packetTime = frameTime;
//	DDLogInfo(@"flushing card with inter-packet delay %1.3fms", totalDelay*1000);
	while (stripIdx < nStrips) {
		payload = NO;
		NSMutableData *packet = self.packetFromPool;
		uint8_t *P = packet.mutableBytes;
		uint8_t *endP = P + packet.length;
		int32_t packetLength = 0;

		packetLength += addIntToBuffer(&P, (int32_t)self.packetNumber);
		
		// TODO: PusherCommands sent here!
		
		for (int i = 0; i < stripPerPacket;) {
			if (stripIdx >= nStrips) {
				break;
			}
			PPStrip *strip = self.pusher.strips[stripIdx];
			stripIdx++;
			// output the strip if is touched, or if this is a fixed packet size pusher.
			if (strip.touched || (self.pusher.pusherFlags & PFLAG_FIXEDSIZE)) {
				strip.powerScale = powerScale;
				*(P++) = (uint8_t)strip.stripNumber;
				packetLength++;
				uint32_t stripPacketSize = [strip serialize:P size:(endP-P)];
				if (self.writeStream) {
					// TODO: update to canfile format 2
					
					// we need to make the pusher wait on playback the same length of time between strips as we wait between packets
					// this number is in microseconds.
					uint32_t buf = 0;
					if (i == 0 && self.lastSendTime != 0 ) {  // only write the delay in the first strip in a datagram.
						buf = NSSwapHostIntToLittle( (uint32_t)((packetTime-self.lastSendTime)*1000000.) );
					}
					[self.writeStream write:(uint8_t*)&buf maxLength:sizeof(buf)];

					[self.writeStream write:P-1 maxLength:stripPacketSize+1];
				}
				packetLength += stripPacketSize;
				P += stripPacketSize;

				NSAssert(packetLength <= self.maxPacketSize, @"packet buffer overrun!");
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

			// calculate the send time of the packet
			CFTimeInterval now = CACurrentMediaTime();
			CFTimeInterval lastInterval = now - self.lastSendTime;
			CFTimeInterval delay = totalDelay;
			if (lastInterval > totalDelay) {
				delay = 0;
			} else {
				delay = totalDelay - lastInterval;
			}
			self.lastSendTime = now + delay;
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self.packetQueue, ^{
//				CFTimeInterval delta = CACurrentMediaTime() - self.lastFrameTime;
				[self.udpsocket sendData:outGoing withTimeout:1 tag:packetNumber];
				dispatch_async(dispatch_get_main_queue(), ^{
					// resolve packet promise
					HLDeferred *promise = self.packetPromises[key];
					[self.packetPromises removeObjectForKey:key];
					[promise takeResult:nil];
				});
//				DDLogInfo(@"packet %lld queue time %1.3fms", packetNumber, delta*1000);
			});
			// bump the packet count
			self.packetNumber++;
			sentPacket = YES;
			totalLength += packetLength;
			packetTime += totalDelay;
		} else {
			[self returnPacketToPool:packet];
		}
	}

	if (sentPacket) {
		// if we actually sent a packet, generate a new flush promise from all of the
		// packet promises.
		// if flush is called before a previous flush completes, the returned promise
		// will wait for all uncompleted packet promises to complete.
		self.flushPromise = [HLDeferredList.alloc initWithDeferreds:[self.packetPromises allValues]];
	}

	return self.flushPromise;
}

#pragma mark - GCDAsyncUdpSocketDelegate methods

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag {
	id key = @(tag);
//	CFTimeInterval delta = CACurrentMediaTime() - self.lastFrameTime;
//	DDLogInfo(@"packet %ld send time %1.3fms", tag, delta*1000);
	dispatch_async(dispatch_get_main_queue(), ^{
		// return packet to packet pool
		NSMutableData *packet = self.packetsInFlight[key];
		[self returnPacketToPool:packet];
		[self.packetsInFlight removeObjectForKey:key];
	});
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error {
	id key = @(tag);
	// resolve packet promise
	DDLogError(@"upd packet %ld send failed with error: %@", tag, error);
	dispatch_async(dispatch_get_main_queue(), ^{
		HLDeferred *promise = self.packetPromises[key];
		[self.packetPromises removeObjectForKey:key];
		NSMutableData *packet = self.packetsInFlight[key];
		[self returnPacketToPool:packet];
		[self.packetsInFlight removeObjectForKey:key];
		[promise takeResult:error];
	});
}

- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError *)error {
	DDLogError(@"card socket closed with error: %@", error);
	dispatch_async(dispatch_get_main_queue(), ^{
		[self cancelAllInFlight];
		[self.udpsocket close];

		[PPDeviceRegistry.sharedRegistry expireDevice:self.pusher.macAddress];
	});
}
@end

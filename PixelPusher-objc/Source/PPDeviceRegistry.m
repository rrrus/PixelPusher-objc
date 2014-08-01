//
//  PPDeviceRegistry.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "PPDeviceHeader.h"
#import "PPDeviceRegistry.h"
#import "PPPixel.h"
#import "PPPixelPusher.h"
#import "PPPusherGroup.h"
#import "PPScene.h"
#import "GCDAsyncUdpSocket.h"
#import <UIKit/UIKit.h>

INIT_LOG_LEVEL_INFO

STRING_KEY(PPDeviceRegistryAddedPusher);
STRING_KEY(PPDeviceRegistryUpdatedPusher);
STRING_KEY(PPDeviceRegistryRemovedPusher);

static const int32_t kDiscoveryPort = 7331;
static const int32_t kDisconnectTimeout = 10;
static const int64_t kExpiryTimerInterval = 1;

static int64_t gTotalPower = 0;
static int64_t gTotalPowerLimit = -1;
static float gPowerScale = 1.0;
static BOOL gAutoThrottle = NO;
static PPDeviceRegistry *gSharedRegistry;

@interface PPDeviceRegistry () <GCDAsyncUdpSocketDelegate> {
	NSMutableDictionary *_pusherMap;
	NSMutableDictionary *_groupMap;
}
@property (nonatomic, strong) NSMutableDictionary *pusherLastSeenMap;
@property (nonatomic, strong) NSMutableOrderedSet *sortedPushers;
@property (nonatomic, strong) NSMutableOrderedSet *sortedGroups;
@property (nonatomic, strong) NSMutableArray *stripsCache;

@property (nonatomic, strong) GCDAsyncUdpSocket	*discoverySocket;
@property (nonatomic, strong) PPScene *scene;

@end


@implementation PPDeviceRegistry

+ (PPDeviceRegistry*)sharedRegistry {
	if (!gSharedRegistry) gSharedRegistry = PPDeviceRegistry.new;
	return gSharedRegistry;
}

- (int64_t)totalPower {
	return gTotalPower;
}

- (void)setTotalPowerLimit:(int64_t)powerLimit {
	gTotalPowerLimit = powerLimit;
}

- (int64_t)totalPowerLimit {
	return gTotalPowerLimit;
}

- (float)powerScale {
	return gPowerScale;
}

- (void)setExtraDelay:(NSTimeInterval)delay {
	[self.scene setExtraDelay:delay];
}

- (void)setFrameDelegate:(id<PPFrameDelegate>)frameDelegate {
	self.scene.frameDelegate = frameDelegate;
}

- (void)setAutoThrottle:(BOOL)autothrottle {
	gAutoThrottle = autothrottle;
	[self.scene setAutoThrottle:autothrottle];
}

- (void)setGlobalBrightness:(float)globalBrightness {
	self.scene.globalBrightness = globalBrightness;
}

- (float)globalBrightness {
	return self.scene.globalBrightness;
}

- (int64_t)getTotalBandwidth {
	return self.scene.totalBandwidth;
}

- (BOOL)record {
	return self.scene.record;
}

- (void)setRecord:(BOOL)record {
	self.scene.record = record;
}

- (id)init
{
    self = [super init];
    if (self) {
		self.frameRateLimit = 60;
		_pusherMap = NSMutableDictionary.new;
		_groupMap = NSMutableDictionary.new;
		self.sortedPushers = NSMutableOrderedSet.new;
		self.sortedGroups = NSMutableOrderedSet.new;
		self.pusherLastSeenMap = NSMutableDictionary.new;
		self.scene = PPScene.new;

		[self bind];
		
		// monitor pushers' timeouts
		[NSTimer scheduledTimerWithTimeInterval:kExpiryTimerInterval
										 target:self
									   selector:@selector(deviceExpiryTask:)
									   userInfo:nil
										repeats:YES];
		
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(appDidBackground)
												   name:UIApplicationDidEnterBackgroundNotification
												 object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(appDidActivate)
												   name:UIApplicationDidBecomeActiveNotification
												 object:nil];

    }
    return self;
}

- (void)appDidActivate {
	// delay 1s in case we were switched in from another PP app
	[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(bind) userInfo:nil repeats:NO];
}

- (void)appDidBackground {
	[self unbind];
}

- (void)bind {
	if (!self.discoverySocket) {
		// setup the discovery service
		self.discoverySocket = [GCDAsyncUdpSocket.alloc initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
		[self.discoverySocket setIPv6Enabled:NO];
		NSError *error;
		[self.discoverySocket bindToPort:kDiscoveryPort error:&error];
		if (error) {
			UIAlertView *alert = [UIAlertView.alloc initWithTitle:@"PixelPusher"
														  message:@"Another PixelPusher app is preventing me from finding PixelPushers.  Be a lamb and kill it for me?"
														 delegate:nil
												cancelButtonTitle:@"Sure thing, honey"
												otherButtonTitles:nil, nil];
			[alert show];
			return;
//			self.discoverySocket = nil;
		}
		[self.discoverySocket enableBroadcast:YES error:&error];
		if (error) {
			[NSException raise:NSGenericException format:@"error enabling broadcast on discovery port: %@", error];
		}
		[self.discoverySocket beginReceiving:&error];
		if (error) {
			[NSException raise:NSGenericException format:@"error beginning receive on discovery port: %@", error];
		}
	}
}

- (void)unbind {
	if (self.discoverySocket) {
		[self.discoverySocket close];
		self.discoverySocket = nil;
	}
}

- (NSArray*)strips {
	if (!self.stripsCache) {
		self.stripsCache = NSMutableArray.new;
		[self.sortedPushers forEach:^(PPPixelPusher *pusher, NSUInteger idx, BOOL *stop) {
			[self.stripsCache addObjectsFromArray:pusher.strips];
		}];
	}
	return self.stripsCache;
}

- (NSArray*)pushers {
	return self.sortedPushers.array;
}

- (NSArray*)groups {
	return self.sortedGroups.array;
}

- (NSArray*)pushersInGroup:(int32_t)groupNumber {
	PPPusherGroup *group = DYNAMIC_CAST(PPPusherGroup, self.groupMap[@(groupNumber)]);
	
	if (group != nil)	return group.pushers;
	else				return @[];
}

- (NSArray*)stripsInGroup:(int32_t)groupNumber {
	PPPusherGroup *group = DYNAMIC_CAST(PPPusherGroup, self.groupMap[@(groupNumber)]);

	if (group != nil)	return group.strips;
	else				return @[];
}

- (void)deviceExpiryTask:(NSTimer*)timer {
	NSMutableArray *toKill = NSMutableArray.new;
	[self.pusherMap forEach:^(NSString *deviceMac, PPPixelPusher *pusher, BOOL *stop) {
		NSTimeInterval lastSeenSeconds = fabs( [self.pusherLastSeenMap[deviceMac] timeIntervalSinceNow] );
		if (lastSeenSeconds > kDisconnectTimeout) [toKill addObject:deviceMac];
	}];
	[toKill forEach:^(NSString *doomedIndividual, NSUInteger idx, BOOL *stop) {
		[self expireDevice:doomedIndividual];
	}];
}

- (void)expireDevice:(NSString*)macAddr {
	DDLogInfo(@"Device gone: %@", macAddr);
	PPPixelPusher *pusher = self.pusherMap[macAddr];
	if (pusher) {
		[_pusherMap removeObjectForKey:macAddr];
		[self.pusherLastSeenMap removeObjectForKey:macAddr];
		[self.sortedPushers removeObject:pusher];
		self.stripsCache = nil;
		PPPusherGroup *group = self.groupMap[@(pusher.groupOrdinal)];
		[group removePusher:pusher];
		if (group.pushers.count == 0) {
			[_groupMap removeObjectForKey:@(pusher.groupOrdinal)];
			[self.sortedGroups removeObject:group];
		}
		
		if (self.scene.isRunning) [self.scene removePusher:pusher];

		[NSNotificationCenter.defaultCenter postNotificationName:PPDeviceRegistryRemovedPusher object:pusher];
	}
}

- (void)setStrip:(NSString*)macAddress index:(int32_t)stripNumber pixels:(NSArray*)pixels {
//	[self.pusherMap[macAddress] setStrip:stripNumber pixels:pixels];
}

- (void)startPushing {
	if (!self.scene.isRunning) [self.scene start];
}

- (void)stopPushing {
	if (self.scene.isRunning) [self.scene cancel];
}

- (void)receive:(NSData*)data {
    // This is for the UDP callback, this should not be called directly
	PPDeviceHeader *header = [PPDeviceHeader.alloc initWithPacket:data];
	NSString *macAddr = header.macAddressString;
	if (header.deviceType != ePixelPusher) {
		DDLogInfo(@"Ignoring non-PixelPusher discovery packet from %@", header);
		return;
	}
	PPPixelPusher *device = [PPPixelPusher.alloc initWithHeader:header];
	DDLogVerbose(@"squitter %@", device);
	// Set the timestamp for the last time this device checked in
	self.pusherLastSeenMap[macAddr] = NSDate.date;
	if (!self.pusherMap[macAddr]) {
		// We haven't seen this device before
		[self addNewPusher:device macAddress:macAddr];
	} else {
		PPPixelPusher *existing = self.pusherMap[macAddr];
		if (![existing isEqualToPusher:device]) { // we already saw it
			[self updatePusher:device macAddress:macAddr];
		} else {
			// The device is identical, nothing has changed
			DDLogVerbose(@"Device still present: %@", existing.ipAddress);
			// if we dropped more than occasional packets, slow down a little
			if (device.deltaSequence > 3) {
				DDLogInfo(@"packet loss %lld on %@", device.deltaSequence, existing.ipAddress);
				[existing increaseExtraDelay:0.002];
			} else if (device.deltaSequence < 1) {
				[existing decreaseExtraDelay:0.001];
			}
		}
	}

	// update the power limit variables
	if (gTotalPowerLimit > 0) {
		gTotalPower = 0;
		[self.sortedPushers forEach:^(PPPixelPusher *pusher, NSUInteger idx, BOOL *stop) {
			gTotalPower += pusher.powerTotal;
		}];
		if (gTotalPower > gTotalPowerLimit) {
			gPowerScale = gTotalPowerLimit / gTotalPower;
		} else {
			gPowerScale = 1.0;
		}
	}
}

- (void)updatePusher:(PPPixelPusher*)device macAddress:(NSString*)macAddr {
	// We already knew about this device at the given MAC, but its details
	// have changed
	DDLogVerbose(@"Device changed: %@", macAddr);
	PPPixelPusher *pusher = self.pusherMap[macAddr];
	[pusher copyHeader:device];
	[self.sortedPushers sortUsingComparator:PPPixelPusher.sortComparator];

	// NOTE: dispatch on main queue if ever udp receive is handled on non-main queue
	[NSNotificationCenter.defaultCenter postNotificationName:PPDeviceRegistryUpdatedPusher object:pusher];
}

- (void)addNewPusher:(PPPixelPusher*)pusher macAddress:(NSString*)macAddr {
	// tell the pusher to finish allocating itself
	[pusher allocateStrips];
	DDLogInfo(@"new pusher: %@", pusher);
	DDLogVerbose(@"New device: %@ has group ordinal %d", macAddr, pusher.groupOrdinal);
	_pusherMap[macAddr] = pusher;
	[self.sortedPushers addObject:pusher];
	// TODO: would be nice to use a tree-based set that inserts in sort order
	[self.sortedPushers sortUsingComparator:PPPixelPusher.sortComparator];
	self.stripsCache = nil;

	if (self.groupMap[@(pusher.groupOrdinal)] != nil) {
		DDLogVerbose(@"Adding pusher to group %d", pusher.groupOrdinal);
		[self.groupMap[@(pusher.groupOrdinal)] addPusher:pusher];
	} else {
		// we need to create a PusherGroup since it doesn't exist yet.
		PPPusherGroup *pg = [PPPusherGroup.alloc initWithOrdinal:pusher.groupOrdinal];
		DDLogVerbose(@"Creating group and adding pusher to group %d", pusher.groupOrdinal);
		[pg addPusher:pusher];
		_groupMap[@(pusher.groupOrdinal)] = pg;
		[self.sortedGroups addObject:pg];
		[self.sortedGroups sortUsingComparator:^NSComparisonResult(PPPusherGroup *group0, PPPusherGroup *group1) {
			if (group0.ordinal == group1.ordinal) return NSOrderedSame;
			if (group0.ordinal  < group1.ordinal) return NSOrderedAscending;
			return NSOrderedDescending;
		}];
	}
		
	pusher.autoThrottle = gAutoThrottle;

	[NSNotificationCenter.defaultCenter postNotificationName:PPDeviceRegistryAddedPusher object:pusher];
}

#pragma mark - GCDAsyncUdpSocketDelegate methods

- (void)udpSocket:(GCDAsyncUdpSocket *)sock
   didReceiveData:(NSData *)data
	  fromAddress:(NSData *)address
withFilterContext:(id)filterContext
{
	[self receive:data];
}

- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError *)error {
	DDLogError(@"updSocketDidClose: %@", error);
}

@end

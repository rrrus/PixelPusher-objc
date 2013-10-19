//
//  PPDevice.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "PPDevice.h"
#import "PPDeviceHeader.h"
#import <sys/socket.h>

@interface PPDeviceImpl ()
@property (nonatomic, strong) PPDeviceHeader *header;
@end

@implementation PPDeviceImpl
// have to synthesize protocol properties
@synthesize macAddress;
@synthesize ipAddress;
@synthesize deviceType;
@synthesize protocolVersion;
@synthesize vendorId;
@synthesize productId;
@synthesize hardwareRevision;
@synthesize softwareRevision;
@synthesize linkSpeed;

- (id)initWithHeader:(PPDeviceHeader*)header {
	self = [self init];
	if (self) {
		self.header = header;
	}
	return self;
}

- (NSString *)macAddress {
	return self.header.macAddressString;
}

- (NSString *)ipAddress {
	return self.header.ipAddressString;
}

- (PPDeviceType)deviceType {
	return self.header.deviceType;
}

- (int32_t)protocolVersion {
	return self.header.protocolVersion;
}

- (int32_t)vendorId {
	return self.header.vendorId;
}

- (int32_t)productId {
	return self.header.productId;
}

- (int32_t)hardwareRevision {
	return self.header.hwRevision;
}

- (int32_t)softwareRevision {
	return self.header.swRevision;
}

- (int64_t)linkSpeed {
	return self.header.linkSpeed;
}

@end

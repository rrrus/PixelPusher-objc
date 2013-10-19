//
//  PPDeviceHeader.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PPDevice.h"

@interface PPDeviceHeader : NSObject

@property (nonatomic, readonly) struct sockaddr macAddress;
@property (nonatomic, readonly) struct sockaddr ipAddress;
@property (nonatomic, readonly) PPDeviceType deviceType;
@property (nonatomic, readonly) uint8_t protocolVersion;	///< for the device, not the discovery
@property (nonatomic, readonly) uint16_t vendorId;
@property (nonatomic, readonly) uint16_t productId;
@property (nonatomic, readonly) uint16_t hwRevision;
@property (nonatomic, readonly) uint16_t swRevision;
@property (nonatomic, readonly) uint32_t linkSpeed;			///< in bits per second
@property (nonatomic, readonly) NSData	*packetRemainder;

- (id)initWithPacket:(NSData*)packet;
- (NSString*)macAddressString;
- (NSString*)ipAddressString;

@end

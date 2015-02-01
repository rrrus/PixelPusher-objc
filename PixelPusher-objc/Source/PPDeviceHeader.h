//
//  PPDeviceHeader.h
//  PixelPusher-objc
//
//	PPDeviceHeader contains data read from a broadcast packet sent by a PixelPusher LED controller.
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//	Modified by Christopher Schardt in January of 2015
//	 * re-structured
//	 * brought in PPDeviceType
//	 * using DeviceHeader{} instead of NSData methods - quicker
//	 * quicker implementation of packetRemainder
//	 * created _ipAddress and _macAddress in [initWithPacket:]
//	 * added tests for basic packet validity
//

#import <Foundation/Foundation.h>


/////////////////////////////////////////////////
#pragma mark - TYPES:

typedef enum
{
	eEtherDream,
	eLumiaBridge,
	ePixelPusher
} PPDeviceType;


/////////////////////////////////////////////////
#pragma mark - CLASS:

@interface PPDeviceHeader : NSObject

// EXISTENCE:

- (id)initWithPacket:(NSData*)packet;

// PROPERTIES:

@property (nonatomic, readonly) NSString* macAddress;
@property (nonatomic, readonly) NSString* ipAddress;
@property (nonatomic, readonly) PPDeviceType deviceType;
@property (nonatomic, readonly) uint8_t protocolVersion;	// for the device, not the discovery
@property (nonatomic, readonly) uint16_t vendorId;
@property (nonatomic, readonly) uint16_t productId;
@property (nonatomic, readonly) uint16_t hwRevision;
@property (nonatomic, readonly) uint16_t swRevision;
@property (nonatomic, readonly) uint32_t linkSpeed;			// in bits per second

// PROPERTIES TO BE USED ONLY BY PPPusher:

@property (nonatomic, readonly) uint8_t const* packetRemainder;

@property (nonatomic, readonly) NSUInteger packetRemainderLength;

// OPERATIONS TO BE USED ONLY BY PPPusher:

- (void)releasePacketRemainder;

@end

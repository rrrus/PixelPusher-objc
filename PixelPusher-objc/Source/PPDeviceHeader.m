//
//  PPDeviceHeader.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//	Modified by Christopher Schardt in early 2015:
//	 * re-structured
//	 * brought in PPDeviceType
//	 * using DeviceHeader{} instead of NSData methods - quicker
//	 * quicker implementation of packetRemainder
//	 * created _ipAddress and _macAddress in [initWithPacket:]
//

#import <sys/socket.h>
#import <net/if.h>
#import <net/if_dl.h>
#import "PPPrivate.h"
#import "PPDeviceHeader.h"


/////////////////////////////////////////////////
#pragma mark - CONSTANTS:

static const int32_t PP_ACCEPTABLE_LOWEST_SW_REV = 121;


/////////////////////////////////////////////////
#pragma mark - TYPES:

typedef struct __attribute__((packed)) DeviceHeader
{
	uint8_t			macAddress[6];
	uint8_t			ipAddress[4];
	uint8_t			deviceType;
	uint8_t			protocolVersion;
	uint16_t		vendorId;
	uint16_t		productId;
	uint16_t		hwRevision;
	uint16_t		swRevision;
	uint32_t		linkSpeed;
} DeviceHeader;



/////////////////////////////////////////////////
#pragma mark - PRIVATE STUFF:

@interface PPDeviceHeader ()
{
	struct sockaddr	_macSockAddr;
	struct sockaddr	_ipSockAddr;
	NSData*			_packet;		// retained for [packetRemainder]
}

@end


@implementation PPDeviceHeader


/////////////////////////////////////////////////
#pragma mark - EXISTENCE:

- (id)initWithPacket:(NSData*)packet
{
	self = [self init];

	if (packet.length < sizeof(DeviceHeader))
	{
		ASSERT(NO);		// bad data or bug
		self = nil;		//??? Does ARC release self?
		return self;
	}

	DeviceHeader const*		const data = (DeviceHeader const*)packet.bytes;
	
	_deviceType = data->deviceType;
	if (_deviceType != ePixelPusher)
	{
		ASSERT(NO);		// could be other device, could be bug
		self = nil;		//??? Does ARC release self?
		return self;
	}

	if ((*(uint32_t*)data->macAddress == 0) &&
		(*(uint16_t*)(data->macAddress + 4) == 0))
	{
		ASSERT(NO);		// bad data or bug
		self = nil;		//??? Does ARC release self?
		return self;
	}
	memcpy(&_macSockAddr.sa_data, data->macAddress, 6);
	_macSockAddr.sa_len = 6;
	_macSockAddr.sa_family = AF_LINK;
	_macAddress = [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
								(uint8_t)_macSockAddr.sa_data[0], (uint8_t)_macSockAddr.sa_data[1],
								(uint8_t)_macSockAddr.sa_data[2], (uint8_t)_macSockAddr.sa_data[3],
								(uint8_t)_macSockAddr.sa_data[4], (uint8_t)_macSockAddr.sa_data[5]];

	if (*(uint32_t*)data->ipAddress == 0)	
	{
		ASSERT(NO);		// bad data or bug
		self = nil;		//??? Does ARC release self?
		return self;
	}
	*(uint32_t*)&_ipSockAddr.sa_data = *(uint32_t*)data->ipAddress;
	_ipSockAddr.sa_len = 4;
	_ipSockAddr.sa_family = AF_INET;
	_ipAddress = [NSString stringWithFormat:@"%d.%d.%d.%d",
								(uint8_t)_ipSockAddr.sa_data[0], (uint8_t)_ipSockAddr.sa_data[1],
								(uint8_t)_ipSockAddr.sa_data[2], (uint8_t)_ipSockAddr.sa_data[3]];
	
	_protocolVersion = data->protocolVersion;
	_vendorId = NSSwapLittleShortToHost(data->vendorId);
	_productId = NSSwapLittleShortToHost(data->productId);
	_linkSpeed = NSSwapLittleIntToHost(data->linkSpeed);
	_hwRevision = NSSwapLittleShortToHost(data->hwRevision);
	_swRevision = NSSwapLittleShortToHost(data->swRevision);
	
	if (_swRevision < PP_ACCEPTABLE_LOWEST_SW_REV)
	{
		// TODO: use the device registry delegate to relay this message
		DDLogWarn(@"WARNING!  This PixelPusher Library requires firmware revision %g", PP_ACCEPTABLE_LOWEST_SW_REV/100.0);
		DDLogWarn(@"WARNING!  This PixelPusher is using %g", softwareRevision/100.0);
		DDLogWarn(@"WARNING!  This is not expected to work.  Please update your PixelPusher.");
	}
	
	_packet = packet;	// retain for use by [packetRemainder]
	
	return self;
}


/////////////////////////////////////////////////
#pragma mark - PROPERTIES:

- (NSString*)description
{
	NSMutableString *outStr = NSMutableString.string;
	switch (_deviceType)
	{
		case eEtherDream:	[outStr appendString:@"EtherDream"]; break;
		case eLumiaBridge:	[outStr appendString:@"LumiaBridge"]; break;
		case ePixelPusher:	[outStr appendString:@"PixelPusher"]; break;
		default:			[outStr appendString:@"unknown"]; break;
	}
	[outStr appendFormat:@": MAC(%@), ", self.macAddress];
	[outStr appendFormat:@"IP(%@), ", self.ipAddress];
	[outStr appendFormat:@"Protocol Ver(%d), ", _protocolVersion];
	[outStr appendFormat:@"Vendor ID(%d), ", _vendorId];
	[outStr appendFormat:@"Product ID(%d), ", _productId];
	[outStr appendFormat:@"HW Rev(%d), ", _hwRevision];
	[outStr appendFormat:@"SW Rev(%d), ", _swRevision];
	[outStr appendFormat:@"Link Spd(%d)", _linkSpeed];
	return outStr;
}

- (uint8_t const*)packetRemainder
{
	ASSERT(_packet);		// [releasePacketRemainder called too early?]
	return _packet.bytes + sizeof(DeviceHeader);
}
- (NSUInteger)packetRemainderLength
{
	ASSERT(_packet);		// [releasePacketRemainder called too early?]
	return _packet.length - sizeof(DeviceHeader);
}


/////////////////////////////////////////////////
#pragma mark - OPERATIONS:

- (void)releasePacketRemainder
{
	_packet = nil;
}


@end

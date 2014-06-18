//
//  PPDeviceHeader.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <sys/socket.h>
#import <net/if.h>
#import <net/if_dl.h>
#import "NSData+Utils.h"
#import "PPDeviceHeader.h"

static const int headerLength = 24;

@interface PPDeviceHeader()
@end

@implementation PPDeviceHeader

- (id)initWithPacket:(NSData*)packet {
	self = [self init];
	if (self) {
		if (packet.length < headerLength) {
			[NSException raise:NSInvalidArgumentException format:@"expected header size %d, but got %lu", headerLength, (unsigned long)packet.length];
		}

		[packet getBytes:&(_macAddress.sa_data) range:NSMakeRange(0, 6)];
		_macAddress.sa_len = 6;
		_macAddress.sa_family = AF_LINK;
		[packet getBytes:&_ipAddress.sa_data range:NSMakeRange(6, 4)];
		_ipAddress.sa_len = 4;
		_ipAddress.sa_family = AF_INET;
		_deviceType = [packet ubyteAtOffset:10];
		_protocolVersion = [packet ubyteAtOffset:11];
		_vendorId = [packet ushortAtOffset:12];
		_productId = [packet ushortAtOffset:14];
		_hwRevision = [packet ushortAtOffset:16];
		_swRevision = [packet ushortAtOffset:18];
		_linkSpeed = [packet uintAtOffset:20];
		_packetRemainder = [packet subdataWithRange:NSMakeRange(headerLength, packet.length-headerLength)];
	}
	return self;
}

- (NSString*)description {
	NSMutableString *outStr = NSMutableString.string;
	switch (_deviceType) {
		case eEtherDream:	[outStr appendString:@"EtherDream"]; break;
		case eLumiaBridge:	[outStr appendString:@"LumiaBridge"]; break;
		case ePixelPusher:	[outStr appendString:@"PixelPusher"]; break;
		default:			[outStr appendString:@"unknown"]; break;
	}
	[outStr appendFormat:@": MAC(%@), ", self.macAddressString];
	[outStr appendFormat:@"IP(%@), ", self.ipAddressString];
	[outStr appendFormat:@"Protocol Ver(%d), ", _protocolVersion];
	[outStr appendFormat:@"Vendor ID(%d), ", _vendorId];
	[outStr appendFormat:@"Product ID(%d), ", _productId];
	[outStr appendFormat:@"HW Rev(%d), ", _hwRevision];
	[outStr appendFormat:@"SW Rev(%d), ", _swRevision];
	[outStr appendFormat:@"Link Spd(%d)", _linkSpeed];
	return outStr;
}

- (NSString*)macAddressString {
	return [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
			(uint8_t)_macAddress.sa_data[0], (uint8_t)_macAddress.sa_data[1], (uint8_t)_macAddress.sa_data[2],
			(uint8_t)_macAddress.sa_data[3], (uint8_t)_macAddress.sa_data[4], (uint8_t)_macAddress.sa_data[5]];
}

- (NSString*)ipAddressString {
	NSMutableString *str = NSMutableString.string;
	for (int i=0; i<_ipAddress.sa_len; i++) {
		[str appendFormat:@"%d", (uint8_t)_ipAddress.sa_data[i]];
		if (i<_ipAddress.sa_len-1) [str appendString:@"."];
	}
	return str;
}

@end

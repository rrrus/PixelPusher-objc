//
//  PPPusherCommand.m
//  PixelPusher-objc
//
// PPPusherCommand is an Objective-C class that encapsulates a command sent
// to a PixelPusher LED controller.
//
// After creating a PPPusherCommand, pass it to [PPPusher enqueuePusherCommand:],
// or [PPRegistry enqueuePusherCommandInAllPushers:]
//
// Created in 2014 Christopher Schardt
// Based on PusherCommand.java by Jas Strong
//

#import "PPPusherCommand.h"


/////////////////////////////////////////////////
#pragma mark - SWITCHES:


/////////////////////////////////////////////////
#pragma mark - TYPES:


/////////////////////////////////////////////////
#pragma mark - STATIC DATA:

static UInt8	const theMagicCookie[16] = 
{ 0x40, 0x09, 0x2d, 0xa6, 0x15, 0xa5, 0xdd, 0xe5, 0x6a, 0x9d, 0x4d, 0x5a, 0xcf, 0x09, 0xaf, 0x50 };


/////////////////////////////////////////////////
#pragma mark - PRIVATE STUFF

@interface PPPusherCommand ()

@property (nonatomic, strong) NSData* data;	// re-declared so that we can set it

@end


@implementation PPPusherCommand


/////////////////////////////////////////////////
#pragma mark - EXISTENCE

+ (PPPusherCommand*)resetCommand
{
	UInt8				bytes[sizeof(theMagicCookie) + 1];
	
	memcpy(bytes, theMagicCookie, sizeof(theMagicCookie));
	bytes[sizeof(theMagicCookie)] = PPPusherCommandReset;
	
	PPPusherCommand*	const command = [PPPusherCommand.alloc init];

	[command setData:[NSData dataWithBytes:bytes length:sizeof(bytes)]];
	return command;
}

+ (PPPusherCommand*)globalBrightnessCommand:(UInt16)brightness
{
	UInt8				bytes[sizeof(theMagicCookie) + 3];
	
	memcpy(bytes, theMagicCookie, sizeof(theMagicCookie));
	bytes[sizeof(theMagicCookie)] = PPPusherCommandGlobalBrightness;
	*(UInt16*)&bytes[sizeof(theMagicCookie) + 1] = NSSwapHostShortToLittle(brightness);

	PPPusherCommand*	const command = [PPPusherCommand.alloc init];
	
	[command setData:[NSData dataWithBytes:bytes length:sizeof(bytes)]];
	return command;
}
+ (PPPusherCommand*)brightnessCommand:(UInt16)brightness forStrip:(NSUInteger)strip
{
	assert(strip <= 255);

	UInt8				bytes[sizeof(theMagicCookie) + 4];
	
	memcpy(bytes, theMagicCookie, sizeof(theMagicCookie));
	bytes[sizeof(theMagicCookie)] = PPPusherCommandStripBrightness;
	bytes[sizeof(theMagicCookie) + 1] = (UInt8)strip;
	*(UInt16*)&bytes[sizeof(theMagicCookie) + 2] = NSSwapHostShortToLittle(brightness);

	PPPusherCommand*	const command = [PPPusherCommand.alloc init];
	
	[command setData:[NSData dataWithBytes:bytes length:sizeof(bytes)]];
	return command;
}

+ (PPPusherCommand*)wifiConfigureCommandForSSID:(NSString*)ssid
											key:(NSString*)key
											securityType:(PPPusherCommandSecurityType)securityType
{
	char const*			const ssidCString = ssid.UTF8String;
	char const*			const keyCString = key.UTF8String;
	NSUInteger			const ssidLength = ssid.length;
	NSUInteger			const keyLength = key.length;
	NSUInteger			const byteCount = sizeof(theMagicCookie) + 1 + ssidLength + 1 + keyLength + 1 + 1;
	
	if (byteCount > 1492 - 4)
	{
		NSAssert(NO, @"ssid and/or key are too long");
		return nil;
	}
	if ((strlen(ssidCString) != ssidLength) || (strlen(keyCString) != keyLength))
	{
		NSAssert(NO, @"ssid and/or key have non-ASCII characters");
		return nil;
	}
	
	UInt8				bytes[byteCount];
	UInt8*				b;
	
	b = bytes;
	memcpy(b, theMagicCookie, sizeof(theMagicCookie));
	b += sizeof(theMagicCookie);
	*b++ = PPPusherCommandWifiConfigure;

	memcpy(b, ssidCString, ssidLength + 1);
	b += ssidLength + 1;
	memcpy(b, keyCString, keyLength + 1);
	b += keyLength + 1;
	*b = (UInt8)securityType;
	
	PPPusherCommand*	const command = [PPPusherCommand.alloc init];

	[command setData:[NSData dataWithBytes:bytes length:byteCount]];
	return command;
}

+ (PPPusherCommand*)ledConfigureCommandForStripCount:(uint32_t)stripCount pixelsPerStrip:(uint32_t)pixelsPerStrip
									stripTypes:(PPPusherCommandStripTypes)stripTypes
									componentOrderings:(PPPusherCommandComponentOrderings)componentOrderings
{
	return [self ledConfigureCommandForStripCount:stripCount pixelsPerStrip:pixelsPerStrip
										stripTypes:stripTypes componentOrderings:componentOrderings
										group:0 controller:0
										artnetUniverse:0 artnetChannel:0];
}
+ (PPPusherCommand*)ledConfigureCommandForStripCount:(uint32_t)stripCount pixelsPerStrip:(uint32_t)pixelsPerStrip
									stripTypes:(PPPusherCommandStripTypes)stripTypes
									componentOrderings:(PPPusherCommandComponentOrderings)componentOrderings
									group:(UInt16)group controller:(UInt16)controller
{
	return [self ledConfigureCommandForStripCount:stripCount pixelsPerStrip:pixelsPerStrip
										stripTypes:stripTypes componentOrderings:componentOrderings
										group:group controller:controller
										artnetUniverse:0 artnetChannel:0];
}
+ (PPPusherCommand*)ledConfigureCommandForStripCount:(uint32_t)stripCount pixelsPerStrip:(uint32_t)pixelsPerStrip
									stripTypes:(PPPusherCommandStripTypes)stripTypes
									componentOrderings:(PPPusherCommandComponentOrderings)componentOrderings
									group:(UInt16)group controller:(UInt16)controller
									artnetUniverse:(UInt16)artnetUniverse artnetChannel:(UInt16)artnetChannel
{
	UInt8				bytes[sizeof(theMagicCookie) + 1 + 4 + 4 + 8 + 8 + 2 + 2 + 2 + 2];
	UInt8*				b;
	
	b = bytes;
	memcpy(b, theMagicCookie, sizeof(theMagicCookie));
	b += sizeof(theMagicCookie);
	*b++ = PPPusherCommandLedConfigure;
	
	*(uint32_t*)b = NSSwapHostIntToLittle(stripCount);
	b += sizeof(uint32_t);
	*(uint32_t*)b = NSSwapHostIntToLittle(pixelsPerStrip);
	b += sizeof(uint32_t);
	
	memcpy(b, stripTypes, sizeof(PPPusherCommandStripTypes));
	b += sizeof(PPPusherCommandStripTypes);
	memcpy(b, componentOrderings, sizeof(PPPusherCommandComponentOrderings));
	b += sizeof(PPPusherCommandComponentOrderings);
	
	*(UInt16*)b = NSSwapHostShortToLittle(group);
	b += sizeof(UInt16);
	*(UInt16*)b = NSSwapHostShortToLittle(controller);
	b += sizeof(UInt16);
	*(UInt16*)b = NSSwapHostShortToLittle(artnetUniverse);
	b += sizeof(UInt16);
	*(UInt16*)b = NSSwapHostShortToLittle(artnetChannel);

	PPPusherCommand*	const command = [PPPusherCommand.alloc init];

	[command setData:[NSData dataWithBytes:bytes length:sizeof(bytes)]];
	return command;
}


/////////////////////////////////////////////////
#pragma mark - PROPERTIES

- (PPPusherCommandType)type
{
	if (_data)
	{
		uint8_t const*	const data = _data.bytes;
		
		return data[sizeof(theMagicCookie)];
	}
	return 0;
}


@end



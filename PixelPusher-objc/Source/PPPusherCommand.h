//
//  PPPusherCommand.h
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

#import <Foundation/Foundation.h>


/////////////////////////////////////////////////
#pragma mark - TYPES:

typedef enum PPPusherCommandType
{
	PPPusherCommandReset =				0x01,
	PPPusherCommandGlobalBrightness =	0x02,
	PPPusherCommandWifiConfigure =		0x03,
	PPPusherCommandLedConfigure =		0x04,
	PPPusherCommandStripBrightness =	0x05,
}					PPPusherCommandType;

typedef enum PPPusherCommandSecurityType
{
	PPPusherCommandSecurityNone =		0,
	PPPusherCommandSecurityWep =		1,
	PPPusherCommandSecurityWpa =		2,
	PPPusherCommandSecurityWpa2 =		3,
}					PPPusherCommandSecurityType;

typedef enum PPPusherCommandStripType
{
	PPPusherCommandStripLPD8806 =	0,
	PPPusherCommandStripWS2801 =	1,
	PPPusherCommandStripWS2811 =	2,
	PPPusherCommandStripAPA102 =	3,
}					PPPusherCommandStripType;
typedef UInt8		PPPusherCommandStripTypes[8];

typedef enum PPPusherCommandComponentOrdering
{
	PPPusherCommandComponentRGB =	0,
	PPPusherCommandComponentRBG =	1,
	PPPusherCommandComponentGBR =	2,
	PPPusherCommandComponentGRB =	3,
	PPPusherCommandComponentBGR =	4,
	PPPusherCommandComponentBRG =	5,
}					PPPusherCommandComponentOrdering;
typedef UInt8		PPPusherCommandComponentOrderings[8];


/////////////////////////////////////////////////
#pragma mark - CLASS DEFINITION:

@interface PPPusherCommand : NSObject

// EXISTENCE

+ (PPPusherCommand*)resetCommand;
+ (PPPusherCommand*)globalBrightnessCommand:(UInt16)brightness;
+ (PPPusherCommand*)brightnessCommand:(UInt16)brightness forStrip:(NSUInteger)strip;
+ (PPPusherCommand*)wifiConfigureCommandForSSID:(NSString*)ssid
											key:(NSString*)key
											securityType:(PPPusherCommandSecurityType)securityType;
+ (PPPusherCommand*)ledConfigureCommandForStripCount:(uint32_t)stripCount pixelsPerStrip:(uint32_t)pixelsPerStrip
									stripTypes:(PPPusherCommandStripTypes)stripTypes
									componentOrderings:(PPPusherCommandComponentOrderings)componentOrderings;
+ (PPPusherCommand*)ledConfigureCommandForStripCount:(uint32_t)stripCount pixelsPerStrip:(uint32_t)pixelsPerStrip
									stripTypes:(PPPusherCommandStripTypes)stripTypes
									componentOrderings:(PPPusherCommandComponentOrderings)componentOrderings
									group:(UInt16)group controller:(UInt16)controller;
+ (PPPusherCommand*)ledConfigureCommandForStripCount:(uint32_t)stripCount pixelsPerStrip:(uint32_t)pixelsPerStrip
									stripTypes:(PPPusherCommandStripTypes)stripTypes
									componentOrderings:(PPPusherCommandComponentOrderings)componentOrderings
									group:(UInt16)group controller:(UInt16)controller
									artnetUniverse:(UInt16)artnetUniverse artnetChannel:(UInt16)artnetChannel;

// PROPERTIES

@property (nonatomic, readonly) PPPusherCommandType type;
@property (nonatomic, readonly) NSData* data;


@end



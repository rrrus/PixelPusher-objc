//
//  PPDevice.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
	eEtherDream,
	eLumiaBridge,
	ePixelPusher
} PPDeviceType;

@class PPDeviceHeader;

@protocol PPDevice <NSObject>

@property (nonatomic, readonly)	NSString *macAddress;
@property (nonatomic, readonly) NSString *ipAddress;
@property (nonatomic, readonly) PPDeviceType deviceType;
@property (nonatomic, readonly) int32_t protocolVersion;
@property (nonatomic, readonly) int32_t vendorId;
@property (nonatomic, readonly) int32_t productId;
@property (nonatomic, readonly) int32_t hardwareRevision;
@property (nonatomic, readonly) int32_t softwareRevision;
@property (nonatomic, readonly) int64_t linkSpeed;

@end

@interface PPDeviceImpl : NSObject<PPDevice>

- (id)initWithHeader:(PPDeviceHeader*)header;

@end

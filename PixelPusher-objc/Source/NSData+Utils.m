//
//  NSData+Utils.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/28/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "NSData+Utils.h"

@implementation NSData (Utils)

- (uint8_t)ubyteAtOffset:(NSUInteger)offset {
	uint8_t byte;
	[self getBytes:&byte range:NSMakeRange(offset, sizeof(byte))];
	return byte;
}
- (int8_t)byteAtOffset:(NSUInteger)offset {
	return (int8_t)[self ubyteAtOffset:offset];
}

- (uint16_t)ushortAtOffset:(NSUInteger)offset {
	uint16_t word;
	[self getBytes:&word range:NSMakeRange(offset, sizeof(word))];
	word = NSSwapLittleShortToHost(word);
	return word;
}
- (int16_t)shortAtOffset:(NSUInteger)offset {
	return (int16_t)[self ushortAtOffset:offset];
}

- (uint16_t)bigUshortAtOffset:(NSUInteger)offset {
	uint16_t word;
	[self getBytes:&word range:NSMakeRange(offset, sizeof(word))];
	word = NSSwapBigShortToHost(word);
	return word;
}

- (uint32_t)uintAtOffset:(NSUInteger)offset {
	uint32_t dword;
	[self getBytes:&dword range:NSMakeRange(offset, sizeof(dword))];
	dword = NSSwapLittleIntToHost(dword);
	return dword;
}
- (int32_t)intAtOffset:(NSUInteger)offset {
	return (int32_t)[self uintAtOffset:offset];
}

@end

size_t addIntToBuffer(uint8_t** buffer, int32_t num) {
	num = NSSwapHostIntToLittle(num);
	memcpy(*buffer, &num, sizeof(num));
	*buffer += sizeof(num);
	return sizeof(num);
}

size_t addInt64ToBuffer(uint8_t** buffer, int64_t num) {
	num = NSSwapHostLongLongToLittle(num);
	memcpy(*buffer, &num, sizeof(num));
	*buffer += sizeof(num);
	return sizeof(num);
}

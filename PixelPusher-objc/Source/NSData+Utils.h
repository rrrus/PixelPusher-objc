//
//  NSData+Utils.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/28/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (Utils)

- (uint8_t)ubyteAtOffset:(NSUInteger)offset;
- (int8_t)byteAtOffset:(NSUInteger)offset;

- (uint16_t)ushortAtOffset:(NSUInteger)offset;
- (int16_t)shortAtOffset:(NSUInteger)offset;
- (uint16_t)bigUshortAtOffset:(NSUInteger)offset;

- (uint32_t)uintAtOffset:(NSUInteger)offset;
- (int32_t)intAtOffset:(NSUInteger)offset;

@end

// copies the num into the buffer in little endian, advances the pointer,
// and returns the number of bytes the pointer was advanced
size_t addIntToBuffer(uint8_t** buffer, int32_t num);
size_t addInt64ToBuffer(uint8_t** buffer, int64_t num);
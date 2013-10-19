//
//  RRForEach.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSArray (ForEach)
- (void)forEach:(void (^)(id obj, NSUInteger idx, BOOL *stop))block NS_AVAILABLE(10_6, 4_0);
@end

@interface NSDictionary (ForEach)
- (void)forEach:(void (^)(id key, id obj, BOOL *stop))block NS_AVAILABLE(10_6, 4_0);
@end

@interface NSSet (ForEach)
- (void)forEach:(void (^)(id obj, BOOL *stop))block NS_AVAILABLE(10_6, 4_0);
@end

@interface NSOrderedSet (ForEach)
- (void)forEach:(void (^)(id obj, NSUInteger idx, BOOL *stop))block;
@end

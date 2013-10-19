//
//  NSArray+Utils.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "RRForEach.h"

@implementation NSArray (Utils)
- (void)forEach:(void (^)(id obj, NSUInteger idx, BOOL *stop))block {
	[self enumerateObjectsUsingBlock:block];
}
@end

@implementation NSDictionary (ForEach)
- (void)forEach:(void (^)(id key, id obj, BOOL *stop))block {
	[self enumerateKeysAndObjectsUsingBlock:block];
}
@end

@implementation NSSet (ForEach)
- (void)forEach:(void (^)(id obj, BOOL *stop))block {
	[self enumerateObjectsUsingBlock:block];
}
@end

@implementation NSOrderedSet (ForEach)
- (void)forEach:(void (^)(id obj, NSUInteger idx, BOOL *stop))block {
	[self enumerateObjectsUsingBlock:block];
}
@end

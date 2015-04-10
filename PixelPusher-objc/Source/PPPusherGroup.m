//
//  PPPusherGroup.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "PPPusherGroup.h"
#import "PPPixelPusher.h"

@interface PPPusherGroup ()
@property (nonatomic) uint32_t ordinal;
@property (nonatomic, strong) NSMutableArray *pushers;
@property (nonatomic, strong) NSArray *stripCache;
@end

@implementation PPPusherGroup

- (id)initWithOrdinal:(uint32_t)ordinal {
	self = [super init];
	if (self) {
		self.ordinal = ordinal;
		self.pushers = NSMutableArray.new;
	}
	return self;
}

- (uint32_t)ordinal {
	return _ordinal;
}

- (NSArray*)pushers {
	return _pushers;
}

- (NSUInteger)size {
	return self.pushers.count;
}

- (NSArray*)strips {
	if (!self.stripCache) {
		NSMutableArray *strips = NSMutableArray.new;
		self.stripCache = strips;
		[self.pushers forEach:^(PPPixelPusher* pusher, NSUInteger idx, BOOL *stop) {
			[strips addObjectsFromArray:pusher.strips];
		}];
	}
	return self.stripCache;
}

- (void)removePusher:(PPPixelPusher*)pusher {
	[_pushers removeObject:pusher];
	self.stripCache = nil;
}

- (void)addPusher:(PPPixelPusher*)pusher {
	[_pushers addObject:pusher];
	[_pushers sortUsingComparator:PPPixelPusher.sortComparator];
	self.stripCache = nil;
}

@end

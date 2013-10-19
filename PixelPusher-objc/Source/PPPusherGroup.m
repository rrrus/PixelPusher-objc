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
@property (nonatomic, strong) NSMutableSet *pushers;
@end

@implementation PPPusherGroup

- (id)initWithPushers:(NSSet*)pushers {
	self = [super init];
	if (self) {
		self.pushers = pushers.mutableCopy;
	}
	return self;
}

- (id)init {
	self = [super init];
	if (self) {
		self.pushers = NSMutableSet.new;
	}
	return self;
}

- (NSSet*)pushers {
	return self.pushers;
}

- (NSUInteger)size {
	return self.pushers.count;
}

- (NSArray*)strips {
	NSMutableArray *strips = NSMutableArray.new;
	[self.pushers forEach:^(PPPixelPusher* pusher, BOOL *stop) {
		[strips addObjectsFromArray:pusher.strips];
	}];
	return strips;
}

- (void)removePusher:(PPPixelPusher*)pusher {
	[_pushers removeObject:pusher];
}

- (void)addPusher:(PPPixelPusher*)pusher {
	[_pushers addObject:pusher];
}

@end

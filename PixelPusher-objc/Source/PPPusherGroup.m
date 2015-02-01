//
//  PPPusherGroup.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//	Modified by Christopher Schardt in late 2014
//	 * arranged stuff in source files
//	 * converted private properties to ivars
//	 * replaced insert-then-sort with sorted insertion
//

#import "PPPusherGroup.h"
#import "PPPusher.h"


/////////////////////////////////////////////////
#pragma mark - PRIVATE STUFF:

@interface PPPusherGroup ()
{
	NSMutableArray*		_pushers;
	NSMutableArray*		_strips;
}

@end


@implementation PPPusherGroup


/////////////////////////////////////////////////
#pragma mark - EXISTENCE:

- (id)initWithOrdinal:(uint32_t)ordinal
{
	self = [super init];
	if (self)
	{
		_ordinal = ordinal;
		_pushers = NSMutableArray.new;
	}
	return self;
}


/////////////////////////////////////////////////
#pragma mark - PROPERTIES:

- (NSArray*)pushers
{
	return _pushers;
}
- (NSArray*)strips
{
	if (!_strips)
	{
		PPPusher*		pusher;
		
		_strips = NSMutableArray.new;
		for (pusher in _pushers)
		{
			[_strips addObjectsFromArray:pusher.strips];
		}
	}
	return _strips;
}


/////////////////////////////////////////////////
#pragma mark - OPERATIONS:

- (void)addPusher:(PPPusher*)pusher
{
	NSUInteger		const insertionIndex = [_pushers indexOfObject:pusher
														inSortedRange:(NSRange){0, [_pushers count]}
														options:NSBinarySearchingInsertionIndex
														usingComparator:PPPusher.sortComparator];
	[_pushers insertObject:pusher atIndex:insertionIndex];
	_strips = nil;
}
- (void)removePusher:(PPPusher*)pusher
{
	[_pushers removeObject:pusher];
	_strips = nil;
}


@end

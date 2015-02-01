//
//  PPPusherGroup.h
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

#import <Foundation/Foundation.h>


/////////////////////////////////////////////////
#pragma mark - FORWARDS:

@class PPPusher;


/////////////////////////////////////////////////
#pragma mark - CLASS DEFINITION:

@interface PPPusherGroup : NSObject

// EXISTENCE:

- (id)initWithOrdinal:(uint32_t)ordinal;

// PROPERTIES:

@property (nonatomic, readonly) uint32_t ordinal;
@property (nonatomic, readonly) NSArray* pushers;	// sorted by controller ordinal
@property (nonatomic, readonly) NSArray* strips;	// sorted by controller ordinal, strip index

// OPERATIONS:

- (void)removePusher:(PPPusher*)pusher;
- (void)addPusher:(PPPusher*)pusher;

@end

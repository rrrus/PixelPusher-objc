/****************************************************************************
 *
 * "PPCard.h" defines the Objective-C class that sends data to a PixelPusher
 * controller on behalf of a PPPixelPusher object.  It is a separate class
 * (apparently) because in the Java PixelPusher library, it is a subclass
 * of Thread.  Ultimately someday someone might want to fold all of this
 * class' capabilities into PPPixelPusher.
 *
 * Originally Created by Rus Maxham on 5/31/13.
 * Copyright (c) 2013 rrrus. All rights reserved.
 *
 * Modified extensively by Christopher Schardt in November of 2014
 * The modifications largeley consisted of:
 *	- adding support for pusher commands
 *	- adding the DO_PACKET_POOL compiler switch to remove overly-complicated code
 *	- code made easier to read by adding blank lines, separating declarations, etc...
 *	- many private properties converted to IVARs
 *
 ****************************************************************************/

#import <Foundation/Foundation.h>


/////////////////////////////////////////////////
#pragma mark - SWICHES:

@class PPPixelPusher;


/////////////////////////////////////////////////
#pragma mark - CLASS DEFINITION:

@interface PPCard : NSObject

// EXISTENCE:

- (id)initWithPusher:(PPPixelPusher*)pusher;

// PROPERTIES:

@property (nonatomic, assign) NSTimeInterval extraDelay;
@property (nonatomic, assign) BOOL record;
@property (nonatomic, readonly) uint64_t bandwidthEstimate;	//??? currently just returns zero

- (BOOL)controls:(PPPixelPusher*)pusher;

// OPERATIONS:

- (void)shutDown;	// currently does nothing
- (void)start;		// currently does nothing
- (void)cancel;		// currently does nothing

- (HLDeferred*)flush;	// does everything

@end

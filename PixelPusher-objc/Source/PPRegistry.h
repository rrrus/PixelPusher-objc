//
//  PPRegistry.h
//  PixelPusher-objc
//
//	PPRegistry is an singleton Objective-C class that keeps track of all the
//	current PPPusherGroups and PPPushers.
//	 * It opens a UDP socket to receive broadcast packets from the PixelPusher controllers.
//	 * When it receives a packet, it either updates the corresponding PPPusher or creates it.
//	 * If a controller hasn't been heard from in a while, the corresponding PPPusher is deleted.
//	 * PPPusherGroups are formed using the groupOrdinal fields of the PPPushers.
//
//	To use this class:
//	 * Have one of your classes implement <PPFrameDelegate>
//	 * In [ppRenderStart], call the "setPixel(s)" methods in each PPStrip to set RGB data to send.
//	   (get references to PPStrips with PPRegistry.the.stripArray or PPRegistry.the.pusherArray[n].stripArray.)
//	 * You can do the above operation in the main queue and just return YES, or...
//	   you can return NO and then call [ppRenderFinished] (from the main thread) when you're finished.
//	 * The "setPixel(s)" methods may be called from a worker queue if not more than one queue is doing so,
//	   and not after [ppRenderFinished] has been called
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//
//	Modified extensively by Christopher Schardt in late 2014:
//		grouped properties, operations, responders, etc...
//		removed pusherMap, which was a duplicate of PPScene.pusherDict
//		fixed calculation of _powerScale
//		added [isRunning]
//		stripped out a lot of never-used code
//		combined with PPScene
//

#import <Foundation/Foundation.h>
#import "PPPusher.h"
#import "PPPusherCommand.h"
#import "PPPixel.h"


/////////////////////////////////////////////////
#pragma mark - CONSTANTS:

// These are posted to NSNotificationCenter.defaultCenter when
// PPPushers appear or disappear, with the PPPusher object as data:
extern NSString*	const PPRegistryPusherAppeared;
extern NSString*	const PPRegistryPusherDisappeared;


/////////////////////////////////////////////////
#pragma mark - FORWARDS:

@class PPPusherGroup;


/////////////////////////////////////////////////
#pragma mark - PROTOCOLS:

@protocol PPFrameDelegate <NSObject>

@required
// must return whether rendering was finished.
// If it wasn't, [ppRenderFinished] must be called when it is.
- (BOOL)ppRenderStart;

@end


/////////////////////////////////////////////////
#pragma mark - CLASS DEFINITION:

@interface PPRegistry : NSObject

// PROPERTIES:

+ (PPRegistry*)the;

@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL isCapturingToFile;

@property (nonatomic, weak) id<PPFrameDelegate> frameDelegate;
@property (nonatomic, assign) PPFloatPixel brightnessScale;

@property (nonatomic, readonly) NSArray* groupArray;		// PPPusherGroups, sorted by ordinal
@property (nonatomic, readonly) NSArray* pusherArray;		// PPPushers, sorted by [PPPusher sortComparator]	
@property (nonatomic, readonly) NSArray* stripArray;		// PPStrips, sorted by pusher/index in pusher
@property (nonatomic, readonly) NSDictionary* groupDict;	// PPPusherGroups, keyed by NSNumbers with ordinal
@property (nonatomic, readonly) NSDictionary* pusherDict;	// PPPushers, keyed by mac address string

- (PPPusherGroup*)groupWithOrdinal:(int32_t)groupOrdinal;	// convenience method

// Two ways of thinking of what is best to do when PPScene not running:
//	1) Keep PPPushers alive, so as to more seamlessly resume.
//	2) Release all PPPushers immediately so that resources are released
@property (nonatomic, assign) BOOL doKillPushersWhenNotRunning;

@property (nonatomic, assign) BOOL doAdjustForDroppedPackets;
@property (nonatomic, assign) uint32_t frameRateLimit;		// frames per second
@property (nonatomic, assign) NSTimeInterval extraDelay;
//@property (nonatomic, readonly) uint64_t totalBandwidthEstimate;	// not truly calculated yet

@property (nonatomic, assign) int64_t totalPowerLimit;		// if negative, no limiting applied
@property (nonatomic, readonly) uint64_t totalPower;		// not calculated if no limiting
@property (nonatomic, readonly) float powerScale;			// 1.0 when no scaling

// OPERATIONS:

- (void)enqueuePusherCommandInAllPushers:(PPPusherCommand*)command;

- (BOOL)scaleAverageBrightnessForLimit:(float)brightnessLimit		// >=1.0 for no scaling
							forEachPusher:(BOOL)forEachPusher;		// compute average for each pusher

// RESPONDERS:

// If [delegate ppRenderStart] returns NO, this must be called when rendering is finished:
- (void)ppRenderFinished;

// RESPONDERS FOR USE ONLY BY PPPusher:

- (void)ppAllPacketsSentByPusher:(PPPusher*)pusher;
- (void)pusherSocketFailed:(PPPusher*)pusher;

@end

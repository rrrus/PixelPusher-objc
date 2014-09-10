//
//  PPPusherGroup.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PPPixelPusher;

@interface PPPusherGroup : NSObject

- (id)initWithOrdinal:(int32_t)ordinal;

- (int32_t)ordinal;
// pushers array is sorted by controller ordinal
- (NSArray*)pushers;
- (NSArray*)strips;
- (void)removePusher:(PPPixelPusher*)pusher;
- (void)addPusher:(PPPixelPusher*)pusher;

@end

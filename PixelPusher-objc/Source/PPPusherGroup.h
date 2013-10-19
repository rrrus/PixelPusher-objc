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

- (NSSet*)pushers;
- (NSUInteger)size;
- (NSArray*)strips;
- (void)removePusher:(PPPixelPusher*)pusher;
- (void)addPusher:(PPPixelPusher*)pusher;

@end

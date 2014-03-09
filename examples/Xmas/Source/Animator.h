//
//  Animator.h
//  swyzzle
//
//  Created by rrrus on 2/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKit.h>

@class HLDeferred;

typedef enum {
	eIdle,
	eFading,
	eHolding,
} AnimatorState;

@interface Animator : NSObject
@property (nonatomic, readonly) AnimatorState state;
@property (nonatomic, readonly) GLKVector4 value;

// TODO: fade curve (linear, ease in/out)
- (HLDeferred*)fadeTo:(GLKVector4)value duration:(NSTimeInterval)duration;
- (HLDeferred*)fadeTo:(GLKVector4)value duration:(NSTimeInterval)duration thenHoldFor:(NSTimeInterval)hold;
@end

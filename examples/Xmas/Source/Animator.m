//
//  Animator.m
//  swyzzle
//
//  Created by rrrus on 2/27/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "Animator.h"
#import "HLDeferred.h"

@interface Animator() {
	GLKVector4 curVal, nextVal;
	CFTimeInterval startTime, fadeEndTime, holdEndTime;
	HLDeferred *deferred;
	NSTimer *completionTimer;
}
@end

@implementation Animator

- (id)init
{
    self = [super init];
    if (self) {
        nextVal  = curVal = GLKVector4Make(0,0,0,0);
		// prevent divide by zero on first calculation
		fadeEndTime = 1;
		holdEndTime	= 2;
    }
    return self;
}

- (AnimatorState)state {
	CFTimeInterval now = CACurrentMediaTime();
	if (now > holdEndTime)
		return eIdle;
	else if (now > fadeEndTime)
		return eHolding;
	else
		return eFading;
}

- (float)bezierInterp:(float)t {
	//	CAMediaTimingFunction
	// [(0.0,0.0), (0.25,0.1), (0.25,0.1), (1.0,1.0)]
	static const float p0 = 0.42, p1 = 0, p2 = 0.57, p3 = 1;
	float cube = t * t * t;
	float square = t * t;
	float a = 3 * (p1 - p0);
	float b = 3 * (p2 - p0);
	float c = p3 - p0 - a - b;
	return (c * cube) + (b * square) + (a * t) + p0;
	// B(u) = P0 * ( 1 - u )3 + P1 * 3 * u * ( 1 - u )2 + P2 * 3 * u2 * ( 1 - u ) + P3 * u3
}

- (GLKVector4)value {
	CFTimeInterval now = CACurrentMediaTime();
	// linear interpolation
	double interp = MIN(1, ((now-startTime)/(fadeEndTime-startTime)));
//	interp = [self bezierInterp:interp];
	return GLKVector4Add(GLKVector4MultiplyScalar(nextVal, interp), GLKVector4MultiplyScalar(curVal, 1-interp));
}

- (HLDeferred*)fadeTo:(GLKVector4)value duration:(NSTimeInterval)duration {
	return [self fadeTo:value duration:duration thenHoldFor:0];
}

- (HLDeferred*)fadeTo:(GLKVector4)value
			 duration:(NSTimeInterval)duration
		  thenHoldFor:(NSTimeInterval)hold
{
	// grab current state
	curVal = self.value;
	if (deferred && !deferred.called) {
		// cancelled before resolved, error outstanding deferred
		[deferred takeError:nil];
	}
	[completionTimer invalidate];

	// now reset the controls
	startTime = CACurrentMediaTime();
	nextVal = value;
	fadeEndTime = startTime + duration;
	holdEndTime = fadeEndTime + hold;

	deferred = HLDeferred.new;
	completionTimer = [NSTimer scheduledTimerWithTimeInterval:holdEndTime-startTime
													   target:self
													 selector:@selector(animationComplete)
													 userInfo:nil
													  repeats:NO];
	return deferred;
}

- (void)animationComplete {
	[deferred takeResult:nil];
}

@end

//
//  RRComet.h
//  PixelMapper
//
//  Created by Rus Maxham on 6/1/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PPPixel, PPStrip;

@interface RRComet : NSObject
@property (nonatomic, assign) CFTimeInterval startTime;
@property (nonatomic, assign) float startPosition;
@property (nonatomic, assign) float speed;
@property (nonatomic, assign) float speedVariance;
@property (nonatomic, assign) float speedVariancePeriod;
@property (nonatomic, assign) float tailLength;
@property (nonatomic, readonly) float headPosition;
@property (nonatomic, readonly) float tailPosition;
@property (nonatomic, strong) PPPixel *color;

- (BOOL)drawInStrip:(PPStrip*)strip;

@end


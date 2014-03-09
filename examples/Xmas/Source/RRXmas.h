//
//  RRXmas.h
//  PixelMapper
//
//  Created by Rus Maxham on 6/1/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PPPixel, PPStrip;

@interface RRXmas : NSObject
@property (nonatomic) uint32_t length;

- (void)drawInStrip:(PPStrip*)strip;
- (void)drawInStrip:(PPStrip*)strip length:(uint32_t)length;

@end


//
//  RRBorderedButton.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 8/8/14.
//  Copyright (c) 2014 rrrus. All rights reserved.
//

#import "RRBorderedButton.h"

@interface RRBorderedButton ()
@property (nonatomic, strong) UIView *border;
@end

@implementation RRBorderedButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
		[self setupViews];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setupViews];
	}
	return self;
}

- (void)setupViews {
	CGRect rc = self.bounds;
	rc.origin.x = rc.size.width-1;
	rc.size.width = 1;
	self.border = [UIView.alloc initWithFrame:rc];
	self.border.translatesAutoresizingMaskIntoConstraints = YES;
	self.border.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight;
	[self addSubview:self.border];
}

- (void)setBorderColor:(UIColor *)borderColor {
	self.border.backgroundColor = borderColor;
}

- (UIColor *)borderColor {
	return self.border.backgroundColor;
}

@end

//
//  PPConfig2.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 8/6/14.
//  Copyright (c) 2014 rrrus. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface PPConfigVC2 : UIViewController

// load the PPConfigVC from the PixelPusher-objc bundle.  Make sure your project
// depends on the PixelPusher-objc-bundle target and copies the bundle into your
// app's resources.
+ (PPConfigVC2*)loadFromNib;

@end

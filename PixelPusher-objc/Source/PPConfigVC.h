//
//  PPConfigVC.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 7/8/14.
//  Copyright (c) 2014 rrrus. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface PPConfigVC : UIViewController

// load the PPConfigVC from the PixelPusher-objc bundle.  Make sure your project
// depends on the PixelPusher-objc-bundle target and copies the bundle into your
// app's resources.
+ (PPConfigVC*)loadFromNib;

@end

//
//  RRAppDelegate.h
//  Xmas
//
//  Created by Rus Maxham on 5/20/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RRMainViewController;

@interface RRAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (strong, nonatomic) RRMainViewController *mainViewController;

+ (NSString *) applicationDocumentsDirectory;

@end

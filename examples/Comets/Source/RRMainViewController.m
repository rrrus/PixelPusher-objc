//
//  RRMainViewController.m
//  Comets
//
//  Created by Rus Maxham on 5/20/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "HLDeferred.h"
#import "PPConfigVC.h"
#import "PPDeviceRegistry.h"
#import "PPPixel.h"
#import "PPStrip.h"
#import "RRAppDelegate.h"
#import "RRComet.h"
#import "RRForEach.h"
#import "RRMainViewController.h"

//INIT_LOG_LEVEL_INFO

@interface RRMainViewController () <PPFrameDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) IBOutlet UIImageView *imageView;
@property (nonatomic, strong) NSMutableArray *comets;
@property (nonatomic, assign) uint32_t numStrips;

@property (nonatomic, strong) PPConfigVC *pusherConfigVC;
@end

@implementation RRMainViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	self.pusherConfigVC = [PPConfigVC loadFromNib];
	
	[self.view addSubview:self.pusherConfigVC.view];
	CGRect rc = self.pusherConfigVC.view.frame;
	rc.origin.x = 100;
	rc.origin.y = 100;
	self.pusherConfigVC.view.frame = rc;

	PPDeviceRegistry.sharedRegistry.frameDelegate = self;
	[PPDeviceRegistry.sharedRegistry startPushing];

	self.numStrips = 6;
	self.comets = NSMutableArray.array;
	for (int i=0; i<self.numStrips; i++) {
		[self.comets addObject:NSMutableArray.array];
	}
}

- (void)viewDidUnload {
	PPDeviceRegistry.sharedRegistry.frameDelegate = nil;
	[self setImageView:nil];
	[super viewDidUnload];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - PPFrameDelegate

- (void)renderComets {
	NSArray *strips = PPDeviceRegistry.sharedRegistry.strips;
	static float brightness = 1.0;
	if (PPDeviceRegistry.sharedRegistry.globalBrightness != brightness) {
		PPDeviceRegistry.sharedRegistry.globalBrightness = brightness;
	}
	static BOOL linear = NO;
	PPStrip.outputCurveFunction = linear ? sCurveLinearFunction : sCurveAntilogFunction;

	if (strips.count >= self.numStrips) {
		for (NSUInteger s=0; s<self.numStrips; s++) {
			PPStrip *strip = strips[s];
			for (int i=0; i<strip.pixels.count; i++) {
				PPPixel *pix = strip.pixels[i];
				pix.red = pix.green = pix.blue = 0;
			}
			NSMutableArray *stripComets = self.comets[s];
			while (stripComets.count < 8) {
				RRComet *comet = RRComet.alloc.init;
				[stripComets addObject:comet];
			}
			[stripComets.copy forEach:^(RRComet *comet, NSUInteger idx, BOOL *stop) {
				if (![comet drawInStrip:strip]) [stripComets removeObject:comet];
			}];
			strip.touched = YES;
		}
	}
}


- (HLDeferred*)pixelPusherRender {
#if 0
	__block HLDeferred* deferred = HLDeferred.new;
	dispatch_async(your_worker_queue, ^{
		// do your rendering stuff here
		dispatch_async(dispatch_get_main_queue(), ^{
			[deferred takeResult:nil];
		});
	});
	return deferred;
#else
	[self renderComets];
	return nil;
#endif
}

@end



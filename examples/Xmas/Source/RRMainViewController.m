//
//  RRMainViewController.m
//  Xmas
//
//  Created by Rus Maxham on 5/20/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "HLDeferred.h"
#import "PPDeviceRegistry.h"
#import "PPPixelPusher.h"
#import "PPPixel.h"
#import "PPStrip.h"
#import "RRAppDelegate.h"
#import "RRXmas.h"
#import "RRForEach.h"
#import "RRMainViewController.h"

//INIT_LOG_LEVEL_INFO

@interface RRMainViewController () <PPFrameDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) IBOutlet UIImageView *imageView;
@property (nonatomic, strong) NSMutableArray *Xmas;
@property (nonatomic, assign) uint32_t numStrips;
@end

@implementation RRMainViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	self.numStrips = 4;
	self.Xmas = NSMutableArray.array;
	for (int i=0; i<self.numStrips; i++) {
		[self.Xmas addObject:RRXmas.new];
	}
	
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(registryAddedPusher:)
											   name:PPDeviceRegistryAddedPusher
											 object:nil];
	
	PPDeviceRegistry.sharedRegistry.frameRateLimit = 30;
	PPDeviceRegistry.sharedRegistry.frameDelegate = self;
	[PPDeviceRegistry.sharedRegistry startPushing];
	
	double delayInSeconds = 5.0;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
//		PPDeviceRegistry.sharedRegistry.record = YES;
	});
}

- (void)viewDidUnload {
	PPDeviceRegistry.sharedRegistry.frameDelegate = nil;
	[self setImageView:nil];
	[super viewDidUnload];
}

- (void)registryAddedPusher:(NSNotification*)notif {
//	PPPixelPusher *pusher = DYNAMIC_CAST(PPPixelPusher, notif.object);
//	// ensure the strips are using float pixel buffers
//	[pusher.strips forEach:^(PPStrip *strip, NSUInteger idx, BOOL *stop) {
//		[strip setPixelBuffer:nil size:0 pixelType:ePPPixTypeRGB componentType:ePPCompTypeFloat pixelStride:0];
//	}];
}

#pragma mark - PPFrameDelegate

- (void)renderXmas {
	NSArray *strips = PPDeviceRegistry.sharedRegistry.strips;
	[strips forEach:^(PPStrip* strip, NSUInteger idx, BOOL *stop) {
		if (idx >= self.Xmas.count) {
			*stop = YES;
			return;
		}
		
		if (idx > 1)	[self.Xmas[idx] drawInStrip:strip length:50];
		else			[self.Xmas[idx] drawInStrip:strip];
		
		strip.touched = YES;
	}];
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
	[self renderXmas];
	return nil;
#endif
}

@end



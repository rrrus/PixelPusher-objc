//
//  RRMainViewController.m
//  Comets
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
#import "RRComet.h"
#import "RRForEach.h"
#import "RRMainViewController.h"

//INIT_LOG_LEVEL_INFO

@interface RRMainViewController () <PPFrameDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) IBOutlet UIImageView *imageView;
@property (nonatomic, strong) NSMutableArray *comets;
@property (nonatomic, assign) uint32_t numStrips;
@end

@implementation RRMainViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	self.numStrips = 8;
	self.comets = NSMutableArray.array;
	for (int i=0; i<self.numStrips; i++) {
		[self.comets addObject:NSMutableArray.array];
	}

	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(registryAddedPusher:)
											   name:PPDeviceRegistryAddedPusher
											 object:nil];
	
	PPDeviceRegistry.sharedRegistry.frameDelegate = self;
	//	[PPStrip setOutputCurveFunction:sCurveLinearFunction];
	[PPDeviceRegistry.sharedRegistry startPushing];
}

- (void)viewDidUnload {
	PPDeviceRegistry.sharedRegistry.frameDelegate = nil;
	[self setImageView:nil];
	[super viewDidUnload];
}

- (void)registryAddedPusher:(NSNotification*)notif {
	PPPixelPusher *pusher = DYNAMIC_CAST(PPPixelPusher, notif.object);
	// ensure the strips are using float pixel buffers
	[pusher.strips forEach:^(PPStrip *strip, NSUInteger idx, BOOL *stop) {
		[strip setPixelBuffer:nil size:0 pixelType:ePPPixTypeRGB componentType:ePPCompTypeFloat pixelStride:0];
	}];
}

#pragma mark - PPFrameDelegate

- (void)renderComets {
	NSArray *strips = PPDeviceRegistry.sharedRegistry.strips;
	if (strips.count >= self.numStrips) {
		for (NSUInteger s=0; s<self.numStrips; s++) {
			PPStrip *strip = strips[s];
			memset(strip.buffer, 0, strip.pixelCount * sizeof(PPFloatPixel));
			NSMutableArray *stripComets = self.comets[s];
			while (stripComets.count < 10) {
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
	HLDeferred* deferred = HLDeferred.new;
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



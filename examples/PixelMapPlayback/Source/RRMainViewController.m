//
//  RRMainViewController.m
//  PixelMapPlayback
//
//  Created by Rus Maxham on 5/20/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

#import "RRAppDelegate.h"
#import "RRMainViewController.h"
#import "HLDeferred.h"
#import "PPDeviceRegistry.h"
#import "PPPixel.h"
#import "PPStrip.h"

INIT_LOG_LEVEL_INFO

@interface RRMainViewController () <PPFrameDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) IBOutlet UIImageView *imageView;
@property (nonatomic, strong) UIPanGestureRecognizer *panRecognizer;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchRecognizer;
@property (nonatomic, strong) UIRotationGestureRecognizer *rotationRecognizer;
@property (nonatomic, assign) float spacing;
@property (nonatomic, assign) float rotation;

@property (nonatomic, strong) NSMutableDictionary *pixelMap;
@property (nonatomic, assign) float pixelMapAvgSpacing;

@end

@implementation RRMainViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	PPDeviceRegistry.sharedRegistry.frameDelegate = self;
	[PPDeviceRegistry.sharedRegistry startPushing];

	self.panRecognizer = [UIPanGestureRecognizer.alloc initWithTarget:self action:@selector(didPan:)];
	self.pinchRecognizer = [UIPinchGestureRecognizer.alloc initWithTarget:self action:@selector(didPinch:)];
	self.rotationRecognizer = [UIRotationGestureRecognizer.alloc initWithTarget:self action:@selector(didRotate:)];
	self.panRecognizer.delegate = self;
	self.pinchRecognizer.delegate = self;
	self.rotationRecognizer.delegate = self;

	[self.view addGestureRecognizer:self.panRecognizer];
	[self.view addGestureRecognizer:self.pinchRecognizer];
	[self.view addGestureRecognizer:self.rotationRecognizer];

	self.spacing = 10;
	self.rotation = 0;

	[self loadPixelMapping];

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

#pragma mark - map loading

- (void)loadPixelMapping {
	NSString *filePath = [NSBundle.mainBundle pathForResource:@"pixelsOnDaFloor" ofType:@"json"];
	NSData *jsonData = [NSData dataWithContentsOfFile:filePath];
	NSError *error = nil;
	self.pixelMap = [NSJSONSerialization JSONObjectWithData:jsonData
													options:NSJSONReadingMutableContainers
													  error:&error];

	// determine pixel map density
	// and add tangent angle
	NSArray *stripsMap = self.pixelMap[@"strips"];
	__block float sum = 0;
	__block int count = 0;
	[stripsMap forEach:^(NSArray *stripMap, NSUInteger idx, BOOL *stop) {
		int pixcount = stripMap.count;
		for (int i=1; i<pixcount; i++) {
			float x0, x1, y0, y1;
			x0 = [stripMap[i-1][0] floatValue];
			y0 = [stripMap[i-1][1] floatValue];
			x1 = [stripMap[i][0] floatValue];
			y1 = [stripMap[i][1] floatValue];
			float dx = x1 - x0;
			float dy = y1 - y0;
			float dist = sqrtf(dx*dx + dy*dy);
			sum += dist;
			count ++;
			// compute the normal of the pixel based on direction to the next one
			float angle;
			if (idx%2 == 0) angle = atan2f(dy, dx);
			else			angle = atan2f(-dy, -dx);

			stripMap[i-1][2] = @(angle);
		}
		// copy the 2nd to last to the last
		stripMap[pixcount-1][2] = stripMap[pixcount-2][2];
	}];
	self.pixelMapAvgSpacing = sum/count;
	DDLogInfo(@"average pixel spacing %f", self.pixelMapAvgSpacing);
}

#pragma mark - Event handlers

- (void)didPan:(UIPanGestureRecognizer*)recognizer {
}

- (void)didPinch:(UIPinchGestureRecognizer*)recognizer {
	if (recognizer.state == UIGestureRecognizerStateEnded) {
		self.spacing *= recognizer.scale;
	}
}

- (void)didRotate:(UIRotationGestureRecognizer*)recognizer {
	if (recognizer.state == UIGestureRecognizerStateEnded) {
		self.rotation += recognizer.rotation;
	}
}

#pragma mark - PPFrameDelegate

- (void)renderMapping {
	// make an image to map from
	int szWidth = 180;
	int szHeight = 135;
	// determine image size from pixel map density
	if (self.pixelMapAvgSpacing > 0) {
		szWidth = 2 / self.pixelMapAvgSpacing;
		// make the width multiple of 2
		while(szWidth%2 != 0) szWidth++;
		// make image 4:3 aspect ratio to match ipad screen aspect
		// TODO: calc 'aspect ratio' of pixel map, use that.
		szHeight = szWidth * 3 / 4;
	}
	CGSize size = CGSizeMake(szWidth, szHeight);

	// render sliding rectangles with touch inputs
	CGFloat mappingSpacing = self.spacing*10;
	CFTimeInterval now = CACurrentMediaTime();
	CGFloat rotation = self.rotation;
	if (self.pinchRecognizer.state == UIGestureRecognizerStateChanged) {
		mappingSpacing *= self.pinchRecognizer.scale;
	}
	if (self.rotationRecognizer.state == UIGestureRecognizerStateChanged) {
		rotation += self.rotationRecognizer.rotation;
	}
	CGAffineTransform transform = CGAffineTransformIdentity;
	transform = CGAffineTransformTranslate(transform,
										   +(size.width/2.0f),
										   +(size.height/2.0f));
	transform = CGAffineTransformRotate(transform, rotation);
	transform = CGAffineTransformTranslate(transform,
										   -(size.width/2.0f),
										   -(size.height/2.0f));
	if (self.panRecognizer.state == UIGestureRecognizerStateChanged) {
		CGPoint pan = [self.panRecognizer translationInView:self.imageView];
		pan.y *= -1;
		pan = CGPointApplyAffineTransform(pan, transform);
		now = (pan.x+2000)/20;
	}

	// make an offscreen bitmap context
	UIGraphicsBeginImageContext(size);
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextConcatCTM(context, transform);

	CGFloat offset = fmod(now * 40, mappingSpacing) - mappingSpacing;
	[self drawGradient:context offset:offset spacing:mappingSpacing];
//	[self drawSolidFill:context];


	// get access to the pixel buffer
	uint8_t *data = (uint8_t *)CGBitmapContextGetData(context);
	int32_t rowStride = CGBitmapContextGetBytesPerRow(context);

	// TODO: fix pixel angle calculation instead of fixing rotation angle here
	rotation -= M_PI_2;

	// lookup pixels in the pixel buffer
	NSArray *strips = PPDeviceRegistry.sharedRegistry.strips;
	NSArray *stripsMap = self.pixelMap[@"strips"];
	// anti-aliasing radius
	// TODO: dynamically determine this from map pixel density vs rendered image size
	int avgRadius = 4;
	[strips forEach:^(PPStrip *strip, NSUInteger idx, BOOL *stop) {
		int pixcount = strip.pixels.count;
		if (stripsMap.count > idx) {
			NSArray *stripMap = stripsMap[idx];
			for (int i=0; i<pixcount; i++) {
				if (stripMap.count > i) {
					CGFloat px = [stripMap[i][0] floatValue];
					CGFloat py = [stripMap[i][1] floatValue];
					if (px >= 0 && py >= 0) {
						// the 1- is cause the pixmap (or the mapping) is rotated 180°
						int ix = (int)((1-px)*szWidth);
						int iy = (int)((1-py)*szWidth)-szWidth+szHeight;
						// do some neighbor averaging
						int sr, sg, sb, count;
						sr = sg = sb = count = 0;
						for (int dy = -avgRadius; dy <= avgRadius; dy++) {
							int ay = iy+dy;
							if (ay > 0 && ay < szHeight) {
								for (int dx = -avgRadius; dx <= avgRadius; dx++) {
									int ax = ix+dx;
									if (ax > 0 && ax < szWidth) {
										uint8_t *P = data + iy*rowStride + ix*4;
										sb += P[0];
										sg += P[1];
										sr += P[2];
										count++;
									}
								}
							}
						}

						PPPixel *pix = strip.pixels[i];
						pix.red = (float)sr/count/255.0;
						pix.green = (float)sg/count/255.0;
						pix.blue = (float)sb/count/255.0;
					}
				}
			}
			strip.touched = YES;
		}
	}];
	UIImage *viewImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	self.imageView.image = viewImage;
}

- (void)drawGradient:(CGContextRef)context offset:(float)offset spacing:(float)mappingSpacing {
	int szWidth = CGBitmapContextGetWidth(context);
	int szHeight = CGBitmapContextGetHeight(context);
	int szDiff2 = (szWidth - szHeight)/2;
	UIColor *rectColor = [UIColor colorWithHue:fmod(CACurrentMediaTime()/20, 1) saturation:1 brightness:1 alpha:1];
	CGFloat locations[] = { 0.4, 1 };
	NSArray *colors = @[(id)UIColor.blackColor.CGColor, (id)rectColor.CGColor];
	CGGradientRef gradient = CGGradientCreateWithColors(nil,
														(__bridge CFArrayRef)colors,
														locations);

	CGContextSetFillColorWithColor(context, rectColor.CGColor);
	// draw some rects into it
	while (offset < szWidth) {
		CGContextSaveGState(context);
		CGRect rc = CGRectMake(offset, -szDiff2, mappingSpacing, szWidth);
		CGContextAddRect(context, rc);
		CGContextClip(context);
		CGContextDrawLinearGradient(context, gradient, CGPointMake(rc.origin.x, 0), CGPointMake(rc.origin.x+rc.size.width, 0), kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
		offset += mappingSpacing;
		CGContextRestoreGState(context);
	}
	CGGradientRelease(gradient);
}

- (void)drawSolidFill:(CGContextRef)context {
	int szWidth = CGBitmapContextGetWidth(context);
	int szHeight = CGBitmapContextGetHeight(context);
	int szDiff2 = (szWidth - szHeight)/2;
	UIColor *rectColor = [UIColor colorWithHue:fmod(CACurrentMediaTime()/20, 1) saturation:1 brightness:1 alpha:1];
	CGContextSetFillColorWithColor(context, rectColor.CGColor);
	CGRect rc = CGRectMake(0, -szDiff2, szWidth, szWidth);
	CGContextFillRect(context, rc);
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
	[self renderMapping];
	return nil;
#endif
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
	if (otherGestureRecognizer == self.rotationRecognizer) return NO;
	return (otherGestureRecognizer == self.panRecognizer
			|| otherGestureRecognizer == self.pinchRecognizer
			|| otherGestureRecognizer == self.rotationRecognizer);
}

@end



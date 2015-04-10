//
//  PPConfigVC.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 7/8/14.
//  Copyright (c) 2014 rrrus. All rights reserved.
//

#import "PPConfigVC.h"
#import "PPDeviceRegistry.h"
#import "PPPusherGroup.h"
#import "PPPixelPusher.h"

@interface PPPusherListCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UILabel *ordinal;
@property (strong, nonatomic) IBOutlet UILabel *macAddress;
@property (strong, nonatomic) IBOutlet UILabel *numStrips;
@property (strong, nonatomic) IBOutlet UILabel *numPixels;
@property (strong, nonatomic) IBOutlet UILabel *swVersion;
@property (strong, nonatomic) IBOutlet UILabel *hwVersion;
@end

@interface PPConfigVC () <UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) IBOutlet UITableView *pusherList;
@end

@implementation PPConfigVC

+ (NSBundle*)pixelPusherBundle {
	return [NSBundle bundleWithURL:
			[NSBundle.mainBundle URLForResource:@"PixelPusher-objc-bundle" withExtension:@"bundle"]];
}

+ (PPConfigVC *)loadFromNib {
	return [PPConfigVC.alloc initWithNibName:@"PPConfigVC" bundle:self.pixelPusherBundle];
}

- (void)viewDidLoad {
    [super viewDidLoad];

	UINib *nib = [UINib nibWithNibName:@"PPPusherCell" bundle:self.class.pixelPusherBundle];
	[self.pusherList registerNib:nib forCellReuseIdentifier:@"PusherCell"];

	NSNotificationCenter *notifCenter = NSNotificationCenter.defaultCenter;
	[notifCenter addObserver:self selector:@selector(onDeviceListChange:) name:PPDeviceRegistryAddedPusher object:nil];
	[notifCenter addObserver:self selector:@selector(onDeviceListChange:) name:PPDeviceRegistryRemovedPusher object:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

}

- (void)onDeviceListChange:(NSNotification*)notif {
	[self.pusherList reloadData];
}

#pragma mark - UITableViewDelegate methods

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 41;
}

#pragma mark - UITableViewDataSource methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return PPDeviceRegistry.sharedRegistry.groups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSArray *groups = PPDeviceRegistry.sharedRegistry.groups;
	if (section >= groups.count) return 0;
	PPPusherGroup *group = groups[section];
	return group.pushers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

	PPPusherListCell *aCell = DYNAMIC_CAST(PPPusherListCell, [tableView dequeueReusableCellWithIdentifier:@"PusherCell"]);
	NSAssert(aCell != nil, @"PusherCell not registered");

	NSArray *groups = PPDeviceRegistry.sharedRegistry.groups;
	if (aCell && indexPath.section < groups.count) {
		PPPusherGroup *group = groups[indexPath.section];
		NSArray *pushers = group.pushers;
		if (indexPath.item < pushers.count) {
			PPPixelPusher *pusher = pushers[indexPath.item];
			aCell.ordinal.text = [NSString stringWithFormat:@"%d", pusher.controllerOrdinal];
			aCell.macAddress.text = pusher.macAddress;
			aCell.numStrips.text = [NSString stringWithFormat:@"%d strips", pusher.strips.count];
			aCell.numPixels.text = [NSString stringWithFormat:@"%d px", pusher.pixelsPerStrip];
			aCell.swVersion.text = [NSString stringWithFormat:@"v%1.2f", pusher.softwareRevision/100.0f];
			aCell.hwVersion.text = [NSString stringWithFormat:@"r%d", pusher.hardwareRevision];

			if (pusher.softwareRevision < PP_ACCEPTABLE_LOWEST_SW_REV)	aCell.swVersion.textColor = UIColor.redColor;
			else														aCell.swVersion.textColor = UIColor.blackColor;
		}
	}


	return aCell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	NSArray *groups = PPDeviceRegistry.sharedRegistry.groups;
	if (section >= groups.count) return 0;
	PPPusherGroup *group = groups[section];
	return [NSString stringWithFormat:@"Group %d", group.ordinal];
}

@end

@implementation PPPusherListCell



@end
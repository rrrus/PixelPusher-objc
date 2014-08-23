//
//  PPConfig2.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 8/6/14.
//  Copyright (c) 2014 rrrus. All rights reserved.
//

#import "PPConfigVC2.h"
#import "PPDeviceRegistry.h"
#import "PPPusherGroup.h"
#import "PPPixelPusher.h"
#import "RRBorderedButton.h"
#import "RRSimpleCollectionView.h"
#import "UIImage+RRR.h"

UIColor *gBorderColor;
UIColor *gSelectedBackgroundColor;

typedef enum {
	eStateGlobal,
	eStateAll,
	eStateGroups
} ConfigTopState;

@interface PPConfigGroupCell : RRSimpleCollectionViewCell
@property (nonatomic, strong) UILabel *label;
@end

@interface PPConfigPusherCell : PPConfigGroupCell
@end

@interface PPConfigAllPusherCell : PPConfigGroupCell
@property (nonatomic, strong) UILabel *subLabel;
@end

@interface PPConfigVC2 () <RRSimpleCollectionViewDelegate>

@property (nonatomic, strong) IBOutlet UIButton *globalBtn;
@property (nonatomic, strong) IBOutlet UIButton *allBtn;
@property (nonatomic, strong) IBOutlet UIButton *groupsBtn;
@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *topLevelBtns;

@property (nonatomic, strong) IBOutlet UIView *groupsMenu;
@property (nonatomic, strong) IBOutlet RRSimpleCollectionView *groupsCollectionView;
@property (nonatomic, strong) IBOutlet RRSimpleCollectionView *pushersCollectionView;

@property (nonatomic, strong) NSTimer *debounceTimer;
@property (nonatomic, assign) ConfigTopState topState;

@property (strong, nonatomic) IBOutlet UILabel *pusherMac;
@property (strong, nonatomic) IBOutlet UILabel *pusherIP;
@property (strong, nonatomic) IBOutlet UILabel *pusherSwVers;
@property (strong, nonatomic) IBOutlet UILabel *pusherHwVers;
@property (strong, nonatomic) IBOutlet UILabel *pusherNumStrips;
@property (strong, nonatomic) IBOutlet UILabel *pusherNumPixels;
@property (strong, nonatomic) IBOutlet UILabel *pusherDeviceType;
@property (strong, nonatomic) IBOutlet UILabel *pusherGroup;
@property (strong, nonatomic) IBOutlet UILabel *pusherNumber;

@end

@implementation PPConfigVC2

+ (NSBundle*)pixelPusherBundle {
	return [NSBundle bundleWithURL:
			[NSBundle.mainBundle URLForResource:@"PixelPusher-objc-bundle" withExtension:@"bundle"]];
}

+ (PPConfigVC2 *)loadFromNib {
	return [PPConfigVC2.alloc initWithNibName:@"PPConfigVC2" bundle:self.pixelPusherBundle];
}

- (void)viewDidLoad {
    [super viewDidLoad];

	gBorderColor = [UIColor colorWithWhite:0 alpha:0.15f];
	gSelectedBackgroundColor = [UIColor colorWithRed:0.1f green:0.1f blue:1.0 alpha:1.0];
	
	self.groupsCollectionView.delegate = self;
	self.groupsCollectionView.scrollDirection = UICollectionViewScrollDirectionHorizontal;
	[self.groupsCollectionView registerCellViewClass:PPConfigGroupCell.class forIdentifier:@"groupCell"];
	self.groupsCollectionView.minimumLineSpacing = 0;
	self.groupsCollectionView.minimumInteritemSpacing = 0;
	self.groupsCollectionView.itemSize = CGSizeMake(88, 44);

	self.pushersCollectionView.delegate = self;
	self.pushersCollectionView.scrollDirection = UICollectionViewScrollDirectionHorizontal;
	[self.pushersCollectionView registerCellViewClass:PPConfigPusherCell.class forIdentifier:@"pusherInGroup"];
	[self.pushersCollectionView registerCellViewClass:PPConfigAllPusherCell.class forIdentifier:@"allPusher"];
	self.pushersCollectionView.minimumLineSpacing = 0;
	self.pushersCollectionView.minimumInteritemSpacing = 0;
	self.pushersCollectionView.itemSize = CGSizeMake(88, 44);
	self.pushersCollectionView.showsScrollIndicator = NO;
	
	UIImage *blueImg = [UIImage imageWithColor:gSelectedBackgroundColor size:CGSizeMake(1, 1)];
	[self.topLevelBtns forEach:^(UIButton *btn, NSUInteger idx, BOOL *stop) {
		[btn setBackgroundImage:blueImg forState:UIControlStateSelected];
		btn.contentMode = UIViewContentModeScaleToFill;
		RRBorderedButton *borderBtn = DYNAMIC_CAST(RRBorderedButton, btn);
		borderBtn.borderColor = gBorderColor;
	}];
	
	self.topState = eStateGroups;
	self.groupsBtn.selected = YES;
	
	NSNotificationCenter *notifCenter = NSNotificationCenter.defaultCenter;
	[notifCenter addObserver:self selector:@selector(onDeviceListChange:) name:PPDeviceRegistryAddedPusher object:nil];
	[notifCenter addObserver:self selector:@selector(onDeviceListChange:) name:PPDeviceRegistryRemovedPusher object:nil];

}

- (void)onDeviceListChange:(NSNotification*)notif {
	if (self.debounceTimer) {
		[self.debounceTimer invalidate];
		self.debounceTimer = nil;
	}
	[NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(onDeviceListChangeDebounced:) userInfo:nil repeats:NO];
}

- (void)onDeviceListChangeDebounced:(NSTimer*)aTimer {
	self.debounceTimer = nil;
	
	if (self.topState == eStateGroups) {
		self.pushersCollectionView.cellIdentifier = @"pusherInGroup";
		NSArray *groups = PPDeviceRegistry.sharedRegistry.groups;
		self.groupsCollectionView.data = groups;
		if (!self.groupsCollectionView.selectedItem && groups.count > 0) {
			NSIndexPath *defaultItem = [NSIndexPath indexPathForItem:0 inSection:0];
			self.groupsCollectionView.selectedItem = defaultItem;
			[self collectionView:self.groupsCollectionView didSelectItemAtIndexPath:defaultItem];
		} else {
			self.pushersCollectionView.data = nil;
		}
	} else {
		self.pushersCollectionView.cellIdentifier = @"allPusher";
		self.pushersCollectionView.data = PPDeviceRegistry.sharedRegistry.pushers;
	}
}

- (void)selectTopLevelButton:(UIButton*)toSelect {
	[self.topLevelBtns forEach:^(UIButton *btn, NSUInteger idx, BOOL *stop) {
		btn.selected = (btn == toSelect);
	}];
	
	ConfigTopState newState = self.topState;
	if (toSelect == self.globalBtn) {
		newState = eStateGlobal;
	} else if (toSelect == self.allBtn) {
		newState = eStateAll;
	} else if (toSelect == self.groupsBtn) {
		newState = eStateGroups;
	}
	
	if (self.topState != newState) {
		self.topState = newState;
		self.groupsCollectionView.hidden = (self.topState != eStateGroups);
		[self onDeviceListChangeDebounced:nil];
	}
}

- (IBAction)onGlobalBtn:(id)sender {
	[self selectTopLevelButton:sender];
}

- (IBAction)onAllBtn:(id)sender {
	[self selectTopLevelButton:sender];
}

- (IBAction)onGroupsBtn:(id)sender {
	[self selectTopLevelButton:sender];
}

- (void)collectionView:(RRSimpleCollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (collectionView == self.groupsCollectionView) {
		NSArray *groups = PPDeviceRegistry.sharedRegistry.groups;
		if (indexPath.item < groups.count) {
			PPPusherGroup *group = DYNAMIC_CAST(PPPusherGroup, groups[indexPath.item]);
			self.pushersCollectionView.data = group.pushers;
		} else {
			self.pushersCollectionView.data = nil;
		}
	}
	if (collectionView == self.pushersCollectionView) {
		NSArray *pushers = self.pushersCollectionView.data;
		if (indexPath.item < pushers.count) {
			PPPixelPusher *pusher = DYNAMIC_CAST(PPPixelPusher, pushers[indexPath.item]);
			if (pusher) {
				self.pusherMac.text = pusher.macAddress;
				self.pusherIP.text = pusher.ipAddress;
				self.pusherNumStrips.text = @(pusher.strips.count).description;
				self.pusherNumPixels.text = @(pusher.pixelsPerStrip).description;
				self.pusherDeviceType.text = @(pusher.deviceType).description;
				self.pusherSwVers.text = [NSString stringWithFormat:@"v%1.2f", ((float)pusher.softwareRevision/100.f)];
				self.pusherHwVers.text = [NSString stringWithFormat:@"r%d", pusher.hardwareRevision];
				self.pusherGroup.text = @(pusher.groupOrdinal).description;
				self.pusherNumber.text = @(pusher.controllerOrdinal).description;
			} else {
				self.pusherMac.text = nil;
				self.pusherIP.text = nil;
				self.pusherNumStrips.text = nil;
				self.pusherNumPixels.text = nil;
				self.pusherDeviceType.text = nil;
				self.pusherSwVers.text = nil;
				self.pusherHwVers.text = nil;
				self.pusherGroup.text = nil;
				self.pusherNumber.text = nil;
			}
		}
	}
}

- (void)collectionView:(RRSimpleCollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
	self.pusherMac.text = nil;
	self.pusherIP.text = nil;
	self.pusherNumStrips.text = nil;
	self.pusherNumPixels.text = nil;
	self.pusherDeviceType.text = nil;
	self.pusherSwVers.text = nil;
	self.pusherHwVers.text = nil;
	self.pusherGroup.text = nil;
	self.pusherNumber.text = nil;
}

@end

#pragma mark - Cell view classes

@implementation PPConfigGroupCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = UIColor.clearColor;
		self.label = [UILabel.alloc initWithFrame:self.contentView.bounds];
		self.label.font = [UIFont boldSystemFontOfSize:24];
		self.label.textColor = UIColor.whiteColor;
		self.label.textAlignment = NSTextAlignmentCenter;
		self.label.translatesAutoresizingMaskIntoConstraints = YES;
		self.label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[self.contentView addSubview:self.label];
		
		CGRect rc = self.contentView.bounds;
		rc.origin.x = rc.size.width - 1;
		rc.size.width = 1;
		UIView *border = [UIView.alloc initWithFrame:rc];
		border.translatesAutoresizingMaskIntoConstraints = YES;
		border.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight;
		border.backgroundColor = gBorderColor;
		[self.contentView addSubview:border];
	}
	return self;
}

- (void)setObject:(NSObject *)object atIndexPath:(NSIndexPath *)idx {
	PPPusherGroup *group = DYNAMIC_CAST(PPPusherGroup, object);
	if (group) {
		self.label.text = [NSString stringWithFormat:@"%d", group.ordinal];
	} else {
		self.label.text = @"INVALID";
	}
}

- (void)setSelected:(BOOL)selected {
	[super setSelected:selected];
	
	self.backgroundColor = (selected ? gSelectedBackgroundColor : UIColor.clearColor);
}

@end

@implementation PPConfigPusherCell

- (void)setObject:(NSObject *)object atIndexPath:(NSIndexPath *)idx {
	PPPixelPusher *pusher = DYNAMIC_CAST(PPPixelPusher, object);
	if (pusher) {
		self.label.text = [NSString stringWithFormat:@"%d", pusher.controllerOrdinal];
	} else {
		self.label.text = @"";
	}
}

@end

@implementation PPConfigAllPusherCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		CGRect rc = self.contentView.bounds;
		rc.size.height -= 13;
		self.label.frame = rc;
		rc.origin.y = rc.size.height;
		rc.size.height = 13;
		
		self.subLabel = [UILabel.alloc initWithFrame:rc];
		self.subLabel.font = [UIFont boldSystemFontOfSize:12];
		self.subLabel.textColor = UIColor.whiteColor;
		self.subLabel.textAlignment = NSTextAlignmentCenter;
		self.subLabel.translatesAutoresizingMaskIntoConstraints = YES;
		self.subLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
		[self.contentView addSubview:self.subLabel];
		
	}
	return self;
}

- (void)setObject:(NSObject *)object atIndexPath:(NSIndexPath *)idx {
	PPPixelPusher *pusher = DYNAMIC_CAST(PPPixelPusher, object);
	if (pusher) {
		self.subLabel.text = [NSString stringWithFormat:@"%d:%d", pusher.groupOrdinal, pusher.controllerOrdinal];
	} else {
		self.subLabel.text = @"";
	}
	self.label.text = [NSString stringWithFormat:@"%d", idx.item+1];
}

@end



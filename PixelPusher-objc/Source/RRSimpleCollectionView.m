//
//  RRSimpleCollectionView.m
//  PixelPusher-objc
//
//  Created by Rus Maxham on 8/8/14.
//  Copyright (c) 2014 rrrus. All rights reserved.
//

#import "RRSimpleCollectionView.h"

@interface RRSimpleCollectionView () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, strong) UICollectionViewFlowLayout* layout;
@property (nonatomic, strong) UICollectionView* collectionView;

@end

@implementation RRSimpleCollectionView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
		self.layout = UICollectionViewFlowLayout.new;
		self.collectionView = [UICollectionView.alloc initWithFrame:self.bounds collectionViewLayout:self.layout];
		self.collectionView.translatesAutoresizingMaskIntoConstraints = YES;
		self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		self.collectionView.backgroundColor = self.backgroundColor;
		[self addSubview:self.collectionView];
		
		self.collectionView.dataSource = self;
		self.collectionView.delegate = self;
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
	self = [super initWithCoder:aDecoder];
	if (self) {
		self.layout = UICollectionViewFlowLayout.new;
		self.collectionView = [UICollectionView.alloc initWithFrame:self.bounds collectionViewLayout:self.layout];
		self.collectionView.translatesAutoresizingMaskIntoConstraints = YES;
		self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		self.collectionView.backgroundColor = self.backgroundColor;
		[self addSubview:self.collectionView];
		
		self.collectionView.dataSource = self;
		self.collectionView.delegate = self;
	}
	return self;
}

- (void)registerCellViewClass:(Class)aClass forIdentifier:(NSString *)identifier {
	NSAssert([aClass isSubclassOfClass:RRSimpleCollectionViewCell.class], @"RRSimpleCollectionView.registerCellViewClass must be a subclass of RRSimpleCollectionViewCell");
	[self.collectionView registerClass:aClass forCellWithReuseIdentifier:identifier];
	if (!self.cellIdentifier) self.cellIdentifier = identifier;
}

- (void)setData:(NSArray *)data {
	if (_data != data) {
		if (data) {
			NSAssert([data isKindOfClass:NSArray.class], @"data must be an array");
		}
		_data = data;
		[self.collectionView reloadData];
	}
}

- (NSIndexPath *)selectedItem {
	NSArray *selectedItems = self.collectionView.indexPathsForSelectedItems;
	if (selectedItems && selectedItems.count > 0) {
		return selectedItems[0];
	} else {
		return nil;
	}
}

- (void)setSelectedItem:(NSIndexPath *)selectedItem {
	[self.collectionView selectItemAtIndexPath:selectedItem
									  animated:YES
								scrollPosition:UICollectionViewScrollPositionCenteredVertically|UICollectionViewScrollPositionCenteredHorizontally];
}

#pragma mark - UICollectionView delegates

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.data.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	UICollectionViewCell *acell = [self.collectionView dequeueReusableCellWithReuseIdentifier:self.cellIdentifier forIndexPath:indexPath];
	RRSimpleCollectionViewCell *cell = DYNAMIC_CAST(RRSimpleCollectionViewCell, acell);
	if (cell && indexPath.item < self.data.count) {
		[cell setObject:self.data[indexPath.item] atIndexPath:indexPath];
	}
	return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	id<RRSimpleCollectionViewDelegate> strongDelegate = self.delegate;
	[strongDelegate collectionView:self didSelectItemAtIndexPath:indexPath];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
	id<RRSimpleCollectionViewDelegate> strongDelegate = self.delegate;
	[strongDelegate collectionView:self didDeselectItemAtIndexPath:indexPath];
}

#pragma mark - layout passthrough properties

- (void)setScrollDirection:(UICollectionViewScrollDirection)scrollDirection {
	self.layout.scrollDirection = scrollDirection;
}

- (void)setShowsScrollIndicator:(BOOL)showsScrollIndicator {
	self.collectionView.showsHorizontalScrollIndicator = showsScrollIndicator;
	self.collectionView.showsVerticalScrollIndicator = showsScrollIndicator;
}

- (BOOL)showsScrollIndicator {
	return self.collectionView.showsHorizontalScrollIndicator;
}

- (UICollectionViewScrollDirection)scrollDirection {
	return self.layout.scrollDirection;
}

- (void)setMinimumLineSpacing:(CGFloat)minimumLineSpacing {
	self.layout.minimumLineSpacing = minimumLineSpacing;
}

- (CGFloat)minimumLineSpacing {
	return self.layout.minimumLineSpacing;
}

- (void)setMinimumInteritemSpacing:(CGFloat)minimumInteritemSpacing {
	self.layout.minimumInteritemSpacing = minimumInteritemSpacing;
}

- (CGFloat)minimumInteritemSpacing {
	return self.layout.minimumInteritemSpacing;
}

- (void)setItemSize:(CGSize)itemSize {
	self.layout.itemSize = itemSize;
}

- (CGSize)itemSize {
	return self.layout.itemSize;
}

@end

@implementation RRSimpleCollectionViewCell
- (void)setObject:(NSObject*)object atIndexPath:(NSIndexPath*)idx {}
@end
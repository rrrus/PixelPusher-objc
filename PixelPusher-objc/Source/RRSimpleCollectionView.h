//
//  RRSimpleCollectionView.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 8/8/14.
//  Copyright (c) 2014 rrrus. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RRSimpleCollectionView;

@protocol RRSimpleCollectionViewDelegate <NSObject>

- (void)collectionView:(RRSimpleCollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(RRSimpleCollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath;

@end

@interface RRSimpleCollectionViewCell : UICollectionViewCell

- (void)setObject:(NSObject*)object atIndexPath:(NSIndexPath*)idx;

@end

@interface RRSimpleCollectionView : UIView

@property (nonatomic, weak) id<RRSimpleCollectionViewDelegate> delegate;

@property (nonatomic) UICollectionViewScrollDirection scrollDirection; // default is UICollectionViewScrollDirectionVertical
@property (nonatomic) BOOL showsScrollIndicator;
@property (nonatomic) CGFloat minimumLineSpacing;
@property (nonatomic) CGFloat minimumInteritemSpacing;
@property (nonatomic) CGSize itemSize;

@property (nonatomic, strong) NSArray *data;
@property (nonatomic, copy) NSString *cellIdentifier;
@property (nonatomic, strong) NSIndexPath *selectedItem;

// class must be a subclass of RRSimpleCollectionViewCell
- (void)registerCellViewClass:(Class)aClass forIdentifier:(NSString*)identifier;


@end

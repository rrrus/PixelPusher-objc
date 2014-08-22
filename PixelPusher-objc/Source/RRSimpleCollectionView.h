//
//  RRSimpleCollectionView.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 8/8/14.
//  Copyright (c) 2014 rrrus. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface RRSimpleCollectionViewCell : UICollectionViewCell

- (void)setObject:(NSObject*)object atIndexPath:(NSIndexPath*)idx;

@end

@interface RRSimpleCollectionView : UIView

@property (nonatomic) UICollectionViewScrollDirection scrollDirection; // default is UICollectionViewScrollDirectionVertical
@property (nonatomic) BOOL showsScrollIndicator;
@property (nonatomic) CGFloat minimumLineSpacing;
@property (nonatomic) CGFloat minimumInteritemSpacing;
@property (nonatomic) CGSize itemSize;

@property (nonatomic, strong) NSArray *data;
@property (nonatomic, copy) NSString *cellIdentifier;

// class must be a subclass of RRSimpleCollectionViewCell
- (void)registerCellViewClass:(Class)aClass forIdentifier:(NSString*)identifier;


@end

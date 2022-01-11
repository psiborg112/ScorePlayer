//
//  Mosaic.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 8/08/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Mosaic : NSObject {
    CALayer *background;
    NSMutableArray *tiles;
    CGPoint size;
    
    UIImage *image1;
    UIImage *image2;
}

@property (nonatomic, strong) CALayer *background;
@property (nonatomic) CGPoint size;
@property (nonatomic, strong) UIImage *image1;
@property (nonatomic, strong) UIImage *image2;
@property (nonatomic) NSInteger changedTiles;

- (id)initWithTileRows:(NSInteger)rows columns:(NSInteger)columns size:(CGPoint)dimensions;
- (void)setChangedPercent:(int)percentage;

@end

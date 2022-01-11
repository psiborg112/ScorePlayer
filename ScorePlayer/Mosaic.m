//
//  Mosaic.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 8/08/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "Mosaic.h"

@implementation Mosaic {
    NSMutableArray *group1;
    NSMutableArray *group2;
}

@synthesize background;

- (id)initWithTileRows:(NSInteger)rows columns:(NSInteger)columns size:(CGPoint)dimensions
{
    //Dimensions cannot be zero.
    if (dimensions.x == 0 || dimensions.y == 0 || rows == 0 || columns == 0) {
        return nil;
    }
    
    self = [super init];
    
    size = dimensions;
    background = [CALayer layer];
    background.bounds = CGRectMake(0, 0, size.x, size.y);
    CGPoint tileSize = CGPointMake(size.x / columns, size.y / rows);
    
    tiles = [[NSMutableArray alloc] init];
    group1 = [[NSMutableArray alloc] init];
    group2 = [[NSMutableArray alloc] init];
    
    for (int i = 0; i < rows; i++) {
        NSMutableArray *currentRow = [[NSMutableArray alloc] init];
        for (int j = 0; j < columns; j++) {
            CALayer *tile = [CALayer layer];
            tile.frame = CGRectMake(j * tileSize.x, i * tileSize.y, tileSize.x, tileSize.y);
            tile.contentsRect = CGRectMake(j / (CGFloat)columns, i / (CGFloat)rows, 1.0 / columns, 1.0 / rows);
            [background addSublayer:tile];
            [currentRow addObject:tile];
            //Start with all of the tiles in group 1
            [group1 addObject:tile];
        }
        [tiles addObject:currentRow];
    }
    return self;
}

- (void)setSize:(CGPoint)dimensions
{
    size = dimensions;
    background.bounds = CGRectMake(0, 0, size.x, size.y);
    CGPoint tileSize = CGPointMake(size.x / [[tiles objectAtIndex:0] count], size.y / [tiles count]);
    for (int i = 0; i < [tiles count]; i++) {
        for (int j = 0; j < [[tiles objectAtIndex:i] count]; j++) {
            ((CALayer *)[[tiles objectAtIndex:i] objectAtIndex:j]).frame = CGRectMake(j * tileSize.x, i * tileSize.y, tileSize.x, tileSize.y);
        }
    }
}

- (CGPoint)size
{
    return size;
}

- (void)setImage1:(UIImage *)newImage
{
    image1 = newImage;
    for (int i = 0; i < [group1 count]; i++) {
        ((CALayer *)[group1 objectAtIndex:i]).contents = (id)image1.CGImage;
    }
}

- (UIImage *)image1
{
    return image1;
}

- (void)setImage2:(UIImage *)newImage
{
    image2 = newImage;
    for (int i = 0; i < [group2 count]; i++) {
        ((CALayer *)[group2 objectAtIndex:i]).contents = (id)image2.CGImage;
    }
}

- (UIImage *)image2
{
    return image2;
}

- (void)setChangedTiles:(NSInteger)number
{
    //Move the necessary number of tiles across from one group to the other
    NSMutableArray *from;
    NSMutableArray *to;
    int change = (int)(number - [group2 count]);
    if (change == 0) {
        return;
    } else if (change > 0) {
        from = group1;
        to = group2;
    } else {
        from = group2;
        to = group1;
        change = abs(change);
    }
    
    if (change >= [from count]) {
        [to addObjectsFromArray:from];
        [from removeAllObjects];
    } else {
        for (int i = 0; i < change; i++) {
            int index = arc4random_uniform((int)[from count]);
            [to addObject:[from objectAtIndex:index]];
            [from removeObjectAtIndex:index];
        }
    }
    
    //Now update the contents of the tiles
    for (int i = 0; i < [group1 count]; i++) {
        ((CALayer *)[group1 objectAtIndex:i]).contents = (id)image1.CGImage;
    }
    for (int i = 0; i < [group2 count]; i++) {
        ((CALayer *)[group2 objectAtIndex:i]).contents = (id)image2.CGImage;
    }
}

- (NSInteger)changedTiles
{
    return [group2 count];
}

- (void)setChangedPercent:(int)percentage
{
    int number = roundf([[tiles objectAtIndex:0] count] * [tiles count] * percentage / 100.0);
    [self setChangedTiles:number];
}

@end

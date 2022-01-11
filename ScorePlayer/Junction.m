//
//  Junction.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/08/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "Junction.h"

@implementation Junction

@synthesize stops, finalPath, finalDirection, isBorderJunction, f, parentJunction, parentPath, directionFromParent;

- (id)init
{
    self = [super init];
    if (self) {
        stops = [[NSMutableArray alloc] init];
        finalPath = -1;
        finalDirection = 0;
        isBorderJunction = NO;
        f = 0;
        g = 0;
        h = 0;
        parentJunction = 0;
        parentPath = -1;
    }
    return self;
}

- (void)setG:(NSInteger)gCost
{
    g = gCost;
    f = g + h;
}

- (NSInteger)g
{
    return g;
}

- (void)setH:(NSInteger)hCost
{
    h = hCost;
    f = g + h;
}

- (NSInteger)h
{
    return h;
}

- (void)resetCosts
{
    f = 0;
    g = 0;
    h = 0;
    parentJunction = 0;
    parentPath = -1;
}

@end

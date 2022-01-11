//
//  Junction.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/08/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Junction : NSObject {
    NSMutableArray *stops;
    NSInteger finalPath;
    NSInteger finalDirection;
    BOOL isBorderJunction;
    
    NSInteger f;
    NSInteger g;
    NSInteger h;
    NSInteger parentJunction;
    NSInteger parentPath;
    NSInteger directionFromParent;
}

@property (nonatomic, strong) NSMutableArray *stops;
@property (nonatomic) NSInteger finalPath;
@property (nonatomic) NSInteger finalDirection;
@property (nonatomic) BOOL isBorderJunction;
@property (nonatomic, readonly) NSInteger f;
@property (nonatomic) NSInteger g;
@property (nonatomic) NSInteger h;
@property (nonatomic) NSInteger parentJunction;
@property (nonatomic) NSInteger parentPath;
@property (nonatomic) NSInteger directionFromParent;

- (void)resetCosts;

@end

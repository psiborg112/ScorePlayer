//
//  TiledScroller.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 6/12/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ScrollScore.h"

@interface TiledScroller : NSObject <ScrollerDelegate> {
    CGFloat height;
    CGFloat width;
    
    NSInteger numberOfTiles;
    CALayer *background;
    BOOL loadOccurred;
    NSString *annotationsDirectory;
    CGSize canvasSize;
    ScrollOrientation orientation;
    
}

@property (nonatomic) CGFloat height;
@property (nonatomic, readonly) CGFloat width;
@property (nonatomic) CGFloat x;
@property (nonatomic) CGFloat y;
@property (nonatomic, readonly) NSInteger numberOfTiles;
@property (nonatomic, strong) CALayer *background;
@property (nonatomic) BOOL loadOccurred;
@property (nonatomic) NSString *annotationsDirectory;
@property (nonatomic) CGSize canvasSize;
@property (nonatomic) ScrollOrientation orientation;

@end

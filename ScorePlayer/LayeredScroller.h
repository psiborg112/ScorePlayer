//
//  LayeredScroller.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 18/07/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ScrollScore.h"

@interface LayeredScroller : NSObject <ScrollerDelegate> {
    CGFloat height;
    CGFloat width;
    
    NSInteger numberOfTiles;
    CALayer *background;
    BOOL loadOccurred;
}

@property (nonatomic) CGFloat height;
@property (nonatomic, readonly) CGFloat width;
@property (nonatomic) CGFloat x;
@property (nonatomic) CGFloat y;
@property (nonatomic, readonly) NSInteger numberOfTiles;
@property (nonatomic, strong) CALayer *background;
@property (nonatomic) BOOL loadOccurred;

@end

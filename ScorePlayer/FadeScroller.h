//
//  FadeScroller.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 22/02/2014.
//  Copyright (c) 2014 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ScrollScore.h"

@interface FadeScroller : NSObject <ScrollerDelegate> {
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

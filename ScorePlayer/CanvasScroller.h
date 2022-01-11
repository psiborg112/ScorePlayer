//
//  CanvasScroller.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/6/18.
//  Copyright (c) 2018 Decibel. All rights reserved.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "Renderer.h"
#import "Canvas.h"

static const CGFloat MAX_CANVASSCROLLER_FRAMERATE = 25;

@interface CanvasScroller : NSObject <CanvasObject> {
    CALayer *containerLayer;
    NSInteger partNumber;
    NSString *parentLayer;
    NSString *imageFile;
    CGFloat scrollerSpeed;
    BOOL isRunning;
}

@property (nonatomic, strong, readonly) CALayer *containerLayer;
@property (nonatomic, strong, readonly) CALayer *objectLayer;
@property (nonatomic) NSInteger partNumber;
@property (nonatomic, strong) NSString *parentLayer;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGPoint position;
@property (nonatomic) CGSize size;
@property (nonatomic, strong) NSString *colour;
@property (nonatomic) CGFloat opacity;

@property (nonatomic, strong) NSString *imageFile;
@property (nonatomic) NSInteger scrollerWidth;
@property (nonatomic) NSInteger scrollerPosition;
@property (nonatomic) CGFloat scrollerSpeed;
@property (nonatomic, readonly) BOOL isRunning;

@end

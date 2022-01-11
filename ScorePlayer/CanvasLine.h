//
//  CanvasLine.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 25/9/18.
//  Copyright (c) 2018 Decibel. All rights reserved.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "Renderer.h"
#import "Canvas.h"

@interface CanvasLine : NSObject <CanvasObject> {
    CAShapeLayer *containerLayer;
    NSInteger partNumber;
    NSString *parentLayer;
    NSInteger width;
    CGPoint startPoint;
    CGPoint endPoint;
}

@property (nonatomic, strong, readonly) CALayer *containerLayer;
@property (nonatomic, strong, readonly) CALayer *objectLayer;
@property (nonatomic) NSInteger partNumber;
@property (nonatomic, strong) NSString *parentLayer;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGPoint position;
@property (nonatomic) CGSize size;
@property (nonatomic) NSString *colour;
@property (nonatomic) CGFloat opacity;
@property (nonatomic) NSInteger width;
@property (nonatomic) CGPoint startPoint;
@property (nonatomic) CGPoint endPoint;
@property (nonatomic) NSString *points;

@end

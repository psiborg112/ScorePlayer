//
//  CanvasStave.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 23/9/18.
//  Copyright (c) 2018 Decibel. All rights reserved.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "Renderer.h"
#import "Canvas.h"

@interface CanvasStave : NSObject <CanvasObject> {
    CALayer *containerLayer;
    NSInteger partNumber;
    NSString *parentLayer;
    NSString *imageFile;
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
@property (nonatomic) NSInteger lineWidth;

@property (nonatomic) NSString *clefCollection;
@property (nonatomic) NSString *noteCollection;

@end

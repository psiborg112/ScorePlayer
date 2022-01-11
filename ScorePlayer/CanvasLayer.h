//
//  CanvasLayer.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 16/12/17.
//  Copyright (c) 2017 Decibel. All rights reserved.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "Renderer.h"
#import "Canvas.h"

@interface CanvasLayer : NSObject <CanvasObject> {
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
@property (nonatomic, strong) NSString *imageFile;

@end

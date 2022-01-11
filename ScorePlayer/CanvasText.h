//
//  CanvasText.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 8/8/18.
//  Copyright (c) 2018 Decibel. All rights reserved.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "Renderer.h"
#import "Canvas.h"

@interface CanvasText : NSObject <CanvasObject> {
    CALayer *containerLayer;
    NSInteger partNumber;
    NSString *parentLayer;
    NSString *imageFile;
    NSString *font;
    CGFloat paddingFactor;
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

@property (nonatomic, strong) NSString *text;
@property (nonatomic, strong) NSString *font;
@property (nonatomic) CGFloat fontSize;
@property (nonatomic) CGFloat paddingFactor;

@end

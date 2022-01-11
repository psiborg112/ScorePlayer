//
//  CanvasLayer.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 16/12/17.
//  Copyright (c) 2017 Decibel. All rights reserved.

#import "CanvasLayer.h"

@implementation CanvasLayer {
    NSString *scorePath;
    
    int rgba[4];
}

@synthesize containerLayer, partNumber, parentLayer;

#pragma mark CanvasObject delegate

- (id)initWithScorePath:(NSString *)path;
{
    self = [super init];
    containerLayer = [CALayer layer];
    containerLayer.anchorPoint = CGPointZero;
    scorePath = path;
    
    for (int i = 0; i < 4; i++) {
        rgba[i] = 0;
    }
    
    return self;
}

- (CALayer *)objectLayer
{
    return containerLayer;
}

- (void)setHidden:(BOOL)hidden
{
    containerLayer.hidden = hidden;
}

- (BOOL)hidden
{
    return containerLayer.hidden;
}

- (void)setPosition:(CGPoint)position
{
    containerLayer.position = position;
}

- (CGPoint)position
{
    return containerLayer.position;
}

- (void)setSize:(CGSize)size
{
    containerLayer.frame = CGRectMake(containerLayer.frame.origin.x, containerLayer.frame.origin.y, size.width, size.height);
}

- (CGSize)size
{
    return CGSizeMake(containerLayer.bounds.size.width, containerLayer.bounds.size.height);
}

- (void)setColour:(NSString *)colour
{
    [Canvas colourString:colour toArray:rgba];
    containerLayer.backgroundColor = [UIColor colorWithRed:(rgba[0] / 255.0) green:(rgba[1] / 255.0) blue:(rgba[2] / 255.0) alpha:(rgba[3] / 255.0)].CGColor;
}

- (NSString *)colour{
    return [NSString stringWithFormat:@"%i,%i,%i,%i", rgba[0], rgba[1], rgba[2], rgba[3]];
}

- (void)setOpacity:(CGFloat)opacity
{
    //Clamp value to between 0 and 1.
    opacity = opacity > 1 ? 1 : opacity;
    opacity = opacity < 0 ? 0 : opacity;
    containerLayer.opacity = opacity;
}

- (CGFloat)opacity
{
    return containerLayer.opacity;
}

- (void)setImageFile:(NSString *)image
{
    [self loadImage:image autoSizing:NO];
}

- (NSString *)imageFile
{
    return imageFile;
}

- (void)loadImage:(NSString *)file autoSizing:(BOOL)autosize
{
    UIImage *image = [Renderer cachedImage:[scorePath stringByAppendingPathComponent:file]];
    
    [CATransaction begin];
    [CATransaction setDisableActions:autosize];
    //Check to see if we're trying to load the same image before taking action.
    if (![file isEqualToString:imageFile]) {
        containerLayer.contents = (id)image.CGImage;
        imageFile = file;
    }
    if (autosize) {
        containerLayer.bounds = CGRectMake(0, 0, image.size.width, image.size.height);
    }
    [CATransaction commit];
}

- (void)clearImage
{
    containerLayer.contents = nil;
    imageFile = nil;
}

@end

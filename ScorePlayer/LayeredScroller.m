//
//  LayeredScroller.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 18/07/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import "LayeredScroller.h"
#import <QuartzCore/QuartzCore.h>
#import "Renderer.h"

@implementation LayeredScroller {
    CALayer *fadeLayer;
    CGSize originalSize;
    CGSize originalFadeLayerSize;
    NSString *layerFileName;
    CGFloat scaleFactor;
    
    BOOL fadeLayerDisplayed;
    NSInteger displayedCount;
    NSInteger fadeLength;
    NSInteger minDisplayLength;
    NSInteger maxDisplayLength;
    NSInteger minClearLength;
    NSInteger maxClearLength;
    
    NSInteger displayLength;
    NSInteger clearLength;
    
    NSInteger xAdjustMax;
    NSInteger yAdjustMax;
    NSInteger xAdjust;
    NSInteger yAdjust;
    CGPoint origin;
    BOOL allowRotation;
    CGPoint rotationCentre;
}

@synthesize width, numberOfTiles, background, loadOccurred;

#pragma mark - Scroller delegate

+ (BOOL)allowsParts
{
    return YES;
}

+ (BOOL)requiresData
{
    return NO;
}

+ (NSArray *)requiredOptions
{
    return [NSArray arrayWithObjects:@"layerfile", @"fadelength", @"mindisplay", @"maxdisplay", @"minclear", @"maxclear", nil];
}

- (id)initWithTiles:(NSInteger)tiles options:(NSMutableDictionary *)options
{
    self = [super init];
    
    //Check that our arguments are sane.
    /*if (tiles < 1) {
        tiles = 1;
    }*/
    
    //For the moment, we're not implementing any tiling system here
    numberOfTiles = 1;
    loadOccurred = NO;
    
    //Set up the background layer.
    background = [CALayer layer];
    background.bounds = CGRectMake(0, 0, 1, 1);
    background.anchorPoint = CGPointZero;
    background.position = CGPointZero;
    background.masksToBounds = YES;
    
    //And then the layer to fade in and out.
    fadeLayer = [CALayer layer];
    fadeLayer.bounds = CGRectMake(0, 0, 1, 1);
    fadeLayer.position = CGPointZero;
    fadeLayer.masksToBounds = YES;
    fadeLayer.opacity = 0;
    [background addSublayer:fadeLayer];
    
    //Load options and reset variables.
    fadeLayerDisplayed = NO;
    displayedCount = 0;
    layerFileName = [options objectForKey:@"layerfile"];
    fadeLength = [[options objectForKey:@"fadelength"] integerValue];
    minDisplayLength = [[options objectForKey:@"mindisplay"] integerValue];
    maxDisplayLength = [[options objectForKey:@"maxdisplay"] integerValue];
    minClearLength = [[options objectForKey:@"minclear"] integerValue];
    maxClearLength = [[options objectForKey:@"maxclear"] integerValue];
    
    //Load our optional properties if we can find them or set sensibel defaults.
    xAdjustMax =  [options objectForKey:@"xadjustmax"] != nil ? [[options objectForKey:@"xadjustmax"] integerValue]: 0;
    yAdjustMax =  [options objectForKey:@"yadjustmax"] != nil ? [[options objectForKey:@"yadjustmax"] integerValue]: 0;
    xAdjust = 0;
    yAdjust = 0;
    
    if ([options objectForKey:@"origin"] != nil) {
        NSArray *originArray = [[options objectForKey:@"origin"] componentsSeparatedByString:@","];
        if ([originArray count] == 2) {
            origin = CGPointMake([[originArray objectAtIndex:0] integerValue], [[originArray objectAtIndex:1] integerValue]);
        } else {
            origin = CGPointZero;
        }
    } else {
        origin = CGPointZero;
    }
    
    if ([[options objectForKey:@"allowrotation"] caseInsensitiveCompare:@"yes"] == NSOrderedSame && [options objectForKey:@"rotationcentre"] != nil) {
        NSArray *centre = [[options objectForKey:@"rotationcentre"] componentsSeparatedByString:@","];
        if ([centre count] == 2) {
            rotationCentre = CGPointMake([[centre objectAtIndex:0] integerValue], [[centre objectAtIndex:1] integerValue]);
            origin = CGPointMake(origin.x + rotationCentre.x, origin.y + rotationCentre.y);
            allowRotation = YES;
        } else {
            allowRotation = NO;
            fadeLayer.anchorPoint = CGPointZero;
        }
    } else {
        allowRotation = NO;
        fadeLayer.anchorPoint = CGPointZero;
    }
    
    displayLength = arc4random_uniform((int)(maxDisplayLength - minDisplayLength) + 1) + minDisplayLength;
    clearLength = arc4random_uniform((int)(maxClearLength - minClearLength) + 1) + minClearLength;
    
    originalSize = CGSizeMake(0, 0);
    originalFadeLayerSize = CGSizeMake(0, 0);
    
    return self;
}

- (void)setHeight:(CGFloat)newHeight
{
    //Calculate the new width
    scaleFactor = newHeight / originalSize.height;
    
    width = (int)roundf(originalSize.width * scaleFactor);
    height = newHeight;
    
    //Resize the layers
    background.bounds = CGRectMake(0, 0, width, height);
    fadeLayer.bounds = CGRectMake(0, 0, originalFadeLayerSize.width * scaleFactor, originalFadeLayerSize.height * scaleFactor);
    fadeLayer.position = CGPointMake(scaleFactor * (origin.x + xAdjust), scaleFactor * (origin.y + yAdjust));
}

- (CGFloat)height
{
    return height;
}

- (void)setX:(CGFloat)x
{
    [CATransaction begin];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    background.position = CGPointMake(x, background.position.y);
    [CATransaction commit];
}

- (CGFloat)x
{
    return background.position.x;
}

- (void)setY:(CGFloat)y
{
    background.position = CGPointMake(background.position.x, y);
}

- (CGFloat)y
{
    return background.position.y;
}

- (void)changePart:(NSString *)firstImageName
{
    //Load our image.
    UIImage *backgroundImage = [Renderer cachedImage:firstImageName];
    UIImage *fadeImage =  [Renderer cachedImage:[[firstImageName stringByDeletingLastPathComponent] stringByAppendingPathComponent:layerFileName]];
    
    background.contents = (id)backgroundImage.CGImage;
    fadeLayer.contents = (id)fadeImage.CGImage;
    
    //For the moment, we're not doing any fancy resizing for changes of parts. We're simply loading the parts into
    //into the layer size created from loading the score image. Should change this later.
    if (originalSize.width == 0) {
        background.bounds = CGRectMake(0, 0, backgroundImage.size.width, backgroundImage.size.height);
        fadeLayer.bounds = CGRectMake(0, 0, fadeImage.size.width, fadeImage.size.height);
        originalSize = CGSizeMake(backgroundImage.size.width, backgroundImage.size.height);
        originalFadeLayerSize = CGSizeMake(fadeImage.size.width, fadeImage.size.height);
        if (allowRotation) {
            fadeLayer.anchorPoint = CGPointMake(rotationCentre.x / originalFadeLayerSize.width, rotationCentre.y / originalFadeLayerSize.height);
        }
        scaleFactor = 1;
    }
}

- (CGSize)originalSizeOfImages:(NSString *)firstImageName
{
    return originalSize;
}

- (CGSize)originalSize
{
    return originalSize;
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    displayedCount++;
    
    if (fadeLayerDisplayed) {
        if (displayedCount >= displayLength) {
            [CATransaction begin];
            [CATransaction setAnimationDuration:fadeLength];
            fadeLayer.opacity = 0;
            [CATransaction commit];
            displayedCount = 0;
            clearLength = arc4random_uniform((int)(maxClearLength - minClearLength) + 1) + minClearLength;
            fadeLayerDisplayed = NO;
        }
    } else {
        if (displayedCount >= clearLength) {
            //As well as fading in the layer, we should apply a random offset if one is specified.
            xAdjust = xAdjustMax > 0 ? (int)arc4random_uniform((int)xAdjustMax * 2 + 1) - xAdjustMax: 0;
            yAdjust = yAdjustMax > 0 ? (int)arc4random_uniform((int)yAdjustMax * 2 + 1) - yAdjustMax: 0;
            //NSLog(@"%i, %i", (int)xOffset, (int)yOffset);
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            fadeLayer.position = CGPointMake(scaleFactor * (origin.x + xAdjust), scaleFactor * (origin.y + yAdjust));
            //Rotate here as well if necessary.
            if (allowRotation) {
                CGFloat angle = (CGFloat)arc4random_uniform(360);
                [fadeLayer setValue:[NSNumber numberWithFloat:(M_PI * angle / 180.0)] forKeyPath:@"transform.rotation.z"];
            }
            
            [CATransaction commit];
            
            [CATransaction begin];
            [CATransaction setAnimationDuration:fadeLength];
            fadeLayer.opacity = 1;
            [CATransaction commit];
            displayedCount = 0;
            displayLength = arc4random_uniform((int)(maxDisplayLength - minDisplayLength) + 1) + minDisplayLength;
            fadeLayerDisplayed = YES;
        }
    }
}

@end

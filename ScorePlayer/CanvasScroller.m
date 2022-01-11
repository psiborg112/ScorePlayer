//
//  CanvasScroller.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/6/18.
//  Copyright (c) 2018 Decibel. All rights reserved.

#import "CanvasScroller.h"

@interface CanvasScroller ()

- (void)animate;

@end

@implementation CanvasScroller {
    NSString *scorePath;
    CALayer *scroller;
    
    NSTimer *highRes;
    CGFloat pixelsPerShift;
    CGFloat timerInterval;
    
    int rgba[4];
}

@synthesize containerLayer, partNumber, parentLayer, isRunning;

- (void)animate
{
    int scrollerX = scroller.position.x - pixelsPerShift;
    //If the scroller has reached the boundaries of the container, stop our timer.
    //Keep the isRunning variable set though so that a change in speed in the opposite
    //direction will resume the scroller.
    
    if (pixelsPerShift > 0) {
        if (scrollerX <= -scroller.bounds.size.width) {
            scrollerX = -scroller.bounds.size.width;
            [highRes invalidate];
        }
    } else if (pixelsPerShift < 0) {
        if (scrollerX >= containerLayer.bounds.size.width) {
            scrollerX = containerLayer.bounds.size.width;
            [highRes invalidate];
        }
    }
    [CATransaction begin];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    scroller.position = CGPointMake(scrollerX, 0);
    [CATransaction commit];
}

#pragma mark CanvasObject delegate

- (id)initWithScorePath:(NSString *)path
{
    self = [super init];
    containerLayer = [CALayer layer];
    containerLayer.anchorPoint = CGPointZero;
    containerLayer.masksToBounds = YES;
    scorePath = path;
    
    scroller = [CALayer layer];
    scroller.anchorPoint = CGPointZero;
    scroller.position = CGPointZero;
    [containerLayer addSublayer:scroller];
    
    isRunning = NO;
    scrollerSpeed = 0;
    for (int i = 0; i < 4; i++) {
        rgba[i] = 0;
    }
    
    return self;
}

- (CALayer *)objectLayer
{
    return scroller;
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
    scroller.frame = CGRectMake(scroller.frame.origin.x, scroller.frame.origin.y, scroller.frame.size.width, size.height);
    
    if (scroller.position.x > size.width) {
        scroller.position = CGPointMake(size.width, scroller.position.x);
    }
}

- (CGSize)size
{
    return CGSizeMake(containerLayer.bounds.size.width, containerLayer.bounds.size.height);
}

- (void)setColour:(NSString *)colour
{
    [Canvas colourString:colour toArray:rgba];
    scroller.backgroundColor = [UIColor colorWithRed:(rgba[0] / 255.0) green:(rgba[1] / 255.0) blue:(rgba[2] / 255.0) alpha:(rgba[3] / 255.0)].CGColor;
}

- (NSString *)colour
{
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

- (void)setScrollerWidth:(NSInteger)scrollerWidth
{
    scroller.bounds = CGRectMake(0, 0, scrollerWidth, scroller.bounds.size.height);
}

- (NSInteger)scrollerWidth
{
    return scroller.bounds.size.width;
}

- (void)setScrollerPosition:(NSInteger)scrollerPosition
{
    //Clamp values so that the scroller can only go so far as just being off the edge of the container.
    scrollerPosition = scrollerPosition > scroller.bounds.size.width ? scroller.bounds.size.width : scrollerPosition;
    scrollerPosition = scrollerPosition < -containerLayer.bounds.size.width ? -containerLayer.bounds.size.width : scrollerPosition;
    
    BOOL wasRunning = NO;
    if (isRunning) {
        wasRunning = YES;
        [self stop];
    }
    [scroller removeAllAnimations];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    scroller.position = CGPointMake(-scrollerPosition, 0);
    [CATransaction commit];
    if (wasRunning) {
        [self start];
    }
}

- (NSInteger)scrollerPosition
{
    return -scroller.position.x;
}

- (void)setScrollerSpeed:(CGFloat)speed
{
    scrollerSpeed = speed;
    //Limit our scroller to a predefined maximum framerate.
    if (speed > 0) {
        pixelsPerShift = ceilf(speed / MAX_CANVASSCROLLER_FRAMERATE);
    } else if (speed < 0) {
        pixelsPerShift = floorf(speed / MAX_CANVASSCROLLER_FRAMERATE);
    } else {
        //If our speed is set to zero, then invalidate the timer and leave.
        pixelsPerShift = 0;
        [highRes invalidate];
        return;
    }
    
    //Otherwise set the timer interval and restart the timer if necessary.
    timerInterval = pixelsPerShift / speed;
    
    if (isRunning) {
        [self stop];
        [self start];
    }
}

- (CGFloat)scrollerSpeed
{
    return scrollerSpeed;
}

- (void)loadImage:(NSString *)file autoSizing:(BOOL)autosize
{
    UIImage *image = [Renderer cachedImage:[scorePath stringByAppendingPathComponent:file]];
    
    [CATransaction begin];
    [CATransaction setDisableActions:autosize];
    //Check to see if we're trying to load the same image before taking action.
    if (![file isEqualToString:imageFile]) {
        scroller.contents = (id)image.CGImage;
        imageFile = file;
    }
    if (autosize) {
        //If autosize is set, make the scroller and container heigh match the image height and the
        //scroller width match the image width. (There is no change to the container width.)
        containerLayer.bounds = CGRectMake(0, 0, containerLayer.bounds.size.width, image.size.height);
        scroller.bounds = CGRectMake(0, 0, image.size.width, image.size.height);
    }
    [CATransaction commit];
}

- (void)clearImage
{
    scroller.contents = nil;
    imageFile = nil;
}

- (void)start
{
    //If our timer is already running or our scroller speed is zero he are done here.
    if (isRunning || scrollerSpeed == 0) {
        //Even if our speed is zero, set our scroller as running.
        //This way a change of speed will have the effect of starting it.
        isRunning = YES;
        return;
    }
    
    //For safety, invalidate the highres timer if it already exists.
    if (highRes != nil) {
        [highRes invalidate];
    }
    
    //Set up our timer.
    highRes = [NSTimer scheduledTimerWithTimeInterval:timerInterval target:self selector:@selector(animate) userInfo:nil repeats:YES];
    isRunning = YES;
}

- (void)stop
{
    [highRes invalidate];
    isRunning = NO;
}

@end

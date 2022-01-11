//
//  BigClock.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 25/04/13.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "BigClock.h"
#import "Score.h"

@interface BigClock ()

- (void)updateDisplay:(int)progress;

@end

@implementation BigClock {
    Score *score;
    CALayer *canvas;
    
    BOOL countDown;
    BOOL darkMode;
    BOOL split;
    
    UILabel *display;
    
    __weak id<RendererUI> UIDelegate;
}

@synthesize isMaster;

- (void)updateDisplay:(int)progress
{
    int value = progress;
    if (countDown) {
        value = UIDelegate.clockDuration - progress;
    }
    NSUInteger minutes = value / 60;
    NSUInteger seconds = value % 60;
    if (split) {
        display.text = [NSString stringWithFormat:@"%lu %02lu", (unsigned long)minutes, (unsigned long)seconds];
    } else {
        display.text = [NSString stringWithFormat:@"%lu:%02lu", (unsigned long)minutes, (unsigned long)seconds];
    }
}

#pragma mark - Renderer delegate

+ (RendererFeatures)getRendererRequirements
{
    return kPositiveDuration;
}

+ (UIImage *)generateThumbnailForScore:(Score *)score ofSize:(CGSize)size
{
    //Make image double resolution for retina screens.
    CGFloat screenScale = [[UIScreen mainScreen] scale];
    size = CGSizeMake(size.width * screenScale, size.height * screenScale);
    NSString *timeString = [NSString stringWithFormat:@"%lu:%02lu", (unsigned long)score.originalDuration / 60, (unsigned long)score.originalDuration % 60];
    UIFont *font = [UIFont fontWithName:@"Courier-Bold" size:21 * screenScale];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
    CGSize textSize = [timeString sizeWithAttributes:attributes];
    
    UIGraphicsBeginImageContext(size);
    [[UIColor whiteColor] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    CGFloat x = (size.width - textSize.width) / 2.0;
    CGFloat y = (size.height - textSize.height) / 2.0;
    [timeString drawInRect:CGRectMake(x, y, textSize.width, textSize.height) withAttributes:attributes];
    UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return thumbnail;
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    
    isMaster = YES;
    score = scoreData;
    canvas = playerCanvas;
    UIDelegate = UIDel;
    UIDelegate.splitSecondMode = YES;
    darkMode = NO;
    display = [[UILabel alloc] init];
    display.textColor = [UIColor blackColor];
    display.font = [UIFont fontWithName:@"Courier-Bold" size:UIDelegate.cueLightScale * 240];
    display.textAlignment = NSTextAlignmentCenter;
    
    if (@available(iOS 13.0, *)) {
        if ([UIApplication sharedApplication].keyWindow.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            darkMode = YES;
            [UIDelegate setPlayerBackgroundColour:[UIColor blackColor]];
            [UIDelegate setMarginColour:[UIColor blackColor]];
            display.textColor = [UIColor whiteColor];
        }
    }
    
    countDown = NO;
    
    return self;
}

- (void)reset
{
    split = NO;
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    canvas.sublayers = nil;
    display.frame = CGRectMake(0, 0, canvas.bounds.size.width, canvas.bounds.size.height);
    [self updateDisplay:0];
    [canvas addSublayer:display.layer];
    
    [CATransaction commit];
}

- (void)play
{
    //Nothing needs to be done here. It's all handled by the tick function.
}

- (void)stop
{
    //Same as above.
}

- (void)seek:(CGFloat)location
{
    split = NO;
    [self updateDisplay:UIDelegate.clockProgress];
}

- (void)rotate
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    display.frame = CGRectMake(0, 0, canvas.bounds.size.width, canvas.bounds.size.height);
    [CATransaction commit];
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    if (splitSecond == 1) {
        split = YES;
    } else {
        split = NO;
    }

    [self updateDisplay:progress];
}

- (void)swipeUp
{
    darkMode = !darkMode;
    if (darkMode) {
        [UIDelegate setPlayerBackgroundColour:[UIColor blackColor]];
        [UIDelegate setMarginColour:[UIColor blackColor]];
        if (!countDown) {
            display.textColor = [UIColor whiteColor];
        }
    } else {
        [UIDelegate setPlayerBackgroundColour:[UIColor whiteColor]];
        [UIDelegate setMarginColour:[UIColor whiteColor]];
        if (!countDown) {
            display.textColor = [UIColor blackColor];
        }
    }
}

- (void)swipeDown
{
    [self swipeUp];
}

- (void)tapAt:(CGPoint)location
{
    countDown = !countDown;
    if (countDown) {
        display.textColor = [UIColor redColor];
    } else {
        if (darkMode) {
            display.textColor = [UIColor whiteColor];
        } else {
            display.textColor = [UIColor blackColor];
        }
    }
    [self updateDisplay:UIDelegate.clockProgress];
}

@end

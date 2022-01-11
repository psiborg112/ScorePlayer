//
//  CageEvent.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 18/07/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "CageEvent.h"

@implementation CageEvent {
    CATextLayer *numberDisplay;
}

@synthesize layer;

+ (NSInteger)getFrameRate
{
    return CAGE_FRAMERATE;
}

- (id)initWithNumberOfEvents:(NSInteger)events duration:(NSInteger)length timbre:(NSInteger)quality dynamics:(NSInteger)volume
{
    self = [super init];
    layer = [CALayer layer];
    //Set some placeholder bounds for the event
    layer.bounds = CGRectMake(0, 0, 500, 20);
    layer.anchorPoint = CGPointMake(0, 0.5);
    layer.borderWidth = 0;
    
    numberDisplay = [CATextLayer layer];
    numberDisplay.bounds = CGRectMake(0, 0, 48, 48);
    numberDisplay.anchorPoint = CGPointMake(0, 1);
    numberDisplay.position = CGPointMake(0, 2);
    numberDisplay.fontSize = 48;
    numberDisplay.alignmentMode = kCAAlignmentLeft;
    numberDisplay.contentsScale = [[UIScreen mainScreen] scale];
    [layer addSublayer:numberDisplay];
    
    [self setNumber:events];
    [self setDuration:length];
    [self setTimbre:quality];
    [self setDynamics:volume];
    
    return self;
}

- (void)setNumber:(NSInteger)newNumber
{
    number = newNumber;
    if (number > 4) {
        number = 4;
    } else if (number < 1) {
        number = 1;
    }
    
    numberDisplay.string = [NSString stringWithFormat:@"%i", (int)number];
}

- (NSInteger)number
{
    return number;
}

- (void)setDuration:(NSInteger)newDuration
{
    duration = newDuration;
    
    int length = duration * (CGFloat)CAGE_FRAMERATE / 1000;
    
    layer.bounds = CGRectMake(0, 0, length, layer.bounds.size.height);
}

- (NSInteger)duration
{
    return duration;
}

- (void)setTimbre:(NSInteger)newTimbre
{
    timbre = newTimbre;
    if (timbre > 5) {
        timbre = 5;
    } else if (timbre < 1) {
        timbre = 1;
    }
    
    layer.backgroundColor = [UIColor colorWithWhite:(5 - timbre) / 5.0 alpha:1].CGColor;
    numberDisplay.foregroundColor = [UIColor colorWithWhite:(5 - timbre) / 5.0 alpha:1].CGColor;
}

- (NSInteger)timbre
{
    return timbre;
}

- (void)setDynamics:(NSInteger)newDynamics
{
    dynamics = newDynamics;
    if (dynamics > 5) {
        dynamics = 5;
    } else if (dynamics < 1) {
        dynamics = 1;
    }
    
    layer.bounds = CGRectMake(0, 0, layer.bounds.size.width, 5 * dynamics);
}

- (NSInteger)dynamics
{
    return dynamics;
}

@end

/* Five different line thicknesses and shades, length variable within bounds
 (1 - 700 pixels added to a base of 300)
 */

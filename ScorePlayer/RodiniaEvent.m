//
//  RodiniaEvent.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 10/09/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "RodiniaEvent.h"

@implementation RodiniaEvent {
    CAShapeLayer *articulationLayer;
    CAShapeLayer *lengthLayer;
    CAShapeLayer *tremoloLayer;
}

@synthesize streamPosition, layer;

- (id)initWithArticulation:(Articulation)style glissAmount:(NSInteger)gliss ghost:(BOOL)ghosted tremolo:(BOOL)trem length:(NSInteger)len
{
    self = [super init];
    
    layer = [CALayer layer];
    //Set some placeholder bounds for the event
    layer.bounds = CGRectMake(0, 0, 500, 100);
    layer.anchorPoint = CGPointMake(0, 0.5);
    
    colour = [UIColor blackColor];
    rotation = 0;
    
    articulationLayer = [CAShapeLayer layer];
    articulationLayer.bounds = CGRectMake(0, 0, 20, 20);
    articulationLayer.position = CGPointMake(0, 50);
    articulationLayer.borderWidth = 2;
    articulationLayer.lineWidth = 2;
    articulationLayer.strokeColor = colour.CGColor;
    
    ghost = ghosted;
    [self setArticulation:style];
    
    lengthLayer = [CAShapeLayer layer];
    lengthLayer.strokeColor = colour.CGColor;
    lengthLayer.fillColor = [UIColor clearColor].CGColor;
    lengthLayer.lineWidth = 8;
    lengthLayer.bounds = CGRectMake(0, 0, 500, 100);
    lengthLayer.anchorPoint = CGPointZero;
    lengthLayer.position = CGPointZero;
    glissAmount = gliss;
    [self setLength:len];
    
    tremoloLayer = [CAShapeLayer layer];
    tremoloLayer.strokeColor = colour.CGColor;
    tremoloLayer.fillColor = [UIColor clearColor].CGColor;
    tremoloLayer.lineWidth = 16;
    tremoloLayer.bounds = CGRectMake(0, 0, 500, 100);
    tremoloLayer.anchorPoint = CGPointZero;
    tremoloLayer.position = CGPointZero;
    tremoloLayer.lineDashPattern = [NSArray arrayWithObjects:[NSNumber numberWithInt:2], [NSNumber numberWithInt:2], nil];
    [self setTremolo:trem];
    
    [layer addSublayer:lengthLayer];
    [layer addSublayer:tremoloLayer];
    [layer addSublayer:articulationLayer];
    
    return self;
}

- (id)initAsDuplicateOfEvent:(RodiniaEvent *)event
{
    self = [[RodiniaEvent alloc] initWithArticulation:event.articulation glissAmount:event.glissAmount ghost:event.ghost tremolo:event.tremolo length:event.length];
    [self setColour:event.colour];
    [self setRotation:event.rotation];
    [self setStreamPosition:event.streamPosition];
    
    return self;
}

- (void)setArticulation:(Articulation)style
{
    articulation = style;
    
    switch (style) {
        case kNormal:
            articulationLayer.borderColor = colour.CGColor;
            articulationLayer.path = nil;
            articulationLayer.cornerRadius = 10;
            break;
            
        case kNoise:
            articulationLayer.borderColor = colour.CGColor;
            articulationLayer.path = nil;
            articulationLayer.cornerRadius = 0;
            break;
            
        case kPoint:
            articulationLayer.backgroundColor = [UIColor clearColor].CGColor;
            articulationLayer.borderColor = [UIColor clearColor].CGColor;
            UIBezierPath *trianglePath = [UIBezierPath bezierPath];
            [trianglePath moveToPoint:CGPointZero];
            [trianglePath addLineToPoint:CGPointMake(20, 0)];
            [trianglePath addLineToPoint:CGPointMake(10, 20)];
            [trianglePath closePath];
            articulationLayer.path = trianglePath.CGPath;
            break;
    }
    
    [self setGhost:ghost];
}

- (Articulation)articulation
{
    return articulation;
}

- (void)setGlissAmount:(NSInteger)gliss
{
    glissAmount = gliss;
    [self setLength:length];
}

- (NSInteger)glissAmount
{
    return glissAmount;
}

- (void)setGhost:(BOOL)ghosted
{
    ghost = ghosted;
    if (articulation == kPoint) {
        if (ghost) {
            articulationLayer.fillColor = [UIColor whiteColor].CGColor;
        } else {
            articulationLayer.fillColor = colour.CGColor;
        }
    } else {
        if (ghost) {
            articulationLayer.backgroundColor = [UIColor whiteColor].CGColor;
        } else {
            articulationLayer.backgroundColor = colour.CGColor;
        }
    }
}

- (BOOL)ghost
{
    return ghost;
}

- (void)setTremolo:(BOOL)trem
{
    tremolo = trem;
    //At the moment, tremolo is only possible if there is no gliss.
    if (trem && glissAmount == 0 && length > 20) {
        UIBezierPath *trem = [UIBezierPath bezierPath];
        [trem moveToPoint:CGPointMake(15, 50)];
        [trem addLineToPoint:CGPointMake(length - 5, 50)];
        tremoloLayer.path = trem.CGPath;
    } else {
        tremoloLayer.path = nil;
    }
}

- (BOOL)tremolo
{
    return tremolo;
}

- (void)setLength:(NSInteger)len
{
    length = len;
    if (length <= 0) {
        lengthLayer.path = nil;
    } else if (glissAmount == 0) {
        UIBezierPath *line = [UIBezierPath bezierPath];
        [line moveToPoint:CGPointMake(0, 50)];
        [line addLineToPoint:CGPointMake(length, 50)];
        lengthLayer.path = line.CGPath;
    } else {
        UIBezierPath *curve = [UIBezierPath bezierPath];
        [curve moveToPoint:CGPointMake(0, 50)];
        [curve addCurveToPoint:CGPointMake(length, 50 - glissAmount) controlPoint1:CGPointMake(0.6 * length, 50.0 - (0.1 * glissAmount)) controlPoint2:CGPointMake(0.8 * length, 50.0 - (0.1 * glissAmount))];
        lengthLayer.path = curve.CGPath;
    }
    [self setTremolo:tremolo];
}

- (NSInteger)length
{
    return length;
}

- (void)setColour:(UIColor *)newColour
{
    colour = newColour;
    articulationLayer.strokeColor = colour.CGColor;
    if (articulation != kPoint) {
        articulationLayer.borderColor = colour.CGColor;
    }
    [self setGhost:ghost];
    
    lengthLayer.strokeColor = colour.CGColor;
    tremoloLayer.strokeColor = colour.CGColor;
}

- (UIColor *)colour
{
    return colour;
}

- (void)setRotation:(NSInteger)newRotation
{
    rotation = newRotation;
    CGFloat angle = M_PI_2 * rotation;
    [layer setValue:[NSNumber numberWithFloat: angle] forKeyPath:@"transform.rotation.z"];
}

- (NSInteger)rotation
{
    return rotation;
}

@end

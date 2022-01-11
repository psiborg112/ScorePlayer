//
//  PlayerCanvas.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 27/2/20.
//  Copyright (c) 2020 Decibel. All rights reserved.
//

#import "PlayerCanvas.h"
#import "AnnotationLayer.h"

@interface PlayerCanvas ()

- (CGRect)getDirtyRectFrom:(CGPoint)startPoint to:(CGPoint)endPoint;
- (void)save;

@end

@implementation PlayerCanvas {
    CGPoint lastPoint;
    AnnotationLayer *annotationLayer;
    CAShapeLayer *currentLine;
    UIBezierPath *currentPath;
    BOOL continuous;
    
    CGFloat lineWidth;
    NSInteger counter;
    
    NSTimer *saveTimer;
}

@synthesize erasing, changed, delegate;

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    annotationLayer = [AnnotationLayer layer];
    annotationLayer.opacity = 0;
    
    lineWidth = 4;
    annotationLayer.eraserWidth = 8 * lineWidth;
    
    currentLine = [CAShapeLayer layer];
    currentLine.fillColor = nil;
    currentLine.strokeColor = [UIColor redColor].CGColor;
    currentLine.lineWidth = lineWidth;
    currentLine.lineCap = kCALineCapRound;
    currentLine.lineJoin = kCALineJoinRound;
    
    return self;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

- (void)layoutSubviews {
    [super layoutSubviews];
    annotationLayer.frame = delegate.canvasScaledFrame;
    [self.layer addSublayer:annotationLayer];
}


- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    if (!annotating) {
        return;
    }
    [saveTimer invalidate];
    
    //Hide the saved annotations and show the working copy.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    annotationLayer.opacity = 1;
    [delegate hideSavedAnnotations:YES];
    changed = YES;
    
    continuous = NO;
    lastPoint = [[touches anyObject] locationInView:self];
    currentPath = [UIBezierPath bezierPath];
    [currentPath moveToPoint:lastPoint];
    if (!erasing) {
        if (currentLine.superlayer == nil) {
            [annotationLayer addSublayer:currentLine];
        }
    } else {
        annotationLayer.eraserPath = currentPath;
    }
    [CATransaction commit];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];
    
    if (!annotating) {
        return;
    }
    
    continuous = YES;
    CGPoint currentPoint = [[touches anyObject] locationInView:self];
    [currentPath addLineToPoint:currentPoint];
    if (!erasing) {
        currentLine.path = currentPath.CGPath;
    } else {
        [annotationLayer setNeedsDisplayInRect:[self getDirtyRectFrom:lastPoint to:currentPoint]];
    }
    lastPoint = currentPoint;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    
    if (!annotating) {
        return;
    }
    [currentPath addLineToPoint:lastPoint];
    if (!continuous) {
        if (!erasing) {
            currentLine.path = currentPath.CGPath;
        } else {
            [annotationLayer setNeedsDisplayInRect:[self getDirtyRectFrom:lastPoint to:lastPoint]];
        }
    }
    
    //Start our save timer running.
    saveTimer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(save) userInfo:nil repeats:NO];
    
    //Flatten our new line into our annotation layer.
    UIGraphicsBeginImageContextWithOptions(annotationLayer.bounds.size, NO, 1);
    CGContextRef currentContext = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(currentContext, kCGInterpolationHigh);
    CGContextSetShouldAntialias(currentContext, YES);
    //Draw from our saved image to try to avoid any repeated resizing and antialiasing issues.
    [annotationLayer.flattenedImage drawInRect:CGRectMake(0, 0, annotationLayer.bounds.size.width, annotationLayer.bounds.size.height)];
    if (!erasing) {
        [currentLine renderInContext:UIGraphicsGetCurrentContext()];
    } else {
        [currentPath strokeWithBlendMode:kCGBlendModeClear alpha:1];
    }
    UIImage *annotationImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    annotationLayer.flattenedImage = annotationImage;
    annotationLayer.sublayers = nil;
    currentLine.path = nil;
    [CATransaction commit];
}

- (UIImage *)currentImage
{
    return annotationLayer.flattenedImage;
}

- (void)setCurrentImage:(UIImage *)currentImage;
{
    annotationLayer.flattenedImage = currentImage;
}

- (CALayer *)currentMask
{
    return annotationLayer.mask;
}

- (void)setCurrentMask:(CALayer *)currentMask
{
    annotationLayer.mask = currentMask;
}

- (BOOL)annotating
{
    return annotating;
}

- (void)setAnnotating:(BOOL)annotate
{
    annotating = annotate;
    /*if (annotating) {
        //Testing only.
        annotationLayer.backgroundColor = [UIColor colorWithRed:0 green:0 blue:1 alpha:0.4].CGColor;
    } else {
        annotationLayer.backgroundColor = [UIColor clearColor].CGColor;
    }*/
}

- (void)save
{
    //Save our current annotations.
    [saveTimer invalidate];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [delegate saveAnnotation:annotationLayer.flattenedImage];
    annotationLayer.opacity = 0;
    [delegate hideSavedAnnotations:NO];
    [CATransaction commit];
    changed = NO;
}

- (CGRect)getDirtyRectFrom:(CGPoint)startPoint to:(CGPoint)endPoint
{
    //Double the line width that we're using as an aditional safety margin.
    CGFloat width = fabs(startPoint.x - endPoint.x) + annotationLayer.eraserWidth * 2;
    CGFloat height = fabs(startPoint.y - endPoint.y) + annotationLayer.eraserWidth * 2;
    
    CGFloat x = MIN(startPoint.x, endPoint.x) - annotationLayer.eraserWidth;
    CGFloat y = MIN(startPoint.y, endPoint.y) - annotationLayer.eraserWidth;
    
    return CGRectMake(x, y, width, height);
}
   
@end

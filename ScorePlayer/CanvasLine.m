//
//  CanvasLine.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 25/9/18.
//

#import "CanvasLine.h"

@interface CanvasLine ()

- (void)drawLine;

@end

@implementation CanvasLine {
    int rgba[4];
    BOOL hasStartPoint;
    BOOL hasEndPoint;
}

@synthesize containerLayer, partNumber, parentLayer;

- (void)drawLine {
    UIBezierPath *linePath = [UIBezierPath bezierPath];
    [linePath moveToPoint:startPoint];
    [linePath addLineToPoint:endPoint];
    containerLayer.path = linePath.CGPath;
}

#pragma mark CanvasObject delegate

- (id)initWithScorePath:(NSString *)path;
{
    self = [super init];
    containerLayer = [CAShapeLayer layer];
    
    [self setColour:@"0,0,0,255"];
    
    hasStartPoint = NO;
    hasEndPoint = NO;
    
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
    containerLayer.strokeColor = [UIColor colorWithRed:(rgba[0] / 255.0) green:(rgba[1] / 255.0) blue:(rgba[2] / 255.0) alpha:(rgba[3] / 255.0)].CGColor;
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

- (void)setWidth:(NSInteger)width
{
    containerLayer.lineWidth = width;
}

- (NSInteger)width
{
    return containerLayer.lineWidth;
}

- (void)setStartPoint:(CGPoint)point
{
    hasStartPoint = YES;
    startPoint = point;
    if (hasStartPoint && hasEndPoint) {
        [self drawLine];
    }
}

- (CGPoint)startPoint
{
    return startPoint;
}

- (void)setEndPoint:(CGPoint)point
{
    hasEndPoint = YES;
    endPoint = point;
    if (hasStartPoint && hasEndPoint) {
        [self drawLine];
    }
}

- (CGPoint)endPoint
{
    return endPoint;
}

- (void)setPoints:(NSString *)points
{
    NSArray *coordinates = [points componentsSeparatedByString:@","];
    if ([coordinates count] == 4) {
        hasEndPoint = YES;
        hasStartPoint = YES;
        startPoint = CGPointMake([[coordinates objectAtIndex:0] intValue], [[coordinates objectAtIndex:1] intValue]);
        endPoint = CGPointMake([[coordinates objectAtIndex:2] intValue], [[coordinates objectAtIndex:3] intValue]);
        [self drawLine];
    }
}

- (NSString *)points
{
    return [NSString stringWithFormat:@"%i,%i,%i,%i", (int)startPoint.x, (int)startPoint.y, (int)endPoint.x, (int)endPoint.y];
}

@end

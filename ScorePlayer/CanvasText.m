//
//  CanvasText.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 8/8/18.
//

#import "CanvasText.h"

@interface CanvasText ()

- (void)adjustFrameToText;

@end

@implementation CanvasText {
    int rgba[4];
    BOOL debug;
}

@synthesize containerLayer, partNumber, parentLayer;

- (void)adjustFrameToText
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[UIFont fontWithName:font size:((CATextLayer *)containerLayer).fontSize] forKey:NSFontAttributeName];
    CGSize size = [((CATextLayer *)containerLayer).string sizeWithAttributes:attributes];
    if (debug) {
        NSLog(@"%f,%f", size.width, size.height);
    }
    //Add a safety margin determined by the padding factor. (Default is 1.1)
    containerLayer.bounds = CGRectMake(0, 0, size.width * paddingFactor, size.height * paddingFactor);
}

#pragma mark CanvasObject delegate

- (id)initWithScorePath:(NSString *)path;
{
    self = [super init];
    containerLayer = [CATextLayer layer];
    containerLayer.anchorPoint = CGPointZero;
    ((CATextLayer *)containerLayer).contentsScale = [[UIScreen mainScreen] scale];
    
    [self setColour:@"0,0,0,255"];
    paddingFactor = 1.1;
    debug = NO;
    
    if (debug) {
        containerLayer.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.5].CGColor;
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
    containerLayer.bounds = CGRectMake(0, 0, size.width, size.height);
}

- (CGSize)size
{
    return CGSizeMake(containerLayer.bounds.size.width, containerLayer.bounds.size.height);
}

- (void)setColour:(NSString *)colour
{
    [Canvas colourString:colour toArray:rgba];
    ((CATextLayer *)containerLayer).foregroundColor = [UIColor colorWithRed:(rgba[0] / 255.0) green:(rgba[1] / 255.0) blue:(rgba[2] / 255.0) alpha:(rgba[3] / 255.0)].CGColor;
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

- (NSString *)text
{
    if (((CATextLayer *)containerLayer).string != nil) {
        return ((CATextLayer *)containerLayer).string;
    } else {
        return @"";
    }
}

- (void)setText:(NSString *)text
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    ((CATextLayer *)containerLayer).string = text;
    [self adjustFrameToText];
    [CATransaction commit];
}

- (NSString *)font
{
    return font;
}

- (void)setFont:(NSString *)newFont
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    font = newFont;
    ((CATextLayer *)containerLayer).font = (__bridge CFTypeRef)newFont;
    [self adjustFrameToText];
    [CATransaction commit];
}

- (CGFloat)fontSize
{
    return ((CATextLayer *)containerLayer).fontSize;
}

- (void)setFontSize:(CGFloat)fontSize
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    ((CATextLayer *)containerLayer).fontSize = fontSize;
    [self adjustFrameToText];
    [CATransaction commit];
}

- (CGFloat)paddingFactor
{
    return paddingFactor;
}

- (void)setPaddingFactor:(CGFloat)factor
{
    paddingFactor = factor;
    [self adjustFrameToText];
}

@end

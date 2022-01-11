//
//  AnnotationLayer.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 27/2/20.
//

#import "AnnotationLayer.h"

@implementation AnnotationLayer

@synthesize eraserPath, eraserWidth;

- (void)drawInContext:(CGContextRef)ctx
{
    if (eraserPath != nil) {
        UIGraphicsPushContext(ctx);
        [flattenedImage drawInRect:CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height)];
        [[UIColor redColor] setStroke];
        eraserPath.lineWidth = eraserWidth;
        [eraserPath strokeWithBlendMode:kCGBlendModeClear alpha:1];
        //[eraserPath stroke];
        UIGraphicsPopContext();
    }
}

- (UIImage *)flattenedImage
{
    return flattenedImage;
}

- (void)setFlattenedImage:(UIImage *)image
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (image != nil) {
        flattenedImage = image;
    } else {
        //Create a blank image of the right size.
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(self.bounds.size.width, self.bounds.size.height), NO, 1);
        flattenedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    self.contents = (id)flattenedImage.CGImage;
    [CATransaction commit];
}

@end

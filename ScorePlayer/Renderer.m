//
//  Renderer.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 16/07/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "Renderer.h"
#import <ImageIO/ImageIO.h>
#import "Score.h"

static NSMutableDictionary *imageCache;

@implementation Renderer

+ (UIImage *)cachedImage:(NSString *)fileName
{
    //Check to see if the cache already exists and if the requested image has already been loaded
    UIImage *image;
    if (imageCache == nil) {
        imageCache = [[NSMutableDictionary alloc] init];
    } else {
        image = [imageCache objectForKey:fileName];
        if (image != nil) {
            return image;
        }
    }
    
    //Otherwise load the image
    image = [UIImage imageWithContentsOfFile:fileName];
    if (image != nil) {
        [imageCache setObject:image forKey:fileName];
    }
    return image;
}

+ (void)removeDirectoryFromCache:(NSString *)path
{
    //If our cache doesn't exist then we have nothing to do here
    if (imageCache == nil) {
        return;
    }
    
    //Remove any images from the cache in the given directory
    NSArray *imageFiles = [imageCache allKeys];
    for (int i = 0; i < [imageFiles count]; i++) {
        if ([[imageFiles objectAtIndex:i] hasPrefix:path]) {
            [imageCache removeObjectForKey:[imageFiles objectAtIndex:i]];
        }
    }
}

+ (void)clearCache
{
    [imageCache removeAllObjects];
}

+ (NSMutableArray *)getDecibelColours
{
    NSMutableArray *colourArray = [[NSMutableArray alloc] initWithCapacity:6];
    [colourArray addObject:[UIColor redColor]];
    [colourArray addObject:[UIColor blueColor]];
    [colourArray addObject:[UIColor greenColor]];
    [colourArray addObject:[UIColor orangeColor]];
    [colourArray addObject:[UIColor purpleColor]];
    [colourArray addObject:[UIColor grayColor]];
    return colourArray;
}

+ (CGSize)getImageSize:(NSString *)fileName
{
    //Return the dimensions of an image without loading it into memory.
    NSURL *imageFileURL = [NSURL fileURLWithPath:fileName];
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)imageFileURL, NULL);
    
    if (imageSource == NULL) {
        //Something has gone wrong. Return a zero size.
        return CGSizeMake(0, 0);
    }
    
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], (NSString *)kCGImageSourceShouldCache, nil];
    CFDictionaryRef imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, (__bridge CFDictionaryRef)options);
    if (imageProperties) {
        NSNumber *width = (NSNumber *)CFDictionaryGetValue(imageProperties, kCGImagePropertyPixelWidth);
        NSNumber *height = (NSNumber *)CFDictionaryGetValue(imageProperties, kCGImagePropertyPixelHeight);
        
        CFRelease(imageProperties);
        CFRelease(imageSource);
        return CGSizeMake([width intValue], [height intValue]);
    } else {
        CFRelease(imageSource);
        return CGSizeMake(0, 0);
    }
}

+ (UIImage *)defaultThumbnail:(NSString *)imageFile ofSize:(CGSize)size
{
    //Make image double resolution for retina screens.
    CGFloat screenScale = [[UIScreen mainScreen] scale];
    size = CGSizeMake(size.width * screenScale, size.height * screenScale);
    
    //Scale to fit our image within the size of the thumbnail, maintainting the aspect ratio.
    UIImage *image = [UIImage imageWithContentsOfFile:imageFile];
    CGFloat widthRatio = size.width / image.size.width;
    CGFloat heightRatio = size.height / image.size.height;
    CGFloat scaleFactor;
    if (widthRatio > heightRatio) {
        scaleFactor = heightRatio;
    } else {
        scaleFactor = widthRatio;
    }
    
    UIGraphicsBeginImageContext(size);
    CGFloat width = image.size.width * scaleFactor;
    CGFloat height = image.size.height * scaleFactor;
    //Centre our image.
    CGFloat x = (size.width - width) / 2.0;
    CGFloat y = (size.height - height) / 2.0;
    [image drawInRect:CGRectMake(x, y, width, height)];
    UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return thumbnail;
}

+ (NSString *)getAnnotationsDirectoryForScore:(Score *)score
{
    NSString *path;
    if (score.annotationsPathOverride != nil) {
        path = score.annotationsPathOverride;
    } else {
        path = [score.scorePath stringByAppendingPathComponent:@"Annotations"];
        path = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", score.composerFullText, score.scoreName]];
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]) {
        return path;
    } else {
        return nil;
    }
}

+ (UIImage *)rotateImage:(UIImage *)image byRadians:(CGFloat)radians
{
    //Only really set up to rotate at right angles.
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(image.size.height, image.size.width), NO, 1);
    CGContextRef currentContext = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(currentContext, image.size.height / 2, image.size.width / 2);
    CGContextRotateCTM(currentContext, radians);
    [image drawAtPoint:CGPointMake(-image.size.width / 2, -image.size.height / 2)];
    UIImage *rotated = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rotated;
}

@end

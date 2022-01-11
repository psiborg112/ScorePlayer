//
//  Spectrogram.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 22/05/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "Spectrogram.h"

@interface Spectrogram ()

- (Float32)getMaximumValue;
- (rgb)getColourForFloatValue:(CGFloat)value;

@end

@implementation Spectrogram {
    NSMutableArray *frequencyColumns;
    NSUInteger expectedDataLength;
    NSMutableDictionary *gradientColours;
    NSArray *gradientPoints;
}

@synthesize spectrogramImage, multiplier, sampleRate;

- (id)init
{
    self = [super init];
    frequencyColumns = [[NSMutableArray alloc] init];
    expectedDataLength = 0;
    sampleRate = 0;
    multiplier = 1;
    
    //Set up the initial gradient points. By default, use a gradient from black to white
    gradientColours = [[NSMutableDictionary alloc] init];
    [self resetGradientPoints];
    
    return self;
}

- (void)addDataColumn:(NSData *)frequencyColumn
{
    if (frequencyColumn.length % sizeof(Float32) != 0) {
        //We don't have an array of floats.
        return;
    }
    
    if (expectedDataLength == 0) {
        expectedDataLength = frequencyColumn.length;
    }
    
    if (frequencyColumn.length == expectedDataLength) {
        [frequencyColumns addObject:frequencyColumn];
    }
}

- (void)normalise
{
    multiplier = 1.0 / [self getMaximumValue];
}

- (CGFloat)getAverageValue
{
    if (expectedDataLength == 0) {
        return 0;
    }
    
    CGFloat total = 0;
    for (int i = 0; i < [frequencyColumns count]; i++) {
        Float32 *rawData = (Float32 *)[[frequencyColumns objectAtIndex:i] bytes];
        for (int j = 0; j < expectedDataLength / sizeof(Float32); j++) {
            total += rawData[j];
        }
    }
    return total / ([frequencyColumns count] * expectedDataLength / sizeof(Float32));
}

- (CGFloat)getPercentAboveThreshold:(CGFloat)threshold
{
    if (expectedDataLength == 0) {
        return 0;
    }
    
    NSInteger aboveCount = 0;
    
    for (int i = 0; i < [frequencyColumns count]; i++) {
        Float32 *rawData = (Float32 *)[[frequencyColumns objectAtIndex:i] bytes];
        for (int j = 0; j < expectedDataLength / sizeof(Float32); j++) {
            if (rawData[j] >= threshold) {
                aboveCount++;
            }
        }
    }
    
    return (CGFloat)aboveCount / ([frequencyColumns count] * expectedDataLength / sizeof(Float32));
}

- (void)generateImageWithCutoffFrequency:(NSUInteger)cutoff
{
    //Currently just render the data to a grayscale image. We should pretty this up later.
    //Work out how much of the data falls below the cutoff frequency. If the cutoff frequency is 0 or our
    //sample rate hasn't been defined then we should use all of the data.
    Float32 percentageKept;
    if (sampleRate == 0 || cutoff == 0) {
        percentageKept = 1;
    } else {
        percentageKept = (Float32)cutoff * 2 / sampleRate;
        if (percentageKept > 1) {
            percentageKept = 1;
        }
    }
    
    NSUInteger width = [frequencyColumns count];
    NSUInteger height = ceilf(percentageKept * expectedDataLength / sizeof(Float32));
    size_t bitsPerComponent = 8;
    size_t components = 4;
    size_t bytesPerPixel = bitsPerComponent * components / 8;
    size_t bytesPerRow = bytesPerPixel * width;
    
    //Firstly we need to allocate memory to create a 32bit RGBA bitmap. (By using a UInt8, we can more
    //easily address individual components.)
    uint8_t *pixels = malloc(width * height * bytesPerPixel);
    NSUInteger offset;
    
    //Then calculate the values for our pixels from the frequency data we've been given.
    for (int i = 0; i < width; i ++) {
        //Only use the bottom quarter of the image at the moment. (Up to around 5.5kHz)
        for (int j = 0; j < height; j++) {
            offset = (bytesPerRow * j) + (bytesPerPixel * i);
            Float32 *rawData = (Float32 *)[[frequencyColumns objectAtIndex:i] bytes];
            //Since our image coordinates go from top to bottom and our data goes from bottom to top
            //we need to read backwards through the array.
            Float32 rawValue = multiplier * rawData[height - 1 - j];
            rgb colour = [self getColourForFloatValue:rawValue];
            pixels[offset] = colour.r;
            pixels[offset + 1] = colour.g;
            pixels[offset + 2] = colour.b;
            //Make sure our image is opaque.
            pixels[offset + 3] = 255;
        }
    }
    
    //Now create our bitmap context and convert it into a UIImage.
    CGColorSpaceRef colourSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmapContext = CGBitmapContextCreate(pixels, width, height, bitsPerComponent, bytesPerRow, colourSpace, kCGImageAlphaPremultipliedLast);
    CGImageRef imageRef = CGBitmapContextCreateImage(bitmapContext);
    //At the moment ignore any retina screen scaling. This way the bitmap will appear the same size on all devices.
    //(If we need to change that behaviour then use the following commented out block of code.)
    spectrogramImage = [UIImage imageWithCGImage:imageRef];
    
    /*if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
        spectrogramImage = [UIImage imageWithCGImage:imageRef scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
    } else {
        spectrogramImage = [UIImage imageWithCGImage:imageRef];
    }*/
    
    //Free everything we're done with.
    free(pixels);
    CGImageRelease(imageRef);
    CGContextRelease(bitmapContext);
    CGColorSpaceRelease(colourSpace);
}

- (void)addGradientPointForValue:(CGFloat)value withRed:(uint8_t)r green:(uint8_t)g blue:(uint8_t)b
{
    //Come on! Let's respect ranges people!
    if (value > 1 || value < 0) {
        return;
    }
    
    rgb colour = {r, g, b};
    [gradientColours setObject:[NSValue valueWithBytes:&colour objCType:@encode(rgb)] forKey:[NSNumber numberWithFloat:value]];
    gradientPoints = [[gradientColours allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (void)resetGradientPoints
{
    [gradientColours removeAllObjects];
    
    rgb zeroColour = {0, 0, 0};
    rgb fullColour = {255, 255, 255};
    
    [gradientColours setObject:[NSValue valueWithBytes:&zeroColour objCType:@encode(rgb)] forKey:[NSNumber numberWithFloat:0]];
    [gradientColours setObject:[NSValue valueWithBytes:&fullColour objCType:@encode(rgb)] forKey:[NSNumber numberWithFloat:1]];
    
    gradientPoints = [[gradientColours allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (Float32)getMaximumValue
{
    Float32 maximum = 0;
    for (int i = 0; i < [frequencyColumns count]; i++) {
        Float32 *rawData = (Float32 *)[[frequencyColumns objectAtIndex:i] bytes];
        for (int j = 0; j < expectedDataLength / sizeof(Float32); j++) {
            if (rawData[j] > maximum) {
                maximum = rawData[j];
            }
        }
    }
    return maximum;
}

- (rgb)getColourForFloatValue:(CGFloat)value
{
    if (value > 1) {
        value = 1;
    }
    
    //Find which section of the gradient map we're in.
    NSUInteger index = [gradientPoints count] - 2;
    while ((index > 0) && (value < [[gradientPoints objectAtIndex:index] floatValue])) {
        index --;
    }
    
    rgb colour1, colour2;
    CGFloat value1, value2;
    [[gradientColours objectForKey:[gradientPoints objectAtIndex:index]] getValue:&colour1];
    [[gradientColours objectForKey:[gradientPoints objectAtIndex:index + 1]] getValue:&colour2];
    value1 = [[gradientPoints objectAtIndex:index] floatValue];
    value2 = [[gradientPoints objectAtIndex:index + 1] floatValue];
    CGFloat location = (value - value1) / (value2 - value1);
    
    //Work out the necessary colour using a linear gradient.
    rgb colour;
    colour.r = colour1.r + ((colour2.r - colour1.r) * location);
    colour.g = colour1.g + ((colour2.g - colour1.g) * location);
    colour.b = colour1.b + ((colour2.b - colour1.b) * location);
    return colour;
}

@end

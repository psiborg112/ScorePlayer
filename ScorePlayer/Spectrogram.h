//
//  Spectrogram.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 22/05/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} rgb;

@interface Spectrogram : NSObject

@property (nonatomic, strong) UIImage *spectrogramImage;
@property (nonatomic) CGFloat multiplier;
@property (nonatomic) Float64 sampleRate;

- (id)init;
- (void)addDataColumn:(NSData *)frequencyColumn;
- (void)normalise;
- (CGFloat)getAverageValue;
- (CGFloat)getPercentAboveThreshold:(CGFloat)threshold;
- (void)generateImageWithCutoffFrequency:(NSUInteger)cutoff;
- (void)addGradientPointForValue:(CGFloat)value withRed:(uint8_t)r green:(uint8_t)g blue:(uint8_t)b;
- (void)resetGradientPoints;

@end

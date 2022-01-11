//
//  AnnotationLayer.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 27/2/20.
//  Copyright (c) 2020 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

@interface AnnotationLayer : CALayer {
    UIBezierPath *eraserPath;
    UIImage *flattenedImage;
    
    CGFloat eraserWidth;
}

@property (nonatomic, strong) UIBezierPath *eraserPath;
@property (nonatomic, strong) UIImage *flattenedImage;
@property (nonatomic) CGFloat eraserWidth;

@end

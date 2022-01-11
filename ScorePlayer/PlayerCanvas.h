//
//  PlayerCanvas.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 27/2/20.
//  Copyright (c) 2020 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol AnnotationDelegate <NSObject>
@required
- (CGRect)canvasScaledFrame;
- (void)saveAnnotation:(UIImage *)image;
- (void)hideSavedAnnotations:(BOOL)hide;

@end

@interface PlayerCanvas : UIView {
    BOOL annotating;
    BOOL erasing;
    BOOL changed;
    
    __weak id<AnnotationDelegate> delegate;
}

@property (nonatomic, strong) UIImage *currentImage;
@property (nonatomic, strong) CALayer *currentMask;
@property (nonatomic) BOOL annotating;
@property (nonatomic) BOOL erasing;
@property (nonatomic) BOOL changed;
@property (nonatomic, weak) id<AnnotationDelegate> delegate;

- (void)save;

@end


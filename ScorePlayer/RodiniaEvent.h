//
//  RodiniaEvent.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 10/09/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    kNormal = 0,
    kNoise = 1,
    kPoint = 2
} Articulation;

@interface RodiniaEvent : NSObject {
    Articulation articulation;
    NSInteger glissAmount;
    BOOL ghost;
    BOOL tremolo;
    NSInteger length;
    
    CALayer *layer;
    UIColor *colour;
    NSInteger rotation;
    
    CGPoint streamPosition;
}

@property (nonatomic) Articulation articulation;
@property (nonatomic) NSInteger glissAmount;
@property (nonatomic) BOOL ghost;
@property (nonatomic) BOOL tremolo;
@property (nonatomic) NSInteger length;
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic, strong) UIColor *colour;
@property (nonatomic) NSInteger rotation;
@property (nonatomic) CGPoint streamPosition;

- (id)initWithArticulation:(Articulation)style glissAmount:(NSInteger)gliss ghost:(BOOL)ghosted tremolo:(BOOL)trem length:(NSInteger)len;
- (id)initAsDuplicateOfEvent:(RodiniaEvent *)event;

@end

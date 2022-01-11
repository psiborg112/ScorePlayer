//
//  CageEvent.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 18/07/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

static const NSInteger CAGE_FRAMERATE = 30;

@interface CageEvent : NSObject {
    NSInteger number;
    NSInteger duration;
    NSInteger timbre;
    NSInteger dynamics;
    
    CALayer *layer;
}

@property (nonatomic) NSInteger number;
@property (nonatomic) NSInteger duration;
@property (nonatomic) NSInteger timbre;
@property (nonatomic) NSInteger dynamics;
@property (nonatomic, strong) CALayer *layer;

+ (NSInteger)getFrameRate;

- (id)initWithNumberOfEvents:(NSInteger)events duration:(NSInteger)length timbre:(NSInteger)quality dynamics:(NSInteger)volume;

@end

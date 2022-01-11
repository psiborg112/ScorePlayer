//
//  Rodinia.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 12/02/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"

static const NSInteger RODINIA_FRAMERATE = 12;
static const NSInteger RODINIA_SCROLLRATE = 2;

typedef enum {
    kController = 0,
    kPlayer = 1
} ViewMode;

typedef struct {
    CGPoint location;
    CGFloat heading;
} StreamState;

@interface Rodinia : NSObject <RendererDelegate> {
    BOOL isMaster;
}

@property (nonatomic) BOOL isMaster;

@end

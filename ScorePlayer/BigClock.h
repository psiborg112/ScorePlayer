//
//  BigClock.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 25/04/13.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"

@interface BigClock : NSObject <RendererDelegate> {
    BOOL isMaster;
}

@property (nonatomic) BOOL isMaster;

@end

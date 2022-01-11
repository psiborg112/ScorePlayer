//
//  FlashCards.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 7/03/2015.
//  Copyright (c) 2015 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"

typedef enum {
    kTopLevel = 0,
    kTimer = 1,
    kDynamics = 2,
    kDuo = 3,
    kOrder = 4
} xmlLocation;

typedef enum {
    kGraphical = 0,
    kNumerical = 1
} TimerStyle;

@interface FlashCards : NSObject <NSXMLParserDelegate, RendererDelegate> {
    BOOL isMaster;
    BOOL detached;
}

@property (nonatomic) BOOL isMaster;
@property (nonatomic) BOOL detached;

@end

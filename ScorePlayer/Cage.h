//
//  Cage.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 15/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"
#import "CageParser.h"

@interface Cage : NSObject <RendererDelegate, RendererMessaging, CageParserDelegate> {
    BOOL isMaster;
}

@property (nonatomic) BOOL isMaster;
@property (nonatomic) PlayerState playerState;

@end

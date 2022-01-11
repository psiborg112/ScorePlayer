//
//  Radar.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 1/9/17.
//  Copyright (c) 2017 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"

static const NSInteger RADAR_FRAMERATE = 25;

@interface Radar : NSObject <NSXMLParserDelegate, RendererDelegate> {
    BOOL isMaster;
}

@property (nonatomic) BOOL isMaster;

@end

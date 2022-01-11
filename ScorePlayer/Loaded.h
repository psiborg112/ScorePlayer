//
//  Loaded.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 8/04/2015.
//  Copyright (c) 2015 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"

typedef enum {
    kTopLevel = 0,
    kPanel = 1,
    kPartNames = 2
} xmlLocation;

@interface Loaded : NSObject <RendererDelegate, NSXMLParserDelegate> {
    BOOL isMaster;
}

@property (nonatomic) BOOL isMaster;

@end

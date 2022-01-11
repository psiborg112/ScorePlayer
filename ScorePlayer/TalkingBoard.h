//
//  TalkingBoard.h
//  ScorePlayer
//
//  Created by Aaron Wyatt and Stuart James on 14/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"

typedef enum {
    kTopLevel = 0,
    kPlanchette = 1
} xmlLocation;

@interface TalkingBoard : NSObject <RendererDelegate, NSXMLParserDelegate> {
    BOOL isMaster;
}

@property (nonatomic) BOOL isMaster;

@end

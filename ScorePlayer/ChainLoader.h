//
//  ChainLoader.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 30/08/2015.
//  Copyright (c) 2015 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"
#import "OpusParser.h"

@interface ChainLoader : NSObject <NSXMLParserDelegate, OpusParserDelegate, RendererDelegate> {
    BOOL isMaster;
}

@property (nonatomic) BOOL isMaster;

@end
 

//
//  SlideShow.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/08/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"

@interface SlideShow : NSObject <NSXMLParserDelegate, RendererDelegate> {
    BOOL isMaster;
}

@property (nonatomic) BOOL isMaster;

@end

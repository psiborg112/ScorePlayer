//
//  UBahn.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 20/07/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"

typedef enum {
    kTopLevel = 0,
    kPath = 1,
    kTrains = 2,
    kMosaic = 3,
    kImage = 4
} xmlLocation;

typedef enum {
    kMapView = 0,
    kTrainView = 1
} MapMode;

@interface UBahn : NSObject <RendererDelegate, NSXMLParserDelegate> {
    BOOL isMaster;
}

@property (nonatomic) BOOL isMaster;

@end

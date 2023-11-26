//
//  ScrollScore.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 13/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"

static const CGFloat MAX_SCROLLER_FRAMERATE = 25;

typedef enum {
    kTopLevel = 0,
    kScrollerMode = 1,
    kTiles = 2,
    kReadLine = 3,
    kModule = 4
} xmlLocation;

typedef enum {
    kDefaultLine = 0,
    kCustomColour = 1,
    kCustomImage = 2
} ReadLineStyle;

typedef enum {
    kHorizontal = 0,
    kUp = 1,
    kDown = 2
} ScrollOrientation;

typedef enum {
    kAlignLeftEdge = 0,
    kAlignCentre = 1,
    kAlignRightEdge = 2
} ReadLineAlignment;

@protocol ScrollerDelegate <NSObject>

@required
@property (nonatomic) CGFloat height;
@property (nonatomic, readonly) CGFloat width;
@property (nonatomic) CGFloat x;
@property (nonatomic) CGFloat y;
@property (nonatomic, readonly) NSInteger numberOfTiles;
@property (nonatomic, strong) CALayer *background;
@property (nonatomic) BOOL loadOccurred;

+ (BOOL)allowsParts;
+ (BOOL)requiresData;
+ (NSArray *)requiredOptions;

- (id)initWithTiles:(NSInteger)tiles options:(NSMutableDictionary *)options;
- (void)changePart:(NSString *)firstImageName;
- (CGSize)originalSizeOfImages:(NSString *)firstImageName;
- (CGSize)originalSize;

@optional
@property (nonatomic, strong) NSString *annotationsDirectory;
@property (nonatomic) CGSize canvasSize;
@property (nonatomic) ScrollOrientation orientation;

+ (NSArray *)arrayTags;
+ (NSArray *)dictionaryTags;

- (OSCMessage *)getData;
- (void)setData:(OSCMessage *)data;
- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished;
- (UIImage *)currentAnnotationImage;
- (CALayer *)currentAnnotationMask;
- (void)saveCurrentAnnotation:(UIImage *)image;
- (void)hideSavedAnnotations:(BOOL)hide;

@end

@interface ScrollScore : NSObject <NSXMLParserDelegate, RendererDelegate> {
    BOOL isMaster;
    BOOL detached;
}

@property (nonatomic) BOOL isMaster;
@property (nonatomic) BOOL detached;
@property (nonatomic) BOOL hideUIElements;

@end

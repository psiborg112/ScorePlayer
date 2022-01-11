//
//  Canvas.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 1/11/16.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"

static const NSInteger CANVAS_NAME_OFFSET = 0;
static const NSInteger CANVAS_TYPE_OFFSET = 1;
static const NSInteger CANVAS_PARENT_OFFSET = 2;
static const NSInteger CANVAS_PART_OFFSET = 3;
static const NSInteger CANVAS_X_OFFSET = 4;
static const NSInteger CANVAS_Y_OFFSET = 5;
static const NSInteger CANVAS_WIDTH_OFFSET = 6;
static const NSInteger CANVAS_HEIGHT_OFFSET = 7;
static const NSInteger CANVAS_COLOUR_OFFSET = 8;
static const NSInteger CANVAS_OPACITY_OFFSET = 9;
static const NSInteger CANVAS_PROPERTIES_OFFSET = 10;

static const NSInteger CANVAS_GLOBAL_COUNT = 2;

@protocol CanvasObject <NSObject>

@required
//The layer that serves as the background of the object and that gets repositioned on the canvas.
@property (nonatomic, strong, readonly) CALayer *containerLayer;
//The layer that sublayers are added to. (This may or may not be the same as the containerLayer.)
@property (nonatomic, strong, readonly) CALayer *objectLayer;
@property (nonatomic) NSInteger partNumber;
@property (nonatomic, strong) NSString *parentLayer;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGPoint position;
@property (nonatomic) CGSize size;
@property (nonatomic, strong) NSString *colour;
@property (nonatomic) CGFloat opacity;
- (id)initWithScorePath:(NSString *)path;

@optional

//CanvasLayer and CanvasScroller
@property (nonatomic, strong) NSString *imageFile;
- (void)loadImage:(NSString *)imageFile autoSizing:(BOOL)autosize;
- (void)clearImage;

//CanvasText
@property (nonatomic, strong) NSString *text;
@property (nonatomic, strong) NSString *font;
@property (nonatomic) CGFloat fontSize;

//CanvasGlyph
@property (nonatomic, strong) NSString *glyphType;
- (BOOL)setGlyph:(NSString *)glyph;

//CanvasScroller
@property (nonatomic) NSInteger scrollerWidth;
@property (nonatomic) NSInteger scrollerPosition;
@property (nonatomic) CGFloat scrollerSpeed;
@property (nonatomic, readonly) BOOL isRunning;
- (void)start;
- (void)stop;

//CanvasStave
@property (nonatomic) NSInteger lineWidth;
@property (nonatomic) NSString *clefCollection;
@property (nonatomic) NSString *noteCollection;
- (NSString *)setClef:(NSString *)clef atPosition:(NSInteger)position;
- (NSString *)removeClefAtPosition:(NSInteger)position;
- (NSString *)addNote:(NSString *)noteString atPosition:(NSInteger)position ofDuration:(NSInteger)duration;
- (NSString *)addNotehead:(NSString *)noteString atPosition:(NSInteger)position filled:(BOOL)filled;
- (NSString *)removeNote:(NSString *)noteString atPosition:(NSInteger)position;
- (void)clear;

//CanvasLine
@property (nonatomic) CGPoint startPoint;
@property (nonatomic) CGPoint endPoint;
@property (nonatomic) NSInteger width;
@property (nonatomic, strong) NSString *points;

@end

@interface Canvas : NSObject <RendererDelegate, NSXMLParserDelegate> {
    BOOL isMaster;
}

@property (nonatomic) BOOL isMaster;

+ (void)colourString:(NSString *)colourString toArray:(int *)colour;

@end

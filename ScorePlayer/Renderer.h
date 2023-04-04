//
//  Renderer.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 2/07/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Score;
@class OSCMessage;

typedef enum {
    kStopped = 0,
    kPlaying = 1,
    kPaused = 2
} PlayerState;

typedef enum {
    kBasic = 0,
    kVariations = 1 << 0,
    kNonZeroDuration = 1 << 1,
    kPositiveDuration = 1 << 2,
    kFileName = 1 << 3,
    kParts = 1 << 4,
    kPrefsFile = 1 << 5,
    kUsesIdentifier = 1 << 6,
    kUsesScaledCanvas = 1 << 7
} RendererFeatures;

static const NSInteger LOWER_PADDING = 52;

//Used by the player core to communicate back to the view controller
@protocol PlayerUIDelegate <NSObject>

@required
@property (nonatomic, readonly) BOOL alertShown;
- (void)playerPlayWithAudio:(BOOL)startAudio;
- (int)playerReset;
- (void)playerSeekTo:(CGFloat)location endReachedWhilePlaying:(BOOL)ended;
- (void)playerSeekFinishedAfterResync:(BOOL)sync;
- (void)playerStop;
- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished;
- (void)closeScore;
- (void)loadScore:(Score *)score;
- (void)networkErrorWithMessage:(NSString *)message toStandAlone:(BOOL)killNetworking;
- (void)errorWithTitle:(NSString *)title message:(NSString *)message;
- (void)awaitingNetwork:(BOOL)waiting;
- (void)allowAnnotation:(BOOL)allowed;
- (void)setInitialState:(PlayerState)state fromNetwork:(BOOL)connected;

@optional
- (void)showCueLight:(UIColor *)colour;

@end

//Used by rendering modules to communicate back to the player
@protocol RendererUI <NSObject>

@required
//Most of these properties are clock related
@property (nonatomic, readonly) NSString *playerID;
@property (nonatomic, readonly) PlayerState playerState;
@property (nonatomic) BOOL canAnnotate;
@property (nonatomic) CGFloat clockDuration;
@property (nonatomic, readonly) int clockProgress;
@property (nonatomic, readonly) CGFloat clockLocation;
@property (nonatomic) CGFloat sliderMinimumValue;
@property (nonatomic) BOOL clockEnabled;
@property (nonatomic) BOOL splitSecondMode;
@property (nonatomic) BOOL clockVisible;
@property (nonatomic) BOOL allowClockChange;
@property (nonatomic) BOOL allowClockVisibilityChange;
@property (nonatomic) BOOL allowSyncToTick;
@property (nonatomic) BOOL resetViewOnFinish;
@property (nonatomic, readonly) NSInteger statusHeight;
@property (nonatomic, readonly) NSInteger navigationHeight;
@property (nonatomic, readonly) CGFloat canvasScale;
@property (nonatomic, readonly) CGFloat cueLightScale;
- (void)setStaticScoreUI;
- (void)setDynamicScoreUI;
- (void)hideNavigationBar;
- (void)badPreferencesFile:(NSString *)errorMessage;
- (void)stopClockWithStateUpdate:(BOOL)updateState;
- (void)resetClockWithUIUpdate:(BOOL)updateUI;
- (void)setPlayerBackgroundColour:(UIColor *)colour;
- (void)setMarginColour:(UIColor *)colour;
- (void)partChangedToPart:(NSUInteger)part;

@end

@protocol RendererMessaging <NSObject>

- (BOOL)sendData:(OSCMessage *)message;

@end

//Rendering modules for score types must conform to this protocol
@protocol RendererDelegate <NSObject>

@required
@property (nonatomic) BOOL isMaster;
+ (RendererFeatures)getRendererRequirements;
- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel;
- (void)reset;

@optional
@property (nonatomic) BOOL detached;
@property (nonatomic) BOOL hideUIElements;
+ (UIImage *)generateThumbnailForScore:(Score *)score ofSize:(CGSize)size;
- (void)close;
- (void)reset:(CGFloat *)locationOffset;
- (void)play;
- (void)stop;
- (void)seek:(CGFloat)location;
- (void)changeDuration:(CGFloat)duration;
- (CGFloat)changeDuration:(CGFloat)duration currentLocation:(CGFloat *)location;
- (void)regenerate;
- (void)rotate;
- (void)receiveMessage:(OSCMessage *)message;
- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished;
- (void)attemptSync;
- (UIImage *)currentAnnotationImage;
- (CALayer *)currentAnnotationMask;
- (void)saveCurrentAnnotation:(UIImage *)image;
- (void)hideSavedAnnotations:(BOOL)hide;

- (void)swipeUp;
- (void)swipeDown;
- (void)swipeLeft;
- (void)swipeRight;
- (void)tapAt:(CGPoint)location;
- (void)panAt:(CGPoint)location;

- (OSCMessage *)getOptions;
- (void)setOptions:(OSCMessage *)newOptions;

@end

//Implemented by the player core. This allows the options view to send settings
//back to the renderer.
@protocol RendererOptions <NSObject>

@required
- (OSCMessage *)getOptions;
- (void)setOptions:(OSCMessage *)newOptions;

@end

//Protocol implemented by the custom options view for a given renderer
@protocol RendererOptionsView <NSObject>

@required
- (BOOL)optionsChanged;
- (OSCMessage *)getOptions;
- (void)setOptions:(OSCMessage *)newOptions;

@end

@interface Renderer : NSObject

//Image caching functions. (Works around UIImage only caching files in the app bundle directory.)
+ (UIImage *)cachedImage:(NSString *)fileName;
+ (void)removeDirectoryFromCache:(NSString *)path;
+ (void)clearCache;

+ (NSMutableArray *)getDecibelColours;
+ (CGSize)getImageSize:(NSString *)fileName;
+ (UIImage *)defaultThumbnail:(NSString *)imageFile ofSize:(CGSize)size;
+ (NSString *)getAnnotationsDirectoryForScore:(Score *)score;
+ (UIImage *)rotateImage:(UIImage *)image byRadians:(CGFloat)radians;

@end

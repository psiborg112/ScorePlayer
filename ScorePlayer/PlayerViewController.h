//
//  PlayerViewController.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Renderer.h"
#import "PlayerCanvas.h"

@class Score;

//Be all the delegates! (But fewer now that we have the player core.)
@interface PlayerViewController : UIViewController <UITextFieldDelegate, UIGestureRecognizerDelegate, PlayerUIDelegate, RendererUI, AnnotationDelegate> {
    Score *initialScore;
    NSArray *availableScores;
    NSString *serviceName;
    BOOL projectionMode;
    
    BOOL clockVisible;
    BOOL allowClockVisibilityChange;
    BOOL resetViewOnFinish;
    NSInteger statusHeight;
    NSInteger navigationHeight;
    CGFloat canvasScale;
    CGFloat cueLightScale;
}

@property (nonatomic, strong) IBOutlet UIBarButtonItem *networkButton;
@property (nonatomic, strong) IBOutlet UIButton *playButton;
@property (nonatomic, strong) IBOutlet UIButton *resetButton;
@property (nonatomic, strong) IBOutlet UISlider *locationSlider;
@property (nonatomic, strong) IBOutlet UILabel *clockDisplay;
@property (nonatomic, strong) IBOutlet UIButton *instructionsButton;
@property (nonatomic, strong) IBOutlet UIButton *optionsButton;
@property (nonatomic, strong) IBOutlet UIButton *annotateButton;
@property (nonatomic, strong) IBOutlet UISegmentedControl *annotationControl;
@property (nonatomic, strong) IBOutlet PlayerCanvas *canvasView;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *connectingIndicator;
@property (nonatomic, strong) IBOutlet UILabel *titleLabel;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *resetLeadingConstraint;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *optionsTrailingConstraint;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *annotateFirstTrailingConstraint;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *annotateSecondTrailingConstraint;

@property (nonatomic, strong) Score *initialScore;
@property (nonatomic, strong) NSArray *availableScores;
@property (nonatomic, strong) NSString *serviceName;
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, readonly) PlayerState playerState;
@property (nonatomic) BOOL projectionMode;

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
@property (nonatomic, readonly) CGFloat marginSize;

- (IBAction)play;
- (IBAction)reset;
- (IBAction)seek;
- (IBAction)seekFinished;
- (IBAction)viewInstructions;
- (IBAction)viewOptions;
- (IBAction)annotate;
- (IBAction)selectAnnotationType;
- (IBAction)viewNetworkStatus;
- (IBAction)hideNavigation;
- (IBAction)prepareForUnwind:(UIStoryboardSegue *)segue;

- (void)playerShutdown;

@end

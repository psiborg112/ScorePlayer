//
//  PlayerViewController.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "PlayerViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "PlayerCore.h"
#import "AudioPlayerProtocol.h"
#import "OSCMessage.h"
#import "Score.h"
#import "Network.h"
#import "InstructionsViewController.h"
#import "OptionsViewController.h"

@interface PlayerViewController ()

- (void)hideNavigationBar:(BOOL)hidden;
- (void)disableControls:(BOOL)disabled;
- (void)hideRemainingUI;
- (void)scaleCanvas:(CGSize)screenSize;
- (void)layoutUpperButtons;

- (void)editDuration;
- (void)swipeUp;
- (void)swipeDown;
- (void)swipeLeft;
- (void)swipeRight;
- (void)tap;
- (void)pan;
- (void)enableGestures:(BOOL)enabled;

- (void)updateClockDisplay;

@end

@implementation PlayerViewController {
    PlayerCore *playerCore;
    
    CALayer *canvas;
    CGPoint canvasOffset;
    BOOL useScaledCanvas;
    //CALayer *statusBarBackground;
    CALayer *dimmer;
    CALayer *cueLight;
    UIColor *clockColour;
    CGFloat savedDuration;
    
    BOOL hasInstructions;
    BOOL hasOptions;
    BOOL canAnnotate;
    BOOL checkAnnotation;
    id<AudioPlayer> audioPlayer;
    NSInteger audioSeek;
    BOOL resetViewOnSeek;
    BOOL hideEntireUI;
    BOOL hideStatusBar;
    UITapGestureRecognizer *navigationTap;
    
    BOOL alertShown;
    UITapGestureRecognizer *tap;
    UIPanGestureRecognizer *pan;
    NSMutableArray *gestureRecognizers;
    
    BOOL shutdownPlayer;

    BOOL controlsDisabled;
    BOOL controlsPreviousState[3];
    
    BOOL rendererAcceptsTick;
    
    id<RendererDelegate> rendererDelegate;
    
    BOOL pingTest;
    BOOL annotating;
    NSLock *annotationLock;
}

@synthesize networkButton, playButton, resetButton, locationSlider, clockDisplay, instructionsButton, optionsButton, annotateButton, annotationControl, canvasView, connectingIndicator, titleLabel, resetLeadingConstraint, optionsTrailingConstraint, annotateFirstTrailingConstraint, annotateSecondTrailingConstraint, initialScore, availableScores, serviceName, identifier, playerState, projectionMode, allowClockVisibilityChange, resetViewOnFinish, statusHeight, navigationHeight, canvasScale, cueLightScale, alertShown;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
	// Do any additional setup after loading the view, typically from a nib.
    statusHeight = [UIApplication sharedApplication].statusBarFrame.size.height;
    navigationHeight = self.navigationController.navigationBar.frame.size.height;
    
    //TODO: For testing only. Remove later.
    pingTest = NO;
    
    self.navigationItem.rightBarButtonItem.enabled = NO;
    hideEntireUI = NO;
    hideStatusBar = NO;
    
    canvasScale = 1;
    canvasOffset = CGPointZero;
    
    //Stop the device from dimming the screen or sleeping
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    clockDisplay.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular];
    
    //Set up our canvas
    canvas = [CALayer layer];
    canvas.anchorPoint = CGPointMake(0, 0);
    canvas.masksToBounds = NO;
    [canvasView.layer addSublayer:canvas];
    useScaledCanvas = YES;
    annotating = NO;
    annotationLock = [[NSLock alloc] init];
    
    //Set up our cue light and dimmer layer
    cueLight = [CALayer layer];
    dimmer = [CALayer layer];
    dimmer.backgroundColor = [UIColor blackColor].CGColor;
    dimmer.opacity = 0.4;
    CGFloat longSide = MAX(self.view.frame.size.width, self.view.frame.size.height);
    dimmer.frame = CGRectMake(-20, -20, longSide + 40, longSide + 40);
    
    //Set up status bar background
    /*statusBarBackground = [CALayer layer];
     statusBarBackground.backgroundColor = [UIColor colorWithRed:(244.0/255.0) green:(244.0/255.0) blue:(244.0/255) alpha:0.85].CGColor;
     statusBarBackground.frame = CGRectMake(0, 0, 1024, STATUS_HEIGHT);*/
    
    //Hide the various UI elements if in projection mode.
    if (projectionMode) {
        playButton.hidden = YES;
        resetButton.hidden = YES;
        self.clockVisible = NO;
        /*if (self.navigationItem.titleView != nil) {
            navigationTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideRemainingUI)];
            self.navigationItem.titleView.userInteractionEnabled = YES;
            [self.navigationItem.titleView addGestureRecognizer:navigationTap];
        }*/
    }
    
    alertShown = NO;
    
    //Allow the clock display to accept touch events to edit the score duration
    gestureRecognizers = [[NSMutableArray alloc] init];
    UITapGestureRecognizer *changeDuration = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(editDuration)];
    [clockDisplay addGestureRecognizer:changeDuration];
    
    //Add swipe gesture recognizers for the renderers
    UISwipeGestureRecognizer *swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeUp)];
    UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDown)];
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
    tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)];
    pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan)];
    pan.delegate = self;
    swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
    swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [canvasView addGestureRecognizer:swipeUp];
    [canvasView addGestureRecognizer:swipeDown];
    [canvasView addGestureRecognizer:swipeLeft];
    [canvasView addGestureRecognizer:swipeRight];
    [canvasView addGestureRecognizer:tap];
    [canvasView addGestureRecognizer:pan];
    
    [gestureRecognizers addObject:swipeUp];
    [gestureRecognizers addObject:swipeDown];
    [gestureRecognizers addObject:swipeLeft];
    [gestureRecognizers addObject:swipeRight];
    [gestureRecognizers addObject:tap];
    [gestureRecognizers addObject:pan];
    
    //Disable the play button until we're in a usable state.
    playButton.enabled = NO;
    
    //Create our player core and load our score
    playerCore = [[PlayerCore alloc] initWithScore:initialScore delegate:self];
    [playerCore loadScore:initialScore];

    if (![playerCore initializeServerWithServiceName:serviceName identifier:identifier]) {
        //Couldn't start the server
        [self networkErrorWithMessage:@"Unable to create server. Falling back to stand alone player." toStandAlone:YES];
    } else {
        self.navigationItem.rightBarButtonItem.enabled = YES;
        
        //If we have a list of available scores, register them with the server.
        if (availableScores != nil && [availableScores count] > 0) {
            [playerCore registerScoreList:availableScores];
        }
    }
    playButton.enabled = YES;
    controlsDisabled = NO;
    resetViewOnSeek = NO;
    
    canvasView.delegate = self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    canvas.opacity = 1;
    
    //Disable pop to score selection screen via swipe gesture (currently it detects swipes in a region that
    //overlaps with that of our location scroller.)
    [[self navigationController] interactivePopGestureRecognizer].enabled = NO;
    
    //Scale our canvas as needed.
    [self scaleCanvas:self.view.frame.size];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    //Check to see if we're disappearing because we're checking the network status
    //or because we're changing score. (Do this by looking at the navigationController stack).
    //This appears to be redundant now, but keep for safety.
    NSArray *viewControllers = self.navigationController.viewControllers;
    if (viewControllers.count > 1 && [viewControllers objectAtIndex:viewControllers.count-2] == self) {
        // View is disappearing because a new view controller was pushed onto the stack
        shutdownPlayer = NO;
    } else if ([viewControllers indexOfObjectIdenticalTo:self] == NSNotFound) {
        //We're moving back to the score selection window. Shut down the player.
        if (annotating && canvasView.changed) {
            //Save our current annotations if we haven't already.
            [canvasView save];
        }
        canvas.opacity = 0;
        shutdownPlayer = YES;
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    //If our view is disappearing because our application is moving to the background then the
    //necessary code has already been called. (Nothing else to do here.)
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
        return;
    } else {
        if (shutdownPlayer) {
            [self playerShutdown];
        }
    }
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if (@available(iOS 13.0, *)) {
        [segue.destinationViewController setModalInPresentation:YES];
    }
    if ([segue.identifier isEqualToString:@"toNetworkStatus"] && [segue.destinationViewController conformsToProtocol:@protocol(NetworkStatus)]) {
        //This is handled by the player core since it has all of the networking details.
        [playerCore prepareNetworkStatusView:segue.destinationViewController];
    } else if ([segue.identifier isEqualToString:@"toInstructions"]) {
        ((InstructionsViewController *)segue.destinationViewController).instructionsFile = [playerCore.currentScore.scorePath stringByAppendingPathComponent:playerCore.currentScore.instructions];
    } else if ([segue.identifier isEqualToString:@"toOptions"]) {
        ((OptionsViewController *)segue.destinationViewController).rendererOptionsDelegate = playerCore;
        ((OptionsViewController *)segue.destinationViewController).className = [playerCore.currentScore.scoreType stringByAppendingString:@"Options"];
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    //If we're annotating, save what we're currently doing.
    if (annotating && canvasView.changed) {
        [canvasView save];
    }
    
    //Set the canvas size to be full screen.
    //It is assumed that the navigation bar will be hidden for playback.
    //(This currently doesn't happen with static scores, so they need to compensate for that
    //in their rendering calculations.)
    
    [self scaleCanvas:size];
    
    //Send notification of the canvas size change to any score renderers that
    //might require it.
    if ([rendererDelegate respondsToSelector:@selector(rotate)]) {
        [rendererDelegate rotate];
    }
    
    if (annotating) {
        canvasView.currentImage = [rendererDelegate currentAnnotationImage];
        if ([rendererDelegate respondsToSelector:@selector(currentAnnotationMask)]) {
            canvasView.currentMask = [rendererDelegate currentAnnotationMask];
        }
    }
    
    //Try to maintain synch with the network tick if we're not the master player
    [playerCore attemptSync];
}

- (BOOL)prefersStatusBarHidden
{
    return hideStatusBar;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
    return UIRectEdgeBottom;
}

- (IBAction)play
{
    if (playerState == kPlaying) {
        [playerCore pause];
    } else {
        [playerCore play];
    }
}

- (IBAction)reset
{
    [playerCore reset];
}

- (IBAction)seek
{
    if (!annotating) {
        [playerCore seekTo:locationSlider.value];
    } else {
        //Check if we have changes to save from our editing layer before moving.
        if (canvasView.changed) {
            //Save our current annotations.
            [canvasView save];
        }
        
        CGFloat location = roundf(locationSlider.value * savedDuration) / savedDuration;
        locationSlider.value = location;
        [rendererDelegate seek:location];
        [self updateClockDisplay];
    }
}

- (IBAction)seekFinished
{
    if (!annotating) {
        [playerCore seekFinished];
    } else {
        canvasView.currentImage = [rendererDelegate currentAnnotationImage];
        if ([rendererDelegate respondsToSelector:@selector(currentAnnotationMask)]) {
            canvasView.currentMask = [rendererDelegate currentAnnotationMask];
        }
    }
}

- (IBAction)viewInstructions
{
    [self performSegueWithIdentifier:@"toInstructions" sender:self];
}

- (IBAction)viewOptions {
    if (!hasOptions) {
        //We shouldn't be here
        return;
    }
    [self performSegueWithIdentifier:@"toOptions" sender:self];
}

- (IBAction)annotate {
    if (!canAnnotate || playerState == kPlaying) {
        return;
    }
    
    [annotationLock lock];
    annotating = !annotating;
    [annotationLock unlock];
    
    if (!annotating && canvasView.changed) {
        //Save our current annotations if we haven't already.
        [canvasView save];
    }
    
    //Detach ourselves from or reattach ourselves to the player.
    //And save a copy of the current clock duration in the process.
    savedDuration = [playerCore detach:annotating];
    self.navigationItem.rightBarButtonItem.enabled = !annotating;
    [self enableGestures:!annotating];
    canvasView.annotating = annotating;
    
    if (!annotating) {
        [UIView performWithoutAnimation:^{
            [self->annotateButton setTitle:@"Annotate" forState:UIControlStateNormal];
            [self->annotateButton layoutIfNeeded];
        }];
        annotateButton.titleLabel.text = @"Annotate";
        annotationControl.hidden = YES;
        playButton.enabled = locationSlider.value < 1;
        resetButton.enabled = YES;
    } else {
        canvasView.currentImage = [rendererDelegate currentAnnotationImage];
        if ([rendererDelegate respondsToSelector:@selector(currentAnnotationMask)]) {
            canvasView.currentMask = [rendererDelegate currentAnnotationMask];
        }
        [UIView performWithoutAnimation:^{
            [self->annotateButton setTitle:@"Done" forState:UIControlStateNormal];
            [self->annotateButton layoutIfNeeded];
        }];
        annotationControl.hidden = NO;
        playButton.enabled = NO;
        resetButton.enabled = NO;
    }
}

- (IBAction)selectAnnotationType
{
    canvasView.erasing = (annotationControl.selectedSegmentIndex == 1);
}

- (IBAction)viewNetworkStatus
{
    [self performSegueWithIdentifier:@"toNetworkStatus" sender:self];
}

- (IBAction)hideNavigation;
{
    if (projectionMode) {
        [self hideRemainingUI];
    }
}

- (IBAction)prepareForUnwind:(UIStoryboardSegue *)segue
{
    if ([segue.identifier isEqualToString:@"returnToPlayer"]) {
        //Make sure we don't keep a reference to any NetworkViewController instance.
        playerCore.networkStatusDelegate = nil;
    }
}

- (void)playerShutdown
{
    //Shutdown all networking. This is called when we go back to the score selection window or
    //when the user backgrounds our application.
    [playerCore shutdown];
    self.navigationItem.rightBarButtonItem.enabled = NO;
  
    //Stop any audio
    if (audioPlayer != nil) {
        [audioPlayer stopWithReset:NO];
        audioPlayer = nil;
    }
    
    //Clean up the rendering delegate
    /*if ([rendererDelegate respondsToSelector:@selector(setDelegate:)]) {
        rendererDelegate.delegate = nil;
    }*/
    if ([rendererDelegate respondsToSelector:@selector(close)]) {
        [rendererDelegate close];
    }
    rendererDelegate = nil;
    canvas.sublayers = nil;
    playerCore = nil;
    
    //Invalidate any potentially running timers
    [self resetClockWithUIUpdate:NO];
    
    //Reinstate the idle timer and the navigation bar
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [self hideNavigationBar:NO];
}

- (void)hideNavigationBar:(BOOL)hidden
{
    [self.navigationController setNavigationBarHidden:hidden animated:NO];
    if (hidden) {
        //Old manual changes are now handled by autolayout
        //canvasView.frame = CGRectMake(0, 0, canvasView.frame.size.width, canvasView.frame.size.height);
        hideStatusBar = YES;
        [self setNeedsStatusBarAppearanceUpdate];
        /*if (statusBarBackground.superlayer == nil) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [self.view.layer addSublayer:statusBarBackground];
            [CATransaction commit];
        }*/
    } else {
        //canvasView.frame = CGRectMake(0, NAVIGATION_HEIGHT + STATUS_HEIGHT, canvasView.frame.size.width, canvasView.frame.size.height);
        hideStatusBar = NO;
        [self setNeedsStatusBarAppearanceUpdate];
        /*[CATransaction begin];
        [CATransaction setDisableActions:YES];
        [statusBarBackground removeFromSuperlayer];
        [CATransaction commit];*/
    }
}

-(void)disableControls:(BOOL)disabled
{
    //This is used to prevent the user from using the play or reset button, or the location slider
    //(to no effect) while a network reconnection attempt is happening.
    if (controlsDisabled == disabled) {
        //No need to do anything here.
        return;
    }
    
    controlsDisabled = disabled;
    if (disabled) {
        //Save the previous state of the controls first.
        controlsPreviousState[0] = playButton.enabled;
        controlsPreviousState[1] = resetButton.enabled;
        controlsPreviousState[2] = locationSlider.enabled;
        //They tried to make me go to rehab but I said:
        playButton.enabled = NO;
        resetButton.enabled = NO;
        locationSlider.enabled = NO;
    } else {
        playButton.enabled = controlsPreviousState[0];
        resetButton.enabled = controlsPreviousState[1];
        locationSlider.enabled = controlsPreviousState[2];
    }
}

- (void)hideRemainingUI
{
    UIAlertController *hideInterfaceWarning = [UIAlertController alertControllerWithTitle:@"Hide Navigation Bar" message:@"Hiding the navigation bar will make it impossible to change network settings or return to the score selection screen without first returning to the iPad's home screen.\n\nDo you want to continue?" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *yesAction = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        self->hideEntireUI = YES;
        [self.navigationItem.titleView removeGestureRecognizer:self->navigationTap];
        self.navigationItem.titleView.userInteractionEnabled = NO;
        [self hideNavigationBar:YES];
    }];
    UIAlertAction *noAction = [UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleDefault handler:nil];
    [hideInterfaceWarning addAction:yesAction];
    [hideInterfaceWarning addAction:noAction];
    [self presentViewController:hideInterfaceWarning animated:YES completion:nil];
}

- (void)scaleCanvas:(CGSize)screenSize
{
    //With iOS 13 we need some work arounds. Currently we're keeping our canvas at 1024x768
    //and scaling to fit, but we should rework this later down the line and make it
    //renderer dependent. (And now it is!)
        
    CGSize coordSize;
    if (screenSize.width > screenSize.height) {
        coordSize = CGSizeMake(1024, 768);
    } else {
        coordSize = CGSizeMake(768, 1024);
    }
    
    CGFloat widthRatio = screenSize.width / coordSize.width;
    CGFloat heightRatio = screenSize.height / coordSize.height;
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    //Note: Need to change frame after applying transform for the bounds to be updated properly.
    if (useScaledCanvas) {
        if (widthRatio > heightRatio) {
            canvas.transform = CATransform3DMakeScale(heightRatio, heightRatio, 1);
            canvas.frame = CGRectMake(0, 0, coordSize.width * heightRatio, coordSize.height * heightRatio);
            canvasOffset = CGPointMake((screenSize.width - canvas.frame.size.width) / 2, 0);
            canvas.position = canvasOffset;
            canvasScale = heightRatio;
        } else {
            canvas.transform = CATransform3DMakeScale(widthRatio, widthRatio, 1);
            canvas.frame = CGRectMake(0, 0, coordSize.width * widthRatio, coordSize.height * widthRatio);
            canvasOffset = CGPointMake(0, (screenSize.height - canvas.frame.size.height) / 2);
            canvas.position = canvasOffset;
            canvasScale = widthRatio;
        }
    } else {
        canvas.transform = CATransform3DIdentity;
        canvas.frame = CGRectMake(0, 0, screenSize.width, screenSize.height);
        canvasScale = 1;
    }
    
    //Fix our cue light as well
    cueLightScale = MIN(widthRatio, heightRatio);
    cueLight.frame = CGRectMake(screenSize.width - (110 * cueLightScale), 10 * cueLightScale, 100 * cueLightScale, 100 * cueLightScale);
    cueLight.cornerRadius = (50 * cueLightScale);
    [CATransaction commit];
}

- (void)layoutUpperButtons
{
    if (playerState == kPlaying) {
        instructionsButton.hidden = YES;
        optionsButton.hidden = YES;
        annotateButton.hidden = YES;
    } else if (playerState == kPaused) {
        if (!projectionMode) {
            //Hide all our buttons first then change layout and show the reset button if available.
            optionsButton.hidden = YES;
            instructionsButton.hidden = YES;
            annotateButton.hidden = YES;
            annotateFirstTrailingConstraint.active = NO;
            annotateSecondTrailingConstraint.active = NO;
            [self.view layoutIfNeeded];
            annotateButton.hidden = !canAnnotate;
        }
    } else {
        if (!projectionMode) {
            annotateFirstTrailingConstraint.active = hasOptions;
            annotateSecondTrailingConstraint.active = hasInstructions;
            [self.view layoutIfNeeded];
            instructionsButton.hidden = !hasInstructions;
            optionsButton.hidden = !hasOptions;
            annotateButton.hidden = !canAnnotate;
        }
    }
}

- (void)editDuration
{
    //Only allow duration to be edited if the player is stopped.
    if (playerState == kStopped && !controlsDisabled && !annotating) {
        if (!clockVisible && allowClockVisibilityChange && !projectionMode) {
            //If our clock isn't visible, the first tap should reshow it.
            self.clockVisible = YES;
        } else if (playerCore.allowClockChange) {
            //Create an input box to get the new duration
            UIAlertController *durationInputBox = [UIAlertController alertControllerWithTitle:@"Change Duration" message:@"Enter a new duration for the score." preferredStyle:UIAlertControllerStyleAlert];
            [durationInputBox addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.delegate = self;
                textField.keyboardType = UIKeyboardTypeNumberPad;
                textField.placeholder = [NSString stringWithFormat:@"%i seconds", (int)self->playerCore.clockDuration];
            }];
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                if ([durationInputBox.textFields objectAtIndex:0].text.length != 0) {
                    //Set duration and resynch to the nearest second
                    [self->playerCore setScoreDuration:[[durationInputBox.textFields objectAtIndex:0].text floatValue]];
                }
            }];
            
            [durationInputBox addAction:cancelAction];
            [durationInputBox addAction:okAction];
            [self presentViewController:durationInputBox animated:YES completion:nil];
        }
    } else if (playerState != kStopped && allowClockVisibilityChange && !projectionMode) {
        //If we are playing, toggle the visibilty of the clock if the score has allowed it.
        self.clockVisible = !clockVisible;
    }
}

- (void)swipeUp
{
    if ([rendererDelegate respondsToSelector:@selector(swipeUp)]) {
        [rendererDelegate swipeUp];
    }
}

- (void)swipeDown
{
    if ([rendererDelegate respondsToSelector:@selector(swipeDown)]) {
        [rendererDelegate swipeDown];
    }
}

- (void)swipeLeft
{
    if ([rendererDelegate respondsToSelector:@selector(swipeLeft)]) {
        [rendererDelegate swipeLeft];
    }
}

- (void)swipeRight
{
    if ([rendererDelegate respondsToSelector:@selector(swipeRight)]) {
        [rendererDelegate swipeRight];
    }
}

- (void)tap
{
    if (pingTest) {
        [playerCore sendPing];
    }
    
    if ([rendererDelegate respondsToSelector:@selector(tapAt:)]) {
        int margin = LOWER_PADDING;
        if (playerState == kStopped) {
            margin += navigationHeight;
        }
        CGPoint location = [tap locationInView:canvasView];
        if (location.y < canvas.frame.size.height - margin) {
            [rendererDelegate tapAt:CGPointMake((location.x / canvasScale) - canvasOffset.x, (location.y / canvasScale) - canvasOffset.y)];
        }
    }
}

- (void)pan
{
    if ([rendererDelegate respondsToSelector:@selector(panAt:)]) {
        int margin = LOWER_PADDING;
        if (playerState == kStopped) {
            margin += navigationHeight;
        }
        CGPoint location = [pan locationInView:canvasView];
        if (location.y < canvas.frame.size.height - margin) {
            [rendererDelegate panAt:CGPointMake((location.x / canvasScale) - canvasOffset.x, (location.y / canvasScale) - canvasOffset.y)];
        }
    }
}

- (void)enableGestures:(BOOL)enabled
{
    for (int i = 0; i < [gestureRecognizers count]; i++) {
        ((UIGestureRecognizer *)[gestureRecognizers objectAtIndex:i]).enabled = enabled;
    }
}

- (void)updateClockDisplay
{
    int displayValue;
    if (!annotating) {
        displayValue = playerCore.clockProgress;
    } else {
        displayValue = (int)roundf(savedDuration * locationSlider.value);
    }
    if (displayValue < 0) {
        clockDisplay.text = @"0:00";
    } else {
        uint minutes = displayValue / 60;
        uint seconds = displayValue % 60;
        clockDisplay.text = [NSString stringWithFormat:@"%i:%02i", minutes, seconds];
    }
}

#pragma mark - PlayerUI delegate
- (void)playerPlayWithAudio:(BOOL)startAudio
{
    //Safety check to make sure we don't play while we're annotating.
    [annotationLock lock];
    if (annotating) {
        [annotationLock unlock];
        return;
    }
    [annotationLock unlock];
    
    //Keep a separate player state in all of these functions so that the UI playerstate
    //can be independant of the player core.
    playerState = kPlaying;
    resetViewOnSeek = NO;
    
    //UI alterations
    if (playerCore.isPausable) {
        [UIView performWithoutAnimation:^{
            [self->playButton setTitle:@"Pause" forState:UIControlStateNormal];
            [self->playButton layoutIfNeeded];
        }];
    } else {
        playButton.enabled = NO;
    }
    [self layoutUpperButtons];
    [self hideNavigationBar:YES];
    
    //Make sure we're not on the network status page
    NSArray *viewControllers = self.navigationController.viewControllers;
    if ([viewControllers objectAtIndex:viewControllers.count - 2] == self) {
        [self.navigationController popViewControllerAnimated:YES];
    }
    
    //Make sure we're not viewing the instructions or options, or trying to change the duration.
    [self dismissViewControllerAnimated:YES completion:nil];

    //First check that we're in a valid playback area and start the audio player
    if (playerCore.clockEnabled) {
        if (locationSlider.value < 0) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [self playerSeekTo:0 endReachedWhilePlaying:NO];
            [CATransaction commit];
        }
        if (audioPlayer != nil && startAudio) {
            [audioPlayer play];
        }
    }
    
    //Send the renderer the order to play
    if ([rendererDelegate respondsToSelector:@selector(play)]) {
        [rendererDelegate play];
    }
}

- (int)playerReset
{
    playerState = kStopped;
    resetViewOnSeek = NO;
    
    //Basic canvas reset
    //This is now the responsibility of individual renderers. It should be done between data verification
    //and initial rendering. (This avoids any obvious flash to a blank screen.)
    //canvas.sublayers = nil;
    
    //Reset the clock display and location slider if we're using it
    if (playerCore.clockEnabled) {
        locationSlider.value = 0;
        [self updateClockDisplay];
    }
    
    //Reset renderer
    CGFloat sliderOffset = 0;
    int clockAdjust = 0;
    if ([rendererDelegate respondsToSelector:@selector(reset:)]) {
        [rendererDelegate reset:&sliderOffset];
    } else {
        [rendererDelegate reset];
    }
    
    //Adjust our slider for any offset and make sure it's rounded to the nearest second.
    if (sliderOffset != 0) {
        clockAdjust = (int)roundf(sliderOffset * playerCore.clockDuration);
        locationSlider.value = clockAdjust / (CGFloat)playerCore.clockDuration;
        [self updateClockDisplay];
    }
    
    //UI reset and timer reset - applies to all scores
    [UIView performWithoutAnimation:^{
        [self->playButton setTitle:@"Play" forState:UIControlStateNormal];
        [self->playButton layoutIfNeeded];
    }];
    playButton.enabled = YES;
    [self layoutUpperButtons];
    if (!hideEntireUI) {
        [self hideNavigationBar:NO];
    }
    
    if (audioPlayer != nil) {
        [audioPlayer stopWithReset:YES];
    }
    
    return clockAdjust;
}

- (void)playerSeekTo:(CGFloat)location endReachedWhilePlaying:(BOOL)ended
{
    locationSlider.value = location;
    [self updateClockDisplay];

    //Send the seek command to the renderer if it supports it
    if ([rendererDelegate respondsToSelector:@selector(seek:)]) {
        [rendererDelegate seek:locationSlider.value];
    }
    
    //Perform UI updates if we reached the end of the score while playing.
    if (playerCore.clockEnabled && ended) {
        if (!hideEntireUI) {
            [self hideNavigationBar:NO];
        }
        playerState = kStopped;
        [self layoutUpperButtons];
        [UIView performWithoutAnimation:^{
            [self->playButton setTitle:@"Play" forState:UIControlStateNormal];
            [self->playButton layoutIfNeeded];
        }];
        playButton.enabled = NO;
        [UIView performWithoutAnimation:^{
            [self->playButton setTitle:@"Play" forState:UIControlStateNormal];
            [self->playButton layoutIfNeeded];
        }];
        playButton.enabled = NO;
    } else if (playerState == kStopped) {
        playButton.enabled = locationSlider.value < 1;
    }
    
    //Reset the view if needed.
    if (resetViewOnSeek) {
        if (!hideEntireUI) {
            [self hideNavigationBar:NO];
        }
        [self layoutUpperButtons];
        resetViewOnSeek = NO;
    }
}

- (void)playerSeekFinishedAfterResync:(BOOL)sync
{
    //If there's an audio file we need to handle seeking here.
    //This way we aren't constantly changing the content of the buffers.
    if (audioPlayer != nil) {
        if (playerState == kPlaying) {
            if (sync) {
                //Buy us an extra second here.
                //(In case this is happening right before a tick and don't have a full second.)
                audioSeek = playerCore.clockProgress + 2;
                [audioPlayer seekToTime:(int)audioSeek];
            } else {
                audioSeek = playerCore.clockProgress + 1;
                [audioPlayer seekToTime:(int)audioSeek];
            }
        } else {
            [audioPlayer seekToTime:playerCore.clockProgress];
        }
    }
}

- (void)playerStop
{
    //Safety checks for this function are performed in the player core.
    playerState = kPaused;
    [rendererDelegate stop];
    if (audioPlayer != nil) {
        [audioPlayer stopWithReset:NO];
    }
    [UIView performWithoutAnimation:^{
        [self->playButton setTitle:@"Play" forState:UIControlStateNormal];
        [self->playButton layoutIfNeeded];
    }];
    
    //Show our annotation button if that's an option.
    [self layoutUpperButtons];
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    //Only update our values if we're at a second mark.
    //(Split seconds only exist for renderers that need a slightly higher clock resolution.)
    if (splitSecond == 0) {
        if (playerCore.clockDuration > 0) {
            locationSlider.value = progress / (CGFloat)playerCore.clockDuration;
        }
        [self updateClockDisplay];
    }
    
    if (rendererAcceptsTick) {
        [rendererDelegate tick:progress tock:splitSecond noMoreClock:finished];
    }
    
    if (finished) {
        playerState = kStopped;
        if (resetViewOnFinish) {
            if (!hideEntireUI) {
                [self hideNavigationBar:NO];
            }
            [self layoutUpperButtons];
        } else {
            resetViewOnSeek = YES;
        }
        
        playButton.enabled = NO;
        [UIView performWithoutAnimation:^{
            [self->playButton setTitle:@"Play" forState:UIControlStateNormal];
            [self->playButton layoutIfNeeded];
        }];
    }
    
    if (audioSeek == playerCore.clockProgress && !splitSecond) {
        [audioPlayer play];
        if ([rendererDelegate respondsToSelector:@selector(attemptSync)]) {
            //Make sure our renderer hasn't been put out by the audio load time.
            [rendererDelegate attemptSync];
        }
    }
}

- (void)closeScore {
    //Check that we actually have a score loaded.
    if (rendererDelegate != nil) {
        //Shutdown the current renderer and reset our player.
        //Stop any audio
        if (audioPlayer != nil) {
            [audioPlayer stopWithReset:NO];
            audioPlayer = nil;
        }
        
        //Save any annotations and reset the UI.
        if (annotating) {
            [self annotate];
        }
        
        [self dismissViewControllerAnimated:YES completion:nil];
        
        //Clean up the rendering delegate
        if ([rendererDelegate respondsToSelector:@selector(close)]) {
            [rendererDelegate close];
        }
        rendererDelegate = nil;
        canvas.sublayers = nil;
        [self resetClockWithUIUpdate:NO];
        
        if (playerCore.isStatic) {
            [self setDynamicScoreUI];
        }
        
        //Reset the location slider minimum.
        locationSlider.minimumValue = 0;
    }
}

- (void)loadScore:(Score *)score
{
    //Update the navigation bar title.
    if (titleLabel != nil) {
        titleLabel.text = [NSString stringWithFormat:@"%@ - %@", score.composerFullText, score.scoreName];
    } else {
        self.navigationItem.title = [NSString stringWithFormat:@"%@ - %@", score.composerFullText, score.scoreName];
    }
    
    //Initialize the correct class needed for the score type and configure UI elements as needed.
    //Start with the clock UI elements
    
    allowClockVisibilityChange = NO;
    canAnnotate = NO;
    
    if (playerCore.clockDuration > 0) {
        clockVisible = YES;
        resetViewOnFinish = YES;
    } else {
        clockVisible = NO;
        
        //Disable the location slider. (Handled by setting clockVisible now.)
        //locationSlider.enabled = NO;
        //locationSlider.hidden = YES;
    }
    //Initially set our margin colour to be the same as our background colour.
    [self setPlayerBackgroundColour:score.backgroundColour];
    [self setMarginColour:score.backgroundColour];
    
    //Create our renderer
    //NSMutableArray *validRenderers = [Renderer validRenderers];
    Class rendererClass = NSClassFromString(score.scoreType);
    if ([rendererClass conformsToProtocol:@protocol(RendererDelegate)]) {
        useScaledCanvas = [rendererClass getRendererRequirements] & kUsesScaledCanvas;
        [self scaleCanvas:self.view.frame.size];
        rendererDelegate = [[rendererClass alloc] initRendererWithScore:score canvas:canvas UIDelegate:self messagingDelegate:playerCore];
    } else {
        //This should never be called. The score selection window should check against the exact same
        //list that we have here. For safety though we should probably add something here.
        [self badPreferencesFile:@"Renderer not found."];
    }
    //Pass a reference to the renderer to our player core.
    playerCore.rendererDelegate = rendererDelegate;
    
    rendererAcceptsTick = [rendererDelegate respondsToSelector:@selector(tick:tock:noMoreClock:)];
    
    //Check if the score has instructions, and enable or disable the instructions button.
    if (score.instructions != nil) {
        hasInstructions = YES;
        optionsTrailingConstraint.active = YES;
        annotateSecondTrailingConstraint.active = YES;
    } else {
        hasInstructions = NO;
        optionsTrailingConstraint.active = NO;
        annotateSecondTrailingConstraint.active = NO;
    }
    instructionsButton.hidden = !hasInstructions || projectionMode;
    
    //Check if the score has options associated with it.
    if (score.allowsOptions && [rendererDelegate respondsToSelector:@selector(getOptions)] && [rendererDelegate respondsToSelector:@selector(setOptions:)]) {
        hasOptions = YES;
        annotateFirstTrailingConstraint.active = YES;
    } else {
        hasOptions = NO;
        annotateFirstTrailingConstraint.active = NO;
    }
    optionsButton.hidden = !hasOptions || projectionMode;
    
    //If our score has enabled annotation during load, check that the renderer actually
    //has the necessary functions to properly support it.
    if (canAnnotate && !([rendererDelegate respondsToSelector:@selector(currentAnnotationImage)] && [rendererDelegate respondsToSelector:@selector(saveCurrentAnnotation:)] && [rendererDelegate respondsToSelector:@selector(hideSavedAnnotations:)])) {
        canAnnotate = NO;
    }
    annotateButton.hidden = !canAnnotate || projectionMode;
    
    //Update our layout in case our buttons have shifted position
    [self.view layoutIfNeeded];
    
    //Check if the current score is pausable and set the associated variable
    if ([rendererDelegate respondsToSelector:@selector(stop)]) {
        playerCore.isPausable = YES;
    } else {
        playerCore.isPausable = NO;
    }
    
    //Initialiaze the audio player if needed.
    if (score.audioFile != nil && playerCore.clockEnabled) {
        //Edit the following line to change which class acts as the audio player.
        Class audioPlayerClass = NSClassFromString(@"AudioPlayer2");
        if ([audioPlayerClass conformsToProtocol:@protocol(AudioPlayer)]) {
            audioPlayer = [[audioPlayerClass alloc] initWithAudioFile:[score.scorePath stringByAppendingPathComponent:score.audioFile] withOptions:nil];
        }
        audioSeek = 0;
    } else {
        audioPlayer = nil;
    }
    
    //Leave the player core to send the initial reset command.
    rendererDelegate.isMaster = playerCore.isMaster;
}

- (void)networkErrorWithMessage:(NSString *)message toStandAlone:(BOOL)killNetworking
{
    if (killNetworking) {
        self.navigationItem.rightBarButtonItem.enabled = NO;
    }
    [self errorWithTitle:@"Network Error" message:message];
}

- (void)errorWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *networkAlert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [networkAlert addAction:okAction];
    [self presentViewController:networkAlert animated:YES completion:nil];
}

- (void)awaitingNetwork:(BOOL)waiting
{
    if (waiting) {
        if (!connectingIndicator.isAnimating) {
            [canvasView.layer addSublayer:dimmer];
            [connectingIndicator startAnimating];
            [self disableControls:YES];
        }
    } else {
        [connectingIndicator stopAnimating];
        [dimmer removeFromSuperlayer];
        [self disableControls:NO];
    }
}

- (void)preventAnnotation
{
    //This is used to prevent annotation mode from being entered before we have a valid status
    //following connection to a server. It is cancelled when the setInitialState function is called.
    annotateButton.enabled = NO;
}

- (void)setInitialState:(PlayerState)state
{
    playerState = state;
    [self layoutUpperButtons];
    //Do additional any UI changes needed when connecting to another iPad.
    if (playerState == kStopped) {
        //The seek operation will only have set the proper status of the play button if the
        //score uses the built in clock. If we're not using it then enable the button here.
        //TODO: Check how this interacts with pausing and check if we can't do this elsewhere.
        if (!playerCore.clockEnabled) {
            playButton.enabled = YES;
        }
        //Make sure our navigation bar is visible if need be.
        if (self.navigationController.navigationBarHidden && !hideEntireUI) {
            //Assume that if our navigation slider value is 1 we might have just finished
            //playing, and should maybe reset the navigation bar on seek.
            if (locationSlider.value == 1 && !resetViewOnFinish) {
                resetViewOnSeek = YES;
            } else {
                [self hideNavigationBar:NO];
            }
        }
    } else if (playerState == kPaused) {
        [self hideNavigationBar:YES];
    }
    annotateButton.enabled = YES;
}

- (void)showCueLight:(UIColor *)colour
{
    [cueLight removeAllAnimations];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [CATransaction setCompletionBlock:^{
        [CATransaction begin];
        //[CATransaction setCompletionBlock:^{[self->cueLight removeFromSuperlayer];}];
        [CATransaction setAnimationDuration:5];
        self->cueLight.opacity = 0;
        [CATransaction commit];
    }];
    cueLight.backgroundColor = colour.CGColor;
    cueLight.opacity = 1;
    if (cueLight.superlayer == nil) {
        [canvasView.layer addSublayer:cueLight];
    }
    [CATransaction commit];
}

#pragma mark - RendererUI delegate

//Clock, messaging and UI functions
- (NSString *)playerID
{
    return playerCore.identifier;
}

- (BOOL)canAnnotate
{
    return canAnnotate;
}

- (void)setCanAnnotate:(BOOL)annotate
{
    //Check if the renderer has the necessary functions to support annotation.
    //(If it's still being initialized this check will happen once it's loaded.)
    if (rendererDelegate != nil && !([rendererDelegate respondsToSelector:@selector(currentAnnotationImage)] && [rendererDelegate respondsToSelector:@selector(saveCurrentAnnotation:)] && [rendererDelegate respondsToSelector:@selector(hideSavedAnnotations:)])) {
        annotate = NO;
    }
    canAnnotate = annotate;
    annotateButton.hidden = !canAnnotate || projectionMode;
}

- (CGFloat)clockDuration
{
    if (!annotating) {
        return playerCore.clockDuration;
    } else {
        return savedDuration;
    }
}

- (void)setClockDuration:(CGFloat)newDuration
{
    //TODO: Maybe move more of this into the playercore.
    if (newDuration == 0 && playerCore.clockDuration != 0) {
        //Changing to a static score. Make the appropriate changes.
        playerCore.clockEnabled = NO;
        self.clockVisible = NO;
        playerCore.allowClockChange = NO;
        playerCore.allowSyncToTick = NO;
    }
    playerCore.clockDuration = newDuration;
}

- (int)clockProgress
{
    if (!annotating) {
        return playerCore.clockProgress;
    } else {
        return (int)roundf(locationSlider.value * savedDuration);
    }
}

- (CGFloat)clockLocation
{
    if (!annotating) {
        return playerCore.clockLocation;
    } else {
        return locationSlider.value;
    }
}

- (CGFloat)sliderMinimumValue
{
    return locationSlider.minimumValue;
}

- (void)setSliderMinimumValue:(CGFloat)newMinimumValue;
{
    locationSlider.minimumValue = newMinimumValue;
}

- (BOOL)clockEnabled
{
    return playerCore.clockEnabled;
}

- (void)setClockEnabled:(BOOL)clockEnabled
{
    playerCore.clockEnabled = clockEnabled;
}

- (BOOL)splitSecondMode
{
    return playerCore.splitSecondMode;
}

- (void)setSplitSecondMode:(BOOL)splitSecondMode
{
    playerCore.splitSecondMode = splitSecondMode;
}

- (BOOL)clockVisible
{
    return clockVisible;
}

- (void)setClockVisible:(BOOL)visible
{
    //If projection mode is enabled, don't allow us to set the clock visible.
    if (projectionMode && visible) {
        return;
    }
    
    clockVisible = visible;
    if (playerCore.clockDuration > 0) {
        locationSlider.hidden = !clockVisible;
    } else {
        locationSlider.hidden = YES;
    }
    if (clockVisible) {
        clockDisplay.textColor = clockColour;
    } else {
        clockDisplay.textColor = [UIColor clearColor];
    }
}

- (BOOL)allowClockChange
{
    return playerCore.allowClockChange;
}

- (void)setAllowClockChange:(BOOL)allowClockChange
{
    playerCore.allowClockChange = allowClockChange;
}

- (BOOL)allowSyncToTick
{
    return playerCore.allowSyncToTick;
}

- (void)setAllowSyncToTick:(BOOL)allowSyncToTick
{
    playerCore.allowSyncToTick = allowSyncToTick;
}

- (void)setStaticScoreUI
{
    //Common settings for static scores. We only need to set these if we haven't already done so.
    if (!playerCore.isStatic) {
        playButton.hidden = YES;
        //resetButton.center = playButton.center;
        resetLeadingConstraint.active = NO;
        [self.view layoutIfNeeded];
        playerCore.isStatic = YES;
    }
}

- (void)setDynamicScoreUI
{
    //By default, scores are dynamic. We only need this if we're changing back from a static score.
    if (playerCore.isStatic) {
        //resetButton.center = CGPointMake(resetButton.center.x + 80, resetButton.center.y);
        resetLeadingConstraint.active = YES;
        [self.view layoutIfNeeded];
        if (!projectionMode) {
            playButton.hidden = NO;
        }
        playerCore.isStatic = NO;
    }
}

- (void)hideNavigationBar {
    [self hideNavigationBar:YES];
}

- (void)badPreferencesFile:(NSString *)errorMessage
{
    //If a score specific preference file is corrupt then alert the user and return to the
    //score selection screen.
    resetButton.enabled = NO;
    playButton.enabled = NO;
    locationSlider.enabled = NO;
    instructionsButton.enabled = NO;
    optionsButton.enabled = NO;
    annotateButton.enabled = NO;
    
    if (alertShown) {
        return;
    }
    
    alertShown = YES;
    NSString *message;
    if (errorMessage != nil) {
        message = [NSString stringWithFormat:@"There is an unrecoverable error in the chosen score.\n\n(%@)", errorMessage];
    } else {
        message = @"There is an unrecoverable error in the chosen score.";
    }
    UIAlertController *badPrefsFileAlert = [UIAlertController alertControllerWithTitle:@"Corrupt Score" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController popViewControllerAnimated:YES];
    }];
    [badPrefsFileAlert addAction:okAction];
    [self presentViewController:badPrefsFileAlert animated:YES completion:nil];
}

- (void)stopClockWithStateUpdate:(BOOL)updateState
{
    [playerCore stopClockWithStateUpdate:updateState];
    if (updateState) {
        playerState = kStopped;
    }
}

- (void)resetClockWithUIUpdate:(BOOL)updateUI
{
    [playerCore resetClock];
    locationSlider.value = 0;
    [self updateClockDisplay];
    
    //Updates the state of the play button if requested.
    if (updateUI && playerState == kStopped) {
        playButton.enabled = YES;
        [UIView performWithoutAnimation:^{
            [self->playButton setTitle:@"Play" forState:UIControlStateNormal];
            [self->playButton layoutIfNeeded];
        }];
    }
}

- (void)setPlayerBackgroundColour:(UIColor *)colour
{
    canvas.backgroundColor = colour.CGColor;
    
    //Check that we have a big enough difference between the text and background colour.
    //(Using appropriate colour weighting.)
    CGFloat red, green, blue, alpha;
    if (![colour getRed:&red green:&green blue:&blue alpha:&alpha]) {
        [colour getWhite:&red alpha:&alpha];
        green = red;
        blue = red;
    }
    red = (red * alpha) + 1 - alpha;
    green = (green * alpha) + 1 - alpha;
    blue = (blue * alpha) + 1 - alpha;
    CGFloat yiq = (red * 0.299) + (green * 0.587) + (blue * 0.114);
    if (yiq < 0.5) {
        clockColour = [UIColor whiteColor];
    } else {
        clockColour = [UIColor blackColor];
    }
    self.clockVisible = clockVisible;
}

- (void)setMarginColour:(UIColor *)colour
{
    canvasView.backgroundColor = colour;
}

- (void)partChangedToPart:(NSUInteger)part
{
    if (audioPlayer != nil && [playerCore.currentScore.audioParts count] > 0) {
        NSString *audioFile;
        if (part == 0) {
            audioFile = [playerCore.currentScore.scorePath stringByAppendingPathComponent: playerCore.currentScore.audioFile];
        } else if (part <= [playerCore.currentScore.audioParts count]) {
            audioFile = [playerCore.currentScore.scorePath stringByAppendingPathComponent:[playerCore.currentScore.audioParts objectAtIndex:part - 1]];
        }
        if (audioFile != nil) {
            [audioPlayer loadAudioFile:audioFile];
            if (playerState == kPlaying) {
                //Buy us an extra second here.
                audioSeek = playerCore.clockProgress + 2;
                [audioPlayer seekToTime:(int)audioSeek];
            } else {
                [audioPlayer loadAudioFile:audioFile];
                [audioPlayer seekToTime:playerCore.clockProgress];
            }
        }
    }
}

#pragma mark - Annotation delegate
- (CGRect)canvasScaledFrame
{
    return canvas.frame;
}

- (void)saveAnnotation:(UIImage *)image
{
    [rendererDelegate saveCurrentAnnotation:image];
}

- (void)hideSavedAnnotations:(BOOL)hide
{
    [rendererDelegate hideSavedAnnotations:hide];
}

#pragma mark - UITextField delegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    //Only allow numbers in the duration text box.
    NSCharacterSet *numbers = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    for (int i = 0; i < [string length]; i++) {
        unichar currentCharacter = [string characterAtIndex:i];
        if (![numbers characterIsMember:currentCharacter]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    return YES;
}

#pragma mark - UIGestureRecognizer delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if (gestureRecognizer == pan) {
        return YES;
    } else {
        return NO;
    }
}

@end

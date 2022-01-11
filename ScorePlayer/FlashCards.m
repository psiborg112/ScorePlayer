//
//  FlashCards.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 7/03/2015.
//  Copyright (c) 2015 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "FlashCards.h"
#import "Score.h"
#import "OSCMessage.h"

@interface FlashCards ()

- (void)changePart:(NSInteger)relativeChange;
- (NSMutableArray *)generateCardOrderWithDuos:(BOOL)enableDuos fromTime:(NSInteger)startTime toTime:(NSInteger)endTime;
- (OSCMessage *)generateDuoMessageAsNew:(BOOL)new;
- (void)displayCard:(NSInteger)cardNumber animated:(BOOL)animated;
- (void)resetCardPool;
- (void)resetDuoPool;
- (void)initLayers;
- (void)resizeLayers;

@end

@implementation FlashCards {
    Score *score;
    CALayer *canvas;
    
    CALayer *card;
    CALayer *annotationLayer;
    CALayer *dynamicsDisplay;
    UILabel *dynamicsText;
    CALayer *timerDisplay;
    CALayer *timerBar;
    UILabel *timerText;
    NSInteger timerBorders;
    BOOL startTimer;
    NSInteger timerAdjust;
    NSInteger currentPart;
    UIColor *backgroundColour;
    UIColor *dynamicsBackgroundColour;
    UIColor *dynamicsTextColour;
    int countdownRemaining;
    int counterOffset;
    BOOL hideTimer;
    
    NSInteger minDisplay;
    NSInteger maxDisplay;
    NSInteger fadeTime;
    
    NSInteger cards;
    NSInteger currentCard;
    NSString *currentAnnotationFileName;
    NSString *annotationsDirectory;
    BOOL graphicalDynamics;
    NSMutableArray *dynamics;
    TimerStyle timerStyle;
    NSInteger duoCards;
    NSString *duoFileName;
    NSInteger duoPercentage;
    OSCMessage *duoMessage;
    
    NSMutableArray *workingCardOrder;
    NSMutableArray *latestCardOrder;
    NSMutableArray *cardPool;
    NSMutableArray *duoPool;
    
    NSXMLParser *xmlParser;
    NSMutableString *currentString;
    BOOL isData;
    BOOL prefsLoaded;
    NSCondition *prefsCondition;
    BOOL badPrefs;
    NSString *errorMessage;
    xmlLocation currentPrefs;
    NSMutableArray *prescribedChanges;
    
    BOOL allowUpsideDown;
    BOOL allowRepeats;
    BOOL firstLoad;
    BOOL hasData;
    BOOL newCardOrder;
    BOOL ordered;
    BOOL syncCards;
    
    __weak id<RendererUI> UIDelegate;
    __weak id<RendererMessaging> messagingDelegate;
}

- (void)changePart:(NSInteger)relativeChange
{
    NSInteger newPart = currentPart + relativeChange;
    if (newPart > (NSInteger)[score.parts count]) {
        newPart = 0;
    } else if (newPart < 0) {
        newPart = [score.parts count];
    }
    
    currentPart = newPart;
    [self displayCard:currentCard animated:NO];
}

- (NSMutableArray *)generateCardOrderWithDuos:(BOOL)enableDuos fromTime:(NSInteger)startTime toTime:(NSInteger)endTime
{
    NSMutableArray *result = [[NSMutableArray alloc] init];
    NSInteger remaining = endTime - startTime;
    NSInteger nextChange = startTime;
    
    //Keep randomly assigning card durations until we near the end.
    while (remaining >= minDisplay) {
        NSInteger cardDuration = minDisplay + arc4random_uniform((int)(maxDisplay - minDisplay + 1));
        if (cardDuration > remaining) {
            cardDuration = remaining;
        }
        //Decide whether we should use a duo card. These are represented with a negative number.
        //(Don't allow our first card to be a duo card, so that we can properly select our part if necessary.)
        NSInteger cardIndex;
        NSInteger cardNumber;
        if (nextChange != 0 && enableDuos && (arc4random_uniform(100) < duoPercentage)) {
            cardIndex = arc4random_uniform((int)[duoPool count]);
            cardNumber = -[[duoPool objectAtIndex:cardIndex] integerValue];
            if (!allowRepeats) {
                //Remove our card from the pool if we don't allow for repeats within each cycle.
                [duoPool removeObjectAtIndex:cardIndex];
                if ([duoPool count] == 0) {
                    [self resetDuoPool];
                }
            }
        } else {
            cardIndex = arc4random_uniform((int)[cardPool count]);
            cardNumber = [[cardPool objectAtIndex:cardIndex] integerValue];
            if (!allowRepeats) {
                [cardPool removeObjectAtIndex:cardIndex];
                if ([cardPool count] == 0) {
                    [self resetCardPool];
                }
            }
        }
        
        NSInteger dynamic = arc4random_uniform((uint)[dynamics count]);
        
        NSMutableArray *nextCard = [[NSMutableArray alloc] init];
        [nextCard addObject:[NSNumber numberWithInteger:nextChange]];
        [nextCard addObject:[NSNumber numberWithInteger:cardNumber]];
        [nextCard addObject:[NSNumber numberWithInteger:cardDuration]];
        [nextCard addObject:[NSNumber numberWithInteger:dynamic]];
        //Use 0 for an unchanged card, and 1 for a rotated one.
        if (allowUpsideDown) {
            [nextCard addObject:[NSNumber numberWithInteger:arc4random_uniform(2)]];
        } else {
            [nextCard addObject:[NSNumber numberWithInteger:0]];
        }
        
        [result addObject:nextCard];
        nextChange += cardDuration;
        remaining -= cardDuration;
    }
    
    //If we still have time left to allocate, adjust the previous card to take up the remainder of time or split it
    //between two cards if their combined time is greater than twice the minimum display time.
    
    if (remaining != 0) {
        NSInteger previousCardDuration = [[[result lastObject] objectAtIndex:2] integerValue];
        remaining += previousCardDuration;
        if (remaining >= (minDisplay * 2)) {
            [[result lastObject] replaceObjectAtIndex:2 withObject:[NSNumber numberWithInteger:remaining / 2]];
            
            NSMutableArray *nextCard = [[NSMutableArray alloc] init];
            [nextCard addObject:[NSNumber numberWithInteger:[[[result lastObject] objectAtIndex:0] integerValue] + (remaining / 2)]];
            
            NSInteger cardIndex;
            cardIndex = arc4random_uniform((int)[cardPool count]);
            [nextCard addObject:[cardPool objectAtIndex:cardIndex]];
            if (!allowRepeats) {
                [cardPool removeObjectAtIndex:cardIndex];
                if ([cardPool count] == 0) {
                    [self resetCardPool];
                }
            }
            
            [nextCard addObject:[NSNumber numberWithInteger:(remaining / 2) + (remaining % 2)]];
            [nextCard addObject:[NSNumber numberWithInteger:arc4random_uniform((uint)[dynamics count])]];
            if (allowUpsideDown) {
                [nextCard addObject:[NSNumber numberWithInteger:arc4random_uniform(2)]];
            } else {
                [nextCard addObject:[NSNumber numberWithInteger:0]];
            }
            
            [result addObject:nextCard];
        } else {
            [[result lastObject] replaceObjectAtIndex:2 withObject:[NSNumber numberWithInteger:remaining]];
        }
    }
    
    return result;
}

- (OSCMessage *)generateDuoMessageAsNew:(BOOL)new
{
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"DuoCards"];
    if (new) {
        [message addStringArgument:@"New"];
    } else {
        [message addStringArgument:@"Refresh"];
    }
    
    for (int i = 0; i < [latestCardOrder count]; i++) {
        //Unless we are syncing every card, we only need to add card entries to our message if they involve duo cards.
        if ([[[latestCardOrder objectAtIndex:i] objectAtIndex:1] integerValue] < 0 || syncCards) {
            for (int j = 0; j < [[latestCardOrder objectAtIndex:i] count]; j++) {
                [message addIntegerArgument:[[[latestCardOrder objectAtIndex:i] objectAtIndex:j] integerValue]];
            }
        }
    }
    
    return message;
}

- (void)displayCard:(NSInteger)cardNumber animated:(BOOL)animated
{
    //Do this whether we're changing card number or not, since this is called by the part changing code.
    
    NSString *currentCardFileName;
    if ([[[workingCardOrder objectAtIndex:cardNumber] objectAtIndex:1] integerValue] < 0) {
        currentCardFileName = [duoFileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", abs([[[workingCardOrder objectAtIndex:cardNumber] objectAtIndex:1] intValue])]];
    } else {
        if (currentPart == 0) {
            currentCardFileName = [score.fileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", [[[workingCardOrder objectAtIndex:cardNumber] objectAtIndex:1] intValue]]];
        } else {
            currentCardFileName = [[score.parts objectAtIndex:currentPart - 1] stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", [[[workingCardOrder objectAtIndex:cardNumber] objectAtIndex:1] intValue]]];
        }
    }
    currentAnnotationFileName = [annotationsDirectory stringByAppendingPathComponent:currentCardFileName];
    currentAnnotationFileName = [[currentAnnotationFileName stringByDeletingPathExtension] stringByAppendingPathExtension:@"png"];
    
    if (currentCard != cardNumber) {
        //We also need to update the dynamics if we're actually moving to a different card.
        if ([[[workingCardOrder objectAtIndex:cardNumber] objectAtIndex:3] integerValue] < [dynamics count]) {
            if (graphicalDynamics) {
                dynamicsDisplay.contents = (id)[Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:[dynamics objectAtIndex:[[[workingCardOrder objectAtIndex:cardNumber] objectAtIndex:3] integerValue]]]].CGImage;
            } else {
                dynamicsText.text = [dynamics objectAtIndex:[[[workingCardOrder objectAtIndex:cardNumber] objectAtIndex:3] integerValue]];
            }
        }
        
        //And check that our rotation is correct.
        if (allowUpsideDown) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            card.contents = nil;
            if ([[[workingCardOrder objectAtIndex:cardNumber] objectAtIndex:4] integerValue] == 0) {
                [card setValue:[NSNumber numberWithFloat: 0] forKeyPath:@"transform.rotation.z"];
            } else {
                [card setValue:[NSNumber numberWithFloat: M_PI] forKeyPath:@"transform.rotation.z"];
            }
            [CATransaction commit];
        }
    }
    
    [card removeAllAnimations];
    [CATransaction begin];
    if (animated) {
        [CATransaction setAnimationDuration:fadeTime];
    } else {
        [CATransaction setDisableActions:YES];
    }
    card.contents = (id)[Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:currentCardFileName]].CGImage;
    annotationLayer.contents = (id)[UIImage imageWithContentsOfFile:currentAnnotationFileName].CGImage;
    [CATransaction commit];
    currentCard = cardNumber;
}

- (void)resetCardPool
{
    [cardPool removeAllObjects];
    for (int i = 1; i <= cards; i++) {
        [cardPool addObject:[NSNumber numberWithInteger:i]];
    }
}

- (void)resetDuoPool
{
    [duoPool removeAllObjects];
    for (int i = 1; i <= duoCards; i++) {
        [duoPool addObject:[NSNumber numberWithInteger:i]];
    }
}

- (void)initLayers
{
    card = [CALayer layer];
    card.borderWidth = 10;
    card.borderColor = [UIColor blackColor].CGColor;
    card.backgroundColor = backgroundColour.CGColor;
    card.contentsGravity = kCAGravityResizeAspect;
    
    annotationLayer = [CALayer layer];

    dynamicsDisplay = [CALayer layer];
    dynamicsDisplay.borderWidth = 10;
    dynamicsDisplay.borderColor = [UIColor blackColor].CGColor;
    dynamicsDisplay.backgroundColor = dynamicsBackgroundColour.CGColor;
    dynamicsDisplay.contentsGravity = kCAGravityResizeAspect;
    
    if (!graphicalDynamics) {
        dynamicsText = [[UILabel alloc] init];
        dynamicsText.font = [UIFont fontWithName:@"ArialMT" size:48];
        dynamicsText.textColor = dynamicsTextColour;
        dynamicsText.textAlignment = NSTextAlignmentCenter;
        [dynamicsDisplay addSublayer:dynamicsText.layer];
    }
    
    timerDisplay = [CALayer layer];
    timerDisplay.borderWidth = 10;
    timerDisplay.borderColor = [UIColor blackColor].CGColor;
    //Set this to two less than the width of both borders so that we have a slight overlap between the
    //timer bar and the frame. (This ensures we end up with no errant whitespace when the bar is full.)
    timerBorders = timerDisplay.borderWidth * 2 - 2;
    
    //If our timer is graphical we need to create our timer bar layer.
    if (timerStyle == kGraphical) {
        timerBar = [CALayer layer];
        timerBar.backgroundColor = [UIColor blackColor].CGColor;
        [timerDisplay addSublayer:timerBar];
    } else {
        timerText = [[UILabel alloc] init];
        timerText.font = [UIFont fontWithName:@"ArialMT" size:48];
        timerText.textAlignment= NSTextAlignmentCenter;
        timerText.textColor = [UIColor blackColor];
        [timerDisplay addSublayer:timerText.layer];
    }
    
    [self resizeLayers];
    
    [canvas addSublayer:card];
    [canvas addSublayer:dynamicsDisplay];
    [canvas addSublayer:timerDisplay];
    [canvas addSublayer:annotationLayer];
}

- (void)resizeLayers
{
    //Define some geometry variables. These may eventually be read from the preferences file.
    NSInteger margin = 15;
    NSInteger lowerDisplayHeight = 100;
    NSInteger leftPanelWidth = canvas.bounds.size.width * 6 / 10;
    NSInteger workingHeight = canvas.bounds.size.height - LOWER_PADDING + 10;
    
    CGFloat timerBarLength = 1;
    if (!firstLoad && timerStyle == kGraphical) {
        timerBarLength = timerBar.bounds.size.width / (timerDisplay.bounds.size.width - timerBorders);
    }
    
    card.frame = CGRectMake(margin, margin, canvas.bounds.size.width - (2 * margin), workingHeight - lowerDisplayHeight - (3 * margin));
    dynamicsDisplay.frame = CGRectMake(margin, workingHeight - lowerDisplayHeight - margin, leftPanelWidth - (1.5 * margin), lowerDisplayHeight);
    timerDisplay.frame = CGRectMake(leftPanelWidth + (0.5 * margin), workingHeight - lowerDisplayHeight - margin, canvas.bounds.size.width - leftPanelWidth - (1.5 * margin), lowerDisplayHeight);
    if (!graphicalDynamics) {
        dynamicsText.frame = CGRectMake(0, 0, dynamicsDisplay.bounds.size.width, dynamicsDisplay.bounds.size.height);
    }
    if (timerStyle == kGraphical) {
        if (UIDelegate.playerState == kStopped) {
            timerBar.frame = CGRectMake(timerDisplay.borderWidth - 1, 0, (timerDisplay.bounds.size.width - timerBorders) * timerBarLength, timerDisplay.bounds.size.height);
        } else {
            //If we're playing we need to stop our animation and set the timer bar to where it should be at the next
            //second. The animation will be started at the next tick.
            [timerBar removeAllAnimations];
            timerAdjust = UIDelegate.clockProgress - [[[workingCardOrder objectAtIndex:currentCard] objectAtIndex:0] integerValue];
            timerBar.frame = CGRectMake(timerDisplay.borderWidth - 1, 0, (timerDisplay.bounds.size.width - timerBorders) * ([[[workingCardOrder objectAtIndex:currentCard] objectAtIndex:2] integerValue] - timerAdjust - 1) / (CGFloat)([[[workingCardOrder objectAtIndex:currentCard] objectAtIndex:2] integerValue] - 1), timerDisplay.bounds.size.height);
            startTimer = YES;
        }
    } else {
        timerText.frame = CGRectMake(0, 0, timerDisplay.bounds.size.width, timerDisplay.bounds.size.height);
    }
    
    annotationLayer.frame = CGRectMake(0, 0, canvas.bounds.size.width, canvas.bounds.size.height - LOWER_PADDING);
}

#pragma mark - Renderer delegate

- (void)setIsMaster:(BOOL)master
{
    isMaster = master;
    
    if (!isMaster && !ordered && (duoCards > 0 || syncCards)) {
        //Client connecting for the first time.
        hasData = NO;
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"CardsRequest"];
        [messagingDelegate sendData:message];
    }
}

- (BOOL)isMaster
{
    return isMaster;
}

- (void)setDetached:(BOOL)isDetached
{
    detached = isDetached;
    if (!detached) {
        workingCardOrder = latestCardOrder;
    }
}

- (BOOL)detached
{
    return detached;
}

+ (RendererFeatures)getRendererRequirements
{
    return kPositiveDuration | kFileName | kPrefsFile;
}

+ (UIImage *)generateThumbnailForScore:(Score *)score ofSize:(CGSize)size
{
    return [Renderer defaultThumbnail:[score.scorePath stringByAppendingPathComponent:score.fileName] ofSize:size];
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    
    isMaster = YES;
    hasData = YES;
    newCardOrder = NO;
    score = scoreData;
    canvas = playerCanvas;
    UIDelegate = UIDel;
    messagingDelegate = messagingDel;
    
    //delegate.clockVisible = NO;
    UIDelegate.resetViewOnFinish = NO;
    UIDelegate.allowClockVisibilityChange = YES;
    firstLoad = YES;
    
    timerStyle = kGraphical;
    counterOffset = 0;
    startTimer = NO;
    hideTimer = NO;
    graphicalDynamics = NO;
    dynamics = [[NSMutableArray alloc] init];
    minDisplay = 0;
    maxDisplay = 0;
    fadeTime = 0;
    cards = 0;
    duoCards = 0;
    currentPart = 0;
    currentCard = -1;
    //TODO: Just write the god damned code to read this from the preferences file already, you fucking lazy muppet!
    //Update: Done! But I'm leaving this here as a default, so get off my case!
    duoPercentage = 25;
    backgroundColour = [UIColor whiteColor];
    dynamicsBackgroundColour = [UIColor whiteColor];
    dynamicsTextColour = [UIColor blackColor];
    
    allowUpsideDown = NO;
    allowRepeats = NO;
    ordered = NO;
    syncCards = NO;
    
    annotationsDirectory = [Renderer getAnnotationsDirectoryForScore:score];
    if (annotationsDirectory != nil) {
        UIDelegate.canAnnotate = YES;
    }
    detached = NO;
    
    //Load our preferences
    NSData *prefsData = [[NSData alloc] initWithContentsOfFile:[score.scorePath stringByAppendingPathComponent:score.prefsFile]];
    xmlParser = [[NSXMLParser alloc] initWithData:prefsData];
    
    isData = NO;
    currentPrefs = kTopLevel;
    prefsLoaded = NO;
    prefsCondition = [NSCondition new];
    badPrefs = NO;
    xmlParser.delegate = self;
    [xmlParser parse];
    
    return self;
}

- (void)reset
{
    [prefsCondition lock];
    while (!prefsLoaded) {
        [prefsCondition wait];
    }
    [prefsCondition unlock];
    
    if (badPrefs) {
        [UIDelegate badPreferencesFile:errorMessage];
        return;
    }
    
    if (firstLoad) {
        [self initLayers];
        if ((duoCards > 0 || syncCards) && !ordered && isMaster) {
            latestCardOrder = [self generateCardOrderWithDuos:(duoCards > 0) fromTime:0 toTime:UIDelegate.clockDuration];
            workingCardOrder = latestCardOrder;
            
            OSCMessage *message = [self generateDuoMessageAsNew:YES];
            [messagingDelegate sendData:message];
            
            //Since this data doesn't change unless there's a duration change, save a copy so we
            //don't have to generate it later.
            duoMessage = [[OSCMessage alloc] init];
            [duoMessage copyAddressFromMessage:message];
            [duoMessage appendArgumentsFromMessage:message];
            [duoMessage replaceArgumentAtIndex:0 withString:@"Refresh"];
        } else if (!ordered && !syncCards) {
            latestCardOrder = [self generateCardOrderWithDuos:NO fromTime:0 toTime:UIDelegate.clockDuration];
            workingCardOrder = latestCardOrder;
        }
        firstLoad = NO;
    }
    
    [self displayCard:0 animated:NO];
    
    if (timerStyle == kGraphical) {
        [timerBar removeAllAnimations];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        timerBar.frame = CGRectMake(timerDisplay.borderWidth - 1, 0, timerDisplay.bounds.size.width - timerBorders, timerDisplay.bounds.size.height);
        [CATransaction commit];
    } else {
        countdownRemaining = [[[workingCardOrder objectAtIndex:0] objectAtIndex:2] intValue];
        timerText.text = [NSString stringWithFormat:@"%i", countdownRemaining + counterOffset];
    }
    timerAdjust = 0;
}

- (void)play
{
    startTimer = YES;
}

- (void)stop
{
    if (timerStyle == kGraphical) {
        [timerBar removeAllAnimations];
    }
    if (fadeTime > 0) {
        [card removeAllAnimations];
        [annotationLayer removeAllAnimations];
    }
}

- (void)seek:(CGFloat)location
{
    if (timerStyle == kGraphical) {
        [timerBar removeAllAnimations];
    }
    
    //If we're at the end, clear the card and dynamics display.
    if (location == 1) {
        card.contents = nil;
        if (graphicalDynamics) {
            dynamicsDisplay.contents = nil;
        } else {
            dynamicsText.text = @"";
        }
        //Set the current card variable to show that we're not currently displaying a valid card.
        timerBar.frame = CGRectMake(10, 0, 0, timerDisplay.bounds.size.height);
        currentCard = -1;
        return;
    }
    
    int progress = roundf(location * UIDelegate.clockDuration);
    
    int newCard = 0;
    while ((newCard < [workingCardOrder count]) && ([[[workingCardOrder objectAtIndex:newCard] objectAtIndex:0] integerValue] <= progress)) {
        newCard++;
    }
    
    newCard--;
    
    if ((newCard != currentCard) || newCardOrder) {
        [self displayCard:newCard animated:NO];
        newCardOrder = NO;
    }
    
    if (timerStyle == kGraphical) {
        timerAdjust = progress - [[[workingCardOrder objectAtIndex:newCard] objectAtIndex:0] integerValue];
        //There's a special case where the timer bar will leak outside the left edge of the display at the end of
        //the score. Make sure we account for that first.
        //if (location == 1) {
            //timerBar.frame = CGRectMake(10, 0, 0, timerDisplay.bounds.size.height);
        //} else {
        timerBar.frame = CGRectMake(timerDisplay.borderWidth - 1, 0, (timerDisplay.bounds.size.width - timerBorders) * ([[[workingCardOrder objectAtIndex:newCard] objectAtIndex:2] integerValue] - timerAdjust - 1) / (CGFloat)([[[workingCardOrder objectAtIndex:newCard] objectAtIndex:2] integerValue] - 1), timerDisplay.bounds.size.height);
        if (UIDelegate.playerState == kPlaying) {
            startTimer = YES;
        }
    } else {
        countdownRemaining = [[[workingCardOrder objectAtIndex:newCard] objectAtIndex:2] intValue] - (progress - [[[workingCardOrder objectAtIndex:newCard] objectAtIndex:0] intValue]);
        timerText.text = [NSString stringWithFormat:@"%i", countdownRemaining + counterOffset];
    }

}

- (void)changeDuration:(CGFloat)duration
{
    if (ordered) {
        //Currently we're just adjusting the duration of the final card. We should make this
        //more sophisticated.
        NSInteger finalDuration = duration - [[prescribedChanges objectAtIndex:[prescribedChanges count] - 1] integerValue];
        [[latestCardOrder objectAtIndex:[latestCardOrder count] - 1] replaceObjectAtIndex:2 withObject:[NSNumber numberWithInteger:finalDuration]];
        if (!detached) {
            workingCardOrder = latestCardOrder;
        }
        return;
    }
    
    //We only need to generate new material here if we're not using duo cards or are the master
    if (isMaster || (duoCards == 0)) {
        if (duoCards > 0) {
            duoMessage = nil;
            latestCardOrder = [self generateCardOrderWithDuos:YES fromTime:0 toTime:duration];
            
            OSCMessage *message = [self generateDuoMessageAsNew:YES];
            [messagingDelegate sendData:message];
            
            duoMessage = [[OSCMessage alloc] init];
            [duoMessage copyAddressFromMessage:message];
            [duoMessage appendArgumentsFromMessage:message];
            [duoMessage replaceArgumentAtIndex:0 withString:@"Refresh"];
        } else {
            latestCardOrder = [self generateCardOrderWithDuos:NO fromTime:0 toTime:duration];
        }
        
        //Update our display to make sure we're showing the right card.
        newCardOrder = YES;
        if (!detached) {
            workingCardOrder = latestCardOrder;
            [self seek:UIDelegate.clockLocation];
        }
    }
}

- (void)rotate
{
    [self resizeLayers];
}

- (void)receiveMessage:(OSCMessage *)message
{
    //Don't do anything here if we have a specified order.
    if (ordered) {
        return;
    }
    
    if (isMaster) {
        if ([message.address count] < 1) {
            return;
        }
        if ([[message.address objectAtIndex:0] isEqualToString:@"CardsRequest"]) {
            if (duoMessage != nil) {
                [messagingDelegate sendData:duoMessage];
            } else {
                duoMessage = [self generateDuoMessageAsNew:NO];
                [messagingDelegate sendData:duoMessage];
            }
        }
    } else {
        if ([[message.address objectAtIndex:0] isEqualToString:@"DuoCards"]) {
            if (![message.typeTag hasPrefix:@",s"]) {
                return;
            }
            
            if (!hasData || [[message.arguments objectAtIndex:0] isEqualToString:@"New"]) {
                //First check that we have the right number and type of arguments.
                NSString *typeTag = [message.typeTag substringFromIndex:2];
                NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"i"] invertedSet];
                if (([typeTag rangeOfCharacterFromSet:invalidTags].location != NSNotFound) || ([typeTag length] % 5 != 0)) {
                    return;
                }
                
                NSInteger currentLocation = 0;
                //Initialise our card order array.
                latestCardOrder = [[NSMutableArray alloc] init];
                for (int i = 0; i < [typeTag length] / 5; i++) {
                    NSInteger nextDuoLocation = [[message.arguments objectAtIndex:(5 * i) + 1] integerValue];
                    if (currentLocation < nextDuoLocation) {
                        //We have space to fill with non duo cards.
                        [latestCardOrder addObjectsFromArray:[self generateCardOrderWithDuos:NO fromTime:currentLocation toTime:nextDuoLocation]];
                    }
                    
                    NSMutableArray *duoCard = [[NSMutableArray alloc] init];
                    for (int j = 1; j < 6; j++) {
                        [duoCard addObject:[message.arguments objectAtIndex:(5 * i) + j]];
                    }
                    [latestCardOrder addObject:duoCard];
                    
                    currentLocation = nextDuoLocation + [[message.arguments objectAtIndex:(5 * i) + 3] integerValue];
                }
                
                //Check to see if there is any space at the end left to fill.
                if (currentLocation < UIDelegate.clockDuration) {
                    [latestCardOrder addObjectsFromArray:[self generateCardOrderWithDuos:NO fromTime:currentLocation toTime:UIDelegate.clockDuration]];
                }
                
                //Use a seek operation to check that we're on the right card.
                newCardOrder = YES;
                if (!detached) {
                    workingCardOrder = latestCardOrder;
                    [self seek:UIDelegate.clockLocation];
                }
                hasData = YES;
            }
        }
    }
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    if (startTimer && timerStyle == kGraphical) {
        //Start our timer animation if needed.
        [CATransaction begin];
        [CATransaction setAnimationDuration:[[[workingCardOrder objectAtIndex:currentCard] objectAtIndex:2] integerValue] - 1 - timerAdjust];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
        timerBar.frame = CGRectMake(10, 0, 0, timerDisplay.bounds.size.height);
        [CATransaction commit];
        timerAdjust = 0;
        startTimer = NO;
    } else if (timerStyle == kNumerical) {
        countdownRemaining--;
        if (countdownRemaining > 0) {
            //Don't change our text here if the countdown is at zero. We need to reset it to the next
            //card duration later in the function.
            timerText.text = [NSString stringWithFormat:@"%i", countdownRemaining + counterOffset];
        }
    }
    
    //If we're finished, clear the card space.
    if (finished) {
        card.contents = nil;
        if (graphicalDynamics) {
            dynamicsDisplay.contents = nil;
        } else {
            dynamicsText.text = @"";
        }
        if (timerStyle == kNumerical) {
            timerText.text = @"";
        }
        //Set the current card variable to show that we're not currently displaying a valid card.
        currentCard = -1;
        return;
    }
    
    //If we're on the last card, then there's nothing left to do here.
    if (currentCard == [workingCardOrder count] - 1) {
        return;
    }
    
    if (progress >= [[[workingCardOrder objectAtIndex:currentCard + 1] objectAtIndex:0] intValue]) {
        //Change to our next card if it's time and reset our timer display.
        if (fadeTime > 0) {
            [self displayCard:currentCard + 1 animated:YES];
        } else {
            [self displayCard:currentCard + 1 animated:NO];
        }
        if (timerStyle == kGraphical) {
            [timerBar removeAllAnimations];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            timerBar.frame = CGRectMake(timerDisplay.borderWidth - 1, 0, timerDisplay.bounds.size.width - timerBorders, timerDisplay.bounds.size.height);
            [CATransaction commit];
            
            startTimer = YES;
        } else {
            countdownRemaining = [[[workingCardOrder objectAtIndex:currentCard] objectAtIndex:2] intValue];
            timerText.text = [NSString stringWithFormat:@"%i", countdownRemaining + counterOffset];
        }
    }
}

- (UIImage *)currentAnnotationImage
{
    CGSize sizeWithoutPadding = CGSizeMake(canvas.bounds.size.width, canvas.bounds.size.height - LOWER_PADDING);
    UIGraphicsBeginImageContextWithOptions(canvas.bounds.size, NO, 1);
    UIImage *content = [UIImage imageWithContentsOfFile:currentAnnotationFileName];
    [content drawInRect:CGRectMake(0, 0, sizeWithoutPadding.width, sizeWithoutPadding.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)saveCurrentAnnotation:(UIImage *)image
{
    //Use our portrait size for our saved image.
    CGSize portraitSize = CGSizeMake(MIN(canvas.bounds.size.width, canvas.bounds.size.height), MAX(canvas.bounds.size.width, canvas.bounds.size.height));
    CGSize sizeWithoutPadding = CGSizeMake(portraitSize.width, portraitSize.height - roundf(LOWER_PADDING * canvas.bounds.size.width / portraitSize.width));
    UIGraphicsBeginImageContextWithOptions(sizeWithoutPadding, NO, 1);
    [image drawInRect:CGRectMake(0, 0, portraitSize.width, portraitSize.height)];
    UIImage *annotations = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    annotationLayer.contents = (id)annotations.CGImage;
    [UIImagePNGRepresentation(annotations) writeToFile:currentAnnotationFileName atomically:YES];
}

- (void)hideSavedAnnotations:(BOOL)hide
{
    if (hide) {
        annotationLayer.opacity = 0;
    } else {
        annotationLayer.opacity = 1;
    }
}

- (void)swipeUp
{
    if ([score.parts count] > 0) {
        [self changePart:1];
        [UIDelegate partChangedToPart:currentPart];
    }
}

- (void)swipeDown
{
    if ([score.parts count] > 0) {
        [self changePart:-1];
        [UIDelegate partChangedToPart:currentPart];
    }
}

- (void)tapAt:(CGPoint)location
{
    if (!hideTimer) {
        if (location.y > card.bounds.size.height + 30) {
            hideTimer = YES;
            dynamicsDisplay.opacity = 0;
            timerDisplay.opacity = 0;
        }
    } else {
        hideTimer = NO;
        dynamicsDisplay.opacity = 1;
        timerDisplay.opacity = 1;
    }
}

#pragma mark NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    //Determine which section of the preferences file we're in, and only parse elements that belong.
    if (currentPrefs == kTopLevel) {
        if ([elementName isEqualToString:@"timer"]) {
            currentPrefs = kTimer;
        } else if ([elementName isEqualToString:@"dynamics"]) {
            currentPrefs = kDynamics;
        } else if ([elementName isEqualToString:@"duo"]) {
            currentPrefs = kDuo;
        } else if ([elementName isEqualToString:@"order"]) {
            currentPrefs = kOrder;
            prescribedChanges = [[NSMutableArray alloc] init];
            ordered = YES;
        } else if ([elementName isEqualToString:@"quantity"] || [elementName isEqualToString:@"upsidedown"] || [elementName isEqualToString:@"allowrepeats"] || [elementName isEqualToString:@"fadetime"] || [elementName isEqualToString:@"backgroundrgb"] || [elementName isEqualToString:@"synccards"]) {
            isData = YES;
            currentString = nil;
        }
    } else {
        isData = YES;
        currentString = nil;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (isData) {
        if (currentString == nil) {
            currentString = [[NSMutableString alloc] initWithString:string];
        } else {
            [currentString appendString:string];
        }
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    //Read our preferences. We should do basic checks on completing each section, but will check that
    //we have all our necessary resource files once parsing has completed.
    
    switch (currentPrefs) {
            
        case kTopLevel:
            if ([elementName isEqualToString:@"quantity"]) {
                cards = [currentString integerValue];
                if (cards <= 0) {
                    badPrefs = YES;
                    errorMessage = @"Number of flash cards not properly specified.";
                }
            } else if ([elementName isEqualToString:@"upsidedown"]) {
                if (currentString != nil && [currentString caseInsensitiveCompare:@"yes"] == NSOrderedSame) {
                    allowUpsideDown = YES;
                }
            } else if ([elementName isEqualToString:@"allowrepeats"]) {
                if (currentString != nil && [currentString caseInsensitiveCompare:@"yes"] == NSOrderedSame) {
                    allowRepeats = YES;
                }
            } else if ([elementName isEqualToString:@"fadetime"]) {
                fadeTime = [currentString integerValue];
            } else if ([elementName isEqualToString:@"backgroundrgb"]) {
                NSArray *colour = [currentString componentsSeparatedByString:@","];
                //Check that we have three colour components in our array
                if ([colour count] == 3) {
                    CGFloat r = [[colour objectAtIndex:0] intValue] & 255;
                    CGFloat g = [[colour objectAtIndex:1] intValue] & 255;
                    CGFloat b = [[colour objectAtIndex:2] intValue] & 255;
                    backgroundColour = [UIColor colorWithRed:(r / 255) green:(g / 255) blue:(b / 255) alpha:1];
                }
            } else if ([elementName isEqualToString:@"synccards"]) {
                if (currentString != nil && [currentString caseInsensitiveCompare:@"yes"] == NSOrderedSame) {
                    syncCards = YES;
                }
            }
            break;
            
        case kTimer:
            if ([elementName isEqualToString:@"mindisplay"]) {
                minDisplay = [currentString integerValue];
            } else if ([elementName isEqualToString:@"maxdisplay"]) {
                maxDisplay = [currentString integerValue];
            } else if ([elementName isEqualToString:@"style"]) {
                if (currentString != nil && [currentString caseInsensitiveCompare:@"numerical"] == NSOrderedSame) {
                    timerStyle = kNumerical;
                }
            } else if ([elementName isEqualToString:@"counteroffset"]) {
                counterOffset = [currentString intValue];
            } else if ([elementName isEqualToString:@"timer"]) {
                currentPrefs = kTopLevel;
            }
            break;
            
        case kDynamics:
            if ([elementName isEqualToString:@"graphical"]) {
                if (currentString != nil && [currentString caseInsensitiveCompare:@"yes"] == NSOrderedSame) {
                    graphicalDynamics = YES;
                }
            } else if ([elementName isEqualToString:@"dynamic"]) {
                if (currentString != nil) {
                    [dynamics addObject:[NSString stringWithString:currentString]];
                }
            } else if ([elementName isEqualToString:@"dynamics"]) {
                currentPrefs = kTopLevel;
            } else if ([elementName isEqualToString:@"backgroundrgb"] || [elementName isEqualToString:@"textrgb"]) {
                NSArray *colour = [currentString componentsSeparatedByString:@","];
                //Check that we have three colour components in our array
                if ([colour count] == 3) {
                    CGFloat r = [[colour objectAtIndex:0] intValue] & 255;
                    CGFloat g = [[colour objectAtIndex:1] intValue] & 255;
                    CGFloat b = [[colour objectAtIndex:2] intValue] & 255;
                    if ([elementName isEqualToString:@"backgroundrgb"]) {
                        dynamicsBackgroundColour = [UIColor colorWithRed:(r / 255) green:(g / 255) blue:(b / 255) alpha:1];
                    } else {
                        dynamicsTextColour = [UIColor colorWithRed:(r / 255) green:(g / 255) blue:(b / 255) alpha:1];
                    }
                }
            }
            break;
            
        case kDuo:
            if ([elementName isEqualToString:@"quantity"]) {
                duoCards = [currentString integerValue];
                if (duoCards < 0) {
                    //If we have a non positive value, disable the use of duo cards.
                    duoCards = 0;
                }
            } else if ([elementName isEqualToString:@"filename"]) {
                duoFileName = [NSString stringWithString:currentString];
            } else if ([elementName isEqualToString:@"probability"]) {
                CGFloat probability = [currentString floatValue];
                //Check that we have a sane value for our probability and correct it if we don't.
                if (probability > 1) {
                    probability = 1;
                } else if (probability < 0) {
                    probability = 0;
                }
                duoPercentage = 100 * probability;
            } else if ([elementName isEqualToString:@"duo"]) {
                currentPrefs = kTopLevel;
            }
            break;
            
        case kOrder:
            if ([elementName isEqualToString:@"change"]) {
                [prescribedChanges addObject:[NSNumber numberWithInteger:[currentString integerValue]]];
            } else if ([elementName isEqualToString:@"order"]) {
                currentPrefs = kTopLevel;
                [prescribedChanges sortUsingSelector:@selector(compare:)];
            }
            break;
            
        default:
            break;
    }
    
    isData = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    //Check that we have all of our necessary image files.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (int i = 2; i <= cards; i++) {
        NSString *fileName = [score.scorePath stringByAppendingPathComponent:[score.fileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i]]];
        if (![fileManager fileExistsAtPath:fileName]) {
            badPrefs = YES;
            errorMessage = @"Missing images in score file.";
            i = (int)cards + 1;
        }
        
        //Perform the same checks for parts.
        for (int j = 0; j < [score.parts count]; j++) {
            NSString *fileName = [score.scorePath stringByAppendingPathComponent:[[score.parts objectAtIndex:j] stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i]]];
            if (![fileManager fileExistsAtPath:fileName]) {
                badPrefs = YES;
                errorMessage = @"Missing images in score file.";
                i = (int)cards + 1;
                j = (uint)[score.parts count];
            }
        }
    }
    
    //Now check duo files if we need to.
    if (!badPrefs && duoCards > 0) {
        for (int i = 1; i <= duoCards; i++) {
            NSString *fileName = [score.scorePath stringByAppendingPathComponent:[duoFileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i]]];
            if (![fileManager fileExistsAtPath:fileName]) {
                badPrefs = YES;
                errorMessage = @"Missing images in score file.";
                i = (int)duoCards + 1;
            }
        }
        duoPool = [[NSMutableArray alloc] init];
        [self resetDuoPool];
    }
    
    //Check if we should respect any prescribed order, and set up our array of cards.
    //Currently this ignores duo cards (as it should), dynamics and orientation.
    if (ordered) {
        if ([prescribedChanges count] != cards - 1) {
            ordered = NO;
        } else {
            latestCardOrder = [[NSMutableArray alloc] init];
            
            NSMutableArray *nextCard = [[NSMutableArray alloc] init];
            [nextCard addObject:[NSNumber numberWithInteger:0]];
            [nextCard addObject:[NSNumber numberWithInteger:1]];
            [nextCard addObject:[prescribedChanges objectAtIndex:0]];
            [nextCard addObject:[NSNumber numberWithInteger:0]];
            [nextCard addObject:[NSNumber numberWithInteger:0]];
            [latestCardOrder addObject:nextCard];
            
            for (int i = 1; i <= [prescribedChanges count]; i++) {
                NSMutableArray *nextCard = [[NSMutableArray alloc] init];
                [nextCard addObject:[prescribedChanges objectAtIndex:i - 1]];
                [nextCard addObject:[NSNumber numberWithInteger:i + 1]];
                NSInteger duration;
                if (i < [prescribedChanges count]) {
                    duration = [[prescribedChanges objectAtIndex:i] integerValue] - [[prescribedChanges objectAtIndex:i - 1] integerValue];
                } else {
                    duration = UIDelegate.clockDuration - [[prescribedChanges objectAtIndex:i - 1] integerValue];
                }
                [nextCard addObject:[NSNumber numberWithInteger:duration]];
                [nextCard addObject:[NSNumber numberWithInteger:0]];
                [nextCard addObject:[NSNumber numberWithInteger:0]];
                [latestCardOrder addObject:nextCard];
            }
            workingCardOrder = latestCardOrder;
        }
    }
    
    if (!ordered) {
        //Check our minimum and maximum display times.
        if (minDisplay <= 0 || maxDisplay <= 0) {
            badPrefs = YES;
            errorMessage = @"Flash card display times must be greater than 0.";
        } else {
            if (maxDisplay < minDisplay) {
                maxDisplay = minDisplay;
            }
        }
    }
    
    cardPool = [[NSMutableArray alloc] init];
    [self resetCardPool];
    [prefsCondition lock];
    prefsLoaded = YES;
    [prefsCondition signal];
    [prefsCondition unlock];
    parser.delegate = nil;
    xmlParser = nil;
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    badPrefs = YES;
    errorMessage = @"Damaged preferences file.";
    parser.delegate = nil;
    xmlParser = nil;
    [prefsCondition lock];
    prefsLoaded = YES;
    [prefsCondition signal];
    [prefsCondition unlock];
}

@end

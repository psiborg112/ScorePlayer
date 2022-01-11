//
//  Cage.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 15/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "Cage.h"
#import "Score.h"
#import "OSCMessage.h"
#import "CageEvent.h"
#import "CageSlide.h"
#import "TalkingBoard.h"

@interface Cage ()

//These methods are used for both Variation 1 and 2
- (void)variation1Reset;
- (void)variation1Play;
- (void)variation1Seek:(CGFloat)location;
- (void)variation1ChangeDuration:(CGFloat)duration;
- (void)variation1Rotate;
- (void)scrollerAnimate;
//Variation 1
- (void)initSlides;
- (void)randomizeSlideOrder;
- (void)generate1Events:(CGFloat)duration;
//Variation 2
- (CageSlide *)generate2Slide;
- (void)generate2Events:(CGFloat)duration;
//Both
- (void)renderEvents;

- (void)variation3Reset;
- (void)variation3ReceiveMessage:(OSCMessage *)message;
- (void)generateCircles;
- (void)renderCircles;
- (void)removeCircles;

- (void)variation4Reset;
- (void)variation4ReceiveMessage:(OSCMessage *)message;
- (void)generate4Data;
- (void)render4;
- (void)drawLines;

- (void)variation6Reset;
- (void)variation6ReceiveMessage:(OSCMessage *)message;
- (void)generate6Data;
- (void)render6;

- (CGFloat)getPerpendicularDistance:(Dot)dot toLine:(Line)line;
- (NSMutableArray *)generatePoints:(int)numberOfPoints withMargin:(int)margin;

- (OSCMessage *)generateCirclesMessageAsNew:(BOOL)new;
- (OSCMessage *)generateObjectMessageAsNew:(BOOL)new;

- (void)receiveInitialData:(OSCMessage *)data fromNetwork:(BOOL)fromNet;

@end

@implementation Cage {
    //General
    Score *score;
    Score *variation5Score;
    CALayer *canvas;
    
    NSInteger currentVariation;
    BOOL variationPlayed;
    BOOL fullReset;
    BOOL canGoBack;
    int heightAdjust;
    BOOL badPrefs;
    NSString *errorMessage;
    
    CGFloat variation1Duration;
    CGFloat variation2Duration;
    CGFloat variation5Duration;
    int performers;
    
    //Variation 1 and 2 specific
    CALayer *readLine;
    CALayer *scroller;
    NSTimer *scrollTimer;
    NSMutableArray *lineSlides;
    CageSlide *dotSlide;
    NSMutableArray *events;
    
    NSMutableArray *rawStarts;
    NSMutableArray *rawFrequencies;
    NSMutableArray *rawDurations;
    NSMutableArray *rawTimbres;
    NSMutableArray *rawDynamics;
    NSMutableArray *rawEventNumbers;
    
    CGFloat maxRawStart;
    CGFloat maxRawFrequency;
    CGFloat maxRawDuration;
    CGFloat maxRawTimbre;
    CGFloat maxRawDynamic;
    CGFloat maxRawEventNumbers;
    
    int minDuration[2];
    int maxDuration[2];
    int density[2];
    int yMin;
    int yMax;
    int readLineOffset;
    
    //Variation 3 specific
    int numCircles;
    int radius;
    int biggestGroup;
    
    NSMutableArray *circles;
    NSMutableArray *groupMembership;
    
    NSTimer *fadeTimer;
    
    //Variation 4 and 6 specific
    CALayer *background;
    NSMutableArray *locations;
    NSMutableArray *rotations; //Variation 6 only
    
    //Variation 4 specific
    int circleRadius;
    int pointRadius;
    CALayer *centreCircle;
    NSMutableArray *lines;
    
    //Variation 6 specific
    NSMutableArray *objectNumbers;
    NSMutableArray *objectTypes;
    
    //Variation 5 (bootstrapped talking board)
    TalkingBoard *talkingBoard;
    
    //Networking
    BOOL hasData;
    BOOL renderOK;
    BOOL awaitingVariation;
    BOOL awaitingSeek;
    
    BOOL debug;
    
    //Parser
    CageParser *parser;
    BOOL prefsLoaded;
    NSCondition *prefsCondition;
    BOOL optionsSet;
    
    __weak id<RendererUI> UIDelegate;
    __weak id<RendererMessaging> messagingDelegate;
}

- (void)variation1Reset
{
    [scrollTimer invalidate];
    canvas.sublayers = nil;
    
    //Reading line
    readLine = [CALayer layer];
    readLine.anchorPoint = CGPointMake(0.5, 0);
	readLine.bounds = CGRectMake(0, 0, 4, MAX(canvas.bounds.size.width, canvas.bounds.size.height));
    readLine.position = CGPointMake(readLineOffset, 0);
    if (score.variationNumber == -1 && currentVariation == 2) {
        readLine.backgroundColor = [UIColor blueColor].CGColor;
    } else {
        readLine.backgroundColor = [UIColor orangeColor].CGColor;
    }
	[canvas addSublayer:readLine];
    
    //Create scrolling layer and populate it with the necessary sublayers
    if (!scroller) {
        scroller = [CALayer layer];
        scroller.anchorPoint = CGPointZero;
        scroller.bounds = CGRectMake(0, 0, CAGE_FRAMERATE * UIDelegate.clockDuration, canvas.bounds.size.height - LOWER_PADDING);
    }
    
    scroller.sublayers = nil;
    [scroller removeAllAnimations];
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    scroller.position = CGPointMake(readLineOffset, 0);
    [CATransaction commit];
    
    if (currentVariation == 1) {
        //Variation 1 specific code
        [self generate1Events:UIDelegate.clockDuration];
    } else {
        //Variation 2 specific code
        [self generate2Events:UIDelegate.clockDuration];
    }
    [self renderEvents];
    
    [canvas insertSublayer:scroller below:readLine];
    
}

- (void)variation1Play
{
    scrollTimer = [NSTimer scheduledTimerWithTimeInterval:(1 / (float)CAGE_FRAMERATE) target:self selector:@selector(scrollerAnimate) userInfo:nil repeats:YES];
}

- (void)variation1Seek:(CGFloat)location
{
    scroller.position = CGPointMake(readLineOffset - (scroller.bounds.size.width * location), 0);
}

- (void)variation1ChangeDuration:(CGFloat)duration
{
    scroller.bounds = CGRectMake(0, 0, CAGE_FRAMERATE * duration, scroller.bounds.size.height);
    
    //Remove all the events before regenerating them for the new score size.
    for (int i = 0; i < [events count]; i++) {
        [((CageEvent *)[events objectAtIndex:i]).layer removeFromSuperlayer];
    }
    
    [scroller removeAllAnimations];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self variation1Seek:UIDelegate.clockLocation];
    [CATransaction commit];
    
    if (currentVariation == 1) {
        [self generate1Events:duration];
    } else {
        [self generate2Events:duration];
    }
    if (score.variationNumber != -1 || !variationPlayed) {
        [self renderEvents];
    }
}

- (void)variation1Rotate
{
    //Adjust the vertical position of the events to fit to the height of the screen.
    yMax = (canvas.bounds.size.height - LOWER_PADDING - 30);
    scroller.bounds = CGRectMake(0, 0, scroller.bounds.size.width, canvas.bounds.size.height - LOWER_PADDING);
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    for (int i = 0; i < [events count]; i++) {
        CGFloat y = roundf((maxRawFrequency - [[rawFrequencies objectAtIndex:i] floatValue]) / maxRawFrequency * (yMax - yMin) + yMin);
        ((CageEvent *)[events objectAtIndex:i]).layer.position = CGPointMake(((CageEvent *)[events objectAtIndex:i]).layer.position.x, y);
    }
    
    [CATransaction commit];
}

- (void)scrollerAnimate
{
    [CATransaction begin];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    scroller.position = CGPointMake(scroller.position.x - 1, 0);
    [CATransaction commit];
    if (scroller.position.x <= 150 - scroller.bounds.size.width) {
        [scrollTimer invalidate];
    }
}

- (void)initSlides
{
    lineSlides = [[NSMutableArray alloc] initWithCapacity:5];
    
    CageSlide *slide = [[CageSlide alloc] initWithWidth:440 height:620];
    [slide addLine:LineMake(242, 113, 413, 298)];
    [slide addLine:LineMake(413, 305, 127, 533)];
    [slide addLine:LineMake(202, 113, 134, 534)];
    [slide addLine:LineMake(412, 331, 1, 358)];
    [slide addLine:LineMake(1, 129, 60, 531)];
    [lineSlides addObject:slide];
    
    slide = [[CageSlide alloc] initWithWidth:440 height:620];
    [slide addLine:LineMake(141, 45, 430, 432)];
    [slide addLine:LineMake(103, 47, 214, 467)];
    [slide addLine:LineMake(434, 88, 10, 300)];
    [slide addLine:LineMake(12, 175, 433, 231)];
    [slide addLine:LineMake(11, 269, 299, 470)];
    [lineSlides addObject:slide];
    
    slide = [[CageSlide alloc] initWithWidth:440 height:620];
    [slide addLine:LineMake(187, 55, 265, 478)];
    [slide addLine:LineMake(428, 91, 85, 480)];
    [slide addLine:LineMake(428, 108, 3, 264)];
    [slide addLine:LineMake(3, 126, 427, 159)];
    [slide addLine:LineMake(425, 279, 4, 349)];
    [lineSlides addObject:slide];
    
    slide = [[CageSlide alloc] initWithWidth:440 height:620];
    [slide addLine:LineMake(12, 52, 429, 430)];
    [slide addLine:LineMake(173, 49, 286, 475)];
    [slide addLine:LineMake(276, 52, 432, 333)];
    [slide addLine:LineMake(302, 52, 6, 266)];
    [slide addLine:LineMake(3, 375, 431, 370)];
    [lineSlides addObject:slide];
    
    slide = [[CageSlide alloc] initWithWidth:440 height:620];
    [slide addLine:LineMake(99, 43, 12, 254)];
    [slide addLine:LineMake(146, 36, 432, 392)];
    [slide addLine:LineMake(216, 38, 289, 462)];
    [slide addLine:LineMake(355, 41, 220, 459)];
    [slide addLine:LineMake(434, 349, 33, 456)];
    [lineSlides addObject:slide];
    
    dotSlide = [[CageSlide alloc] initWithWidth:440 height:620];
    [dotSlide addDot:DotMake(139, 198, 4)];
    [dotSlide addDot:DotMake(315, 200, 4)];
    [dotSlide addDot:DotMake(232, 327, 4)];
    [dotSlide addDot:DotMake(402, 374, 4)];
    [dotSlide addDot:DotMake(61, 232, 3)];
    [dotSlide addDot:DotMake(120, 106, 3)];
    [dotSlide addDot:DotMake(396, 281, 3)];
    [dotSlide addDot:DotMake(157, 81, 2)];
    [dotSlide addDot:DotMake(289, 86, 2)];
    [dotSlide addDot:DotMake(335, 289, 2)];
    [dotSlide addDot:DotMake(42, 310, 2)];
    [dotSlide addDot:DotMake(235, 348, 2)];
    [dotSlide addDot:DotMake(92, 365, 2)];
    [dotSlide addDot:DotMake(380, 376, 2)];
    [dotSlide addDot:DotMake(114, 302, 1)];
    [dotSlide addDot:DotMake(139, 229, 1)];
    [dotSlide addDot:DotMake(149, 414, 1)];
    [dotSlide addDot:DotMake(171, 261, 1)];
    [dotSlide addDot:DotMake(190, 162, 1)];
    [dotSlide addDot:DotMake(187, 410, 1)];
    [dotSlide addDot:DotMake(242, 74, 1)];
    [dotSlide addDot:DotMake(244, 313, 1)];
    [dotSlide addDot:DotMake(262, 268, 1)];
    [dotSlide addDot:DotMake(271, 205, 1)];
    [dotSlide addDot:DotMake(303, 236, 1)];
    [dotSlide addDot:DotMake(312, 430, 1)];
    [dotSlide addDot:DotMake(362, 211, 1)];
}

- (void)randomizeSlideOrder
{
    //Randomizes the order of the line slides
    NSMutableArray *newLineSlides = [[NSMutableArray alloc] initWithCapacity:[lineSlides count]];
    
    while ([lineSlides count] > 0) {
        int index = arc4random_uniform((int)[lineSlides count]);
        [newLineSlides addObject:[lineSlides objectAtIndex:index]];
        [lineSlides removeObjectAtIndex:index];
    }
    
    lineSlides = newLineSlides;
    
    //Now we also randomize the order of the lines on the slides.
    for (int i = 0; i < [lineSlides count]; i++) {
        [[lineSlides objectAtIndex:i] randomizeLineOrder];
    }
    
    //We don't need to randomize the dots, since their position on the score depends on their distance
    //from the appropriate line rather than on the order in which they are processed.
    //[dotSlide randomizeDotOrder];
    
    //And finally we randomly rotate or flip the slides.
    for (int i = 0; i < [lineSlides count]; i++) {
        int flip = arc4random_uniform(2);
        if (flip == 1) {
            [[lineSlides objectAtIndex:i] flip];
        }
        int rotate = arc4random_uniform(4);
        for (int j = 0; j < rotate; j++) {
            [[lineSlides objectAtIndex:i] rotate];
        }
    }
    
    int flip = arc4random_uniform(2);
    if (flip == 1) {
        [dotSlide flip];
    }
    int rotate = arc4random_uniform(4);
    for (int i = 0; i < rotate; i++) {
        [dotSlide rotate];
    }
    
}

- (void)generate1Events:(CGFloat)duration
{
    //Set up the slides
    [self initSlides];
    [self randomizeSlideOrder];
    
    if (density[0] < 5) {
        [lineSlides removeObjectsInRange:NSMakeRange(density[0], 5 - density[0])];
    }
    
    rawStarts = [[NSMutableArray alloc] initWithCapacity:([lineSlides count] * [dotSlide dotCount])];
    rawFrequencies = [[NSMutableArray alloc] initWithCapacity:([lineSlides count] * [dotSlide dotCount])];
    rawDurations = [[NSMutableArray alloc] initWithCapacity:([lineSlides count] * [dotSlide dotCount])];
    rawDynamics = [[NSMutableArray alloc] initWithCapacity:([lineSlides count] * [dotSlide dotCount])];
    rawTimbres = [[NSMutableArray alloc] initWithCapacity:([lineSlides count] * [dotSlide dotCount])];
    
    //Perform all the measurements
    for (int i = 0; i < [lineSlides count]; i++) {
        for (int j = 0; j < [dotSlide dotCount]; j++) {
            Dot currentDot = [dotSlide getDotCentredZero:j];
            [rawStarts addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[[lineSlides objectAtIndex:i] getLineCentredZero:0]]]];
            [rawFrequencies addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[[lineSlides objectAtIndex:i] getLineCentredZero:1]]]];
            [rawDurations addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[[lineSlides objectAtIndex:i] getLineCentredZero:2]]]];
            [rawDynamics addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[[lineSlides objectAtIndex:i] getLineCentredZero:3]]]];
            [rawTimbres addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[[lineSlides objectAtIndex:i] getLineCentredZero:4]]]];
        }
    }
    
    //Find the maximums
    maxRawFrequency = [[rawFrequencies valueForKeyPath:@"@max.floatValue"] floatValue];
    maxRawDuration = [[rawDurations valueForKeyPath:@"@max.floatValue"] floatValue];
    maxRawDynamic = [[rawDynamics valueForKeyPath:@"@max.floatValue"] floatValue];
    maxRawTimbre = [[rawTimbres valueForKeyPath:@"@max.floatValue"] floatValue];
    
    events = [[NSMutableArray alloc] initWithCapacity:[rawStarts count]];
    
    //Now create the events
    for (int i = 0; i < [rawStarts count]; i++) {
        int duration = minDuration[0] + roundf((maxDuration[0] - minDuration[0]) * [[rawDurations objectAtIndex:i] floatValue] / maxRawDynamic);
        int dynamic = floorf(5 * [[rawDynamics objectAtIndex:i] floatValue] / maxRawDynamic) + 1;
        int timbre = floorf(5 * [[rawTimbres objectAtIndex:i] floatValue] / maxRawTimbre) + 1;
        NSInteger event = (int)[dotSlide getDot:(i % [dotSlide dotCount])].events;
        
        //Check bounds of our dynamic and timbre
        if (dynamic > 5) {
            dynamic = 5;
        }
        
        if (timbre > 5) {
            timbre = 5;
        }
        
        CageEvent *nextEvent = [[CageEvent alloc] initWithNumberOfEvents:event duration:duration timbre:timbre dynamics:dynamic];
        [events addObject:nextEvent];
    }
    
    //And set their locations
    for (int i = 0; i < [lineSlides count]; i++) {
        //Since the score consists of distinct sections produced by each slide, we need to
        //reset and find the maximum raw start value here.
        maxRawStart = 0;
        for (int j = 0; j < [dotSlide dotCount]; j++) {
            if ([[rawStarts objectAtIndex:(j + (i * [dotSlide dotCount]))] floatValue] > maxRawStart) {
                maxRawStart = [[rawStarts objectAtIndex:(j + (i * [dotSlide dotCount]))] floatValue];
            }
        }
        
        for (int j = 0; j < [dotSlide dotCount]; j++) {
            CGFloat x, y;
            CGFloat sectionDuration = duration * 1000 / (CGFloat)[lineSlides count]; //In milliseconds
            x = [[rawStarts objectAtIndex:(j + (i * [dotSlide dotCount]))] floatValue] / maxRawStart * (sectionDuration - maxDuration[0]);
            x += sectionDuration * i;
            x = x * CAGE_FRAMERATE / 1000;
            y = (maxRawFrequency - [[rawFrequencies objectAtIndex:(j + (i * [dotSlide dotCount]))] floatValue]) / maxRawFrequency * (yMax - yMin) + yMin;
            x = roundf(x);
            y = roundf(y);
            ((CageEvent *)[events objectAtIndex:(j + (i * [dotSlide dotCount]))]).layer.position = CGPointMake(x, y);
        }
    }
}

- (CageSlide *)generate2Slide
{
    int width = 500, height = 500;
    CageSlide *slide = [[CageSlide alloc] initWithWidth:width height:height];
    
    //Randomly generate six lines and five dots
    for (int i = 0; i < 6; i++) {
        int x1 = arc4random_uniform(width);
        int y1 = arc4random_uniform(height);
        int x2 = arc4random_uniform(width);
        int y2 = arc4random_uniform(height);
        
        //It's unlikely, but check that our line isn't just a point
        if (x1 == x2 && y1 == y2) {
            i--;
        } else {
            [slide addLine:LineMake(x1, y1, x2, y2)];
        }
    }
    
    for (int i = 0; i < 5; i++) {
        //For the moment, assign all dots an events number of 1. The true value of this will
        //be determined later using the perpendicular distance to one of our lines.
        [slide addDot:DotMake(arc4random_uniform(width), arc4random_uniform(height), 1)];
    }
    
    return slide;
}

- (void)generate2Events:(CGFloat)duration
{
    //Length of section created by each slide, in seconds.
    int sectionLength = 60 / density[1];
    
    int slideCount = duration / sectionLength;
    if ((int)duration % sectionLength != 0) {
        slideCount++;
    }
    int eventCount = slideCount * 5;
    
    events = [[NSMutableArray alloc] initWithCapacity:eventCount];
    
    rawStarts = [[NSMutableArray alloc] initWithCapacity:eventCount];
    rawFrequencies = [[NSMutableArray alloc] initWithCapacity:eventCount];
    rawDurations = [[NSMutableArray alloc] initWithCapacity:eventCount];
    rawDynamics = [[NSMutableArray alloc] initWithCapacity:eventCount];
    rawTimbres = [[NSMutableArray alloc] initWithCapacity:eventCount];
    rawEventNumbers = [[NSMutableArray alloc] initWithCapacity:eventCount];
    
    //Perform all the measurements
    for (int i = 0; i < slideCount; i++) {
        //Generate a slide
        CageSlide *currentSlide = [self generate2Slide];
        for (int j = 0; j < [currentSlide dotCount]; j++) {
            Dot currentDot = [currentSlide getDot:j];
            [rawStarts addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[currentSlide getLine:0]]]];
            [rawFrequencies addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[currentSlide getLine:1]]]];
            [rawDurations addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[currentSlide getLine:2]]]];
            [rawDynamics addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[currentSlide getLine:3]]]];
            [rawTimbres addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[currentSlide getLine:4]]]];
            [rawEventNumbers addObject:[NSNumber numberWithFloat:[self getPerpendicularDistance:currentDot toLine:[currentSlide getLine:5]]]];
        }
    }
    
    //Find the maximums
    maxRawStart = [[rawStarts valueForKeyPath:@"@max.floatValue"] floatValue];
    maxRawFrequency = [[rawFrequencies valueForKeyPath:@"@max.floatValue"] floatValue];
    maxRawDuration = [[rawDurations valueForKeyPath:@"@max.floatValue"] floatValue];
    maxRawDynamic = [[rawDynamics valueForKeyPath:@"@max.floatValue"] floatValue];
    maxRawTimbre = [[rawTimbres valueForKeyPath:@"@max.floatValue"] floatValue];
    maxRawEventNumbers = [[rawEventNumbers valueForKeyPath:@"@max.floatValue"] floatValue];
    
    //Now create the events
    for (int i = 0; i < [rawStarts count]; i++) {
        int duration = minDuration[1] + roundf((maxDuration[1] - minDuration[1]) * [[rawDurations objectAtIndex:i] floatValue] / maxRawDynamic);
        int dynamic = floorf(5 * [[rawDynamics objectAtIndex:i] floatValue] / maxRawDynamic) + 1;
        int timbre = floorf(5 * [[rawTimbres objectAtIndex:i] floatValue] / maxRawTimbre) + 1;
        int event = floorf(4 * [[rawEventNumbers objectAtIndex:i] floatValue] / maxRawEventNumbers) + 1;
        
        //Check bounds of our dynamic, timbre and event number
        if (dynamic > 5) {
            dynamic = 5;
        }
        
        if (timbre > 5) {
            timbre = 5;
        }
        
        if (event > 4) {
            event = 4;
        }
        
        CageEvent *nextEvent = [[CageEvent alloc] initWithNumberOfEvents:event duration:duration timbre:timbre dynamics:dynamic];
        [events addObject:nextEvent];
        
        //Now set their locations
        CGFloat x, y, offset;
        offset = sectionLength * (i / 5);
        
        x = offset + [[rawStarts objectAtIndex:i] floatValue] / maxRawStart * sectionLength; //In seconds
        x = x * CAGE_FRAMERATE;
        y = (maxRawFrequency - [[rawFrequencies objectAtIndex:i] floatValue]) / maxRawFrequency * (yMax - yMin) + yMin;
        x = roundf(x);
        y = roundf(y);
        nextEvent.layer.position = CGPointMake(x, y);
    }
}

- (void)renderEvents
{
    //This function only renders the events. The scroller and reading line are set up by the
    //reset function.
    for (int i = 0; i < [events count]; i++) {
        [scroller addSublayer:((CageEvent *)[events objectAtIndex:i]).layer];
    }
}

- (void)variation3Reset
{
    renderOK = NO;
    
    if (isMaster) {
        //Generate the circles
        [self generateCircles];
     
        //Send the circles to the clients
        [messagingDelegate sendData:[self generateCirclesMessageAsNew:YES]];
     
        //Render the circles
        [self renderCircles];
    } else {
        if (!hasData) {
            //Client connecting for the first time. Generate circle request message.
            //If we already have circles and explicitly sent a reset we don't have to do
            //any additional work here. (The messaging function will do the work.)
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"CirclesRequest"];
            [messagingDelegate sendData:message];
        }
    }
}

- (void)variation3ReceiveMessage:(OSCMessage *)message
{
    if (isMaster) {
        if ([[message.address objectAtIndex:0] isEqualToString:@"CirclesRequest"]) {
            [messagingDelegate sendData:[self generateCirclesMessageAsNew:NO]];
        }
    } else {
        if ([[message.address objectAtIndex:0] isEqualToString:@"Circles"]) {
            if (![message.typeTag hasPrefix:@",siii"]) {
                return;
            }
            if(!hasData || [[message.arguments objectAtIndex:0] isEqualToString:@"New"]) {
                //Check that we have the right sort of data first
                int circlesCount = [[message.arguments objectAtIndex:1] intValue];
                if (message.typeTag.length != (5 + (circlesCount * 3))) {
                    return;
                }
                NSString *typeTag = [message.typeTag substringFromIndex:5];
                NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"i"] invertedSet];
                if ([typeTag rangeOfCharacterFromSet:invalidTags].location != NSNotFound) {
                    return;
                }
                
                //We need to get the radius first before generating the circles from the received data.
                radius = [[message.arguments objectAtIndex:2] intValue];
                biggestGroup = [[message.arguments objectAtIndex:3] intValue];
                numCircles = circlesCount;
                
                circles = [[NSMutableArray alloc] init];
                groupMembership = [[NSMutableArray alloc] init];
                int offset = 4;
                for (int i = 0; i < numCircles; i++) {
                    CALayer *circle = [CALayer layer];
                    circle.frame = CGRectMake([[message.arguments objectAtIndex:(offset + (3 * i))] intValue] - radius, [[message.arguments objectAtIndex:(offset + (3 * i) + 1)] intValue] - radius, 2 * radius, 2 * radius);
                    circle.cornerRadius = radius;
                    circle.borderWidth = 5;
                    circle.borderColor = [UIColor blackColor].CGColor;
                    circle.backgroundColor = [UIColor clearColor].CGColor;
                    [circles addObject:circle];
                    [groupMembership addObject:[message.arguments objectAtIndex:(offset + (3 * i) + 2)]];
                }
                
                renderOK = YES;
                [self renderCircles];
                hasData = YES;
            }
        }
    }
}

- (void)generateCircles
{
    //Ported from the original Max Java extension, with additional rendering framework code
    radius = 60;
    numCircles = 42;
    
    circles = [NSMutableArray arrayWithCapacity:numCircles];
    groupMembership = [NSMutableArray arrayWithCapacity:numCircles];
    biggestGroup = 0;
    
    //Initialize circles and set group membership to 0
    for (int i = 0; i < numCircles; i++) {
        CALayer *circle = [CALayer layer];
        
        //When generating circles, keep them entirely on screen.
        //Take into account the size of the navigation bar for the y axis.
        int x = radius + arc4random_uniform((int)canvas.bounds.size.width - (radius * 2));
        int y = radius + arc4random_uniform((int)canvas.bounds.size.height - (radius * 2) - heightAdjust);
        circle.frame = CGRectMake(x - radius, y - radius, 2 * radius, 2 * radius);
        circle.cornerRadius = radius;
        circle.borderWidth = 5;
        circle.borderColor = [UIColor blackColor].CGColor;
        circle.backgroundColor = [UIColor clearColor].CGColor;
        
        [circles addObject:circle];
        [groupMembership addObject:[NSNumber numberWithInt:0]];
    }
    
    int currentGroup = 1;
    for (int i = 0; i < numCircles; i++) {
        
        //Iterating through the circles, if the current circle is not already a member
        //of a group then assign it to the current group and increment the next free group number
        
        if ([[groupMembership objectAtIndex:i] isEqualToNumber:[NSNumber numberWithInt:0]]) {
            [groupMembership replaceObjectAtIndex:i withObject:[NSNumber numberWithInt:currentGroup]];
            currentGroup++;
        }
        
        //Check if the current circle is touching any others. If it is then assign them to
        //the group of the current circle. If they're already in a group then the current circle
        //and all the members of its group get reassigned. (The hunter becomes the hunted...)
        
        for (int j = i + 1; j < numCircles; j++) {
            int dx = ((CALayer *)[circles objectAtIndex:i]).position.x - ((CALayer *)[circles objectAtIndex:j]).position.x;
            int dy = ((CALayer *)[circles objectAtIndex:i]).position.y - ((CALayer *)[circles objectAtIndex:j]).position.y;
            double distance = sqrt(pow(dx, 2) + pow(dy, 2));
            if (distance <= radius * 2) {
                if ([[groupMembership objectAtIndex:j] isEqualToNumber:[NSNumber numberWithInt:0]]) {
                    [groupMembership replaceObjectAtIndex:j withObject:[groupMembership objectAtIndex:i]];
                } else {
                    if (!([[groupMembership objectAtIndex:j] isEqualToNumber:[groupMembership objectAtIndex:i]])) {
                        for (int k = 0; k < numCircles; k++) {
                            if ([[groupMembership objectAtIndex:k] isEqualToNumber:[groupMembership objectAtIndex:i]] && k != i) {
                                [groupMembership replaceObjectAtIndex:k withObject:[groupMembership objectAtIndex:j]];
                            }
                        }
                        [groupMembership replaceObjectAtIndex:i withObject:[groupMembership objectAtIndex:j]];
                    }
                }
            }
        }
    }
    
    //Count the number of circles in each group to find the group number with the most circles.
    //(As a behavioural quirk, if there are two or more groups tied for first place then the one
    //with the lowest group number wins.)
    
    int maxCircles = 0;
    for (int i = 1; i < currentGroup; i++) {
        int currentCircles = 0;
        for (int j = 0; j < numCircles; j++) {
            if ([[groupMembership objectAtIndex:j] isEqualToNumber:[NSNumber numberWithInt:i]]) {
                currentCircles++;
            }
        }
        if (currentCircles > maxCircles) {
            maxCircles = currentCircles;
            biggestGroup = i;
        }
    }
    
    renderOK = YES;
}

- (void)renderCircles
{
    //Check to see if we should actually be calling this
    if (!renderOK || currentVariation != 3) {
        return;
    }
    
    //Reset Canvas
    canvas.sublayers = nil;
    
    //Render Circles and paint unused circles blue before fading
    
    [fadeTimer invalidate];
    for (int i = 0; i < numCircles; i++) {
        if (!([[groupMembership objectAtIndex:i] isEqualToNumber:[NSNumber numberWithInt:biggestGroup]])) {
            ((CALayer *)[circles objectAtIndex:i]).backgroundColor = [UIColor blueColor].CGColor;
        }
        [canvas addSublayer:[circles objectAtIndex:i]];
    }
    
    fadeTimer = [NSTimer scheduledTimerWithTimeInterval:4 target:self selector:@selector(removeCircles) userInfo:nil repeats:NO];
}

- (void)removeCircles
{
    //Don't run if we're not playing variation 3 or if the circles haven't been set up yet
    if (!renderOK || currentVariation != 3) {
        return;
    }
    
    [CATransaction begin];
    [CATransaction setAnimationDuration:4];
    for (int i = 0; i < numCircles; i++) {
        if (!([[groupMembership objectAtIndex:i] isEqualToNumber:[NSNumber numberWithInt:biggestGroup]])) {
            ((CALayer *)[circles objectAtIndex:i]).opacity = 0;
        }
    }
    [CATransaction commit];
}

- (void)variation4Reset
{
    renderOK = NO;
    
    if (isMaster) {
        //Generate the necessary data
        [self generate4Data];
        
        //Send the data to the clients
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"InitData"];
        [message addStringArgument:@"New"];
        for (int i = 0; i < [locations count]; i++) {
            [message addIntegerArgument:[[locations objectAtIndex:i] CGPointValue].x];
            [message addIntegerArgument:[[locations objectAtIndex:i] CGPointValue].y];
        }
        
        [messagingDelegate sendData:message];
        
        //Then perform rendering
        [self render4];
    } else {
        if (!hasData) {
            //Client connecting for the first time. Generate data request message.
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"DataRequest"];
            [messagingDelegate sendData:message];
        }
    }
}

- (void)variation4ReceiveMessage:(OSCMessage *)message
{
    if (isMaster) {
        if ([[message.address objectAtIndex:0] isEqualToString:@"DataRequest"]) {
            OSCMessage *response = [[OSCMessage alloc] init];
            [response appendAddressComponent:@"InitData"];
            [response addStringArgument:@"Refresh"];
            for (int i = 0; i < [locations count]; i++) {
                [response addIntegerArgument:[[locations objectAtIndex:i] CGPointValue].x];
                [response addIntegerArgument:[[locations objectAtIndex:i] CGPointValue].y];
            }
            [messagingDelegate sendData:response];
        }
    } else {
        if ([[message.address objectAtIndex:0] isEqualToString:@"InitData"]) {
            if (![message.typeTag hasPrefix:@",s"]) {
                return;
            }

            if(!hasData || [[message.arguments objectAtIndex:0] isEqualToString:@"New"]) {
                //Check that we have the right sort of data first
                NSString *typeTag = [message.typeTag substringFromIndex:2];
                NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"i"] invertedSet];
                if (([typeTag rangeOfCharacterFromSet:invalidTags].location != NSNotFound) || ([typeTag length] % 2 == 1)) {
                    return;
                }
                
                locations = [[NSMutableArray alloc] init];
                for (int i = 1; i < [message.arguments count]; i += 2) {
                    [locations addObject:[NSValue valueWithCGPoint:CGPointMake([[message.arguments objectAtIndex:i] intValue], [[message.arguments objectAtIndex:(i + 1)] intValue])]];
                }
                
                renderOK = YES;
                [self render4];
                hasData = YES;
            }
        }
    }
    
    //Process common messages here.
    if ([[message.address objectAtIndex:0] isEqualToString:@"NewCentre"]) {
        if (![message.typeTag isEqualToString:@",ii"]) {
            return;
        }
        
        CGPoint newCentre = CGPointMake([[message.arguments objectAtIndex:0] intValue], [[message.arguments objectAtIndex:1] intValue]);
        centreCircle.position = newCentre;
        [locations replaceObjectAtIndex:0 withObject:[NSValue valueWithCGPoint:newCentre]];
        
        for (int i = 0; i < [lines count]; i++) {
            [[lines objectAtIndex:i] removeFromSuperlayer];
        }
        [lines removeAllObjects];
        [self drawLines];
    }
}

- (void)generate4Data
{
    //If this is the first time we're running this, then generate a position for the centre circle.
    //Otherwise use its current location.
    
    locations = [[NSMutableArray alloc] init];
    if (centreCircle != nil) {
        [locations addObject:[NSValue valueWithCGPoint:centreCircle.position]];
    } else {
        [locations addObject:[NSValue valueWithCGPoint:CGPointMake(canvas.bounds.size.width / 2, (canvas.bounds.size.height - heightAdjust) / 2)]];
    }
    [locations addObjectsFromArray:[self generatePoints:1 withMargin:circleRadius]];
    [locations addObjectsFromArray:[self generatePoints:7 withMargin:pointRadius]];
    
    renderOK = YES;
}

- (void)render4
{
    //Check to see if we should actually be calling this
    if (!renderOK || currentVariation != 4) {
        return;
    }
    
    //Set up the background layer if a file exists for it. (This only gets called the first time.)
    if (!background && score.fileName != nil) {
        UIImage *backgroundImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:score.fileName]];
        background = [CALayer layer];
        background.contents = (id)backgroundImage.CGImage;
        background.contentsGravity = kCAGravityResizeAspect;
    }
    
    //Reset our canvas
    canvas.sublayers = nil;
    
    if (background != nil) {
        //Resize background for current iPad orientation
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        background.frame = CGRectMake(0, 0, canvas.bounds.size.width, canvas.bounds.size.height - heightAdjust);
        [CATransaction commit];
        
        [canvas addSublayer:background];
    }
    
    //Now set up the circles.
    for (int i = 0; i < 2; i++) {
        CALayer *circle = [CALayer layer];
        circle.frame = CGRectMake([[locations objectAtIndex:i] CGPointValue].x - circleRadius, [[locations objectAtIndex:i] CGPointValue].y - circleRadius, 2 * circleRadius, 2 * circleRadius);
        circle.cornerRadius = circleRadius;
        circle.borderWidth = 5;
        circle.borderColor = [UIColor blackColor].CGColor;
        circle.backgroundColor = [UIColor clearColor].CGColor;
        [canvas addSublayer:circle];
        
        //If this is our centre circle, save a reference to it
        if (i == 0) {
            centreCircle = circle;
        }
    }
    
    NSMutableArray *colourArray = [Renderer getDecibelColours];
    [colourArray addObject:[UIColor blackColor]];
    
    //Add the end points.
    for (int i = 2; i < [locations count]; i++) {
        CALayer *endPoint = [CALayer layer];
        endPoint.frame = CGRectMake([[locations objectAtIndex:i] CGPointValue].x - pointRadius, [[locations objectAtIndex:i] CGPointValue].y - pointRadius, 2 * pointRadius, 2 * pointRadius);
        endPoint.cornerRadius = pointRadius;
        endPoint.borderWidth = 1;
        endPoint.borderColor = ((UIColor *)[colourArray objectAtIndex:i - 2]).CGColor;
        endPoint.backgroundColor = ((UIColor *)[colourArray objectAtIndex:i - 2]).CGColor;
        [canvas addSublayer:endPoint];
    }
    
    //Then Draw our lines
    [self drawLines];
}

- (void)drawLines
{
    //Standard validity check
    if (!renderOK || currentVariation != 4) {
        return;
    }
    
    //Draw our lines using bezier paths.
    for (int i = 2; i < [locations count]; i++) {
        UIBezierPath *linePath = [UIBezierPath bezierPath];
        [linePath moveToPoint:CGPointMake([[locations objectAtIndex:0] CGPointValue].x, [[locations objectAtIndex:0] CGPointValue].y)];
        [linePath addLineToPoint:CGPointMake([[locations objectAtIndex:i] CGPointValue].x, [[locations objectAtIndex:i] CGPointValue].y)];
        
        CAShapeLayer *line = [CAShapeLayer layer];
        line.path = linePath.CGPath;
        line.lineWidth = 3;
        line.strokeColor = [UIColor blackColor].CGColor;
        [canvas insertSublayer:line above:background];
        
        //And store a reference to them.
        [lines addObject:line];
    }
}

- (void)variation6Reset
{
    //See variation4Reset for a commented version of this code
    renderOK = NO;
    
    if (isMaster) {
        [self generate6Data];
        [messagingDelegate sendData:[self generateObjectMessageAsNew:YES]];
        [self render6];
    } else {
        if (!hasData) {
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"DataRequest"];
            [messagingDelegate sendData:message];
        }
    }
}

- (void)variation6ReceiveMessage:(OSCMessage *)message
{
    if (isMaster) {
        if ([[message.address objectAtIndex:0] isEqualToString:@"DataRequest"]) {
            [messagingDelegate sendData:[self generateObjectMessageAsNew:NO]];
        }
    } else {
        if ([[message.address objectAtIndex:0] isEqualToString:@"InitData"]) {
            if (![message.typeTag hasPrefix:@",siiii"]) {
                return;
            }
            
            if(!hasData || [[message.arguments objectAtIndex:0] isEqualToString:@"New"]) {
                //Check that we have the right sort of data first. Remember to add one because we have
                //one more line than we do systems.
                int totalObjects = 1;
                NSMutableArray *newObjectNumbers = [[NSMutableArray alloc] init];
                for (int i = 1; i < 5; i++) {
                    totalObjects += [[message.arguments objectAtIndex:i] intValue];
                    [newObjectNumbers addObject:[message.arguments objectAtIndex:i]];
                }
                
                if (message.typeTag.length != (6 + (3 * totalObjects))) {
                    return;
                }
                for (int i = 6; i < [message.typeTag length]; i += 3) {
                    if (![[message.typeTag substringWithRange:NSMakeRange(i, 3)] isEqualToString:@"iif"]) {
                        return;
                    }
                }
                
                int offset = 5;
                locations = [[NSMutableArray alloc] init];
                rotations = [[NSMutableArray alloc] init];
                objectNumbers = newObjectNumbers;
                for (int i = 0; i < totalObjects; i++) {
                    CGPoint location = CGPointMake([[message.arguments objectAtIndex:(offset + (i * 3))] intValue], [[message.arguments objectAtIndex:(offset + (i * 3) + 1)] intValue]);
                    [locations addObject:[NSValue valueWithCGPoint:location]];
                    [rotations addObject:[message.arguments objectAtIndex:(offset + (i * 3) + 2)]];
                }
                
                renderOK = YES;
                [self render6];
                hasData = YES;
            }
        }
    }
}

- (void)generate6Data
{
    int totalObjects = 0;
    for (int i = 0; i < 4; i++) {
        totalObjects += [[objectNumbers objectAtIndex:i] intValue];
    }
    //Need to add one because we have one more line than there are systems
    totalObjects++;
    
    //Now generate location and rotation data
    rotations = [[NSMutableArray alloc] init];
    locations = [self generatePoints:totalObjects withMargin:20];
    for (int i = 0; i < totalObjects; i++) {
        [rotations addObject:[NSNumber numberWithFloat:(float)(arc4random_uniform(360)) * (M_PI / 180)]];
    }
    
    renderOK = YES;
}

- (void)render6
{
    //Check to see if we should actually be calling this
    if (!renderOK || currentVariation != 6) {
        return;
    }
    
    //Set up baseline if it hasn't already been done.
    if (!background) {
        UIImage *backgroundImage = [Renderer cachedImage:[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"cageLine.png"]];
        background = [CALayer layer];
        background.contents = (id)backgroundImage.CGImage;
        background.bounds = CGRectMake(0, 0, backgroundImage.size.width, backgroundImage.size.height);
    }
    
    canvas.sublayers = nil;
    
    //Centre the baseline based on the current iPad orientation.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    background.position = CGPointMake(canvas.bounds.size.width / 2, (canvas.bounds.size.height - heightAdjust) / 2);
    [CATransaction commit];
    [canvas addSublayer:background];
    
    
    //Set up the layers for the objects.
    int currentIndex = 0;
    BOOL compensated = NO;
    for (int i = 0; i < 4; i++) {
        UIImage *objectImage = [Renderer cachedImage:[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:[objectTypes objectAtIndex:i]]];
        for (int j = 0; j < [[objectNumbers objectAtIndex:i] intValue]; j++) {
            CALayer *object = [CALayer layer];
            object.contents = (id)objectImage.CGImage;
            object.bounds = CGRectMake(0, 0, objectImage.size.width, objectImage.size.height);
            object.position = [[locations objectAtIndex:currentIndex] CGPointValue];
            [object setValue:[rotations objectAtIndex:currentIndex] forKeyPath:@"transform.rotation.z"];
            
            [canvas addSublayer:object];
            currentIndex++;
            
            //If we're processing systems, we need to add one more than given by our array.
            if (!compensated) {
                j--;
                compensated = YES;
            }
        }
    }
}

- (CGFloat)getPerpendicularDistance:(Dot)dot toLine:(Line)line
{
    //Calculate the closest distance from a dot to a line (extended infinitely).
    //Uses dot product to determine the perpendicular.
    
    //P = A + t(B - A)
    //(D - P).(B - A)
    
    //Where A and B are the endpoints of the line, and D is the dot.
    
    CGFloat px, py;
    
    if (line.start.x == line.end.x && line.start.y == line.end.y) {
        //Our line is really a dot and our work here is done.
        px = line.start.x;
        py = line.start.y;
    } else {
        CGFloat t = (dot.location.x - line.start.x) * (line.end.x - line.start.x);
        t += (dot.location.y - line.start.y) * (line.end.y - line.start.y);
        t = t / (powf(line.end.x - line.start.x, 2) + powf(line.end.y - line.start.y, 2));
        px = line.start.x + (t * (CGFloat)(line.end.x - line.start.x));
        py = line.start.y + (t * (CGFloat)(line.end.y - line.start.y));
    }
    
    //Now calculate the distance.
    CGFloat dist = sqrtf(powf(dot.location.x - px, 2) + powf(dot.location.y - py, 2));
    return dist;
}

- (NSMutableArray *)generatePoints:(int)numberOfPoints withMargin:(int)margin
{
    NSMutableArray *points = [[NSMutableArray alloc] initWithCapacity:numberOfPoints];
    int x, y;
    for (int i = 0; i < numberOfPoints; i++) {
        x = margin + arc4random_uniform((int)canvas.bounds.size.width - (margin * 2));
        y = margin + arc4random_uniform((int)canvas.bounds.size.height - (margin * 2) - heightAdjust);
        [points addObject:[NSValue valueWithCGPoint:CGPointMake(x, y)]];
    }
    return points;
}

- (OSCMessage *)generateCirclesMessageAsNew:(BOOL)new
{
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Circles"];
    if (new) {
        [message addStringArgument:@"New"];
    } else {
        [message addStringArgument:@"Refresh"];
    }
    [message addIntegerArgument:numCircles];
    [message addIntegerArgument:radius];
    [message addIntegerArgument:biggestGroup];
    for (int i = 0; i < [circles count]; i++) {
        [message addIntegerArgument:((CALayer *)[circles objectAtIndex:i]).position.x];
        [message addIntegerArgument:((CALayer *)[circles objectAtIndex:i]).position.y];
        [message addIntegerArgument:[[groupMembership objectAtIndex:i] intValue]];
    }
    return message;
}

- (OSCMessage *)generateObjectMessageAsNew:(BOOL)new;
{
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"InitData"];
    if (new) {
        [message addStringArgument:@"New"];
    } else {
        [message addStringArgument:@"Refresh"];
    }
    
    for (int i = 0; i < [objectNumbers count]; i++) {
        [message addIntegerArgument:[[objectNumbers objectAtIndex:i] intValue]];
    }
    for (int i = 0; i < [locations count]; i++) {
        [message addIntegerArgument:[[locations objectAtIndex:i] CGPointValue].x];
        [message addIntegerArgument:[[locations objectAtIndex:i] CGPointValue].y];
        [message addFloatArgument:[[rotations objectAtIndex:i]floatValue]];
    }
    
    return message;
}

- (void)receiveInitialData:(OSCMessage *)data fromNetwork:(BOOL)fromNet
{
    //First check that our data is valid.
    if (![data.typeTag isEqualToString:@",fffiiiiiiiiiii"]) {
        return;
    }
    
    //If we've already received data from the net then don't load our own local values.
    if (!fromNet && !awaitingVariation) {
        return;
    }
    
    variation1Duration = [[data.arguments objectAtIndex:0] floatValue];
    variation2Duration = [[data.arguments objectAtIndex:1] floatValue];
    variation5Duration = [[data.arguments objectAtIndex:2] floatValue];
    performers = [[data.arguments objectAtIndex:3] intValue];
    for (int i = 0; i < 2; i++) {
        minDuration[i] = [[data.arguments objectAtIndex:(3 * i + 4)] intValue];
        maxDuration[i] = [[data.arguments objectAtIndex:(3 * i + 5)] intValue];
        density[i] = [[data.arguments objectAtIndex:(3 * i + 6)] intValue];
    }
    objectNumbers = [[NSMutableArray alloc] initWithObjects:[data.arguments objectAtIndex:10], [data.arguments objectAtIndex:11], [data.arguments objectAtIndex:12], [data.arguments objectAtIndex:13], nil];
    
    //Check minimums and maximums don't cross over if we've recieved remote data. (The parser will already
    //have done this check on local prefs files.)
    if (fromNet) {
        for (int i = 0; i < 2; i++) {
            if (maxDuration[i] < minDuration[i]) {
                maxDuration[i] = minDuration[i];
            }
        }
    }
}

#pragma mark - Renderer delegate

- (void)setIsMaster:(BOOL)master
{
    isMaster = master;
    if (currentVariation == 5) {
        talkingBoard.isMaster = master;
    }
    
    if (!isMaster) {
        hasData = NO;
        if (awaitingVariation) {
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"GetVariation"];
            [messagingDelegate sendData:message];
        } else {
            [self reset];
        }
    }
}

- (BOOL)isMaster
{
    return isMaster;
}

+ (RendererFeatures)getRendererRequirements
{
    return kVariations | kUsesScaledCanvas;
}

+ (UIImage *)generateThumbnailForScore:(Score *)score ofSize:(CGSize)size
{
    if (score.fileName != nil) {
        return [Renderer defaultThumbnail:[score.scorePath stringByAppendingPathComponent:score.fileName] ofSize:size];
    } else {
        return nil;
    }
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    
    debug = NO;
    badPrefs = NO;
    
    isMaster = YES;
    score = scoreData;
    canvas = playerCanvas;
    UIDelegate = UIDel;
    messagingDelegate = messagingDel;
    
    //Networking (only used by the clients)
    hasData = YES;
    renderOK = NO;
    optionsSet = NO;
    
    //Image references for Variation 6
    objectTypes = [[NSMutableArray alloc] init];
    [objectTypes addObject:@"cageSystem.png"];
    [objectTypes addObject:@"cageSource.png"];
    [objectTypes addObject:@"cageSpeaker.png"];
    [objectTypes addObject:@"cageComponent.png"];
    
    //Check to see if allowOptions is incorrectly set by the score, and correct it if needed.
    //(Only Variation 6 has options at this stage.)
    /*if (score.variationNumber != 6 && score.allowsOptions) {
        score.allowsOptions = NO;
    }*/
    
    if (score.variationNumber == -1) {
        score.allowsOptions = NO;
    }
    
    //If changing the default values of here, make sure they are changed in the corresponding CageParser code.
    if (score.variationNumber == 1 || score.variationNumber == 2 || score.variationNumber == -1) {
        for (int i = 0; i < 2; i++) {
            minDuration[i] = 500;
            maxDuration[i] = 5000;
        }
        density[0] = 5;
        density[1] = 3;
        yMin = 50;
        yMax = (canvas.bounds.size.height - LOWER_PADDING - 30);
        
        readLineOffset = 150;
    }
    if (score.variationNumber == 4 || score.variationNumber == -1) {
        //Initialize the array to hold our lines.
        lines = [[NSMutableArray alloc] init];
        circleRadius = 50;
        pointRadius = 10;
    }
    if (score.variationNumber == 6 || score.variationNumber == -1) {
        //Set the default number of objects.
        objectNumbers = [[NSMutableArray alloc] initWithObjects:[NSNumber numberWithInt:2], [NSNumber numberWithInt:3], [NSNumber numberWithInt:3], [NSNumber numberWithInt:3], nil];
    }
    
    if (score.variationNumber == -1) {
        //For the moment, set our current variation to the start.
        currentVariation = 1;
        awaitingVariation = YES;
        if (!debug) {
            UIDelegate.clockVisible = NO;
        }
        UIDelegate.resetViewOnFinish = NO;
        fullReset = YES;
        canGoBack = NO;
        heightAdjust = 0;
        performers = 6;
        
        //Set up our score for variation 5. Some adjustments will need to be made after loading preferences.
        variation5Score = [[Score alloc] init];
        variation5Score.scoreName = @"Variation 5";
        [variation5Score.composers addObject:[NSArray arrayWithObjects:@"Cage", @"John", nil]];
        variation5Score.scoreType = @"TalkingBoard";
        variation5Score.originalDuration = score.originalDuration;
        variation5Score.scorePath = score.scorePath;
        //The part file is used as the star chart. If not given, raise the alarm.
        if ([score.parts count] > 0) {
            variation5Score.fileName = [score.parts objectAtIndex:0];
        } else {
            badPrefs = YES;
            errorMessage = @"No star chart file specified for Variation V.";
        }
    } else {
        currentVariation = score.variationNumber;
        awaitingVariation = NO;
        heightAdjust = (int)(UIDelegate.navigationHeight + UIDelegate.statusHeight);
    }
    
    //Check if we have a valid variation number.
    if (!((currentVariation > 0 && currentVariation < 5) || currentVariation == 6)) {
        badPrefs = YES;
        errorMessage = @"Invalid variation number.";
    }
    
    //Check for necessary files.
    if ((score.variationNumber == 1 || score.variationNumber == 2) && UIDelegate.clockDuration <= 0) {
        badPrefs = YES;
        errorMessage = @"Invalid score duration. (Must be greater than 0.)";
    }
    
    //Load preferences if needed.
    prefsLoaded = YES;
    prefsCondition = [NSCondition new];
    if (score.prefsFile != nil && (score.variationNumber == -1 || score.variationNumber == 1 || score.variationNumber == 2 || score.variationNumber == 6)) {
        
        NSData *prefsData = [[NSData alloc] initWithContentsOfFile:[score.scorePath stringByAppendingPathComponent:score.prefsFile]];
        if (prefsData != nil) {
            prefsLoaded = NO;
            parser = [[CageParser alloc] initWithVaritionNumber:score.variationNumber prefsData:prefsData];
            parser.delegate = self;
            [parser startParse];
        }
    }
    
    return self;
}

- (void)close {
    [scrollTimer invalidate];
    [fadeTimer invalidate];
    
    if (currentVariation == 5) {
        [talkingBoard close];
        talkingBoard = nil;
    }
}

- (void)reset;
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
    
    if (score.variationNumber == -1) {
        if (!isMaster && awaitingVariation) {
            return;
        }
        
        if (fullReset) {
            if (currentVariation > 1) {
                if (variation1Duration > 0) {
                    UIDelegate.clockDuration = variation1Duration;
                } else {
                    UIDelegate.clockDuration = score.originalDuration;
                }
                UIDelegate.clockDuration = variation1Duration;
                scroller.bounds = CGRectMake(0, 0, CAGE_FRAMERATE * UIDelegate.clockDuration, scroller.bounds.size.height);
            }
            if (currentVariation > 2 && currentVariation != 5) {
                UIDelegate.clockEnabled = YES;
                UIDelegate.allowClockChange = YES;
                UIDelegate.allowSyncToTick = YES;
                [UIDelegate setDynamicScoreUI];
            }
            currentVariation = 1;
            variationPlayed = NO;
            
            if (debug) {
                UIDelegate.clockVisible = YES;
            }
        } else {
            fullReset = YES;
        }
    }
    
    switch (currentVariation) {
        //Variation 1 and 2 share most of the same code.
        case 1:
        case 2:
            [self variation1Reset];
            break;
        case 3:
            [UIDelegate setStaticScoreUI];
            [self variation3Reset];
            break;
        case 4:
            [UIDelegate setStaticScoreUI];
            [self variation4Reset];
            break;
        case 6:
            [UIDelegate setStaticScoreUI];
            [self variation6Reset];
            break;
        default:
            //Do nothing if called with an invalid variation number;
            break;
    }
}

- (void)play
{
    switch (currentVariation) {
        case 1:
        case 2:
            [self variation1Play];
            break;
        case 5:
            variationPlayed = YES;
            canGoBack = NO;
            [talkingBoard play];
        default:
            //Game over man, Game Over!
            //(This one's for you, LV)
            break;
    }
}

- (void)seek:(CGFloat)location
{
    if (currentVariation > 2 && currentVariation != 5) {
        //Nothing to do here
        return;
    }
    
    if (score.variationNumber == -1 && !isMaster && awaitingVariation) {
        awaitingSeek = YES;
        return;
    }

    switch (currentVariation) {
        case 1:
        case 2:
            [self variation1Seek:location];
            break;
        case 5:
            [talkingBoard seek:location];
            break;
        default:
            break;
    }
}

- (void)changeDuration:(CGFloat)duration
{
    switch (currentVariation) {
        case 1:
        case 2:
            [self variation1ChangeDuration:duration];
            break;
        case 5:
            [talkingBoard changeDuration:duration];
            break;
        default:
            break;
    }
}

- (void)rotate
{
    switch (currentVariation) {
        case 1:
        case 2:
            [self variation1Rotate];
            break;
        default:
            break;
    }
}

- (void)receiveMessage:(OSCMessage *)message
{
    //Check for minimum message requirements.
    if ([message.address count] < 1) {
        return;
    }
    
    if (score.variationNumber == -1) {
        //Code to handle chages between variations for performing a complete run.
        if (isMaster && [[message.address objectAtIndex:0] isEqualToString:@"GetVariation"]) {
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"CurrentVariation"];
            [message addIntegerArgument:currentVariation];
            
            //Include all of the necessary settings data with the message
            [message addFloatArgument:variation1Duration];
            [message addFloatArgument:variation2Duration];
            [message addFloatArgument:variation5Duration];
            [message addIntegerArgument:performers];
            for (int i = 0; i < 2; i++) {
                [message addIntegerArgument:minDuration[i]];
                [message addIntegerArgument:maxDuration[i]];
                [message addIntegerArgument:density[i]];
            }
            
            for (int i = 0; i < [objectNumbers count]; i++) {
                [message addIntegerArgument:[[objectNumbers objectAtIndex:i] intValue]];
            }
            
            [messagingDelegate sendData:message];
            return;
        } else if (!isMaster && awaitingVariation && [[message.address objectAtIndex:0] isEqualToString:@"CurrentVariation"]) {
            if (![message.typeTag hasPrefix:@",i"]) {
                return;
            }
            currentVariation = [[message.arguments objectAtIndex:0] intValue];
            awaitingVariation = NO;
            
            //Process the settings data that came through with the message
            [message removeArgumentAtIndex:0];
            [self receiveInitialData:message fromNetwork:YES];
            
            //If we're not on the first variation then we've already set things in motion
            //and the navigation bar should be hidden
            if (currentVariation > 1) {
                [UIDelegate hideNavigationBar];
            }
            
            //Deal with the special case of variation 5 before applying settings
            //common to the other scores.
            if (currentVariation == 5) {
                talkingBoard = [[TalkingBoard alloc] initRendererWithScore:variation5Score canvas:canvas UIDelegate:UIDelegate messagingDelegate:self];
                OSCMessage *options = [[OSCMessage alloc] init];
                [options appendAddressComponent:@"Options"];
                [options addIntegerArgument:performers];
                [talkingBoard setOptions:options];
                talkingBoard.isMaster = isMaster;
                [talkingBoard reset];
            } else {
                fullReset = NO;
                if (currentVariation > 2) {
                    UIDelegate.clockDuration = 0;
                    variationPlayed = YES;
                }
                if (currentVariation == 4) {
                    canGoBack = YES;
                }
                [self reset];
            }
            
            if (awaitingSeek) {
                [self seek:UIDelegate.clockLocation];
                awaitingSeek = NO;
            }
            
            return;
        } else if ([[message.address objectAtIndex:0] isEqualToString:@"NextVariation"]) {
            if (currentVariation < 6) {
                currentVariation++;
                hasData = NO;
                
                switch (currentVariation) {
                    case 2:
                        if (variation2Duration > 0) {
                            UIDelegate.clockDuration = variation2Duration;
                        } else {
                            UIDelegate.clockDuration = score.originalDuration;
                        }
                        scroller.bounds = CGRectMake(0, 0, CAGE_FRAMERATE * UIDelegate.clockDuration, scroller.bounds.size.height);
                        variationPlayed = NO;
                        [UIDelegate resetClockWithUIUpdate:YES];
                        break;
                    case 3:
                        [UIDelegate resetClockWithUIUpdate:NO];
                        UIDelegate.clockDuration = 0;
                        break;
                    case 4:
                        canGoBack = YES;
                        background = nil;
                        break;
                    case 5:
                        if (variation5Duration > 0) {
                            UIDelegate.clockDuration = variation5Duration;
                        } else {
                            UIDelegate.clockDuration = variation5Score.originalDuration;
                        }
                        variationPlayed = NO;
                        UIDelegate.clockEnabled = YES;
                        UIDelegate.allowClockChange = YES;
                        UIDelegate.allowSyncToTick = YES;
                        [UIDelegate resetClockWithUIUpdate:YES];
                        [UIDelegate setDynamicScoreUI];
                        if (talkingBoard == nil) {
                            talkingBoard = [[TalkingBoard alloc] initRendererWithScore:variation5Score canvas:canvas UIDelegate:UIDelegate messagingDelegate:self];
                            OSCMessage *options = [[OSCMessage alloc] init];
                            [options appendAddressComponent:@"Options"];
                            [options addIntegerArgument:performers];
                            [talkingBoard setOptions:options];
                        }
                        talkingBoard.isMaster = isMaster;
                        [talkingBoard reset];
                        break;
                    case 6:
                        [talkingBoard close];
                        talkingBoard = nil;
                        [UIDelegate resetClockWithUIUpdate:NO];
                        UIDelegate.clockDuration = 0;
                        background = nil;
                        [UIDelegate setMarginColour:score.backgroundColour];
                        break;
                    default:
                        break;
                }
                fullReset = NO;
                [self reset];
            }
            return;
        } else if ([[message.address objectAtIndex:0] isEqualToString:@"GoBack"]) {
            if (canGoBack) {
                currentVariation--;
                switch (currentVariation) {
                    case 3:
                        canGoBack = NO;
                        hasData = NO;
                        fullReset = NO;
                        [self reset];
                        break;
                    case 4:
                        variationPlayed = YES;
                        UIDelegate.clockDuration = 0;
                        fullReset = NO;
                        [self reset];
                        break;
                    default:
                        //Nothing to do here
                        break;
                }
            }
            return;
        } else if ([[message.address objectAtIndex:0] isEqualToString:@"TalkingBoard"]) {
            [message stripFirstAddressComponent];
            [talkingBoard receiveMessage:message];
            return;
        }
    }
    
    //Code to handle the regenerate command
    if (currentVariation > 2 && currentVariation != 5) {
        if ([[message.address objectAtIndex:0] isEqualToString:@"Regenerate"]) {
            if (score.variationNumber == -1) {
                fullReset = NO;
            }
            [self reset];
            return;
        }
    }
    
    //Variation specific messages
    switch (currentVariation) {
        case 3:
            [self variation3ReceiveMessage:message];
            break;
        case 4:
            [self variation4ReceiveMessage:message];
            break;
        case 6:
            [self variation6ReceiveMessage:message];
            break;
        default:
            break;
    }
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    if (currentVariation == 5) {
        [talkingBoard tick:progress tock:splitSecond noMoreClock:finished];
    }
    
    if (finished && score.variationNumber == -1) {
        variationPlayed = YES;
        if (currentVariation < 3) {
            [CATransaction begin];
            [CATransaction setAnimationDuration:2];
            readLine.opacity = 0;
            for (int i = 0; i < [events count]; i++) {
                ((CageEvent *)[events objectAtIndex:i]).layer.opacity = 0;
            }
            [CATransaction commit];
        }
    }
}

- (void)swipeUp
{
    if (currentVariation > 2) {
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"Regenerate"];
        [messagingDelegate sendData:message];
    }
}

- (void)swipeLeft
{
    if (score.variationNumber == -1 && variationPlayed) { //&& delegate.playerState == kStopped) {
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"NextVariation"];
        [messagingDelegate sendData:message];
    }
}

- (void)swipeRight
{
    if (score.variationNumber == -1 && canGoBack) {
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"GoBack"];
        [messagingDelegate sendData:message];
    }
}

- (void)tapAt:(CGPoint)location
{
    if (currentVariation == 4) {
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"NewCentre"];
        [message addIntegerArgument:location.x];
        [message addIntegerArgument:location.y];
        [messagingDelegate sendData:message];
    }
}

- (OSCMessage *)getOptions
{
    //The first field gives the current variation number.
    OSCMessage *options = [[OSCMessage alloc] init];
    [options appendAddressComponent:@"Options"];
    [options addIntegerArgument:currentVariation];
    
    switch (currentVariation) {
        case 1:
        case 2:
            [options addIntegerArgument:minDuration[currentVariation - 1]];
            [options addIntegerArgument:maxDuration[currentVariation - 1]];
            [options addIntegerArgument:density[currentVariation -1]];
            break;
        case 6:
            for (int i = 0; i < [objectNumbers count]; i++) {
                [options addIntegerArgument:[[objectNumbers objectAtIndex:i] intValue]];
            }
            break;
        default:
            return nil;
            break;
    }
    
    return options;
}

- (void)setOptions:(OSCMessage *)newOptions
{
    if (![newOptions.typeTag hasPrefix:@",i"] && ([[newOptions.arguments objectAtIndex:0] integerValue] != currentVariation)) {
        return;
    } else {
        [newOptions removeArgumentAtIndex:0];
    }
    
    switch (currentVariation) {
        case 1:
        case 2:
            if (![newOptions.typeTag isEqualToString:@",iii"]) {
                return;
            }
            
            minDuration[currentVariation - 1] = [[newOptions.arguments objectAtIndex:0] intValue];
            maxDuration[currentVariation - 1] = [[newOptions.arguments objectAtIndex:1] intValue];
            density[currentVariation - 1] = [[newOptions.arguments objectAtIndex:2] intValue];
            [self reset];
            break;
        case 6:
            //We only need to do this if we're the master.
            if (isMaster) {
                if (![newOptions.typeTag isEqualToString:@",iiii"]) {
                    return;
                }
                
                objectNumbers = [[NSMutableArray alloc] init];
                for (int i = 0; i < 4; i++) {
                    [objectNumbers addObject:[newOptions.arguments objectAtIndex:i]];
                }
                
                [self reset];
            }
            break;
        default:
            //Return here so that we don't set the optionsSet flag.
            return;
            break;
    }
    
    optionsSet = YES;
}

#pragma mark - RendererMessaging delegate
//Implemented to allow the cage module to bootstrap the talking board module for variation 5

- (BOOL)sendData:(OSCMessage *)message;
{
    [message prependAddressComponent:@"TalkingBoard"];
    return [messagingDelegate sendData:message];
}

#pragma mark - CageParser delegate

- (void)parserFinishedWithResult:(OSCMessage *)data
{
    switch (score.variationNumber) {
        case -1:
            [self receiveInitialData:data fromNetwork:NO];
            if ((variation1Duration == 0 || variation2Duration == 0 || variation5Duration == 0) && score.originalDuration == 0) {
                badPrefs = YES;
                errorMessage = @"Invalid score duration. (Must be greater than 0.)";
            }
            break;
        case 1:
        case 2:
            //Don't make changes if we've already received options over the network.
            //(We need network options to take precedence over local ones.)
            
            //Also, no need to check bounds as this is already done by the parser.
            if (!optionsSet) {
                minDuration[score.variationNumber - 1] = [[data.arguments objectAtIndex:0] intValue];
                maxDuration[score.variationNumber - 1] = [[data.arguments objectAtIndex:1] intValue];
                density[score.variationNumber - 1] = [[data.arguments objectAtIndex:2] intValue];
            }
            break;
        case 6:
            if (!optionsSet) {
                objectNumbers = [[NSMutableArray alloc] initWithArray:data.arguments];
            }
            break;
        default:
            break;
    }

    [prefsCondition lock];
    prefsLoaded = YES;
    [prefsCondition signal];
    [prefsCondition unlock];
    
    parser.delegate = nil;
    parser = nil;
}

- (void)parserError
{
    badPrefs = YES;
    errorMessage = @"Damaged preferences file.";
    parser.delegate = nil;
    parser = nil;
    [prefsCondition lock];
    prefsLoaded = YES;
    [prefsCondition signal];
    [prefsCondition unlock];
}

@end

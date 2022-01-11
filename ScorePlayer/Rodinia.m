//
//  Rodinia.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 12/02/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import "Rodinia.h"
#import "RodiniaEvent.h"
#import "Score.h"
#import "OSCMessage.h"

@interface Rodinia ()

- (NSMutableArray *)getColourArray;
- (NSArray *)getUIColours;
- (void)selectArticulation:(Articulation)articulationType ghosted:(BOOL)ghost;
- (void)selectDurationStyle:(NSUInteger)style;
- (void)selectHold:(BOOL)isHolding;
- (void)updateControllerUIFromState;
- (CGPoint)scoreCoordinatesFromStreamNumber:(NSInteger)stream withCoordinates:(CGPoint)streamCoordinates;

- (void)initControllerLayers;
- (void)initPlayerLayers;
- (void)changePart:(NSInteger)relativeChange;

- (void)scrollerAnimate;
- (void)showEvent:(NSTimer *)timer;

- (void)relayMessageToExternal:(OSCMessage *)message;

@end

@implementation Rodinia {
    Score *score;
    CALayer *canvas;
    
    ViewMode viewMode;
    CALayer *toPerformer;
    CALayer *toConductor;
    
    CALayer *controllerLayer;
    CALayer *articulationSeletionLayer;
    CALayer *durationSelectionLayer;
    CALayer *holdSelectionLayer;
    CALayer *durationBar;
    CALayer *pitchBar;
    CALayer *dynamicBar;
    CALayer *rateBar;
    CALayer *compassBar;
    CATextLayer *numPlayersLayer;
    
    //Controller states
    NSInteger numPlayers[4];
    BOOL holdStates[4];
    NSInteger durationTypes[4];
    Articulation articulations[4];
    BOOL ghostStates[4];
    CGFloat barStates[4][5];
    
    NSArray *barArray;
    NSInteger barBase;
    NSInteger barWidth;
    NSInteger barHeights[5];
    NSInteger barX[5];
    NSInteger maxLength;
    
    CALayer *playerLayer;
    CALayer *readLine;
    CALayer *scroller;
    CALayer *scoreLayer;
    CALayer *blackLayer;
    NSMutableArray *streamLayers;
    NSInteger streamXOffset;
    
    StreamState streamStates[4];
    NSInteger xFromLastEvent[4];
    
    NSTimer *scrollTimer;
    NSInteger currentPart;
    
    NSArray *uiColours;
    NSMutableArray *eventColours;
    
    NSMutableArray *events;
    NSMutableArray *eventTimers;
    
    __weak id<RendererUI> UIDelegate;
    __weak id<RendererMessaging> messagingDelegate;
}

//There is so much hard coded in this that needs to be somehow placed into some sort of XML schema.
//This is what happens when results are more important than code elegance. (And I die a little inside...)

- (NSMutableArray *)getColourArray;
{
    NSMutableArray *colours = [[NSMutableArray alloc] init];
    //Orange, blue, red, green
    [colours addObject:[NSArray arrayWithObjects:[UIColor colorWithRed:170.0 / 255.0 green:92.0 / 255.0 blue:2.0 / 255.0 alpha:1], [UIColor colorWithRed:235.0 / 255.0 green:129.0 / 255.0 blue:6.0 / 255.0 alpha:1], [UIColor colorWithRed:252.0 / 255.0 green:203.0 / 255.0 blue:161.0 / 255.0 alpha:1], [UIColor colorWithRed:253.0 / 255.0 green:221.0 / 255.0 blue:193.0 / 255.0 alpha:1], nil]];
    [colours addObject:[NSArray arrayWithObjects:[UIColor colorWithRed:89.0 / 255.0 green:110.0 / 255.0 blue:128.0 / 255.0 alpha:1], [UIColor colorWithRed:109.0 / 255.0 green:134.0 / 255.0 blue:167.0 / 255.0 alpha:1], [UIColor colorWithRed:182.0 / 255.0 green: 200.0 / 255.0 blue:220.0 / 255.0 alpha:1], [UIColor colorWithRed:206.0 / 255.0 green:217.0 / 255.0 blue:232.0 / 255.0 alpha:1], nil]];
    [colours addObject:[NSArray arrayWithObjects:[UIColor colorWithRed:118.0 / 255.0 green:50.0 / 255.0 blue:48.0 / 255.0 alpha:1], [UIColor colorWithRed:164.0 / 255.0 green:74.0 / 255.0 blue:67.0 / 255.0 alpha:1], [UIColor colorWithRed:226.0 / 255.0 green:167.0 / 255.0 blue:166.0 / 255.0 alpha:1], [UIColor colorWithRed:236.0 / 255.0 green:197.0 / 255.0 blue:197.0 / 255.0 alpha:1], nil]];
    [colours addObject:[NSArray arrayWithObjects: [UIColor colorWithRed:97.0 / 255.0 green:116.0 / 255.0 blue:53.0 / 255.0 alpha:1], [UIColor colorWithRed:137.0 / 255.0 green:162.0 / 255.0 blue:76.0 / 255.0 alpha:1], [UIColor colorWithRed:205.0 / 255.0 green:221.0 / 255.0 blue:172.0 / 255.0 alpha:1], [UIColor colorWithRed:222.0 / 255.0 green:231.0 / 255.0 blue:199.0 / 255.0 alpha:1], nil]];
    
    return colours;
}

- (NSArray *)getUIColours
{
    return [NSArray arrayWithObjects:[UIColor colorWithRed:228.0 / 255.0 green:108.0 / 255.0 blue:11.0 / 255.0 alpha:1], [UIColor colorWithRed:54.0 / 255.0 green:96.0 / 255.0 blue:146.0 / 255.0 alpha:1], [UIColor colorWithRed:149.0 / 255.0 green:55.0 / 255.0 blue:53.0 / 255.0 alpha:1], [UIColor colorWithRed:119.0 / 255.0 green:147.0 / 255.0 blue:60.0 / 255.0 alpha:1], nil];
}

- (void)selectArticulation:(Articulation)articulationType ghosted:(BOOL)ghost
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    switch (articulationType) {
        case kNormal:
            if (ghost) {
                articulationSeletionLayer.position = CGPointMake(54, 373);
            } else {
                articulationSeletionLayer.position = CGPointMake(54, 275);
            }
            break;
            
        case kNoise:
            if (ghost) {
                articulationSeletionLayer.position = CGPointMake(54, 403);
            } else {
                articulationSeletionLayer.position = CGPointMake(54, 306);
            }
            break;
            
        case kPoint:
            if (ghost) {
                articulationSeletionLayer.position = CGPointMake(54, 434);
            } else {
                articulationSeletionLayer.position = CGPointMake(54, 336);
            }
            break;
    }
    [CATransaction commit];
}

- (void)selectDurationStyle:(NSUInteger)style
{
    if (style > 3) {
        return;
    }
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (style == 0) {
        durationSelectionLayer.frame = CGRectMake(42, 529, 80, 28);
    } else if (style == 1) {
        durationSelectionLayer.frame = CGRectMake(42, 562, 80, 45);
    } else if (style == 2) {
        durationSelectionLayer.frame = CGRectMake(42, 608, 80, 45);
    } else {
        durationSelectionLayer.frame = CGRectMake(42, 657, 80, 28);
    }
    [CATransaction commit];
}

- (void)selectHold:(BOOL)isHolding
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (isHolding) {
        holdSelectionLayer.position = CGPointMake(151, 151);
    } else {
        holdSelectionLayer.position = CGPointMake(62, 151);
    }
    [CATransaction commit];
}

- (void)updateControllerUIFromState
{
    [self selectArticulation:articulations[currentPart - 1] ghosted:ghostStates[currentPart - 1]];
    [self selectDurationStyle:durationTypes[currentPart - 1]];
    [self selectHold:holdStates[currentPart - 1]];
    
    for (int i = 0; i < 5; i++) {
        ((CALayer *)[barArray objectAtIndex:i]).bounds = CGRectMake(0, 0, barWidth, (int)(barStates[currentPart - 1][i] * (CGFloat)barHeights[i]));
    }
    
    numPlayersLayer.string = [NSString stringWithFormat:@"%i", (int)numPlayers[currentPart - 1]];
}

- (CGPoint)scoreCoordinatesFromStreamNumber:(NSInteger)stream withCoordinates:(CGPoint)streamCoordinates
{
    int x, y;
    switch (stream) {
        case 0:
            x = 768 - ((int)streamCoordinates.x % 768);
            y = streamCoordinates.y;
            break;
        case 1:
            x = 768 - streamCoordinates.y;
            y = 768 - ((int)streamCoordinates.x % 768);
            break;
        case 2:
            x = (int)streamCoordinates.x % 768;
            y = 768 - streamCoordinates.y;
            break;
        case 3:
            x = streamCoordinates.y;
            y = (int)streamCoordinates.x % 768;
            break;
        default:
            x = 0;
            y = 0;
            break;
    }
    
    return CGPointMake(x, y);
}

- (void)initControllerLayers
{
    uiColours = [self getUIColours];
    
    controllerLayer = [CALayer layer];
    controllerLayer.bounds = CGRectMake(0, 0, MAX(canvas.bounds.size.width, canvas.bounds.size.height), MIN(canvas.bounds.size.width, canvas.bounds.size.height));
    controllerLayer.anchorPoint = CGPointZero;
    controllerLayer.position = CGPointZero;
    
    UIImage *controllerBackground = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:@"controller_1.jpg"]];
    controllerLayer.contents = (id)controllerBackground.CGImage;
    
    articulationSeletionLayer = [CALayer layer];
    articulationSeletionLayer.borderColor = ((UIColor *)[uiColours objectAtIndex:0]).CGColor;
    articulationSeletionLayer.backgroundColor = [UIColor clearColor].CGColor;
    articulationSeletionLayer.anchorPoint = CGPointZero;
    articulationSeletionLayer.frame = CGRectMake(54, 275, 28, 28);
    articulationSeletionLayer.borderWidth = 4;
    [controllerLayer addSublayer:articulationSeletionLayer];
    
    durationSelectionLayer = [CALayer layer];
    durationSelectionLayer.borderColor = ((UIColor *)[uiColours objectAtIndex:0]).CGColor;
    durationSelectionLayer.backgroundColor = [UIColor clearColor].CGColor;
    durationSelectionLayer.anchorPoint = CGPointZero;
    durationSelectionLayer.frame = CGRectMake(42, 529, 80, 28);
    durationSelectionLayer.borderWidth = 4;
    [controllerLayer addSublayer:durationSelectionLayer];
    
    holdSelectionLayer = [CALayer layer];
    holdSelectionLayer.borderColor = ((UIColor *)[uiColours objectAtIndex:0]).CGColor;
    holdSelectionLayer.backgroundColor = [UIColor clearColor].CGColor;
    holdSelectionLayer.anchorPoint = CGPointZero;
    holdSelectionLayer.frame = CGRectMake(62, 151, 53, 51);
    holdSelectionLayer.borderWidth = 4;
    [controllerLayer addSublayer:holdSelectionLayer];
    
    durationBar = [CALayer layer];
    pitchBar = [CALayer layer];
    dynamicBar = [CALayer layer];
    rateBar = [CALayer layer];
    compassBar = [CALayer layer];
    
    barArray = [NSArray arrayWithObjects:durationBar, pitchBar, dynamicBar, rateBar, compassBar, nil];
    barBase = 678;
    barWidth = 41;
    barHeights[0] = barBase - 431;
    barHeights[1] = barBase - 220;
    barHeights[2] = barBase - 185;
    barHeights[3] = barBase - 208;
    barHeights[4] = barBase - 300;
    barX[0] = 375;
    barX[1] = 510;
    barX[2] = 625;
    barX[3] = 740;
    barX[4] = 856;
    
    for (int i = 0; i < 5; i++) {
        ((CALayer *)[barArray objectAtIndex:i]).backgroundColor = ((UIColor *)[uiColours objectAtIndex:0]).CGColor;
        ((CALayer *)[barArray objectAtIndex:i]).anchorPoint = CGPointMake(0, 1);
        ((CALayer *)[barArray objectAtIndex:i]).frame = CGRectMake(barX[i], barBase, barWidth, 0);
        [controllerLayer addSublayer:[barArray objectAtIndex:i]];
    }
    
    numPlayersLayer = [CATextLayer layer];
    numPlayersLayer.font = (__bridge CFTypeRef)@"Helvetica";
    numPlayersLayer.string = @"1";
    numPlayersLayer.alignmentMode = kCAAlignmentCenter;
    numPlayersLayer.foregroundColor = [UIColor whiteColor].CGColor;
    numPlayersLayer.frame = CGRectMake(479, 22, 42, 46);
    numPlayersLayer.contentsScale = [[UIScreen mainScreen] scale];
    [controllerLayer addSublayer:numPlayersLayer];
    
    toPerformer = [CALayer layer];
    toPerformer.borderWidth = 1;
    toPerformer.borderColor = [UIColor blackColor].CGColor;
    toPerformer.frame = CGRectMake(954, 123, 50, 50);
    toPerformer.contents = (id)[Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:@"performer.png"]].CGImage;
    [controllerLayer addSublayer:toPerformer];
}

- (void)initPlayerLayers
{
    NSInteger width = MAX(canvas.bounds.size.width, canvas.bounds.size.height);
    NSInteger height = MIN(canvas.bounds.size.width, canvas.bounds.size.height);
    playerLayer = [CALayer layer];
    playerLayer.bounds = CGRectMake(0, 0, width, height);
    playerLayer.anchorPoint = CGPointZero;
    playerLayer.position = CGPointZero;
    
    //Reading line
    readLine = [CALayer layer];
    readLine.anchorPoint = CGPointMake(0.5, 0);
    readLine.bounds = CGRectMake(0, 0, 4, width);
    readLine.position = CGPointMake(150, 0);
    readLine.backgroundColor = [UIColor blackColor].CGColor;
    //[playerLayer addSublayer:readLine];
    
    //Create scrolling layer and populate it with the necessary sublayers
    scroller = [CALayer layer];
    scroller.anchorPoint = CGPointZero;
    scroller.bounds = CGRectMake(0, 0, RODINIA_FRAMERATE * RODINIA_SCROLLRATE * UIDelegate.clockDuration, playerLayer.bounds.size.height - LOWER_PADDING);
    scroller.position = CGPointMake(150 , 0);
    //[playerLayer insertSublayer:scroller below:readLine];
    
    blackLayer = [CALayer layer];
    blackLayer.bounds = CGRectMake(0, 0, width, height);
    blackLayer.anchorPoint = CGPointZero;
    blackLayer.position = CGPointZero;
    blackLayer.backgroundColor = [UIColor blackColor].CGColor;
    [playerLayer addSublayer:blackLayer];
    
    scoreLayer = [CALayer layer];
    scoreLayer.bounds = CGRectMake(0, 0, 768, 768);
    scoreLayer.position = CGPointMake(playerLayer.bounds.size.width / 2, playerLayer.bounds.size.height / 2);
    scoreLayer.backgroundColor = [UIColor whiteColor].CGColor;
    scoreLayer.masksToBounds = YES;
    [playerLayer addSublayer:scoreLayer];
    
    toConductor = [CALayer layer];
    toConductor.borderWidth = 1;
    toConductor.borderColor = [UIColor blackColor].CGColor;
    toConductor.frame = CGRectMake(954, 53, 50, 50);
    toConductor.contents = (id)[Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:@"conductor.png"]].CGImage;
    [playerLayer addSublayer:toConductor];
    
    //Initialise our stream layers.
    streamLayers = [[NSMutableArray alloc] init];
    for (int i = 0; i < 4; i++) {
        CALayer *streamLayer = [CALayer layer];
        streamLayer.anchorPoint = CGPointZero;
        streamLayer.frame = CGRectMake(streamXOffset, 0, RODINIA_FRAMERATE * RODINIA_SCROLLRATE * UIDelegate.clockDuration, playerLayer.bounds.size.height - LOWER_PADDING);
        [streamLayers addObject:streamLayer];
    }
}

- (void)changePart:(NSInteger)relativeChange
{
    NSInteger newPart = currentPart + relativeChange;
    if (newPart > 4) {
        newPart = 0;
    } else if (newPart < 0) {
        newPart = 4;
    }
        
    currentPart = newPart;
    
    if (currentPart == 0) {
        if (scoreLayer.superlayer == nil) {
            [playerLayer insertSublayer:scoreLayer below:toConductor];
            [playerLayer insertSublayer:blackLayer below:scoreLayer];
            [scroller removeFromSuperlayer];
            [readLine removeFromSuperlayer];
        }
    } else {
        if (scroller.superlayer == nil) {
            [playerLayer insertSublayer:scroller below:toConductor];
            [playerLayer insertSublayer:readLine above:scroller];
            [scoreLayer removeFromSuperlayer];
            [blackLayer removeFromSuperlayer];
        }
        
        scroller.sublayers = nil;
        [scroller addSublayer:[streamLayers objectAtIndex:currentPart - 1]];
    }
}

- (void)scrollerAnimate
{
    [CATransaction begin];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    scroller.position = CGPointMake(scroller.position.x - RODINIA_SCROLLRATE, 0);
    [CATransaction commit];
    if (scroller.position.x <= 150 - scroller.bounds.size.width) {
        [scrollTimer invalidate];
    }
}

- (void)showEvent:(NSTimer *)timer
{
    [scoreLayer addSublayer:((RodiniaEvent *)timer.userInfo).layer];
    [eventTimers removeObjectIdenticalTo:timer];
}

- (void)relayMessageToExternal:(OSCMessage *)message
{
    OSCMessage *external = [[OSCMessage alloc] init];
    [external copyAddressFromMessage:message];
    if ([[external.address objectAtIndex:0] isEqualToString:@"Renderer"]) {
        [external stripFirstAddressComponent];
    }
    [external prependAddressComponent:@"External"];
    [external appendArgumentsFromMessage:message];
    [messagingDelegate sendData:external];
}

#pragma mark - Renderer delegate

- (void)setIsMaster:(BOOL)master
{
    isMaster = master;
}

- (BOOL)isMaster
{
    return isMaster;
}

+ (RendererFeatures)getRendererRequirements
{
    //return kFileName | kPrefsFile | kPositiveDuration;
    return kFileName | kPositiveDuration | kUsesScaledCanvas;
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    
    score = scoreData;
    canvas = playerCanvas;
    UIDelegate = UIDel;
    messagingDelegate = messagingDel;
    UIDelegate.clockVisible = NO;
    UIDelegate.splitSecondMode = YES;
    [UIDelegate setMarginColour:[UIColor blackColor]];
    
    maxLength = 200;
    streamXOffset = 512;
    
    [self initControllerLayers];
    [self initPlayerLayers];
    
    eventColours = [self getColourArray];
    
    currentPart = 1;
    viewMode = kController;
    
    events = [[NSMutableArray alloc] init];
    for (int i = 0; i < 4; i++) {
        [events addObject:[[NSMutableArray alloc] init]];
    }
    eventTimers = [[NSMutableArray alloc] init];
    
    return self;
}

- (void)close
{
    [scrollTimer invalidate];
    
    for (int i = 0; i < [eventTimers count]; i++) {
        [[eventTimers objectAtIndex:i] invalidate];
    }
}

- (void)reset
{
    canvas.sublayers = nil;
    scoreLayer.sublayers = nil;
    scroller.position = CGPointMake(150, 0);
    [scrollTimer invalidate];
    
    for (int i = 0; i < [eventTimers count]; i++) {
        [[eventTimers objectAtIndex:i] invalidate];
    }
    [eventTimers removeAllObjects];
    
    for (int i = 0; i < [streamLayers count]; i++) {
        ((CALayer *)[streamLayers objectAtIndex:i]).sublayers = nil;
    }
    
    //Clear events
    for (int i = 0; i < [events count]; i++) {
        [[events objectAtIndex:i] removeAllObjects];
    }
    
    //Reset state variables
    for (int i = 0; i < 4; i++) {
        numPlayers[i] = 4;
        holdStates[i] = NO;
        durationTypes[i] = 0;
        articulations[i] = kNormal;
        ghostStates[i] = NO;
        barStates[i][0] = 0;
        barStates[i][1] = 0.5;
        barStates[i][2] = 0.5;
        barStates[i][3] = 0.5;
        barStates[i][4] = 0;
    }
    [self updateControllerUIFromState];
    
    for (int i = 0; i < 4; i++) {
        streamStates[i].location.x = 0;
        streamStates[i].location.y = 768 / 2;
        streamStates[i].heading = 0;
        xFromLastEvent[i] = maxLength;
    }
    
    if (viewMode == kController) {
        [canvas addSublayer:controllerLayer];
    } else {
        [canvas addSublayer:playerLayer];
    }
}

- (void)play
{
    scrollTimer = [NSTimer scheduledTimerWithTimeInterval:(1 / (float)RODINIA_FRAMERATE) target:self selector:@selector(scrollerAnimate) userInfo:nil repeats:YES];
}

- (void)receiveMessage:(OSCMessage *)message
{
    if ([message.address count] < 1) {
        return;
    }
    
    if ([[message.address objectAtIndex:0] isEqualToString:@"StreamStates"]) {
        if (![message.typeTag isEqualToString:@",iifiifiifiif"]) {
            return;
        }
        for (int i = 0; i < 4; i++) {
            int x = [[message.arguments objectAtIndex:3 * i] intValue];
            int y = [[message.arguments objectAtIndex:3 * i + 1] intValue];
            CGFloat heading = [[message.arguments objectAtIndex:3 * i + 2] floatValue];
            
            //Clamp values
            x = x < 0 ? 0 : x;
            y = y < 0 ? 0 : y;
            y = y > 768 ? 768: y;
            heading = heading > 2 ? 2 : heading;
            heading = heading < -2 ? -2 : heading;
            
            streamStates[i].location = CGPointMake(x, y);
            streamStates[i].heading = heading;
        }
        
        return;
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"Event"]) {
        //stream, x, y, player. All other data should be able to be taken from the currently stored control values.
        if (![message.typeTag isEqualToString:@",iiii"]) {
            return;
        }
        
        int stream = [[message.arguments objectAtIndex:0] intValue];
        int x = [[message.arguments objectAtIndex:1] intValue];
        int y = [[message.arguments objectAtIndex:2] intValue];
        int player = [[message.arguments objectAtIndex:3] intValue];
        
        //Clamp values
        stream = stream < 0 ? 0 : stream;
        stream = stream > 3 ? 3 : stream;
        player = player < 0 ? 0 : player;
        player = player > 3 ? 3 : player;
        x = x < 0 ? 0 : x;
        y = y < 0 ? 0 : y;
        y = y > 768 ? 768 : y;
        
        //Create the event
        BOOL tremolo = NO;
        if (durationTypes[stream] == 3) {
            tremolo = YES;
        }
        
        int glissAmount = 0;
        if (durationTypes[stream] == 1) {
            glissAmount = -20;
        } else if (durationTypes[stream] == 2) {
            glissAmount = 20;
        }
        
        int volume = 3 - floorf(4 * barStates[stream][2]);
        if (volume < 0) {
            volume = 0;
        }
        
        RodiniaEvent *event = [[RodiniaEvent alloc] initWithArticulation:articulations[stream] glissAmount:glissAmount ghost:ghostStates[stream] tremolo:tremolo length:maxLength * barStates[stream][0]];
        //event.colour = [[eventColours objectAtIndex:stream] objectAtIndex:player];
        event.colour = [[eventColours objectAtIndex:stream] objectAtIndex:volume];
        event.streamPosition = CGPointMake(x, y);
        
        RodiniaEvent *playerEvent = [[RodiniaEvent alloc] initAsDuplicateOfEvent:event];
        playerEvent.layer.position = event.streamPosition;
        [[streamLayers objectAtIndex:stream] addSublayer:playerEvent.layer];
        
        event.rotation = stream;
        event.layer.position = [self scoreCoordinatesFromStreamNumber:stream withCoordinates:event.streamPosition];
        [[events objectAtIndex:stream] addObject:event];
        NSTimer *eventTimer = [NSTimer scheduledTimerWithTimeInterval:(CGFloat)streamXOffset / (RODINIA_SCROLLRATE * RODINIA_FRAMERATE) target:self selector:@selector(showEvent:) userInfo:event repeats:NO];
        [eventTimers addObject:eventTimer];
        
        return;
    }
    
    //All messages past this point deal with controller variables. Check that we have a valid player number setting.
    if (![message.typeTag hasPrefix:@",i"] && ([[message.arguments objectAtIndex:0] integerValue] > 3 || [[message.arguments objectAtIndex:0] integerValue] < 0)) {
        return;
    }
    
    int part = [[message.arguments objectAtIndex:0] intValue];
    
    if ([[message.address objectAtIndex:0] isEqualToString:@"Articulation"]) {
        if (![message.typeTag isEqualToString:@",iii"]) {
            return;
        }
        int newArticulation = [[message.arguments objectAtIndex:1] intValue];
        if (newArticulation < 0 || newArticulation > 2) {
            return;
        }
        
        //We only need to update values if they don't match, and the UI if we're on the specific controller view.
        BOOL updateUI = NO;
        if (articulations[part] != newArticulation) {
            articulations[part] = newArticulation;
            updateUI = YES;
        }
        
        BOOL newGhosted = NO;
        if ([[message.arguments objectAtIndex:2] integerValue] == 1) {
            newGhosted = YES;
        }
        if (ghostStates[part] != newGhosted) {
            ghostStates[part] = newGhosted;
            updateUI = YES;
        }
        
        if (updateUI && currentPart == part + 1) {
            [self updateControllerUIFromState];
        }
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"DurationType"]) {
        if (![message.typeTag isEqualToString:@",ii"]) {
            return;
        }
        
        int newDurationType = [[message.arguments objectAtIndex:1] intValue];
        if (newDurationType < 0 || newDurationType > 3) {
            return;
        }
        
        if (durationTypes[part] != newDurationType) {
            durationTypes[part] = newDurationType;
            if (currentPart == part + 1) {
                [self updateControllerUIFromState];
            }
        }
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"Hold"]) {
        if (![message.typeTag isEqualToString:@",ii"]) {
            return;
        }
        
        BOOL newHold = NO;
        if ([[message.arguments objectAtIndex:1] integerValue] == 1) {
            newHold = YES;
        }
        
        if (holdStates[part] != newHold) {
            holdStates[part] = newHold;
            if (currentPart == part + 1) {
                [self updateControllerUIFromState];
            }
        }
        
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"PlayerNumbers"]) {
        if (![message.typeTag isEqualToString:@",ii"]) {
            return;
        }
        
        int newPlayerNumber = [[message.arguments objectAtIndex:1] intValue];
        if (newPlayerNumber < 1 || newPlayerNumber > 4) {
            return;
        }
        
        if (numPlayers[part] != newPlayerNumber) {
            numPlayers[part] = newPlayerNumber;
            if (currentPart == part + 1) {
                [self updateControllerUIFromState];
            }
        }
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"BarValue"]) {
        if (![message.typeTag isEqualToString:@",iif"]) {
            return;
        }
        
        int barIndex = [[message.arguments objectAtIndex:1] intValue];
        if (barIndex < 0 || barIndex > 4) {
            return;
        }
        
        CGFloat newValue = [[message.arguments objectAtIndex:2] floatValue];
        if (newValue < 0 || newValue > 1) {
            return;
        }
        
        if (barStates[part][barIndex] != newValue) {
            barStates[part][barIndex] = newValue;
            if (currentPart == part + 1) {
                [self updateControllerUIFromState];
            }
        }
        
    }
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    if (!isMaster) {
        return;
    }
    
    OSCMessage *state = [[OSCMessage alloc] init];
    [state appendAddressComponent:@"StreamStates"];
    
    CGFloat headings[4];
    
    //Check headings based on controller input
    for (int i = 0; i < 4; i++) {
        if (streamStates[i].location.y == 768 - (barStates[i][1] * 768)) {
            headings[i] = 0;
        } else if (streamStates[i].location.y < 768 - (barStates[i][1] * 768)) {
            if (fabs(768 - (barStates[i][1] * 768) - streamStates[i].location.y) <= RODINIA_FRAMERATE * RODINIA_SCROLLRATE / 2) {
                headings[i] = 0;
                streamStates[i].location.y = 768 - (barStates[i][1] * 768);
            } else {
                headings[i] = 1;
            }
        } else {
            if (fabs(streamStates[i].location.y - 768 - (barStates[i][1] * 768)) <= RODINIA_FRAMERATE * RODINIA_SCROLLRATE / 2) {
                headings[i] = 0;
                streamStates[i].location.y = 768 - (barStates[i][1] * 768);
            } else {
                headings[i] = -1;
            }
        }
        
        //Average desired heading with previous heading
        if (headings[i] != 0) {
            headings[i] = (headings[i] + streamStates[i].heading / 2);
        }
    }
    
    //Now make any heading overrides to avoid a collision
    //Check opposing streams first
    for (int i = 0; i < 2; i++) {
        //Check distance.
        CGPoint location1 = [self scoreCoordinatesFromStreamNumber:i withCoordinates:streamStates[i].location];
        CGPoint location2 = [self scoreCoordinatesFromStreamNumber:i + 2 withCoordinates:streamStates[i + 2].location];
        
        CGFloat distance = sqrt(powf(location1.x - location2.x, 2) + powf(location1.y - location2.y, 2));
        if (distance < 250) {
            //Start repelling one another. If our first stream is higher then they both need a positive heading. Otherwise the reverse is true.
            if (location1.y >= location2.y) {
                headings[i] += ((250 - distance) / 250) * 3;
                headings[i + 2] += ((250 - distance) / 250) * 3;
            } else {
                headings[i] -= ((250 - distance) / 250) * 3;
                headings[i + 2] -= ((250 - distance) / 250) * 3;
            }
        }
    }
    
    int signs[4][2] = {{1, 1}, {-1, -1}, {-1, 1}, {1, -1}};
    
    //Then perpendicular streams.
    for (int i = 0; i <= 2; i += 2) {
        CGPoint location = [self scoreCoordinatesFromStreamNumber:i withCoordinates:streamStates[i].location];
        
        for (int j = 1; j <= 3; j += 2) {
            CGPoint perpendicular = [self scoreCoordinatesFromStreamNumber:j withCoordinates:streamStates[j].location];
            
            CGFloat distance = sqrt(powf(location.x - perpendicular.x, 2) + powf(location.y - perpendicular.y, 2));
            if (distance < 250) {
                int index = (j - 1) / 2;
                headings[i] += ((250 - distance) / 250) * signs[i + index][0];
                headings[j] += ((250 - distance) / 250) * signs[i + index][1];
            }
        }
    }
    
    //Clamp our values
    for (int i = 0; i < 4; i++) {
        headings[i] = headings[i] > 2 ? 2 : headings[i];
        headings[i] = headings[i] < -2 ? -2 : headings[i];
    }
    
    for (int i = 0; i < 4; i++) {
        if (!holdStates[i] && xFromLastEvent[i] >= (maxLength * barStates[i][0] + arc4random_uniform(RODINIA_FRAMERATE * RODINIA_SCROLLRATE))) {
            OSCMessage *event = [[OSCMessage alloc] init];
            [event appendAddressComponent:@"Event"];
            [event addIntegerArgument:i];
            [event addIntegerArgument:streamStates[i].location.x + arc4random_uniform(12)];
            [event addIntegerArgument:streamStates[i].location.y + ((CGFloat)((int)(arc4random_uniform(200) - 100)) * barStates[i][4])];
            [event addIntegerArgument:(int)arc4random_uniform((uint)numPlayers[i])];
            [messagingDelegate sendData:event];
            
            [self relayMessageToExternal:event];
            xFromLastEvent[i] = 0;
        } else {
            xFromLastEvent[i] += RODINIA_FRAMERATE * RODINIA_SCROLLRATE / 2;
        }
        [state addIntegerArgument:streamStates[i].location.x + (RODINIA_FRAMERATE * RODINIA_SCROLLRATE / 2)];
        [state addIntegerArgument:streamStates[i].location.y + (headings[i] * (RODINIA_FRAMERATE * RODINIA_SCROLLRATE / 2))];
        [state addFloatArgument:headings[i]];
    }

    [messagingDelegate sendData:state];
}

- (void)tapAt:(CGPoint)location
{
    if (viewMode == kController) {
        //Part change
        if (location.x > 252 && location.x < 358 && location.y > 26 && location.y < 68) {
            currentPart = (currentPart + 1) % 5;
            if (currentPart == 0) {
                currentPart++;
            }
            controllerLayer.contents = (id)[Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:[NSString stringWithFormat:@"controller_%i.jpg", (int)currentPart]]].CGImage;
            articulationSeletionLayer.borderColor = ((UIColor *)[uiColours objectAtIndex:currentPart - 1]).CGColor;
            durationSelectionLayer.borderColor = ((UIColor *)[uiColours objectAtIndex:currentPart - 1]).CGColor;
            holdSelectionLayer.borderColor = ((UIColor *)[uiColours objectAtIndex:currentPart - 1]).CGColor;
            
            for (int i = 0; i < 5; i++) {
                ((CALayer *)[barArray objectAtIndex:i]).backgroundColor = ((UIColor *)[uiColours objectAtIndex:currentPart - 1]).CGColor;
            }
            
            [self updateControllerUIFromState];
        }
        //TODO: currently only dealing with UI issues - need to add control structures here as well.
        //Articulations
        if (location.x > 56 && location.x < 192) {
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"Articulation"];
            [message addIntegerArgument:currentPart - 1];
            if (location.y > 277 && location.y < 301) {
                [self selectArticulation:kNormal ghosted:NO];
                articulations[currentPart - 1] = kNormal;
                ghostStates[currentPart - 1] = NO;
                [message addIntegerArgument:kNormal];
                [message addIntegerArgument:0];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            } else if (location.y > 308 && location.y < 332) {
                [self selectArticulation:kNoise ghosted:NO];
                articulations[currentPart - 1] = kNoise;
                ghostStates[currentPart - 1] = NO;
                [message addIntegerArgument:kNoise];
                [message addIntegerArgument:0];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            } else if (location.y > 338 && location.y < 362) {
                [self selectArticulation:kPoint ghosted:NO];
                articulations[currentPart - 1] = kPoint;
                ghostStates[currentPart - 1] = NO;
                [message addIntegerArgument:kPoint];
                [message addIntegerArgument:0];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            } else if (location.y > 375 && location.y < 399) {
                [self selectArticulation:kNormal ghosted:YES];
                articulations[currentPart - 1] = kNormal;
                ghostStates[currentPart - 1] = YES;
                [message addIntegerArgument:kNormal];
                [message addIntegerArgument:1];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            } else if (location.y > 405 && location.y < 429) {
                [self selectArticulation:kNoise ghosted:YES];
                articulations[currentPart - 1] = kNoise;
                ghostStates[currentPart - 1] = YES;
                [message addIntegerArgument:kNoise];
                [message addIntegerArgument:1];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            } else if (location.y > 436 && location.y < 460) {
                [self selectArticulation:kPoint ghosted:YES];
                articulations[currentPart - 1] = kPoint;
                ghostStates[currentPart - 1] = YES;
                [message addIntegerArgument:kPoint];
                [message addIntegerArgument:1];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            }
        }
        
        //Duration types
        if (location.x > 44 && location.x < 209) {
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"DurationType"];
            [message addIntegerArgument:currentPart - 1];
            if (location.y > 531 && location.y < 555) {
                [self selectDurationStyle:0];
                durationTypes[currentPart - 1] = 0;
                [message addIntegerArgument:0];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            } else if (location.y > 564 && location.y < 605) {
                [self selectDurationStyle:1];
                durationTypes[currentPart - 1] = 1;
                [message addIntegerArgument:1];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            } else if (location.y > 610 && location.y < 651) {
                [self selectDurationStyle:2];
                durationTypes[currentPart - 1] = 2;
                [message addIntegerArgument:2];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            } else if (location.y > 657 && location.y < 681) {
                [self selectDurationStyle:3];
                durationTypes[currentPart - 1] = 3;
                [message addIntegerArgument:3];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            }
        }
        
        //Play/Hold
        if (location.y > 153 && location.y < 200) {
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"Hold"];
            [message addIntegerArgument:currentPart - 1];
            if (location.x > 64 && location.x < 113) {
                [self selectHold:NO];
                holdStates[currentPart - 1] = NO;
                [message addIntegerArgument:0];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            } else if (location.x > 153 && location.x < 202) {
                [self selectHold:YES];
                holdStates[currentPart - 1] = YES;
                [message addIntegerArgument:1];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            }
        }
        
        //Number of players
        if (location.x > 479 && location.x < 521) {
            if (location.y > 22 && location.y < 68) {
                OSCMessage *message = [[OSCMessage alloc] init];
                [message appendAddressComponent:@"PlayerNumbers"];
                [message addIntegerArgument:currentPart - 1];
                (numPlayers[currentPart - 1])++;
                if (numPlayers[currentPart - 1] > 4) {
                    numPlayers[currentPart - 1] = 1;
                }
                numPlayersLayer.string = [NSString stringWithFormat:@"%i", (int)numPlayers[currentPart - 1]];
                [message addIntegerArgument:numPlayers[currentPart - 1]];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            }
        }
        
        //To player view
        if (location.x > 954 && location.x < 1004 && location.y > 123 && location.y < 173) {
            viewMode = kPlayer;
            [controllerLayer removeFromSuperlayer];
            [canvas addSublayer:playerLayer];
        }
        
    } else {
        //Player UI
        if (location.x > 954 && location.x < 1004 && location.y > 73 && location.y < 123) {
            viewMode = kController;
            [playerLayer removeFromSuperlayer];
            [canvas addSublayer:controllerLayer];
        }
    }
}

- (void)swipeUp {
    if (viewMode != kPlayer) {
        return;
    } else {
        [self changePart:1];
    }
}

-(void)swipeDown {
    if (viewMode != kPlayer) {
        return;
    } else {
        [self changePart:-1];
    }
}

- (void)panAt:(CGPoint)location
{
    //Bars
    if (viewMode != kController) {
        return;
    }
    
    for (int i = 0; i < 5; i++) {
        if (location.x > barX[i] && location.x < (barX[i] + barWidth)) {
            if (location.y <= barBase && location.y >= (barBase - barHeights[i])) {
                OSCMessage *message = [[OSCMessage alloc] init];
                [message appendAddressComponent:@"BarValue"];
                [message addIntegerArgument:currentPart - 1];
                [message addIntegerArgument:i];
                //Change of anchor point.
                //((CALayer *)[barArray objectAtIndex:i]).frame = CGRectMake(barX[i], location.y, barWidth, barBase - location.y);
                ((CALayer *)[barArray objectAtIndex:i]).bounds = CGRectMake(0, 0, barWidth, barBase - location.y);
                CGFloat barValue = (CGFloat)(barBase - location.y) / barHeights[i];
                barStates[currentPart - 1][i] = barValue;
                [message addFloatArgument:barValue];
                [messagingDelegate sendData:message];
                [self relayMessageToExternal:message];
            }
        }
    }
}

@end

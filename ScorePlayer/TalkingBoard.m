//
//  TalkingBoard.m
//  ScorePlayer
//
//  Created by Aaron Wyatt and Stuart James on 14/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "TalkingBoard.h"
#import "Score.h"
#import "OSCMessage.h"

const NSInteger BACKGROUNDS_PER_MESSAGE = 50;
const NSInteger PLANCHETTES_PER_MESSAGE = 100;
const NSInteger SOLOS_PER_MESSAGE = 50;
const NSInteger HEADER_LENGTH = 7;

@interface TalkingBoard ()

- (void)generateLocationData;
- (NSMutableDictionary *)generateLocationDataMessages;
- (void)extractDataFromLocationMessages:(NSDictionary *)messages startingAtMessage:(int)messageNumber;
- (void)animatePlanchettes:(int)progress;
- (void)animateBackground:(NSNumber *)progress;
- (CGPoint)generateNewPosition;
- (void)initLayers;
- (void)renderLayers;

@end

@implementation TalkingBoard {
    Score *score;
    CALayer *canvas;
    CALayer *blackout;
    
    NSInteger screenWidth;
    NSInteger screenHeight;
    
    CALayer *backgroundLayer;
    NSMutableArray *backgroundLocations;
    int backgroundIndex;
    int backgroundAdjust;
    BOOL didLeap;
    
    NSMutableArray *planchettes;
    NSMutableArray *planchetteLocations;
    int numberOfPlanchettes;
    uint maxPlanchettes;
    int *planchetteAdjust;
    int *planchetteIndex;
    NSMutableArray *solos;
    int soloIndex;
    int soloPlanchette;
    
    BOOL didSeek;
    BOOL seekNotRequired;
    BOOL awaitingSeek;
    
    NSXMLParser *xmlParser;
    NSMutableString *currentString;
    xmlLocation currentPrefs;
    UIColor *planchetteColour;
    NSInteger currentIndex;
    BOOL isData;
    
    //Networking
    BOOL hasData;
    NSMutableDictionary *locationMessages;
    int expectedCount;
    int generationNumber;
    NSLock *dictionaryLock;
    NSLock *extractionLock;
    NSLock *generationLock;
    
    //Debug
    BOOL debug;
    UILabel *timer;
    UILabel *leap;
    UILabel *transition;
    int leapCount;
    int transitionCount;
    
    __weak id<RendererUI> UIDelegate;
    __weak id<RendererMessaging> messagingDelegate;
}

- (void)generateLocationData
{
    //Generate arrays of points that will serve as the location data for the background and planchettes
    //for the duration of the score.
    generationNumber++;
    
    //First generate our backgrounds
    backgroundLocations = [[NSMutableArray alloc] init];
    int backgroundRemaining = UIDelegate.clockDuration;
    BOOL completed = NO;
    BOOL lastOne = NO;
    
    while (!completed) {
        //Create a transition length that varies between 15 and 20 seconds.
        int transitionLength = 15 + arc4random_uniform(6);
        //If this isn't the first background location, and the previous transition wasn't a leap
        //then allow the chance that this could be one.
        if ([backgroundLocations count] > 0 && [[[backgroundLocations lastObject] objectAtIndex:2] intValue] != 0) {
            if (arc4random_uniform(100) < 25) {
                transitionLength = 0;
            }
        }

        NSMutableArray *currentTransition = [[NSMutableArray alloc] init];
        [currentTransition addObject:[NSNumber numberWithInt:UIDelegate.clockDuration - backgroundRemaining]];
        [currentTransition addObject:[NSValue valueWithCGPoint:[self generateNewPosition]]];
        [currentTransition addObject:[NSNumber numberWithInt:transitionLength]];
        [backgroundLocations addObject:currentTransition];
        
        //Check to see if this is our last pass.
        if (lastOne) {
            completed = YES;
        } else {
            backgroundRemaining -= transitionLength;
            if (backgroundRemaining < 0) {
                lastOne = YES;
            }
        }
    }

    //Then generate our planchette data
    planchetteLocations = [[NSMutableArray alloc] init];
    int swarm = 0;
    int formation = 0;
    int planchetteProgress[maxPlanchettes];
    for (int i = 0; i < maxPlanchettes; i++) {
        [planchetteLocations addObject:[[NSMutableArray alloc] init]];
        planchetteProgress[i] = 0;
    }
    int timeUntilNextBehaviour = 20 + (int)arc4random_uniform(6);
    
    for (int i = 0; i < UIDelegate.clockDuration + 10; i++) {
        //Check if we should change behaviour.
        if (timeUntilNextBehaviour == 0) {
            int selectedBehaviour = arc4random_uniform(2);
            if (selectedBehaviour == 0) {
                swarm = 10 + arc4random_uniform(5);
            } else {
                formation = 10 + arc4random_uniform(5);
            }
            
            timeUntilNextBehaviour = 20 + (int)arc4random_uniform(6);
        }
        
        //Branch based on our current behaviour
        if (swarm != 0) {
            //Swarm around a central point
            CGPoint swarmPoint = CGPointMake((int)arc4random_uniform((int)screenWidth + 240) - 120, (int)arc4random_uniform((int)screenHeight + 240) - 120);
            int swarmTime = 3 + arc4random_uniform(3);
            
            for (int j = 0; j < maxPlanchettes; j++) {
                if (i == planchetteProgress[j]) {
                    int x = swarmPoint.x - 30 + arc4random_uniform(60);
                    int y = swarmPoint.y - 30 + arc4random_uniform(60);
                    
                    NSMutableArray *nextCoordinates = [[NSMutableArray alloc] init];
                    [nextCoordinates addObject:[NSNumber numberWithInt:i]];
                    [nextCoordinates addObject:[NSValue valueWithCGPoint:CGPointMake(x, y)]];
                    [nextCoordinates addObject:[NSNumber numberWithInt:swarmTime]];
                    [[planchetteLocations objectAtIndex:j] addObject:nextCoordinates];
                    planchetteProgress[j] += swarmTime;
                }
            }
            swarm--;
        } else if (formation != 0) {
            //Move in formation
            CGPoint formationOffset = CGPointMake((int)arc4random_uniform(600) - 300, (int)arc4random_uniform(600) - 300);
            int formationTime = 3 + arc4random_uniform(3);
            
            for (int j = 0; j < maxPlanchettes; j++) {
                if (i == planchetteProgress[j]) {
                    int x = [[[[planchetteLocations objectAtIndex:j] lastObject] objectAtIndex:1] CGPointValue].x + formationOffset.x;
                    int y = [[[[planchetteLocations objectAtIndex:j] lastObject] objectAtIndex:1] CGPointValue].y + formationOffset.y;
                    
                    NSMutableArray *nextCoordinates = [[NSMutableArray alloc] init];
                    [nextCoordinates addObject:[NSNumber numberWithInt:i]];
                    [nextCoordinates addObject:[NSValue valueWithCGPoint:CGPointMake(x, y)]];
                    [nextCoordinates addObject:[NSNumber numberWithInt:formationTime]];
                    [[planchetteLocations objectAtIndex:j] addObject:nextCoordinates];
                    planchetteProgress[j] += formationTime;
                }
            }
            formation--;
        } else {
            //Default behaviour
            for (int j = 0; j < maxPlanchettes; j++) {
                if (i == planchetteProgress[j]) {
                    int x = (int)arc4random_uniform((int)screenWidth + 240) - 120;
                    int y = (int)arc4random_uniform((int)screenHeight + 240) - 120;
                    int time = 4 + arc4random_uniform(5);
                    
                    //Make sure that our random wandering doesn't cut into other group behaviours.
                    if (time > timeUntilNextBehaviour) {
                        time = timeUntilNextBehaviour;
                    }
                    
                    if (time > 0) {
                    NSMutableArray *nextCoordinates = [[NSMutableArray alloc] init];
                        [nextCoordinates addObject:[NSNumber numberWithInt:i]];
                        [nextCoordinates addObject:[NSValue valueWithCGPoint:CGPointMake(x, y)]];
                        [nextCoordinates addObject:[NSNumber numberWithInt:time]];
                        [[planchetteLocations objectAtIndex:j] addObject:nextCoordinates];
                        planchetteProgress[j] += time;
                    }
                }
            }
            timeUntilNextBehaviour--;
        }
    }
    
    //Generate a list of solos
    solos = [[NSMutableArray alloc] init];
    int timeUntilNextSolo = 25 + arc4random_uniform(11);
    
    for (int i = 0; i < UIDelegate.clockDuration + 10; i++) {
        if (timeUntilNextSolo == 0) {
            int planchette = arc4random_uniform(maxPlanchettes);
            int time = 8 + arc4random_uniform(5);
            
            [solos addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithInt:i], [NSNumber numberWithInt:planchette], [NSNumber numberWithInt:time], nil]];
            
            i += time;
            timeUntilNextSolo = 30 + arc4random_uniform(11);
        }
        
        timeUntilNextSolo--;
    }
}

- (NSMutableDictionary *)generateLocationDataMessages;
{
    NSMutableDictionary *messageDictionary = [[NSMutableDictionary alloc] init];
    
    //Figure out how many messages we'll need to send.
    NSInteger backgroundMessages = 1 + ([backgroundLocations count] / BACKGROUNDS_PER_MESSAGE);
    NSInteger highestPlanchetteCount = 0;
    for (int i = 0; i < [planchetteLocations count]; i++) {
        if ([[planchetteLocations objectAtIndex:i] count] > highestPlanchetteCount) {
            highestPlanchetteCount = [[planchetteLocations objectAtIndex:i] count];
        }
    }
    NSInteger planchetteMessages = 1 + (highestPlanchetteCount / PLANCHETTES_PER_MESSAGE);
    NSInteger soloMessages = 1 + ([solos count] / SOLOS_PER_MESSAGE);
    
    NSInteger messages = backgroundMessages > planchetteMessages ? backgroundMessages : planchetteMessages;
    messages = soloMessages > messages ? soloMessages : messages;
    
    NSInteger *planchettesCount = malloc(sizeof(NSInteger) * [planchetteLocations count]);
    for (int i = 0; i < messages; i++) {
        //Create our messages.
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"InitData"];
        //Save the messages as new. If we resend them later we can just replace the argument then.
        [message addStringArgument:@"New"];
        
        //Check and clamp our numbers. First for our backgrounds.
        NSInteger backgroundCount = [backgroundLocations count] - (i * BACKGROUNDS_PER_MESSAGE);
        backgroundCount = backgroundCount > BACKGROUNDS_PER_MESSAGE ? BACKGROUNDS_PER_MESSAGE : backgroundCount;
        backgroundCount = backgroundCount > 0 ? backgroundCount : 0;
        
        //Then planchettes, and after that solos.
        NSInteger totalPlanchettes = 0;
        for (int j = 0; j < [planchetteLocations count]; j++) {
            planchettesCount[j] = [[planchetteLocations objectAtIndex:j] count] - (i * PLANCHETTES_PER_MESSAGE);
            planchettesCount[j] = planchettesCount[j] > PLANCHETTES_PER_MESSAGE ? PLANCHETTES_PER_MESSAGE : planchettesCount[j];
            planchettesCount[j] = planchettesCount[j] > 0 ? planchettesCount[j] : 0;
            totalPlanchettes += planchettesCount[j];
        }
        NSInteger soloCount = [solos count] - (i * SOLOS_PER_MESSAGE);
        soloCount = soloCount > SOLOS_PER_MESSAGE ? SOLOS_PER_MESSAGE : soloCount;
        soloCount = soloCount > 0 ? soloCount : 0;
        
        //Show which message number this is and then how many of each object we have.
        [message addIntegerArgument:i];
        //Show whether we're sending any more messages.
        if (i == (messages - 1)) {
            [message addIntegerArgument:1];
        } else {
            [message addIntegerArgument:0];
        }
        //Show which generation this is. (Avoids issues with multiple generations in quick succession.)
        [message addIntegerArgument:generationNumber];
        [message addIntegerArgument:backgroundCount];
        [message addIntegerArgument:[planchetteLocations count]];
        [message addIntegerArgument:soloCount];
        for (int j = 0; j < [planchetteLocations count]; j++) {
            [message addIntegerArgument:planchettesCount[j]];
        }
        
        //Iterate through our data
        for (int j = i * BACKGROUNDS_PER_MESSAGE; j < (i * BACKGROUNDS_PER_MESSAGE) + backgroundCount; j++) {
            [message addIntegerArgument:[[[backgroundLocations objectAtIndex:j] objectAtIndex:0] intValue]];
            [message addIntegerArgument:[[[backgroundLocations objectAtIndex:j] objectAtIndex:1] CGPointValue].x];
            [message addIntegerArgument:[[[backgroundLocations objectAtIndex:j] objectAtIndex:1] CGPointValue].y];
            [message addIntegerArgument:[[[backgroundLocations objectAtIndex:j] objectAtIndex:2] intValue]];
        }
        
        for (int j = 0; j < [planchetteLocations count]; j++) {
            for (int k = i * PLANCHETTES_PER_MESSAGE; k < (i * PLANCHETTES_PER_MESSAGE) + planchettesCount[j]; k++) {
                [message addIntegerArgument:[[[[planchetteLocations objectAtIndex:j] objectAtIndex:k] objectAtIndex:0] intValue]];
                [message addIntegerArgument:[[[[planchetteLocations objectAtIndex:j] objectAtIndex:k] objectAtIndex:1] CGPointValue].x];
                [message addIntegerArgument:[[[[planchetteLocations objectAtIndex:j] objectAtIndex:k] objectAtIndex:1] CGPointValue].y];
                [message addIntegerArgument:[[[[planchetteLocations objectAtIndex:j] objectAtIndex:k] objectAtIndex:2] intValue]];
            }
        }
        
        for (int j = i * SOLOS_PER_MESSAGE; j < (i * SOLOS_PER_MESSAGE) + soloCount; j++) {
            [message addIntegerArgument:[[[solos objectAtIndex:j] objectAtIndex:0] intValue]];
            [message addIntegerArgument:[[[solos objectAtIndex:j] objectAtIndex:1] intValue]];
            [message addIntegerArgument:[[[solos objectAtIndex:j] objectAtIndex:2] intValue]];
        }
        
        //Save and then send our message.
        [messageDictionary setObject:message forKey:[NSNumber numberWithInt:i]];
        [messagingDelegate sendData:message];
    }
    
    free(planchettesCount);
    return messageDictionary;
}

- (void)extractDataFromLocationMessages:(NSDictionary *)messages startingAtMessage:(int)messageNumber;
{
    //Initialise our arrays
    if (messageNumber == 0) {
        backgroundLocations = [[NSMutableArray alloc] init];
        planchetteLocations = [[NSMutableArray alloc] init];
        solos = [[NSMutableArray alloc] init];
    }
    
    for (int i = messageNumber; i < [messages count]; i++) {
        //Process our messages in the correct order.
        OSCMessage *message = [messages objectForKey:[NSNumber numberWithInt:i]];
        
        int backgroundCount = [[message.arguments objectAtIndex:4] intValue];
        int planchettesCount = [[message.arguments objectAtIndex:5] intValue];
        int solosCount = [[message.arguments objectAtIndex:6] intValue];
        
        int offset = (HEADER_LENGTH + planchettesCount);
        for (int j = 0; j < backgroundCount; j++) {
            NSMutableArray *currentTransition = [[NSMutableArray alloc] init];
            [currentTransition addObject:[message.arguments objectAtIndex:(offset + (j * 4))]];
            CGPoint location = CGPointMake([[message.arguments objectAtIndex:(offset + (j * 4) + 1)] intValue], [[message.arguments objectAtIndex:(offset + (j * 4) + 2 )] intValue]);
            [currentTransition addObject:[NSValue valueWithCGPoint:location]];
            [currentTransition addObject:[message.arguments objectAtIndex:(offset + (j * 4) + 3)]];
            [backgroundLocations addObject:currentTransition];
        }
        offset += (backgroundCount * 4);

        //...then the planchette movements...
        for (int j = 0; j < planchettesCount; j++) {
            if ([planchetteLocations count] <= j) {
                NSMutableArray *currentPlanchette = [[NSMutableArray alloc] init];
                [planchetteLocations addObject:currentPlanchette];
            }
            for (int k = 0; k < [[message.arguments objectAtIndex:(HEADER_LENGTH + j)] intValue]; k++) {
                NSMutableArray *currentCoordinates = [[NSMutableArray alloc] init];
                [currentCoordinates addObject:[message.arguments objectAtIndex:(offset + (k * 4))]];
                CGPoint location = CGPointMake([[message.arguments objectAtIndex:(offset + (k * 4) + 1)] intValue], [[message.arguments objectAtIndex:(offset + (k * 4) + 2 )] intValue]);
                [currentCoordinates addObject:[NSValue valueWithCGPoint:location]];
                [currentCoordinates addObject:[message.arguments objectAtIndex:(offset + (k * 4) + 3)]];
                [[planchetteLocations objectAtIndex:j] addObject:currentCoordinates];
            }
            offset += [[message.arguments objectAtIndex:(HEADER_LENGTH + j)] intValue] * 4;
        }

        for (int j = 0; j < solosCount; j++) {
            //...then our solos.
            NSMutableArray *currentSolo = [[NSMutableArray alloc] init];
            [currentSolo addObject:[message.arguments objectAtIndex:(offset + (j * 3))]];
            [currentSolo addObject:[message.arguments objectAtIndex:(offset + (j * 3) + 1)]];
            [currentSolo addObject:[message.arguments objectAtIndex:(offset + (j * 3) + 2)]];
            [solos addObject:currentSolo];
        }
    }
}

- (void)animatePlanchettes:(int)progress
{
    for (int i = 0; i < maxPlanchettes; i++) {
        if (progress >= [[[[planchetteLocations objectAtIndex:i] objectAtIndex:planchetteIndex[i]] objectAtIndex:0] intValue]) {
            //Move the planchette to it's new position, with a linear animation of the appropriate length.
            [CATransaction begin];
            [CATransaction setAnimationDuration:[[[[planchetteLocations objectAtIndex:i] objectAtIndex:planchetteIndex[i]] objectAtIndex:2] intValue] - planchetteAdjust[i]];
            [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
            ((CALayer *)[planchettes objectAtIndex:i]).position = [[[[planchetteLocations objectAtIndex:i] objectAtIndex:planchetteIndex[i] + 1] objectAtIndex:1] CGPointValue];
            [CATransaction commit];
            planchetteIndex[i]++;
            planchetteAdjust[i] = 0;
            
            //If we're the master, also send a message to any externals about our planchette movement.
            //(Take into account the fact that we've already increased the index number.)
            if (isMaster) {
                OSCMessage *message = [[OSCMessage alloc] init];
                [message appendAddressComponent:@"External"];
                [message appendAddressComponent:@"MovePlanchette"];
                [message addIntegerArgument:i];
                [message addIntegerArgument:[[[[planchetteLocations objectAtIndex:i] objectAtIndex:planchetteIndex[i]] objectAtIndex:1] CGPointValue].x];
                [message addIntegerArgument:[[[[planchetteLocations objectAtIndex:i] objectAtIndex:planchetteIndex[i]] objectAtIndex:1] CGPointValue].y];
                //We shouldn't need to worry about the planchetteAdjust amount here because the master shouldn't
                //have just been connecting.
                [message addIntegerArgument:[[[[planchetteLocations objectAtIndex:i] objectAtIndex:planchetteIndex[i] - 1] objectAtIndex:2] intValue]];
                [messagingDelegate sendData:message];
            }
        }
    }
    
    //Deal with any solo changes.
    if (soloIndex >= [solos count]) {
        //We have run out of solos.
        return;
    }
    
    if (soloPlanchette == -1) {
        if (progress >= [[[solos objectAtIndex:soloIndex] objectAtIndex:0] intValue]) {
            //Start our solo
            soloPlanchette = [[[solos objectAtIndex:soloIndex] objectAtIndex:1] intValue];
            [CATransaction begin];
            [CATransaction setAnimationDuration:2];
            ((CALayer *)[planchettes objectAtIndex:soloPlanchette]).bounds = CGRectMake(0, 0, 240, 240);
            ((CALayer *)[planchettes objectAtIndex:soloPlanchette]).cornerRadius = 120;
            ((CALayer *)[planchettes objectAtIndex:soloPlanchette]).borderWidth = 10;
            [CATransaction commit];
        }
    } else {
        if (progress >= [[[solos objectAtIndex:soloIndex] objectAtIndex:0] intValue] + [[[solos objectAtIndex:soloIndex] objectAtIndex:2] intValue]) {
            //End our solo
            [CATransaction begin];
            [CATransaction setAnimationDuration:2];
            ((CALayer *)[planchettes objectAtIndex:soloPlanchette]).bounds = CGRectMake(0, 0, 120, 120);
            ((CALayer *)[planchettes objectAtIndex:soloPlanchette]).cornerRadius = 60;
            ((CALayer *)[planchettes objectAtIndex:soloPlanchette]).borderWidth = 5;
            [CATransaction commit];
            soloIndex++;
            soloPlanchette = -1;
        }
    }
}

- (void)animateBackground:(NSNumber *)progress
{
    if ([progress intValue] >= [[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:0] intValue]) {
        if ([[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:2] intValue] == 0) {
            //If we're dealing with a sudden transition, first make the leap.
            [backgroundLayer removeAllAnimations];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            backgroundLayer.position = [[[backgroundLocations objectAtIndex:backgroundIndex + 1] objectAtIndex:1] CGPointValue];
            [CATransaction commit];
            backgroundIndex++;
            didLeap = YES;
            
            //Debug
            if (debug) {
                leap.text = [NSString stringWithFormat:@"%i, %i", (int)([[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:1] CGPointValue].x - [[[backgroundLocations objectAtIndex:backgroundIndex - 1] objectAtIndex:1] CGPointValue].x),(int)([[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:1] CGPointValue].y - [[[backgroundLocations objectAtIndex:backgroundIndex - 1] objectAtIndex:1] CGPointValue].y)];
                leap.hidden = NO;
                leapCount = 5;
            }
            
            //If we're the master, send a message to externals about the leap.
            if (isMaster) {
                OSCMessage *message = [[OSCMessage alloc] init];
                [message appendAddressComponent:@"External"];
                [message appendAddressComponent:@"MoveBackground"];
                [message addIntegerArgument:[[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:1] CGPointValue].x];
                [message addIntegerArgument:[[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:1] CGPointValue].y];
                [message addIntegerArgument:0];
                [messagingDelegate sendData:message];
            }
            
            //Then re-run the method with a 0.1 second delay to start the next transition.
            //(We can't launch the next transition immediately otherwise it might interfere with the leap.
            // This appears to be a quirk of CATransactions, that even acquiring a lock didn't reliably fix.)
            [self performSelector:@selector(animateBackground:) withObject:progress afterDelay:0.1];
        } else {
            [backgroundLayer removeAllAnimations];
            [CATransaction begin];
            if (didLeap) {
                //If we're coming from a leap, ease into the transition, and adjust the length
                //of it to compensate for the delay.
                [CATransaction setAnimationDuration:[[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:2] floatValue] - 0.1];
                [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
            } else {
                [CATransaction setAnimationDuration:[[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:2] intValue] - backgroundAdjust];
                [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
            }
            backgroundLayer.position = [[[backgroundLocations objectAtIndex:backgroundIndex + 1] objectAtIndex:1] CGPointValue];
            [CATransaction commit];
            backgroundIndex++;
            didLeap = NO;
            backgroundAdjust = 0;
            
            //Debug
            if (debug) {
                transition.text = [NSString stringWithFormat:@"%i, %i", (int)([[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:1] CGPointValue].x - [[[backgroundLocations objectAtIndex:backgroundIndex - 1] objectAtIndex:1] CGPointValue].x),(int)([[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:1] CGPointValue].y - [[[backgroundLocations objectAtIndex:backgroundIndex - 1] objectAtIndex:1] CGPointValue].y)];
                transition.hidden = NO;
                transitionCount = 5;
            }
            
            //If we're the master, send a message to externals about the transition.
            if (isMaster) {
                OSCMessage *message = [[OSCMessage alloc] init];
                [message appendAddressComponent:@"External"];
                [message appendAddressComponent:@"MoveBackground"];
                [message addIntegerArgument:[[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:1] CGPointValue].x];
                [message addIntegerArgument:[[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:1] CGPointValue].y];
                [message addIntegerArgument:[[[backgroundLocations objectAtIndex:backgroundIndex - 1] objectAtIndex:2] intValue]];
                [messagingDelegate sendData:message];
            }
        }
    }
}

- (CGPoint)generateNewPosition
{
    //Anchor point is assumed to be 0,0
    //Returned result will need to be adjusted if not
    //(Output should keep background image within canvas)
    
    int x = -(int)(arc4random_uniform((int)(backgroundLayer.bounds.size.width - screenWidth)));
    int y = -(int)(arc4random_uniform((int)(backgroundLayer.bounds.size.height - screenHeight)));
    return CGPointMake(x, y);
}

- (void)initLayers {
    //Load background image
    UIImage *backgroundImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:score.fileName]];
    backgroundLayer = [CALayer layer];
    backgroundLayer.anchorPoint = CGPointZero;
	backgroundLayer.contents = (id)backgroundImage.CGImage;
    
    //If our background image is smaller than our screen size, enlarge it.
    CGFloat widthRatio = (CGFloat)screenWidth / backgroundImage.size.width;
    CGFloat heightRatio = (CGFloat)screenHeight / backgroundImage.size.height;
    CGFloat ratio = MAX(widthRatio, heightRatio);
    if (ratio > 1) {
        backgroundLayer.bounds = CGRectMake(0, 0, backgroundImage.size.width * ratio, backgroundImage.size.height * ratio);
    } else {
        backgroundLayer.bounds = CGRectMake(0, 0, backgroundImage.size.width, backgroundImage.size.height);
    }
    
    //Create planchettes and set attributes
    planchettes = [NSMutableArray arrayWithCapacity:maxPlanchettes];
    if (!planchetteIndex) {
        planchetteIndex = malloc(sizeof(int) * maxPlanchettes);
    }
    if (!planchetteAdjust) {
        planchetteAdjust = malloc(sizeof(int) * maxPlanchettes);
    }
    
    NSArray *colourArray = [Renderer getDecibelColours];
    
    for (int i = 0; i < maxPlanchettes; i++) {
        CALayer *planchette = [CALayer layer];
        planchette.frame = CGRectMake(0, 0, 120, 120);
        planchette.cornerRadius = 60;
        planchette.borderWidth = 5;
        planchette.borderColor = ((UIColor *)[colourArray objectAtIndex:i]).CGColor;
        planchette.backgroundColor = [UIColor clearColor].CGColor;
        //Check whether the planchette should be displayed
        if (i >= numberOfPlanchettes) {
            planchette.opacity = 0;
        }
        [planchettes addObject:planchette];
    }
    
    //Set up layer for blackout
    blackout = [CALayer layer];
    blackout.frame = CGRectMake(-20, -20, MAX(canvas.bounds.size.width + 40, canvas.bounds.size.height + 40), MAX(canvas.bounds.size.width + 40, canvas.bounds.size.height + 40));
    blackout.backgroundColor = [UIColor blackColor].CGColor;
    
    //Debug layers
    if (debug) {
        timer = [[UILabel alloc] init];
        timer.frame = CGRectMake(0, 0, 150, 50);
        timer.backgroundColor = [UIColor whiteColor];
        timer.font = [UIFont systemFontOfSize:24];
        timer.textColor = [UIColor blackColor];
        timer.textAlignment = NSTextAlignmentCenter;
        
        leap = [[UILabel alloc] init];
        leap.frame = CGRectMake(0, 50, 150, 50);
        leap.backgroundColor = [UIColor yellowColor];
        leap.font = [UIFont systemFontOfSize:24];
        leap.textColor = [UIColor blackColor];
        leap.textAlignment = NSTextAlignmentCenter;
        
        transition = [[UILabel alloc] init];
        transition.frame = CGRectMake(0, 100, 150, 50);
        transition.backgroundColor = [UIColor blueColor];
        transition.font = [UIFont systemFontOfSize:24];
        transition.textColor = [UIColor whiteColor];
        transition.textAlignment = NSTextAlignmentCenter;
    }
}

- (void)renderLayers {
    //Disable any currently running animations
    for (int i = 0; i < [canvas.sublayers count]; i++) {
        [[canvas.sublayers objectAtIndex:i] removeAllAnimations];
    }
    
    //Clear canvas
    canvas.sublayers = nil;
    
    //Make position changes without any animations occuring
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    backgroundLayer.position = [[[backgroundLocations objectAtIndex:0] objectAtIndex:1] CGPointValue];
    for (int i = 0; i < maxPlanchettes; i++) {
        ((CALayer *)[planchettes objectAtIndex:i]).position = [[[[planchetteLocations objectAtIndex:i] objectAtIndex:0] objectAtIndex:1] CGPointValue];
    }
    blackout.opacity = 0;
    [CATransaction commit];
    
    [canvas addSublayer:backgroundLayer];
    for (int i = 0; i < maxPlanchettes; i++) {
        [canvas addSublayer:[planchettes objectAtIndex:i]];
    }
    [canvas addSublayer:blackout];
    
    //Debug
    if (debug) {
        leap.hidden = YES;
        transition.hidden = YES;
        timer.text = @"0:00";
        [canvas addSublayer:leap.layer];
        [canvas addSublayer:transition.layer];
        [canvas addSublayer:timer.layer];
    }
}


#pragma mark - Renderer delegate

- (void)setIsMaster:(BOOL)master
{
    isMaster = master;
    
    if (!isMaster) {
        //Client connecting for the first time. Generate data request message.
        hasData = NO;
        [dictionaryLock lock];
        locationMessages = nil;
        [dictionaryLock unlock];
        expectedCount = 0;
        generationNumber = 0;
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"DataRequest"];
        [messagingDelegate sendData:message];
    }
}

- (BOOL)isMaster
{
    return isMaster;
}

+ (RendererFeatures)getRendererRequirements
{
    return kPositiveDuration | kFileName | kUsesScaledCanvas;
}

+ (UIImage *)generateThumbnailForScore:(Score *)score ofSize:(CGSize)size
{
    UIImage *image = [UIImage imageWithContentsOfFile:[score.scorePath stringByAppendingPathComponent:score.fileName]];
    if (image.size.width < 2048 && image.size.height < 1536) {
        return [Renderer defaultThumbnail:[score.scorePath stringByAppendingPathComponent:score.fileName] ofSize:size];
    } else {
        //Make image double resolution for retina screens.
        CGFloat screenScale = [[UIScreen mainScreen] scale];
        size = CGSizeMake(size.width * screenScale, size.height * screenScale);
        
        UIGraphicsBeginImageContext(size);
        CGFloat scaleFactor = size.width / 2048.0;
        [image drawInRect:CGRectMake(0, 0, image.size.width * scaleFactor, image.size.height * scaleFactor)];
        UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return thumbnail;
    }
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    isMaster = YES;
    debug = NO;
    
    UIDelegate = UIDel;
    messagingDelegate = messagingDel;
    UIDelegate.clockVisible = NO;
    UIDelegate.resetViewOnFinish = NO;
    //UIDelegate.allowSyncToTick = NO;
    seekNotRequired = NO;
    awaitingSeek = NO;
    [UIDelegate setMarginColour:[UIColor blackColor]];
    
    score = scoreData;
    canvas = playerCanvas;
    
    //For the moment, lock our dimensions to landscape mode. We will make this configurable
    //per score eventually.
    screenWidth = MAX(canvas.bounds.size.width, canvas.bounds.size.height);
    screenHeight = MIN(canvas.bounds.size.width, canvas.bounds.size.height);
    
    //For now the number is hard coded, but this may be read from an xml file at a later date
    numberOfPlanchettes = 4;
    maxPlanchettes = 6;
    [self initLayers];
    generationNumber = 0;
    dictionaryLock = [[NSLock alloc] init];
    extractionLock = [[NSLock alloc] init];
    generationLock = [[NSLock alloc] init];
    
    if (score.prefsFile != nil) {
        NSData *prefsData = [[NSData alloc] initWithContentsOfFile:[score.scorePath stringByAppendingPathComponent:score.prefsFile]];
        xmlParser = [[NSXMLParser alloc] initWithData:prefsData];
        isData = NO;
        xmlParser.delegate = self;
        currentPrefs = kTopLevel;
        currentIndex = 0;
        [xmlParser parse];
    }
    
    //Flag used only by clients to see if data should be requested from the master
    hasData = YES;
    return self;
}

- (void)close {
    free(planchetteIndex);
    free(planchetteAdjust);
}

- (void)reset
{
    if (!isMaster) {
        expectedCount = 0;
    }
    
    //Reset counters
    backgroundIndex = 0;
    backgroundAdjust = 0;
    didLeap = NO;
    didSeek = NO;
    
    for (int i = 0; i < maxPlanchettes; i++) {
        planchetteIndex[i] = 0;
        planchetteAdjust[i] = 0;
        
        //Reset our planchette sizes.
        ((CALayer *)[planchettes objectAtIndex:i]).bounds = CGRectMake(0, 0, 120, 120);
        ((CALayer *)[planchettes objectAtIndex:i]).cornerRadius = 60;
        ((CALayer *)[planchettes objectAtIndex:i]).borderWidth = 5;
    }
    
    soloIndex = 0;
    soloPlanchette = -1;
    
    //Generate location data for the duration of the score and generate the initilization
    //message to send to clients.
    if (isMaster) {
        [self generateLocationData];
        //Since this data doesn't change between resets, save a copy of the messages that are
        //sent to clients so we don't have to generate them later.
        [dictionaryLock lock];
        locationMessages = [self generateLocationDataMessages];
        [dictionaryLock unlock];
    }
    
    if (isMaster) {
        //Perform initial rendering. For clients this is done on receiving the init data
        [self renderLayers];
    }
}

- (void)play
{
    //Launch initial animation event (only if we haven't had to seek, and if we have data).
    if (!didSeek && (isMaster || hasData)) {
        [self animatePlanchettes:0];
        [self animateBackground:[NSNumber numberWithInt:0]];
        seekNotRequired = YES;
    }
}

- (void)changeDuration:(CGFloat)duration
{
    if (isMaster) {
        //Regenerate the right amount of data for the new score duration.
        [self reset];
    }
}

- (void)seek:(CGFloat)location
{
    //Check to see that we actually have data before running this.
    if (!isMaster && !hasData) {
        awaitingSeek = YES;
        return;
    }
    
    //The seek function for TalkingBoard is used purely to synch new players to the current position.
    int progress = ceilf(location * UIDelegate.clockDuration);
    if (progress == 0 || seekNotRequired) {
        return;
    }
    
    int newBackgroundIndex = 0;
    int newPlanchetteIndex[maxPlanchettes];
    int newSoloIndex = 0;
    
    CGFloat ratio;
    int dx, dy, x, y;
    
    for (int i = 0; i < maxPlanchettes; i++) {
        newPlanchetteIndex[i] = 0;
        while (newPlanchetteIndex[i] < [[planchetteLocations objectAtIndex:i] count] && progress >= [[[[planchetteLocations objectAtIndex:i] objectAtIndex:newPlanchetteIndex[i]] objectAtIndex:0] intValue]) {
            newPlanchetteIndex[i]++;
        }
        newPlanchetteIndex[i]--;
        planchetteAdjust[i] = progress - [[[[planchetteLocations objectAtIndex:i] objectAtIndex:newPlanchetteIndex[i]] objectAtIndex:0] intValue];
        ratio = (float)planchetteAdjust[i] / [[[[planchetteLocations objectAtIndex:i] objectAtIndex:newPlanchetteIndex[i]] objectAtIndex:2] floatValue];
        dx = [[[[planchetteLocations objectAtIndex:i] objectAtIndex:newPlanchetteIndex[i] + 1] objectAtIndex:1] CGPointValue].x - [[[[planchetteLocations objectAtIndex:i] objectAtIndex:newPlanchetteIndex[i]] objectAtIndex:1] CGPointValue].x;
        dy = [[[[planchetteLocations objectAtIndex:i] objectAtIndex:newPlanchetteIndex[i] + 1] objectAtIndex:1] CGPointValue].y - [[[[planchetteLocations objectAtIndex:i] objectAtIndex:newPlanchetteIndex[i]] objectAtIndex:1] CGPointValue].y;
        x = (ratio * dx) + [[[[planchetteLocations objectAtIndex:i] objectAtIndex:newPlanchetteIndex[i]] objectAtIndex:1] CGPointValue].x;
        y = (ratio * dy) + [[[[planchetteLocations objectAtIndex:i] objectAtIndex:newPlanchetteIndex[i]] objectAtIndex:1] CGPointValue].y;
        
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        ((CALayer *)[planchettes objectAtIndex:i]).position = CGPointMake(x, y);
        [CATransaction commit];
    }

    while (newBackgroundIndex < [backgroundLocations count] && progress >= [[[backgroundLocations objectAtIndex:newBackgroundIndex] objectAtIndex:0] intValue]) {
        newBackgroundIndex++;
    }
    if ([[[backgroundLocations objectAtIndex:newBackgroundIndex - 1] objectAtIndex:2] intValue] != 0) {
        //Make sure we adjust to the current transition and not a leap.
        //(This shouldn't happen, unless by a freak chance of timing.)
        newBackgroundIndex--;
    }
    backgroundAdjust = progress - [[[backgroundLocations objectAtIndex:newBackgroundIndex] objectAtIndex:0] intValue];
    ratio = (float)backgroundAdjust / [[[backgroundLocations objectAtIndex:newBackgroundIndex] objectAtIndex:2] floatValue];
    dx = [[[backgroundLocations objectAtIndex:newBackgroundIndex + 1] objectAtIndex:1] CGPointValue].x - [[[backgroundLocations objectAtIndex:newBackgroundIndex] objectAtIndex:1] CGPointValue].x;
    dy = [[[backgroundLocations objectAtIndex:newBackgroundIndex + 1] objectAtIndex:1] CGPointValue].y - [[[backgroundLocations objectAtIndex:newBackgroundIndex] objectAtIndex:1] CGPointValue].y;
    x = (ratio * dx) + [[[backgroundLocations objectAtIndex:newBackgroundIndex] objectAtIndex:1] CGPointValue].x;
    y = (ratio * dy) + [[[backgroundLocations objectAtIndex:newBackgroundIndex] objectAtIndex:1] CGPointValue].y;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    backgroundLayer.position = CGPointMake(x, y);
    [CATransaction commit];
    
    backgroundIndex = newBackgroundIndex;
    for (int i = 0; i < maxPlanchettes; i++) {
        planchetteIndex[i] = newPlanchetteIndex[i];
    }
    
    //TODO: This needs checking - it sometimes briefly displays a solo that has already passed.
    while (newSoloIndex < [solos count] && progress >= [[[solos objectAtIndex:newSoloIndex] objectAtIndex:0] intValue]) {
        newSoloIndex++;
    }
    
    didSeek = YES;
    seekNotRequired = YES;
}

- (void)receiveMessage:(OSCMessage *)message;
{
    if (isMaster) {
        if ([message.address count] < 1) {
            return;
        }
        if ([[message.address objectAtIndex:0] isEqualToString:@"DataRequest"]) {
            for (int i = 0; i < [locationMessages count]; i++) {
                OSCMessage *message = [locationMessages objectForKey:[NSNumber numberWithInt:i]];
                [message replaceArgumentAtIndex:0 withString:@"Refresh"];
                [messagingDelegate sendData:message];
            }
        }
    } else {
        //Check that we're receiving the right data for the background and planchette motion.
        if ([[message.address objectAtIndex:0] isEqualToString:@"InitData"]) {
            if (![message.typeTag hasPrefix:@",siiiii"]) {
                return;
            }
        
            if (!hasData || [[message.arguments objectAtIndex:0] isEqualToString:@"New"]) {
                int messageNumber = [[message.arguments objectAtIndex:1] intValue];
                int finalMessage = [[message.arguments objectAtIndex:2] intValue];
                int generation = [[message.arguments objectAtIndex:3] intValue];
                int backgroundCount = [[message.arguments objectAtIndex:4] intValue];
                int planchettesCount = [[message.arguments objectAtIndex:5] intValue];
                int solosCount = [[message.arguments objectAtIndex:6] intValue];
                int totalPlanchettes = 0;
                if ((message.typeTag.length < (HEADER_LENGTH + 1 + planchettesCount + (backgroundCount * 4))) || (planchettesCount != maxPlanchettes)) {
                    return;
                }
                //Tally up how much data we should be expecting.
                for (int i = 0; i < planchettesCount; i++) {
                    if ([message.typeTag characterAtIndex:(HEADER_LENGTH + 1 + i)] != 'i') {
                        return;
                    } else {
                        totalPlanchettes += [[message.arguments objectAtIndex:(HEADER_LENGTH + i)] intValue];
                    }
                }
                //Check that we have the right number of arguments.
                if (message.typeTag.length != (HEADER_LENGTH + 1 + planchettesCount + (backgroundCount * 4) + (totalPlanchettes * 4) + (solosCount * 3))) {
                    return;
                }
                
                //All good, save our data and see if we can extract our messages yet.
                [generationLock lock];
                if (generation > generationNumber) {
                    generationNumber = generation;
                    [generationLock unlock];
                    expectedCount = 0;
                    [dictionaryLock lock];
                    locationMessages = [[NSMutableDictionary alloc] init];
                    [dictionaryLock unlock];
                } else if (generation < generationNumber) {
                    //We have an old message that hasn't been received in sequence.
                    [generationLock unlock];
                    return;
                } else {
                    //Need to make sure we unlock our lock if our other conditions weren't matched.
                    [generationLock unlock];
                }
                
                [dictionaryLock lock];
                [locationMessages setObject:message forKey:[NSNumber numberWithInt:messageNumber]];
                [dictionaryLock unlock];
                if (messageNumber == 0) {
                    //Render our initial data to the screen now.
                    [dictionaryLock lock];
                    NSDictionary *messages = [NSDictionary dictionaryWithDictionary:locationMessages];
                    [dictionaryLock unlock];
                    //We need to make sure no other message thread tries extracting data
                    //and rendering it at the some time.
                    [extractionLock lock];
                    //Check if our data has been superseded while waiting to acquire our lock.
                    if (generation < generationNumber) {
                        [extractionLock unlock];
                        return;
                    }
                    [self extractDataFromLocationMessages:messages startingAtMessage:0];
                    [self renderLayers];
                    [extractionLock unlock];
                }
                if (finalMessage) {
                    expectedCount = messageNumber + 1;
                }
                if (expectedCount != 0) {
                    //Check if all of our messages have arrived.
                    if (expectedCount == [locationMessages count]) {
                        //And then process the rest of them.
                        //NSLog(@"%i, %i", expectedCount, generationNumber);
                        [dictionaryLock lock];
                        NSDictionary *messages = [NSDictionary dictionaryWithDictionary:locationMessages];
                        [dictionaryLock unlock];
                        [extractionLock lock];
                        if (generation < generationNumber) {
                            [extractionLock unlock];
                            return;
                        }
                        [self extractDataFromLocationMessages:messages startingAtMessage:1];
                        [extractionLock unlock];
                        hasData = YES;
                            
                        if (awaitingSeek) {
                            [self seek:UIDelegate.clockLocation];
                            awaitingSeek = NO;
                        }
                    }
                }
            }
        }
    }
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    if (splitSecond == 1) {
        return;
    }
    
    //Debug
    if (debug) {
        int minutes = progress / 60;
        int seconds = progress % 60;
        int nextMinutes = [[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:0] intValue] / 60;
        int nextSeconds = [[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:0] intValue] % 60;
        timer.text = [NSString stringWithFormat:@"%i:%02i/%i:%02i", minutes, seconds, nextMinutes, nextSeconds];
        
        if ([[[backgroundLocations objectAtIndex:backgroundIndex] objectAtIndex:2] intValue] == 0) {
            timer.text = [timer.text stringByAppendingString:@"(l)"];
        }
        
        if (leapCount > 0) {
            leapCount--;
            if (leapCount == 0) {
                leap.hidden = YES;
            }
        }
        if (transitionCount > 0) {
            transitionCount--;
            if (transitionCount == 0) {
                transition.hidden = YES;
            }
        }
    }
    
    //Start fade to black if needed.
    if (progress == UIDelegate.clockDuration - 5) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:5];
        blackout.opacity = 1;
        [CATransaction commit];
    }
    
    //Animate planchettes then background.
    [self animatePlanchettes:progress];
    [self animateBackground:[NSNumber numberWithInt:progress]];
}

- (OSCMessage *)getOptions
{
    OSCMessage *options = [[OSCMessage alloc] init];
    [options appendAddressComponent:@"Options"];
    [options addIntegerArgument:numberOfPlanchettes];
    return options;
}

- (void)setOptions:(OSCMessage *)newOptions
{
    if (![newOptions.typeTag isEqualToString:@",i"]) {
        return;
    }
    numberOfPlanchettes = [[newOptions.arguments objectAtIndex:0] intValue];
    if (numberOfPlanchettes > maxPlanchettes) {
        numberOfPlanchettes = maxPlanchettes;
    } else if (numberOfPlanchettes < 1) {
        numberOfPlanchettes = 1;
    }
    
    //Adjust visibility of planchettes as needed
    for (int i = 0; i < maxPlanchettes; i++) {
        if (i < numberOfPlanchettes) {
            ((CALayer *)[planchettes objectAtIndex:i]).opacity = 1;
        } else {
            ((CALayer *)[planchettes objectAtIndex:i]).opacity = 0;
        }
    }
}

#pragma mark - NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if ([elementName isEqualToString:@"planchettes"] || [elementName isEqualToString:@"rgb"]) {
        isData = YES;
        currentString = nil;
    } else if ([elementName isEqualToString:@"planchette"]) {
        currentPrefs = kPlanchette;
        planchetteColour = nil;
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
    if ([elementName isEqualToString:@"planchettes"]) {
        //Process using the setOptions method, which does the necessary validity checks.
        OSCMessage *options = [[OSCMessage alloc] init];
        [options appendAddressComponent:@"Options"];
        [options addIntegerArgument:[currentString integerValue]];
        [self setOptions:options];
    } else if ([elementName isEqualToString:@"planchette"]) {
        currentPrefs = kTopLevel;
        if (currentIndex >= maxPlanchettes) {
            //If we already have enough data for our planchettes, we don't need to be here.
            isData = NO;
            return;
        }
        if (planchetteColour != nil) {
            ((CALayer *)[planchettes objectAtIndex:currentIndex]).borderColor = planchetteColour.CGColor;
        }
        currentIndex++;
    } else if ([elementName isEqualToString:@"rgb"] && (currentPrefs == kPlanchette)) {
        NSArray *colour = [currentString componentsSeparatedByString:@","];
        if ([colour count] == 3) {
            CGFloat r = [[colour objectAtIndex:0] intValue] & 255;
            CGFloat g = [[colour objectAtIndex:1] intValue] & 255;
            CGFloat b = [[colour objectAtIndex:2] intValue] & 255;
            planchetteColour = [UIColor colorWithRed:(r / 255) green:(g / 255) blue:(b / 255) alpha:1];
        }
    }
    isData = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    parser.delegate = nil;
    xmlParser = nil;
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    //If the preferences file is bad, just use the default number of planchettes.
    //(No need to flag it as a fatal error.)
    parser.delegate = nil;
    xmlParser = nil;
}

@end

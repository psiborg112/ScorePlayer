//
//  UBahn.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 20/07/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "UBahn.h"
#import "Score.h"
#import "OSCMessage.h"
#import "Train.h"
#import "Junction.h"
#import "Mosaic.h"

@interface UBahn ()

- (void)loadPaths;
- (void)animateTrains;
- (void)animateBackgroundAtNode:(BOOL)atNode junctionNumber:(NSInteger)atJunction;
- (void)enableHighResTimer:(BOOL)enabled;
- (OSCMessage *)createTrainMessage:(BOOL)newData;
- (void)validateDirection:(int)trainNumber;
- (void)changeTrain:(NSInteger)trainNumber;
- (BOOL)findFinalPaths;
- (void)setMapMode:(MapMode)mode;
- (void)initLayers;
- (void)renderLayers;

@end

@implementation UBahn {
    Score *score;
    CALayer *canvas;
    
    NSInteger screenWidth;
    NSInteger screenHeight;
    
    UIImage *mapImage;
    CALayer *map;
    CALayer *sideBar;
    CALayer *fragment;
    CALayer *fragmentBorder;
    CALayer *centre;
    CALayer *mapContents;
    CALayer *background;
    CALayer *fadeLayer;
    CALayer *overlay;
    CALayer *blackout;
    Mosaic *mosaic;
    
    NSMutableArray *trains;
    NSMutableArray *paths;
    NSMutableArray *stops;
    NSMutableDictionary *junctions;
    NSMutableDictionary *invertOrientation;
    BOOL bidirectional;
    BOOL useFinalPaths;
    
    NSMutableArray *endZone;
    NSInteger trapped;
    NSInteger traversals;
    NSInteger safePeriod;
    NSMutableArray *borderJunctions;
    
    NSInteger selectedTrain;
    OSCMessage *initialTrainData;
    
    NSTimer *highRes;
    NSInteger timeLimit;
    int mosaicCounter;
    NSInteger mosaicDuration;
    NSString *mosaicStartImage;
    NSString *mosaicEndImage;
    NSString *mosaicFinalImage;
    
    BOOL faded;
    BOOL hasFaded;
    NSInteger fadeCounter;
    NSInteger fadeLength;
    NSInteger transitionLength;
    
    CGFloat xOffset;
    CGFloat yOffset;
    CGFloat coordinateScaleFactor;
    BOOL scaleFactorLocked;
    
    NSFileManager *fileManager;
    NSXMLParser *xmlParser;
    NSMutableString *currentString;
    xmlLocation currentPrefs;
    BOOL isData;
    
    NSArray *xArray;
    NSArray *yArray;
    NSArray *stopArray;
    NSArray *orientationArray;
    BOOL addToEndZone;
    
    NSInteger assignedPath;
    NSInteger assignedPart;
    NSInteger stopLength;
    NSInteger junctionLength;
    CGFloat trainSpeed;
    UIColor *trainColour;
    
    NSString *imageName;
    CGPoint imageOffset;
    
    BOOL pathsLoaded;
    NSCondition *pathsCondition;
    BOOL badPaths;
    
    BOOL hasData;
    
    __weak id<RendererUI> UIDelegate;
    __weak id<RendererMessaging> messagingDelegate;
}

- (void)loadPaths
{
    //Load the paths file. This now loads more than just the paths, so some of the initialization of layers needs to be
    //done after this has taken place.
    NSData *pathData = [[NSData alloc] initWithContentsOfFile:[score.scorePath stringByAppendingPathComponent:score.prefsFile]];
    if (pathData != nil) {
        xmlParser = [[NSXMLParser alloc] initWithData:pathData];
    }
    
    isData = NO;
    scaleFactorLocked = NO;
    coordinateScaleFactor = 1;
    xmlParser.delegate = self;
    currentPrefs = kTopLevel;
    fileManager = [NSFileManager defaultManager];
    [xmlParser parse];
}

- (void)animateTrains
{
    //Do this for each train. This needs to be done by all clients so that they are ready to take
    //over in the case that they ultimately become the master.
    for (int i = 0; i < [trains count]; i++) {
        BOOL atNode = NO;
    
        //Check distance to current destination
        CGFloat dx = [[((Train *)[trains objectAtIndex:i]).currentPath objectAtIndex:((Train *)[trains objectAtIndex:i]).destinationIndex] CGPointValue].x - ((Train*)[trains objectAtIndex:i]).position.x;
        CGFloat dy = [[((Train *)[trains objectAtIndex:i]).currentPath objectAtIndex:((Train *)[trains objectAtIndex:i]).destinationIndex] CGPointValue].y - ((Train*)[trains objectAtIndex:i]).position.y;
        CGFloat distance = sqrt(pow(dx, 2) + pow(dy, 2));
        
        //If we're less than one position increment away, then set our location to the destination
        if (distance < ((Train *)[trains objectAtIndex:i]).speed) {
            atNode = YES;
            NSInteger currentPath = [paths indexOfObjectIdenticalTo:((Train *)[trains objectAtIndex:i]).currentPath];
            
            ((Train *)[trains objectAtIndex:i]).position = [[((Train *)[trains objectAtIndex:i]).currentPath objectAtIndex:((Train *)[trains objectAtIndex:i]).destinationIndex] CGPointValue];
            NSNumber *stop = [[stops objectAtIndex:currentPath] objectAtIndex:((Train *)[trains objectAtIndex:i]).destinationIndex];
            //If the current point on the path is a stop then stop the train
            if ([stop intValue] >= 0) {
                ((Train *)[trains objectAtIndex:i]).isMoving = NO;
                
                //If the current stop is a junction then we need to add the possibility of switching paths.
                //Only do this here if we are the master.
                if ([stop intValue] > 0) {
                    ((Train *)[trains objectAtIndex:i]).atJunction = [stop intValue];
                    
                    if (isMaster) {
                        Junction *junction = [junctions objectForKey:stop];
                        NSIndexPath *indexPath;
                        
                        //Check to see if the junction leads to our end zone if necessary.
                        if ([endZone count] > 0 && [borderJunctions indexOfObject:stop] != NSNotFound) {
                            //Do we have any more get out of jail free cards?
                            if ((traversals <= 0 && UIDelegate.clockProgress > safePeriod) || useFinalPaths) {
                                //If not, we're trapped in the end zone, and so are any future unfortunates.
                                for (int j = 0; j < [junction.stops count]; j++) {
                                    if ([endZone indexOfObject:[NSNumber numberWithInteger:[[junction.stops objectAtIndex:j] indexAtPosition:0]]] == NSNotFound) {
                                        [junction.stops removeObjectAtIndex:j];
                                    }
                                }
                                indexPath = [junction.stops objectAtIndex:arc4random_uniform((int)[junction.stops count])];
                                if (!((Train *)[trains objectAtIndex:i]).inEndZone) {
                                    ((Train *)[trains objectAtIndex:i]).inEndZone = YES;
                                    trapped++;
                                }
                            } else {
                                //Decrement the number of remaining traversals, and recreate the index path
                                //for the track that we're currenty on (rather than searching for it).
                                if (traversals > 0) {
                                    traversals--;
                                }
                                NSUInteger indexes[2];
                                indexes[0] = currentPath;
                                indexes[1] = ((Train *)[trains objectAtIndex:i]).destinationIndex;
                                indexPath = [[NSIndexPath alloc] initWithIndexes:indexes length:2];
                            }
                        } else if (useFinalPaths && !((Train *)[trains objectAtIndex:i]).inEndZone) {
                            //We've run out of time. Direct the trains to the end zone.
                            for (int j = 0; j < [junction.stops count]; j++) {
                                if ([[junction.stops objectAtIndex:j] indexAtPosition:0] == junction.finalPath) {
                                    indexPath = [junction.stops objectAtIndex:j];
                                    j = (int)[junction.stops count];
                                }
                                ((Train *)[trains objectAtIndex:i]).direction = junction.finalDirection;
                            }
                        } else {
                            //Otherwise choose our path entirely at random.
                            indexPath = [junction.stops objectAtIndex:arc4random_uniform((int)[junction.stops count])];
                        }
                        
                        ((Train *)[trains objectAtIndex:i]).currentPath = [paths objectAtIndex:[indexPath indexAtPosition:0]];
                        ((Train *)[trains objectAtIndex:i]).destinationIndex = [indexPath indexAtPosition:1];
                    
                        //The positions for the different paths at the junctions might not be exactly the same.
                        //Reset to the new coordinates.
                        [[trains objectAtIndex:i] resetPosition];
                        
                        //If changing path, randomly choose the direction (if bidirectional), and notify the clients
                        if (currentPath != [indexPath indexAtPosition:0] || useFinalPaths) {
                            if (!useFinalPaths || ((Train *)[trains objectAtIndex:i]).inEndZone) {
                                ((Train *)[trains objectAtIndex:i]).direction = (2 * (int)arc4random_uniform(2)) - 1;
                            }
                            
                            //If our paths are unidinectional, override the direction.
                            //TODO: fix our pathfinding algorithm to support uniderectional paths. In the meantime,
                            //pathfinding takes precedence over direction.
                            if (!bidirectional && !useFinalPaths) {
                                ((Train *)[trains objectAtIndex:i]).direction = 1;
                            }
                            
                            //Safety check. This should not happen unless a junction has been defined without any stops.
                            if (indexPath != nil) {
                                OSCMessage *message = [[OSCMessage alloc] init];
                                [message appendAddressComponent:@"SwitchTrack"];
                                [message addIntegerArgument:i];
                                [message addIntegerArgument:[indexPath indexAtPosition:0]];
                                [message addIntegerArgument:[indexPath indexAtPosition:1]];
                                [message addIntegerArgument:((Train *)[trains objectAtIndex:i]).direction];
                                [messagingDelegate sendData:message];
                            }
                        }
                    }
                }
            }
            //If we've hit the end of the line turn around.
            //This is the only time that unidirectional pathways are ignored.
            [self validateDirection:i];
            ((Train *)[trains objectAtIndex:i]).destinationIndex += ((Train *)[trains objectAtIndex:i]).direction;
            [[trains objectAtIndex:i] calculateVector];
        } else {
            if (((Train *)[trains objectAtIndex:i]).isMoving) {
                [[trains objectAtIndex:i] move];
            }
        }
        if (i == selectedTrain) {
            [self animateBackgroundAtNode:atNode junctionNumber:((Train *)[trains objectAtIndex:selectedTrain]).atJunction];
        }
    }
    
    if (selectedTrain == -1 && trapped == [trains count] && mosaicDuration > 0) {
        //If all of the trains are trapped and we're in the map view, remove the map and show the mosaic.
        canvas.sublayers = nil;
        [canvas addSublayer:mosaic.background];
    }
}

- (void)animateBackgroundAtNode:(BOOL)atNode junctionNumber:(NSInteger)atJunction
{
    //Animate the background for the selected train's eye view.
    map.anchorPoint = CGPointMake((((Train *)[trains objectAtIndex:selectedTrain]).position.x - xOffset) / (screenWidth - (2 * xOffset)), (((Train *)[trains objectAtIndex:selectedTrain]).position.y - yOffset) / (screenHeight - (2 * yOffset)));
    if (((Train *)[trains objectAtIndex:selectedTrain]).isMoving) {
        fragment.contents = nil;
    }
    if (atNode) {
        CGFloat angle;
        BOOL invert = NO;
        NSInteger currentPath = [paths indexOfObjectIdenticalTo:((Train *)[trains objectAtIndex:selectedTrain]).currentPath];
        if ([invertOrientation objectForKey:[NSNumber numberWithInteger:currentPath]] != nil) {
            NSInteger index = ((Train *)[trains objectAtIndex:selectedTrain]).destinationIndex;
            //Since we need to query the stop before the track segment in question, we need to decrement
            //the index by one if we're travelling forwards.
            if (((Train *)[trains objectAtIndex:selectedTrain]).direction == 1) {
                index--;
                if (index < 0) {
                    //It shouldn't be possible for the index to be negative here, but check for safety.
                    index = 0;
                }
            }
            invert = [[[invertOrientation objectForKey:[NSNumber numberWithInteger:currentPath]] objectAtIndex:index] boolValue];
        }
        if (((Train *)[trains objectAtIndex:selectedTrain]).movementVector.x == 0) {
            angle = M_PI_2;
        } else {
            angle = -atanf(((Train *)[trains objectAtIndex:selectedTrain]).movementVector.y / ((Train *)[trains objectAtIndex:selectedTrain]).movementVector.x);
        }
        if (invert) {
            angle -= M_PI;
        }
        [map setValue:[NSNumber numberWithFloat:angle] forKeyPath:@"transform.rotation.z"];
        
        if (atJunction != 0) {
            //If we're at a junction show one of the fragments. (To avoid this, simply don't provide fragment files.)
            NSString *fragmentPath = [score.scorePath stringByAppendingPathComponent:[score.parts objectAtIndex:((Train *)[trains objectAtIndex:selectedTrain]).assignedPart]];
            fragmentPath = [[fragmentPath stringByDeletingPathExtension] stringByAppendingPathComponent:[NSString stringWithFormat:@"Fragment%i.png", (int)atJunction]];
            UIImage *fragmentImage = [Renderer cachedImage:fragmentPath];
            fragment.contents = (id)fragmentImage.CGImage;
            if (((Train *)[trains objectAtIndex:selectedTrain]).inEndZone && mosaicDuration > 0) {
                //We're in the end zone. Display the mosaic if there is one.
                canvas.sublayers = nil;
                [canvas addSublayer:mosaic.background];
            }
        }
    }
}

- (void)enableHighResTimer:(BOOL)enabled
{
    if (enabled) {
        if (highRes == nil || !highRes.isValid) {
            //Don't start a new timer if there is already a valid high resolution timer running.
            highRes = [NSTimer scheduledTimerWithTimeInterval:0.04 target:self selector:@selector(animateTrains) userInfo:nil repeats:YES];
        }
    } else {
        if (highRes != nil) {
            [highRes invalidate];
            highRes = nil;
        }
    }
}

- (OSCMessage *)createTrainMessage:(BOOL)newData
{
    //Generate the train data to send to the clients.
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Trains"];
    if (newData ) {
        [message addStringArgument:@"New"];
    } else {
        [message addStringArgument:@"Refresh"];
    }
    [message addIntegerArgument:[trains count]];
    
    for (int i = 0; i < [trains count]; i++) {
        [message addIntegerArgument:[paths indexOfObjectIdenticalTo:((Train *)[trains objectAtIndex:i]).currentPath]];
        [message addIntegerArgument:((Train *)[trains objectAtIndex:i]).destinationIndex];
        [message addIntegerArgument:((Train *)[trains objectAtIndex:i]).direction];
        [message addFloatArgument:((Train *)[trains objectAtIndex:i]).speed];
    }
    return message;
}

- (void)validateDirection:(int)trainNumber
{
    if (trainNumber >= [trains count]) {
        return;
    }
    if (((Train *)[trains objectAtIndex:trainNumber]).destinationIndex == 0) {
        ((Train *)[trains objectAtIndex:trainNumber]).direction = 1;
    } else if (((Train *)[trains objectAtIndex:trainNumber]).destinationIndex == [((Train *)[trains objectAtIndex:trainNumber]).currentPath count] - 1) {
        ((Train *)[trains objectAtIndex:trainNumber]).direction = -1;
    }
}

- (void)changeTrain:(NSInteger)trainNumber
{
    //Check the bounds of our argument. We also don't need to do anything here if the train number
    //matches the current train.
    if (trainNumber < -1 || trainNumber >= (NSInteger)[trains count] || trainNumber == selectedTrain) {
        return;
    }
    
    if (trainNumber == -1) {
        //We're moving to the map view.
        //First, check to see if we should be showing the mosaic.
        
        if (trapped == [trains count]) {
            if (mosaic.background.superlayer != canvas){
                canvas.sublayers = nil;
                [canvas addSublayer:mosaic.background];
            }
            if (UIDelegate.playerState == kStopped) {
                //Make sure we're displaying the right final image.
                [mosaic setImage2:[Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:@"ruins.png"]]];
            }
        } else {
            //Otherwise display the map.
            canvas.sublayers = nil;
            [self enableHighResTimer:NO];
            [map removeAllAnimations];
        
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [self setMapMode:kMapView];
            [CATransaction commit];
        
            [canvas addSublayer:map];
        
            for (int i = 0; i < [trains count]; i++) {
                [canvas addSublayer:((Train *)[trains objectAtIndex:i]).sprite];
            }
        
            if (UIDelegate.playerState == kPlaying) {
                [self enableHighResTimer:YES];
            }
        }
        
        //Our work here is done.
        selectedTrain = trainNumber;
        return;
    }
    
    //Decide what layers need to change based on whether we're moving to or from the end zone.
    if (((Train *)[trains objectAtIndex:trainNumber]).inEndZone) {
        if (mosaic.background.superlayer != canvas) {
            //If both of our trains are in the end zone we don't need to do anything.
            //Otherwise, display the mosaic.
            canvas.sublayers = nil;
            [canvas addSublayer:mosaic.background];
        } else if (selectedTrain == -1 && UIDelegate.playerState == kStopped) {
            //If we're coming from the map view, make sure we change to the correct final image
            [mosaic setImage2:[Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:@"ruinsfull.png"]]];
        }
    } else {
        //Reinstate the train view if we're coming from the map view or the end zone.
        if (selectedTrain == -1 || ((Train *)[trains objectAtIndex:selectedTrain]).inEndZone) {
            canvas.sublayers = nil;
            fragment.contents = nil;
            [self enableHighResTimer:NO];
            [map removeAllAnimations];
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            
            //selectedTrain needs to be changed before calling setMapMode or animateBackgroundAtNode
            selectedTrain = trainNumber;
            [self setMapMode:kTrainView];
            [self animateBackgroundAtNode:YES junctionNumber:((Train *)[trains objectAtIndex:trainNumber]).atJunction];
            sideBar.backgroundColor = ((Train *)[trains objectAtIndex:trainNumber]).sprite.backgroundColor;
            fragmentBorder.borderColor = ((Train *)[trains objectAtIndex:trainNumber]).sprite.backgroundColor;
            
            [CATransaction commit];
            [canvas addSublayer:map];
            [canvas addSublayer:sideBar];
            [canvas addSublayer:centre];
            [canvas addSublayer:fragmentBorder];
            
            if (UIDelegate.playerState == kPlaying) {
                [self enableHighResTimer:YES];
            }
        } else {
            fragment.contents = nil;
            [self enableHighResTimer:NO];
            [map removeAllAnimations];
            [map removeFromSuperlayer];
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            
            selectedTrain = trainNumber;
            [self animateBackgroundAtNode:YES junctionNumber:((Train *)[trains objectAtIndex:trainNumber]).atJunction];
            mapImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:[score.parts objectAtIndex:((Train *)[trains objectAtIndex:selectedTrain]).assignedPart]]];
            mapContents.contents = (id)mapImage.CGImage;
            
            [CATransaction commit];
            [canvas insertSublayer:map below:sideBar];
            
            sideBar.backgroundColor = ((Train *)[trains objectAtIndex:trainNumber]).sprite.backgroundColor;
            fragmentBorder.borderColor = ((Train *)[trains objectAtIndex:trainNumber]).sprite.backgroundColor;
            
            if (UIDelegate.playerState == kPlaying) {
                [self enableHighResTimer:YES];
            }
        }
    }
    
    selectedTrain = trainNumber;
}

- (BOOL)findFinalPaths
{
    //Implementation of a somewhat lazy A* path finding algorithm. We use this to direct the trains towards
    //the end zone once time has run out.
    NSMutableArray *openJunctions = [[NSMutableArray alloc] init];
    NSMutableArray *closedJunctions = [[NSMutableArray alloc] init];
    
    int *destinationX;
    int *destinationY;
    NSIndexPath *indexPath;
    
    if ([borderJunctions count] < 1) {
        //These need to be determined before the function is called.
        return NO;
    }
    
    //Find the positions of the border junctions.
    destinationX = malloc(sizeof(int) * [borderJunctions count]);
    destinationY = malloc(sizeof(int) * [borderJunctions count]);
    for (int i = 0; i < [borderJunctions count]; i++) {
        indexPath = [((Junction *)[junctions objectForKey:[borderJunctions objectAtIndex:i]]).stops objectAtIndex:0];
        destinationX[i] = [[[paths objectAtIndex:[indexPath indexAtPosition:0]] objectAtIndex:[indexPath indexAtPosition:1]] CGPointValue].x;
        destinationY[i] = [[[paths objectAtIndex:[indexPath indexAtPosition:0]] objectAtIndex:[indexPath indexAtPosition:1]] CGPointValue].y;
    }
    
    //Do this for each junction
    NSNumber *key;
    for (key in junctions) {
        
        //We only need to do this if the junction isn't part of an existing subpath or a border juncion
        if (((Junction *)[junctions objectForKey:key]).finalPath == -1 && [borderJunctions indexOfObject:key] == NSNotFound) {
            [openJunctions removeAllObjects];
            [closedJunctions removeAllObjects];
            for (NSNumber *i in junctions) {
                [[junctions objectForKey:i] resetCosts];
            }
            
            //Find the closest border junction
            indexPath = [((Junction *)[junctions objectForKey:key]).stops objectAtIndex:0];
            int x = [[[paths objectAtIndex:[indexPath indexAtPosition:0]] objectAtIndex:[indexPath indexAtPosition:1]] CGPointValue].x;
            int y = [[[paths objectAtIndex:[indexPath indexAtPosition:0]] objectAtIndex:[indexPath indexAtPosition:1]] CGPointValue].y;
            int minDistance = sqrt(pow(destinationX[0] - x, 2) + pow(destinationY[0] - y, 2));
            int borderIndex = 0;
            
            for (int i = 1; i < [borderJunctions count]; i++) {
                int distance = sqrt(pow(destinationX[i] - x, 2) + pow(destinationY[i], 2));
                if (distance < minDistance) {
                    minDistance = distance;
                    borderIndex = i;
                }
            }
            
            //Add our starting junction to the open list
            [openJunctions addObject:[junctions objectForKey:key]];
            
            BOOL searching = YES;
            while (searching) {
                //Find the junciton in the open list with the lowest F score.
                if ([openJunctions count] == 0) {
                    //We've failed to find a path. Most likely the network isn't traversable
                    free(destinationX);
                    free(destinationY);
                    return NO;
                }
                NSInteger minF = ((Junction *)[openJunctions objectAtIndex:0]).f;
                int minFIndex = 0;
                for (int i = 1; i < [openJunctions count]; i++) {
                    if (((Junction *)[openJunctions objectAtIndex:i]).f < minF) {
                        minF = ((Junction *)[openJunctions objectAtIndex:i]).f;
                        minFIndex = i;
                    }
                }
                //Move our chosen junction to the closed list
                [closedJunctions addObject:[openJunctions objectAtIndex:minFIndex]];
                [openJunctions removeObjectAtIndex:minFIndex];
                
                //Check if our chosen junction is a border junction or has a path to the end zone
                //already stored. If this is the case then our search is over.
                if (((Junction *)[closedJunctions lastObject]).isBorderJunction || ((Junction *)[closedJunctions lastObject]).finalPath != -1) {
                    searching = NO;
                } else {
                    //Find all of the adjacent junctions. Search each path connected to the junction.
                    for (int i = 0; i < [((Junction *)[closedJunctions lastObject]).stops count]; i++) {
                        NSInteger pathIndex = [[((Junction *)[closedJunctions lastObject]).stops objectAtIndex:i] indexAtPosition:0];
                        //In both directions
                        for (int direction = -1; direction <= 1; direction += 2) {
                            NSInteger stopNumber = [[((Junction *)[closedJunctions lastObject]).stops objectAtIndex:i] indexAtPosition:1];
                            x = [[[paths objectAtIndex:pathIndex] objectAtIndex:stopNumber] CGPointValue].x;
                            y = [[[paths objectAtIndex:pathIndex] objectAtIndex:stopNumber] CGPointValue].y;
                            int distance = 0;
                            BOOL atJunction = NO;
                            //Keep updating the distance travelled until we hit a junction or the end of the line.
                            while ((direction == 1 || stopNumber > 0) && (direction == -1 || stopNumber < [[paths objectAtIndex:pathIndex] count] - 1) && !atJunction) {
                                stopNumber += direction;
                                distance += sqrt(pow([[[paths objectAtIndex:pathIndex] objectAtIndex:stopNumber] CGPointValue].x - x, 2) + pow([[[paths objectAtIndex:pathIndex] objectAtIndex:stopNumber] CGPointValue].y - y, 2));
                                x = [[[paths objectAtIndex:pathIndex] objectAtIndex:stopNumber] CGPointValue].x;
                                y = [[[paths objectAtIndex:pathIndex] objectAtIndex:stopNumber] CGPointValue].y;
                                if ([[[stops objectAtIndex:pathIndex] objectAtIndex:stopNumber] intValue] > 0) {
                                    atJunction = YES;
                                }
                            }

                            //If we've hit a junction, and it's not on the closed list, calculate its g and h
                            //scores, save our current junction as the parent and add it to our list of open
                            //junctions. Otherwise we've hit a dead end and have nothing to process here.
                            if (atJunction && [closedJunctions indexOfObjectIdenticalTo:[junctions objectForKey:[[stops objectAtIndex:pathIndex] objectAtIndex:stopNumber]]] == NSNotFound) {
                                
                                //Check if the junction is already on the open list and compare the g cost to find
                                //the best parent junction.
                                Junction *junction = [junctions objectForKey:[[stops objectAtIndex:pathIndex] objectAtIndex:stopNumber]];
                                if ([openJunctions indexOfObjectIdenticalTo:junction] != NSNotFound) {
                                    NSInteger g = distance + ((Junction *)[closedJunctions lastObject]).g;
                                    if (g < junction.g) {
                                        junction.g = g;
                                        junction.h = sqrt(pow(x - destinationX[borderIndex], 2) + pow(y - destinationY[borderIndex], 2));
                                        junction.parentJunction = [[[junctions allKeysForObject:[closedJunctions lastObject]] objectAtIndex:0] intValue];
                                        junction.parentPath = pathIndex;
                                        junction.directionFromParent = direction;
                                    }
                                } else {
                                    [openJunctions addObject:junction];
                                    junction.g = distance + ((Junction *)[closedJunctions lastObject]).g;
                                    junction.h = sqrt(pow(x - destinationX[borderIndex], 2) + pow(y - destinationY[borderIndex], 2));
                                    junction.parentJunction = [[[junctions allKeysForObject:[closedJunctions lastObject]] objectAtIndex:0] intValue];
                                    junction.parentPath = pathIndex;
                                    junction.directionFromParent = direction;
                                }
                            }
                        }
                    }
                }
            }
            //Reconstruct the path, storing the necessary values in each junction.
            NSInteger junctionNumber = [[[junctions allKeysForObject:[closedJunctions lastObject]] objectAtIndex:0] intValue];
            while (junctionNumber != 0) {
                Junction *junction = [junctions objectForKey:[NSNumber numberWithInteger:junctionNumber]];
                ((Junction *)[junctions objectForKey:[NSNumber numberWithInt:(int)junction.parentJunction]]).finalPath = junction.parentPath;
                ((Junction *)[junctions objectForKey:[NSNumber numberWithInt:(int)junction.parentJunction]]).finalDirection = junction.directionFromParent;
                junctionNumber = ((Junction *)[junctions objectForKey:[NSNumber numberWithInteger:junctionNumber]]).parentJunction;
            }            
        }
    }
    
    free(destinationX);
    free(destinationY);
    return YES;
}

- (void)setMapMode:(MapMode)mode
{
    //This method simply sets the properties of the map layer as required. The caller should decide
    //whether it is necessary to change any CATransaction properties before calling.
    
    //It also does not set the rotation. (This should be achieved by calling the animateBackgroundAtNode
    //method.)
    
    //Make sure the map doesn't have any sublayers left in it.
    map.sublayers = nil;
    
    if (mode == kMapView) {
        //Load the network map
        mapImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:score.fileName]];
        map.contents = (id)mapImage.CGImage;
            
        //Centre the map on the screen. And reset the anchor point and rotation.
        map.anchorPoint = CGPointMake(0.5, 0.5);
        [map setValue:[NSNumber numberWithFloat:0] forKeyPath:@"transform.rotation.z"];
        map.bounds = CGRectMake(0, 0, mapImage.size.width, mapImage.size.height);
        map.position = CGPointMake(screenWidth / 2, screenHeight / 2);
        
    } else {
        //Select the appropriate part to load.
        mapImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:[score.parts objectAtIndex:((Train *)[trains objectAtIndex:selectedTrain]).assignedPart]]];
        map.contents = nil;
        map.bounds = CGRectMake(0, 0, mapImage.size.width, mapImage.size.height);
        mapContents.frame = (CGRectMake(0 ,0, mapImage.size.width, mapImage.size.height));
        mapContents.contents = (id)mapImage.CGImage;
        map.position = CGPointMake(screenWidth / 2 + 20, screenHeight / 2);
        [map addSublayer:background];
        [map addSublayer:fadeLayer];
        [map addSublayer:mapContents];
        [map addSublayer:overlay];
    }
}

- (void)initLayers
{
    //This doesn't set up the mosaic or background layers. We need to wait until the paths file has
    //been processed before we can do that, so they are set up in the parsing code.
    
    //We need to load the map here whether we're the master or slave because we need to find
    //the x and y offsets to add to the path coordinaties.
    mapImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:score.fileName]];
    xOffset = (screenWidth - mapImage.size.width) / 2;
    yOffset = (screenHeight - mapImage.size.height) / 2;
    map = [CALayer layer];
    mapContents = [CALayer layer];
    
    //Set up sidebar
    sideBar = [CALayer layer];
    sideBar.frame = CGRectMake(0, -(UIDelegate.navigationHeight + UIDelegate.statusHeight), 150, 1024 + UIDelegate.navigationHeight + UIDelegate.statusHeight);
    //sideBar.backgroundColor = [UIColor colorWithRed:(123.0 / 255) green:(25.0 / 255) blue:(121.0 / 255) alpha:1].CGColor;
    sideBar.shadowOpacity = 1;
    NSString *titleFile = [[score.scorePath stringByAppendingPathComponent:[score.parts objectAtIndex:((Train *)[trains objectAtIndex:0]).assignedPart]] stringByDeletingPathExtension];
    titleFile = [titleFile stringByAppendingString:@"Title.png"];
    UIImage *partTitleImage = [Renderer cachedImage:titleFile];
    CALayer *partTitle = [CALayer layer];
    partTitle.contents = (id)partTitleImage.CGImage;
    partTitle.bounds = CGRectMake(0, 0, partTitleImage.size.width, partTitleImage.size.height);
    partTitle.position = CGPointMake(150 / 2, 50 + (UIDelegate.navigationHeight + UIDelegate.statusHeight));
    [sideBar addSublayer:partTitle];
    
    //Set up fragment viewer
    fragmentBorder = [CALayer layer];
    fragmentBorder.anchorPoint = CGPointMake(0, 0.5);
    fragmentBorder.bounds = CGRectMake(0, 0, 480, 280);
    fragmentBorder.position = CGPointMake(120, screenHeight / 2 - 20);
    fragmentBorder.backgroundColor = [UIColor clearColor].CGColor;
    //fragmentBorder.borderColor = [UIColor colorWithRed:(123.0 / 255) green:(25.0 / 255) blue:(121.0 / 255) alpha:1].CGColor;
    fragmentBorder.borderWidth = 5;
    fragmentBorder.cornerRadius = 5;
    
    fragment = [CALayer layer];
    fragment.frame = CGRectMake(5, 5, fragmentBorder.bounds.size.width - 10, fragmentBorder.bounds.size.height - 10);
    fragment.backgroundColor = [UIColor clearColor].CGColor;
    [fragmentBorder addSublayer:fragment];
    
    //Set up the centre marker
    centre = [CALayer layer];
    centre.frame = CGRectMake(0, 0, 14, 14);
    centre.cornerRadius = 7;
    centre.borderWidth = 7;
    centre.borderColor = [UIColor redColor].CGColor;
    centre.backgroundColor = [UIColor clearColor].CGColor;
    centre.position = CGPointMake(screenWidth / 2 + 20, screenHeight / 2);
    
    blackout = [CALayer layer];
    blackout.frame = CGRectMake(-20, -20, MAX(canvas.bounds.size.width + 40, canvas.bounds.size.height + 40), MAX(canvas.bounds.size.width + 40, canvas.bounds.size.height + 40));
    blackout.backgroundColor = [UIColor blackColor].CGColor;
    blackout.opacity = 0;
}

- (void)renderLayers
{
    canvas.sublayers = nil;
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    for (int i = 0; i < [trains count]; i++) {
        ((Train *)[trains objectAtIndex:i]).isMoving = NO;
        ((Train *)[trains objectAtIndex:i]).position = [[((Train *)[trains objectAtIndex:i]).currentPath objectAtIndex:((Train *)[trains objectAtIndex:i]).destinationIndex] CGPointValue];
    }

    //Reset the mosaic and the fading layer.
    mosaic.changedTiles = 0;
    fadeLayer.opacity = 1;
    blackout.opacity = 0;
    
    if (selectedTrain == -1) {
        [self setMapMode:kMapView];
        [canvas addSublayer:map];
        
        for (int i = 0; i < [trains count]; i++) {
            [canvas addSublayer:((Train *)[trains objectAtIndex:i]).sprite];
            ((Train *)[trains objectAtIndex:i]).destinationIndex++;
            [[trains objectAtIndex:i] calculateVector];
        }
    } else {
        [self setMapMode:kTrainView];
        
        fragment.contents = nil;
        sideBar.backgroundColor = ((Train *)[trains objectAtIndex:selectedTrain]).sprite.backgroundColor;
        fragmentBorder.borderColor = ((Train *)[trains objectAtIndex:selectedTrain]).sprite.backgroundColor;
        
        //In case we're late to the party here, check whether the currently selected train is
        //already in the end zone.
        if (((Train *)[trains objectAtIndex:selectedTrain]).inEndZone) {
            [canvas addSublayer:mosaic.background];
        } else {
            [canvas addSublayer:map];
            [canvas addSublayer:sideBar];
            [canvas addSublayer:centre];
            [canvas addSublayer:fragmentBorder];
        }
        
        for (int i = 0; i < [trains count]; i++) {
            //Double check that our direction is set properly. If not, fix it.
            [self validateDirection:i];
            ((Train *)[trains objectAtIndex:i]).destinationIndex += ((Train *)[trains objectAtIndex:i]).direction;
            [[trains objectAtIndex:i] calculateVector];
        }
        
        [self animateBackgroundAtNode:YES junctionNumber:0];
    }
    
    [CATransaction commit];
}

#pragma mark - Renderer delegate

- (void)setIsMaster:(BOOL)master
{
    isMaster = master;
    
    if (!isMaster) {
        //Client connecting for the first time. Lets get us some trains.
        hasData = NO;
        selectedTrain = 0;
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"TrainsRequest"];
        [messagingDelegate sendData:message];
    }
}

- (BOOL)isMaster
{
    return isMaster;
}

+ (RendererFeatures)getRendererRequirements
{
    return kFileName | kParts | kPrefsFile | kUsesScaledCanvas;
}

+ (UIImage *)generateThumbnailForScore:(Score *)score ofSize:(CGSize)size
{
    return [Renderer defaultThumbnail:[score.scorePath stringByAppendingPathComponent:score.fileName] ofSize:size];
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    isMaster = YES;
    
    UIDelegate = UIDel;
    messagingDelegate = messagingDel;
    UIDelegate.clockEnabled = YES;
    UIDelegate.splitSecondMode = YES;
    UIDelegate.resetViewOnFinish = NO;
    [UIDelegate setMarginColour:[UIColor blackColor]];
    [UIDelegate setCanvasMask:YES];
    
    score = scoreData;
    canvas = playerCanvas;
    
    //For the moment, lock our dimensions to landscape mode. We will make this configurable
    //per score eventually.
    screenWidth = MAX(canvas.bounds.size.width, canvas.bounds.size.height);
    screenHeight = MIN(canvas.bounds.size.width, canvas.bounds.size.height);
    
    //If our score is running timed we still want to make the scroller invisible.
    if (UIDelegate.clockDuration > 0) {
        UIDelegate.clockVisible = NO;
    }
    
    if (UIDelegate.clockDuration < 0) {
        timeLimit = fabs(UIDelegate.clockDuration);
        safePeriod = timeLimit / 3;
    } else {
        timeLimit = NSIntegerMax;
    }
    
    //Mosaic disabled by default.
    mosaicDuration = 0;
    //Paths are bidirectional by default.
    bidirectional = YES;
    
    //TODO: These should not be hard coded. (Did not learn a thing from last time...)
    fadeLength = 12;
    transitionLength = 3;
    
    [self initLayers];
    selectedTrain = -1;
    initialTrainData = nil;
    
    //Load path data
    pathsLoaded = NO;
    pathsCondition = [NSCondition new];
    badPaths = NO;
    
    paths = [[NSMutableArray alloc] init];
    stops = [[NSMutableArray alloc] init];
    junctions = [[NSMutableDictionary alloc] init];
    invertOrientation = [[NSMutableDictionary alloc] init];
    endZone = [[NSMutableArray alloc] init];
    trains = [[NSMutableArray alloc] init];
    [self loadPaths];
    
    //Flag used only by clients to see if data should be requested from the master
    hasData = YES;
    return self;
}

- (void)close
{
    paths = nil;
    trains = nil;
    
    [self enableHighResTimer:NO];
}

- (void)reset
{
    //For testing
    //timeLimit = 0;
    //safePeriod = 0;
    
    traversals = 0;
    trapped = 0;
    mosaicCounter = 0;
    useFinalPaths = NO;
    faded = NO;
    hasFaded = NO;
    fadeCounter = NO;
    
    [pathsCondition lock];
    while (!pathsLoaded) {
        [pathsCondition wait];
    }
    [pathsCondition unlock];
    
    if (badPaths) {
        [UIDelegate badPreferencesFile:@"Damaged paths file."];
        return;
    }
    
    //Reset timer and remove all animations.
    [self enableHighResTimer:NO];
    [map removeAllAnimations];
    for (int i = 0; i < [trains count]; i++) {
        [((Train *)[trains objectAtIndex:i]).sprite removeAllAnimations];
    }
    
    if (isMaster) {
        for (int i = 0; i < [trains count]; i++) {
            //Reset necessary train data. We need to hold off on resetting the sprite until
            //the rendering function.
            ((Train *)[trains objectAtIndex:i]).currentPath = [paths objectAtIndex:((Train *)[trains objectAtIndex:i]).initialPathIndex];
            ((Train *)[trains objectAtIndex:i]).destinationIndex = 0;
            ((Train *)[trains objectAtIndex:i]).direction = 1;
            ((Train *)[trains objectAtIndex:i]).waitTime = 0;
            ((Train *)[trains objectAtIndex:i]).inEndZone = NO;
            //TODO: Do an actual check on whether the train is at a junction rather than assuming it isn't.
            ((Train *)[trains objectAtIndex:i]).atJunction = 0;
        }
        
        OSCMessage *message = [self createTrainMessage:YES];
        [messagingDelegate sendData:message];
        
        //Save a copy of this message for later with the 'Refresh' property set.
        initialTrainData = [[OSCMessage alloc] init];
        [initialTrainData copyAddressFromMessage:message];
        [initialTrainData appendArgumentsFromMessage:message];
        [initialTrainData replaceArgumentAtIndex:0 withString:@"Refresh"];
        
        [self renderLayers];
    }
}

- (void)play
{
    if (isMaster) {
        //Clear our initial train data message so that we know we have to regenerate it from here on out.
        initialTrainData = nil;
        
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"Go"];
        
        for (int i = 0; i < [trains count]; i ++) {
            [message addIntegerArgument:i];
            [message addIntegerArgument:((Train *)[trains objectAtIndex:i]).destinationIndex];
        }
        
        [messagingDelegate sendData:message];
    }
    
    [self enableHighResTimer:YES];
}

- (void)receiveMessage:(OSCMessage *)message
{
    if ([message.address count] < 1) {
        return;
    }
    
    if (isMaster) {
        if ([[message.address objectAtIndex:0] isEqualToString:@"TrainsRequest"]) {
            if (initialTrainData != nil) {
                [messagingDelegate sendData:initialTrainData];
            } else {
                [messagingDelegate sendData:[self createTrainMessage:NO]];
            }
        }
    } else {
        if ([[message.address objectAtIndex:0] isEqualToString:@"Trains"]) {
            if (![message.typeTag hasPrefix:@",si"]) {
                return;
            }
            
            if (!hasData || [[message.arguments objectAtIndex:0] isEqualToString:@"New"]) {
                //Check that the message has the right sort of data first.
                int trainCount = [[message.arguments objectAtIndex:1] intValue];
                if ((message.typeTag.length != (3 + (trainCount * 4))) || (trainCount != [trains count])) {
                    return;
                }
                
                for (int i = 3; i < [message.typeTag length]; i += 4) {
                    if (![[message.typeTag substringWithRange:NSMakeRange(i, 4)] isEqualToString:@"iiif"]) {
                        return;
                    }
                }
                
                //Now extract the data.
                int offset = 2;
                for (int i = 0; i < trainCount; i++) {
                    ((Train *)[trains objectAtIndex:i]).currentPath = [paths objectAtIndex:[[message.arguments objectAtIndex:(offset + (4 * i))] intValue]];
                    ((Train *)[trains objectAtIndex:i]).destinationIndex = [[message.arguments objectAtIndex:(offset + (4 * i) + 1)]  integerValue];
                    ((Train *)[trains objectAtIndex:i]).direction = [[message.arguments objectAtIndex:(offset + (4 * i) + 2)] integerValue];
                    ((Train *)[trains objectAtIndex:i]).speed = [[message.arguments objectAtIndex:(offset + (4 * i) + 3)] floatValue];
                    
                    //Check if the train is already in the end zone.
                    if ([endZone indexOfObject:[message.arguments objectAtIndex:(offset + (4 * i))]] != NSNotFound) {
                        ((Train *)[trains objectAtIndex:i]).inEndZone = YES;
                    } else {
                        ((Train *)[trains objectAtIndex:i]).inEndZone = NO;
                    }
                }
                
                [self renderLayers];
                hasData = YES;
            }
        } else if ([[message.address objectAtIndex:0] isEqualToString:@"SwitchTrack"]) {
            if (![message.typeTag isEqualToString:@",iiii"]) {
                return;
            }
            int trainNumber = [[message.arguments objectAtIndex:0] intValue];
            
            //We need to make sure the train has actually stopped first.
            ((Train *)[trains objectAtIndex:trainNumber]).position = [[((Train *)[trains objectAtIndex:trainNumber]).currentPath objectAtIndex:((Train *)[trains objectAtIndex:trainNumber]).destinationIndex] CGPointValue];
            ((Train *)[trains objectAtIndex:trainNumber]).isMoving = NO;
            
            //Then change to our new track and update the motion vector.
            NSUInteger indexes[2];
            indexes[0] = [[message.arguments objectAtIndex:1] integerValue];
            indexes[1] = [[message.arguments objectAtIndex:2] integerValue];
            NSIndexPath *indexPath = [[NSIndexPath alloc] initWithIndexes:indexes length:2];
            ((Train *)[trains objectAtIndex:trainNumber]).currentPath = [paths objectAtIndex:[indexPath indexAtPosition:0]];
            ((Train *)[trains objectAtIndex:trainNumber]).destinationIndex = [indexPath indexAtPosition:1];
            [[trains objectAtIndex:trainNumber] resetPosition];
            ((Train *)[trains objectAtIndex:trainNumber]).direction = [[message.arguments objectAtIndex:3] integerValue];
            ((Train *)[trains objectAtIndex:trainNumber]).atJunction = [[[stops objectAtIndex:[indexPath indexAtPosition:0]] objectAtIndex:[indexPath indexAtPosition:1]] intValue];
            
            [self validateDirection:trainNumber];
            ((Train *)[trains objectAtIndex:trainNumber]).destinationIndex += ((Train *)[trains objectAtIndex:trainNumber]).direction;
            [[trains objectAtIndex:trainNumber] calculateVector];
            
            if ([endZone indexOfObject:[NSNumber numberWithInteger:[indexPath indexAtPosition:0]]] != NSNotFound && !((Train *)[trains objectAtIndex:trainNumber]).inEndZone) {
                ((Train *)[trains objectAtIndex:trainNumber]).inEndZone = YES;
                trapped++;
            }
            
            if (trainNumber == selectedTrain) {
                [self animateBackgroundAtNode:YES junctionNumber:((Train *)[trains objectAtIndex:trainNumber]).atJunction];
            }
        }
    }
    
    //Process common "go" message here. The master should also respond to this so that the code path
    //is somewhat comparable. (Minus the network latency.) Hopefully this should help avoid drift issues.
    if ([[message.address objectAtIndex:0] isEqualToString:@"Go"]) {
        NSString *typeTag = [message.typeTag substringFromIndex:1];
        NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"i"] invertedSet];
        if (([typeTag rangeOfCharacterFromSet:invalidTags].location != NSNotFound) || ([typeTag length] % 2 == 1)) {
            return;
        }
        
        //Repeat for each train in the message
        for (int i = 0; i < [message.arguments count]; i += 2) {
            int trainNumber = [[message.arguments objectAtIndex:i] intValue];
            if (((Train *)[trains objectAtIndex:trainNumber]).destinationIndex != [[message.arguments objectAtIndex:(i + 1)] integerValue]) {
                //Check to see if we're out of synch, and fix if we are.
                ((Train *)[trains objectAtIndex:trainNumber]).destinationIndex = [[message.arguments objectAtIndex:(i + 1)] integerValue];
            }
            [[trains objectAtIndex:trainNumber] calculateVector];
            ((Train *)[trains objectAtIndex:trainNumber]).isMoving = YES;
            ((Train *)[trains objectAtIndex:trainNumber]).atJunction = 0;
        }
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"FadeStart"]) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:transitionLength];
        fadeLayer.opacity = 0;
        [CATransaction commit];
        fadeCounter = 0;
        faded = YES;
        hasFaded = YES;
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"FadeEnd"]) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:transitionLength];
        fadeLayer.opacity = 1;
        [CATransaction commit];
        faded = NO;
    }
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    //Before adding code here, remember that we are in split second mode. There will be a tick every half second!
    
    //Check to see if we should be sending the trains to the endzone.
    if (!useFinalPaths && (UIDelegate.clockDuration < 0 && UIDelegate.clockProgress >= timeLimit)) {
        useFinalPaths = YES;
    }
    
    //Increment fade counter and reset fade state if necessary.
    if (splitSecond == 0) {
        if (faded) {
            fadeCounter++;
        }
    
        //Currently hardcoded for one fade every minute where this is enabled.
        if (progress % 60 == 0) {
            hasFaded = NO;
        }
    }
    
    //If all of the trains are in the end zone, start changing the mosaic.
    if (trapped == [trains count]) {
        if (mosaicDuration > 0) {
        mosaicCounter++;
            if (mosaicCounter <= mosaicDuration) {
                [mosaic setChangedPercent:(100 * mosaicCounter / (CGFloat)mosaicDuration)];
            } else {
                if (selectedTrain != -1 && mosaicFinalImage != nil) {
                    [mosaic setImage2:[Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:mosaicFinalImage]]];
                }
                [UIDelegate stopClockWithStateUpdate:YES];
                [self enableHighResTimer:NO];
                return;
            }
        } else {
            //There is no mosaic. Fade to black and end the score here.
            [UIDelegate stopClockWithStateUpdate:YES];
            [self enableHighResTimer:NO];
            [canvas addSublayer:blackout];
            [CATransaction flush];
            [CATransaction begin];
            [CATransaction setAnimationDuration:4];
            blackout.opacity = 1;
            [CATransaction commit];
            return;
        }
    }
    
    if (finished) {
        //We're in timed mode. End and fade to black.
        [self enableHighResTimer:NO];
        [canvas addSublayer:blackout];
        [CATransaction flush];
        [CATransaction begin];
        [CATransaction setAnimationDuration:4];
        blackout.opacity = 1;
        [CATransaction commit];
    }
    
    //Only the master processes events beyond here. The clients rely on network messages for these signals.
    if (!isMaster) {
        return;
    }
    
    OSCMessage *message = [[OSCMessage alloc] init];
    
    for (int i = 0; i < [trains count]; i++) {
        if (!((Train *)[trains objectAtIndex:i]).isMoving) {
            ((Train *)[trains objectAtIndex:i]).waitTime++;
            //Wait longer if we're at a junction. The outcome is the same though.
            if ((((Train *)[trains objectAtIndex:i]).atJunction == 0 && ((Train *)[trains objectAtIndex:i]).waitTime > 2 * ((Train *)[trains objectAtIndex:i]).stopLength) || ((Train *)[trains objectAtIndex:i]).waitTime > 2 * ((Train *)[trains objectAtIndex:i]).junctionLength) {
                
                [message addIntegerArgument:i];
                [message addIntegerArgument:((Train *)[trains objectAtIndex:i]).destinationIndex];
                
                ((Train *)[trains objectAtIndex:i]).waitTime = 0;
            }
        }
    }
    //If any trains have moved in this cycle, send a "go" message to the clients
    if ([message.arguments count] > 0) {
        [message appendAddressComponent:@"Go"];
        [messagingDelegate sendData:message];
    }
    
    //Now deal with fades
    if (faded && fadeCounter >= fadeLength) {
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"FadeEnd"];
        [messagingDelegate sendData:message];
        
        OSCMessage *external = [[OSCMessage alloc] init];
        [external appendAddressComponent:@"External"];
        [external appendAddressComponent:@"FadeEnd"];
        [messagingDelegate sendData:external];
    } else if (splitSecond == 0 && !hasFaded && fadeLayer != nil) {
        NSInteger window = 60 - fadeLength - transitionLength;
        NSInteger outcome = arc4random_uniform((int)window);
        if (outcome < progress) {
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"FadeStart"];
            [messagingDelegate sendData:message];
            
            OSCMessage *external = [[OSCMessage alloc] init];
            [external appendAddressComponent:@"External"];
            [external appendAddressComponent:@"FadeStart"];
            [messagingDelegate sendData:external];
        }
    }
}

- (void)swipeUp
{
    if (selectedTrain == [trains count] - 1) {
        [self changeTrain:-1];
    } else {
        [self changeTrain:(selectedTrain + 1)];
    }
    [UIDelegate partChangedToPart:selectedTrain + 1];
}

- (void)swipeDown
{
    if (selectedTrain == -1) {
        [self changeTrain:([trains count] - 1)];
    } else {
        [self changeTrain:(selectedTrain - 1)];
    }
    [UIDelegate partChangedToPart:selectedTrain + 1];
}

#pragma mark - NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if (currentPrefs == kTopLevel) {
        if ([elementName isEqualToString:@"path"]) {
            xArray = nil;
            yArray = nil;
            stopArray = nil;
            orientationArray = nil;
            addToEndZone = NO;
            currentPrefs = kPath;
        } else if ([elementName isEqualToString:@"trains"]) {
            currentPrefs = kTrains;
        } else if ([elementName isEqualToString:@"mosaic"]) {
            currentPrefs = kMosaic;
        } else if ([elementName isEqualToString:@"background"] || [elementName isEqualToString:@"fadelayer"] || [elementName isEqualToString:@"overlay"]) {
            imageName = nil;
            imageOffset = CGPointZero;
            currentPrefs = kImage;
        } else if ([elementName isEqualToString:@"width"] || [elementName isEqualToString:@"height"] || [elementName isEqualToString:@"bidirectional"]) {
            isData = YES;
            currentString = nil;
        }
    } else {
        if ((currentPrefs == kTrains) && [elementName isEqualToString:@"train"]) {
            //Reset default values.
            assignedPath = 0;
            assignedPart = 0;
            stopLength = 0;
            junctionLength = 0;
            trainSpeed = 1;
            trainColour = [UIColor blackColor];
        } else {
            isData = YES;
            currentString = nil;
        }
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
    switch (currentPrefs) {
        case kTopLevel:
            //Once we've started processing paths none of these tags can have any effect.
            if (!scaleFactorLocked) {
                if ([elementName isEqualToString:@"width"]) {
                    coordinateScaleFactor = screenWidth / [currentString floatValue];
                } else if ([elementName isEqualToString:@"height"]) {
                    coordinateScaleFactor = screenHeight / [currentString floatValue];
                } else if ([elementName isEqualToString:@"bidirectional"]) {
                    if (currentString != nil && [currentString caseInsensitiveCompare:@"no"] == NSOrderedSame) {
                        bidirectional = NO;
                    }
                }
            }
            break;
            
        case kPath:
            if ([elementName isEqualToString:@"path"]) {
                if ([xArray count] != [yArray count] || [xArray count] != [stopArray count]) {
                    //Our arrays aren't the same size. This isn't a valid coordinate list. Ignore it.
                    currentPrefs = kTopLevel;
                    isData = NO;
                    return;
                }
                scaleFactorLocked = YES;
                NSMutableArray *currentPath = [[NSMutableArray alloc] init];
                NSMutableArray *currentStops = [[NSMutableArray alloc] init];
                for (int i = 0; i < [xArray count]; i++) {
                    CGPoint pathPoint = CGPointMake(coordinateScaleFactor * [[xArray objectAtIndex:i] floatValue] + xOffset, coordinateScaleFactor * [[yArray objectAtIndex:i] floatValue] + yOffset);
                    [currentPath addObject:[NSValue valueWithCGPoint:pathPoint]];
                    NSNumber *stop = [NSNumber numberWithInt:[[stopArray objectAtIndex:i] intValue]];
                    [currentStops addObject:stop];
                    if ([stop intValue] > 0 && (bidirectional || i < ([xArray count] - 1))) {
                        //The stop is also a junction. Store a path to it in our junctions dictionary.
                        //(For each junction, we hold an array of path indexes. The first index is the path, while the
                        //second index is the position of the junction stop within the associated path array.)
                        
                        //Don't store it though if it's the end of a one way path.
                        NSUInteger indexes[2];
                        indexes[0] = [paths count];
                        indexes[1] = i;
                        NSIndexPath *indexPath = [[NSIndexPath alloc] initWithIndexes:indexes length:2];
                        if ([junctions objectForKey:stop] == nil) {
                            Junction *junction = [[Junction alloc] init];
                            [junction.stops addObject:indexPath];
                            [junctions setObject:junction forKey:stop];
                        } else {
                            [((Junction *)[junctions objectForKey:stop]).stops addObject:indexPath];
                        }
                    }
                }
                if ([orientationArray count] == [xArray count] - 1) {
                    //Some of our track segments need the part graphic to be inverted. Make a note of them.
                    NSMutableArray *currentOrientations = [[NSMutableArray alloc] init];
                    for (int i = 0; i < [orientationArray count]; i++) {
                        [currentOrientations addObject:[NSNumber numberWithBool:[[orientationArray objectAtIndex:i] boolValue]]];
                    }
                    [invertOrientation setObject:currentOrientations forKey:[NSNumber numberWithInteger:[paths count]]];
                }
                [paths addObject:currentPath];
                [stops addObject:currentStops];
                if (addToEndZone) {
                    //Our current path is part of the endzone. Add it to the list.
                    [endZone addObject:[NSNumber numberWithInteger:[paths count] - 1]];
                }
                currentPrefs = kTopLevel;
            } else if ([elementName isEqualToString:@"x"]) {
                //Convert our values into an array for easier handling
                xArray = [currentString componentsSeparatedByString:@","];
            } else if ([elementName isEqualToString:@"y"]) {
                yArray = [currentString componentsSeparatedByString:@","];
            } else if ([elementName isEqualToString:@"stop"]) {
                stopArray = [currentString componentsSeparatedByString:@","];
            } else if ([elementName isEqualToString:@"invert"]) {
                orientationArray = [currentString componentsSeparatedByString:@","];
            } else if ([elementName isEqualToString:@"endzone"]) {
                //Only worry about having an endzone if our score duration is a soft timelimit rather than a hard value.
                if (currentString != nil && [currentString caseInsensitiveCompare:@"yes"] == NSOrderedSame && UIDelegate.clockDuration < 0) {
                    addToEndZone = YES;
                }
            }
            break;
            
        case kTrains:
            if ([elementName isEqualToString:@"trains"]) {
                currentPrefs = kTopLevel;
            } else if ([elementName isEqualToString:@"train"]) {
                Train *train = [[Train alloc] initWithPart:assignedPart];
                train.initialPathIndex = assignedPath;
                train.stopLength = stopLength;
                train.junctionLength = junctionLength;
                train.speed = trainSpeed;
                train.sprite.backgroundColor = trainColour.CGColor;
                [trains addObject:train];
            } else if ([elementName isEqualToString:@"pathnumber"]) {
                assignedPath = [currentString integerValue];
            } else if ([elementName isEqualToString:@"partnumber"]) {
                assignedPart = [currentString integerValue];
            } else if ([elementName isEqualToString:@"stoptime"]) {
                stopLength = [currentString integerValue];
            } else if ([elementName isEqualToString:@"junctiontime"]) {
                junctionLength = [currentString integerValue];
            } else if ([elementName isEqualToString:@"speed"]) {
                trainSpeed = [currentString floatValue];
            } else if ([elementName isEqualToString:@"rgb"]) {
                NSArray *colour = [currentString componentsSeparatedByString:@","];
                if ([colour count] == 3) {
                    CGFloat r = [[colour objectAtIndex:0] intValue] & 255;
                    CGFloat g = [[colour objectAtIndex:1] intValue] & 255;
                    CGFloat b = [[colour objectAtIndex:2] intValue] & 255;
                    trainColour = [UIColor colorWithRed:(r / 255) green:(g / 255) blue:(b / 255) alpha:1];
                }
            }
            break;
            
        case kMosaic:
            if ([elementName isEqualToString:@"mosaic"]) {
                if (mosaicStartImage == nil || mosaicEndImage == nil) {
                    mosaicDuration = 0;
                } else {
                    UIImage *mosaicStart = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:mosaicStartImage]];
                    mosaic = [[Mosaic alloc] initWithTileRows:18 columns:24 size:CGPointMake(mosaicStart.size.width, mosaicStart.size.height)];
                    mosaic.image1 = mosaicStart;
                    mosaic.image2 = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:mosaicEndImage]];
                    mosaic.background.position = CGPointMake(screenWidth / 2, screenHeight / 2);
                }
                currentPrefs = kTopLevel;
            } else if ([elementName isEqualToString:@"startimage"]) {
                if ([fileManager fileExistsAtPath:[score.scorePath stringByAppendingPathComponent:currentString]]) {
                    mosaicStartImage = currentString;
                }
            } else if ([elementName isEqualToString:@"endimage"]) {
                if ([fileManager fileExistsAtPath:[score.scorePath stringByAppendingPathComponent:currentString]]) {
                    mosaicEndImage = currentString;
                }
            } else if ([elementName isEqualToString:@"finalimage"]) {
                if ([fileManager fileExistsAtPath:[score.scorePath stringByAppendingPathComponent:currentString]]) {
                    mosaicFinalImage = currentString;
                }
            } else if ([elementName isEqualToString:@"duration"]) {
                //Only enable the mosaic if we're running to a timelimit rather than duration.
                if (UIDelegate.clockDuration < 0) {
                    mosaicDuration = [currentString integerValue];
                }
            }
            break;
            
        case kImage:
            if ([elementName isEqualToString:@"background"]) {
                if ([fileManager fileExistsAtPath:[score.scorePath stringByAppendingPathComponent:imageName]]) {
                    UIImage *backgroundImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:imageName]];
                    background = [CALayer layer];
                    background.contents = (id)backgroundImage.CGImage;
                    background.anchorPoint = CGPointZero;
                    background.frame = CGRectMake(imageOffset.x, imageOffset.y, backgroundImage.size.width, backgroundImage.size.height);
                }
            } else if ([elementName isEqualToString:@"fadelayer"]) {
                if ([fileManager fileExistsAtPath:[score.scorePath stringByAppendingPathComponent:imageName]]) {
                    UIImage *fadeImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:imageName]];
                    fadeLayer = [CALayer layer];
                    fadeLayer.contents = (id)fadeImage.CGImage;
                    fadeLayer.anchorPoint = CGPointZero;
                    fadeLayer.frame = CGRectMake(imageOffset.x, imageOffset.y, fadeImage.size.width, fadeImage.size.height);
                }
            } else if ([elementName isEqualToString:@"overlay"]) {
                if ([fileManager fileExistsAtPath:[score.scorePath stringByAppendingPathComponent:imageName]]) {
                    UIImage *overlayImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:imageName]];
                    overlay = [CALayer layer];
                    overlay.contents = (id)overlayImage.CGImage;
                    overlay.anchorPoint = CGPointZero;
                    overlay.frame = CGRectMake(imageOffset.x, imageOffset.y, overlayImage.size.width, overlayImage.size.height);
                }
            } else if ([elementName isEqualToString:@"image"]) {
                imageName = currentString;
            } else if ([elementName isEqualToString:@"xoffset"]) {
                imageOffset.x = [currentString floatValue];
            } else if ([elementName isEqualToString:@"yoffset"]) {
                imageOffset.y = [currentString floatValue];
            }
            break;
            
        default:
            break;
    }
    
    isData = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    pathsLoaded = YES;
    BOOL traversable = YES;
    
    if ([endZone count] > 0) {
        //Check to see which junctions are a gateway to our endzone and keep a list of them.
        borderJunctions = [[NSMutableArray alloc] init];
        NSNumber *key;
        for (key in junctions) {
            for (int i = 0; i < [((Junction *)[junctions objectForKey:key]).stops count]; i++) {
                if ([endZone indexOfObject:[NSNumber numberWithInteger:[[((Junction *)[junctions objectForKey:key]).stops objectAtIndex:i] indexAtPosition:0]]] != NSNotFound) {
                    [borderJunctions addObject:key];
                    ((Junction *)[junctions objectForKey:key]).isBorderJunction = YES;
                    i = (int)[((Junction *)[junctions objectForKey:key]).stops count];
                }
            }
        }
        
        traversable = [self findFinalPaths];
    }
    
    //If we're running with a timelimit rather than an actual duration we need both an endzone
    //and a traversable network. Notify the player we have a bad paths file.
    if (UIDelegate.clockDuration < 0 && !(traversable && ([endZone count] > 0))) {
        badPaths = YES;
    }
    
    //Since we deal with the mosaic every half second, time the duration by 2.
    mosaicDuration *= 2;
    
    parser.delegate = nil;
    xmlParser = nil;
    
    [pathsCondition lock];
    pathsLoaded = YES;
    [pathsCondition signal];
    [pathsCondition unlock];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    badPaths = YES;
    parser.delegate = nil;
    xmlParser = nil;
    [pathsCondition lock];
    pathsLoaded = YES;
    [pathsCondition signal];
    [pathsCondition unlock];
}

@end

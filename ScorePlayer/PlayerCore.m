//
//  PlayerCore.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 20/2/20.
//  Copyright (c) 2020 Decibel. All rights reserved.
//

#import "PlayerCore.h"
#import "OSCMessage.h"
#import "Connection.h"
#import "Score.h"
#import "LastNetworkAddress.h"


//Network protocol version. This must be incremented if a change to the protocol breaks
//backwards compatibility.

const NSInteger NETWORK_PROTOCOL_VERSION = 16;

@interface PlayerCore ()

- (void)sendControlSignal:(NSString *)signalType;
- (void)sendControlSignal:(NSString *)signalType withFloatParameter:(CGFloat)parameter;

- (void)playerPlayWithAudio:(BOOL)startAudio;
- (void)playerReset;
- (void)playerSeekTo:(CGFloat)location;
- (void)playerSeekFinishedAfterResync:(BOOL)sync;
- (void)playerStopAt:(CGFloat)location;
- (void)playerSetScoreDuration:(CGFloat)duration;

- (void)sendNetworkMessage:(OSCMessage *)message;
- (void)messageReceived:(OSCMessage *)message overConnection:(Connection *)connection;

- (void)attemptReconnection;
- (void)disableReconnection;
- (void)disconnect;

- (void)tick;
- (void)startClock;

@end

@implementation PlayerCore {
    NSTimer *clock;
    NSDate *ntpReferenceDate;
    int splitSecond;
    BOOL syncNextTick;
    
    NSArray *availableScores;
    NSMutableArray *commonScores;
    BOOL isNetworked;
    BOOL awaitingStatus;
    
    PlayerServer2 *playerServer;
    NSString *serviceName;
    NSMutableArray *connections;
    NSMutableArray *networkDevices;
    NSInteger retries;
    NSTimer *reconnectionTimer;
    LastNetworkAddress *lastNetworkAddress;
    
    NSLock *durationChangeLock;
    
    __weak id<PlayerUIDelegate> UIDelegate;
    __weak id<PlayerUIDelegate> delegateBackup;
}

@synthesize isPausable, isStatic, playerState, currentScore, isMaster, clockEnabled, allowClockChange, clockDuration, clockProgress, splitSecondMode, allowSyncToTick, identifier, rendererDelegate, networkStatusDelegate, connectedManually;

- (id)initWithScore:(Score *)score delegate:(__weak id<PlayerUIDelegate>)delegate
{
    self = [super init];
    
    currentScore = score;
    ntpReferenceDate = [OSCMessage ntpReferenceDate];
    
    //The network hasn't been brought up yet
    isNetworked = NO;
    //The player is always the master if it's in stand alone mode
    isMaster = YES;
    awaitingStatus = NO;
    syncNextTick = NO;
    
    //Initialize arrays to store list of connected clients and connections
    networkDevices = [[NSMutableArray alloc] init];
    connections = [[NSMutableArray alloc] init];
    lastNetworkAddress = [LastNetworkAddress sharedNetworkAddress];
    connectedManually = NO;
    
    durationChangeLock = [[NSLock alloc] init];
    
    UIDelegate = delegate;
    delegateBackup = delegate;
    
    return self;
}

- (BOOL)initializeServerWithServiceName:(NSString *)name identifier:(NSString *)ident
{
    //If our server has already been initialized we shouldn't be here.
    if (playerServer != nil) {
        return NO;
    }
    
    //If we don't have a manually assigned identifier (requested by the score) use the device name.
    if (ident == nil) {
        identifier = [[UIDevice currentDevice] name];
    } else {
        identifier = ident;
    }
    
    //Set up our server. Use port 3514 by default. (Hex 0dBA. Nerd alert!)
    serviceName = name;
    playerServer = [[PlayerServer2 alloc] initWithName:currentScore.scoreName deviceName:identifier serviceName:serviceName preferredPort:0x0dBA protocolVersion:NETWORK_PROTOCOL_VERSION];
    playerServer.delegate = self;
    isNetworked = [playerServer start];
    return isNetworked;
}

- (void)registerScoreList:(NSArray *)list
{
    availableScores = list;
    
    NSMutableArray *scoreList = [[NSMutableArray alloc] init];
    for (int i = 0; i < [list count]; i++) {
        //Exclude scores which need an identifier for now. We may fix this later.
        if (!((Score *)[list objectAtIndex:i]).askForIdentifier) {
            [scoreList addObject:[NSArray arrayWithObjects:((Score *)([list objectAtIndex:i])).scoreName, ((Score *)([list objectAtIndex:i])).composerFullText, ((Score *)([list objectAtIndex:i])).scoreType, ((Score *)([list objectAtIndex:i])).version, nil]];
        }
    }
    if ([scoreList count] > 0) {
        playerServer.localScoreList = [NSArray arrayWithArray:scoreList];
    }
}

- (void)loadScore:(Score *)score {
    //Close our previous score and perform clean up.
    //Reattach our UI first if it's detached.
    if (UIDelegate == nil) {
        UIDelegate = delegateBackup;
    }
    [UIDelegate closeScore];
    
    clockDuration = (int)roundf(score.originalDuration);
    
    //Set the initial clock properties based on the specified duriation of the score.
    //Duration can be zero for a static score (in which case we disable the clock),
    //or negative to indicate that it should keep going without limit.
    clockEnabled = YES;
    splitSecondMode = NO;
    splitSecond = 0;
    isStatic = NO;
    
    if (clockDuration > 0) {
        clockEnabled = YES;
        allowClockChange = YES;
        allowSyncToTick = YES;
    } else {
        if (clockDuration == 0) {
            clockEnabled = NO;
        }
        allowClockChange = NO;
        allowSyncToTick = NO;
    }
    
    [UIDelegate loadScore:score];
    [self playerReset];
    
    currentScore = score;
}

- (void)shutdown
{
    //Stop any reconnection attempts first.
    [reconnectionTimer invalidate];
    
    
  if (isNetworked) {
      if (isMaster || playerServer.isSecondary) {
          //Stop the server if we're the master or secondary
          [playerServer stop];
      }
      if ([connections count] > 0) {
          //Close any open connections
          [connections makeObjectsPerformSelector:@selector(close)];
          [connections removeAllObjects];
          isMaster = YES;
      }
      isNetworked = NO;
      playerServer.delegate = nil;
      rendererDelegate = nil;
      //playerServer = nil;
  }
  
  networkStatusDelegate = nil;
}

- (void)sendPing
{
    if (isMaster) {
        [playerServer sendPing];
    }
}

- (void)play
{
    //Check if we're already playing.
    if ((playerState == kPlaying) || isStatic) {
        return;
    }
    if (isNetworked) {
        //Play via network message
        [self sendControlSignal:@"Play"];
    } else {
        //Play directly. (Follow the same pattern for all control functions.)
        [self playerPlayWithAudio:YES];
    }
}

- (void)pause
{
    //Since the ability to pause is currently dependent on the renderer having a stop function,
    //don't do anything to the state of the player if this function does not exist.
    if (!isPausable || playerState != kPlaying) {
        return;
    }
    CGFloat pauseLocation = (clockProgress + 1) / clockDuration;
    if (isNetworked) {
        [self sendControlSignal:@"Pause" withFloatParameter:pauseLocation];
    } else {
        [self playerStopAt:pauseLocation];
    }
}

- (void)reset
{
    if (isNetworked) {
        [self sendControlSignal:@"Reset"];
    } else {
        [self playerReset];
    }
}

- (void)seekTo:(CGFloat)location
{
    if (isNetworked) {
        [self sendControlSignal:@"Seek" withFloatParameter:location];
    } else {
        [self playerSeekTo:location];
    }
}

- (void)seekFinished
{
    if (isNetworked) {
        [self sendControlSignal:@"SeekFinished"];
    } else {
        [self playerSeekFinishedAfterResync:NO];
    }
}

- (void)setScoreDuration:(CGFloat)duration
{
    if (isNetworked) {
        [self sendControlSignal:@"SetDuration" withFloatParameter:duration];
    } else {
        [self playerSetScoreDuration:duration];
    }
}

- (void)stopClockWithStateUpdate:(BOOL)updateState
{
    [clock invalidate];
    if (updateState) {
        playerState = kStopped;
    }
}

- (void)resetClock
{
    [clock invalidate];
    clockProgress = 0;
    splitSecond = 0;
}

- (void)attemptSync
{
    if (isNetworked && !isMaster && allowSyncToTick && playerState == kPlaying) {
        syncNextTick = YES;
    } else if (isMaster && allowSyncToTick && playerState == kPlaying && [rendererDelegate respondsToSelector:@selector(attemptSync)]) {
        [rendererDelegate attemptSync];
    }
}

- (void)prepareNetworkStatusView:(id<NetworkStatus>)viewController
{
    //Handle this here since the UIDelegate doesn't know much of anything about our network.
    networkStatusDelegate = viewController;
    networkStatusDelegate.networkDevices = networkDevices;
    
    if (playerServer.isSecondary) {
        networkStatusDelegate.connected = YES;
    } else {
        networkStatusDelegate.connected = (playerServer.portNumber == 0 || playerServer.clientsCount > 0);
    }
    networkStatusDelegate.serviceName = serviceName;
    if (currentScore.scoreName.length > 29) {
        networkStatusDelegate.serverNamePrefix = [currentScore.scoreName substringToIndex:29];
    } else {
        networkStatusDelegate.serverNamePrefix = currentScore.scoreName;
    }
    networkStatusDelegate.localServerName = playerServer.serverName;
    if (lastNetworkAddress != nil) {
        networkStatusDelegate.lastAddress = lastNetworkAddress.address;
    }
    if (playerServer.localScoreList == nil) {
        networkStatusDelegate.allowScoreChange = NO;
    } else {
        networkStatusDelegate.allowScoreChange = YES;
        networkStatusDelegate.availableScores = commonScores;
    }
    networkStatusDelegate.networkConnectionDelegate = self;
}

- (void)sendControlSignal:(NSString *)signalType
{
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Control"];
    [message appendAddressComponent:signalType];
    [self sendNetworkMessage:message];
}

- (void)sendControlSignal:(NSString *)signalType withFloatParameter:(CGFloat)parameter
{
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Control"];
    [message appendAddressComponent:signalType];
    [message addFloatArgument:parameter];
    [self sendNetworkMessage:message];
}

- (CGFloat)clockLocation
{
    if (clockDuration > 0) {
        return clockProgress / clockDuration;
    } else {
        return 0;
    }
}

- (CGFloat)detach:(BOOL)detached
{
    [durationChangeLock lock];
    CGFloat savedDuration = clockDuration;
    [durationChangeLock unlock];
    if (detached) {
        UIDelegate = nil;
        if ([rendererDelegate respondsToSelector:@selector(setDetached:)]) {
            rendererDelegate.detached = YES;
        }
    } else {
        UIDelegate = delegateBackup;
        if ([rendererDelegate respondsToSelector:@selector(setDetached:)]) {
            rendererDelegate.detached = NO;
        }
        //Perform the initial sync instantly. (Similar procedure to updating our status.)
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [UIDelegate playerSeekTo:self.clockLocation endReachedWhilePlaying:NO];
        [CATransaction commit];
        if (playerState == kPlaying) {
            [UIDelegate playerPlayWithAudio:NO];
        }
        [UIDelegate playerSeekFinishedAfterResync:YES];
        if ([rendererDelegate respondsToSelector:@selector(attemptSync)]) {
            [rendererDelegate attemptSync];
        }
        [UIDelegate setInitialState:playerState fromNetwork:NO];
    }
    return savedDuration;
}

//For all of these functions, safety checks are carried out in the calling functions.
//(This prevents additional, invalid network traffic.)
- (void)playerPlayWithAudio:(BOOL)startAudio
{
    playerState = kPlaying;
    
    //Stop updating the client list.
    if (isMaster) {
        [playerServer suspendBroadcastingClientInfo];
    }
    
    //Take care of any user interface changes, and start the clock.
    [UIDelegate playerPlayWithAudio:startAudio];
    if (clockEnabled) {
        [self startClock];
    }
}

- (void)playerReset
{
    //Stop and reset our clock
    playerState = kStopped;
    [clock invalidate];
    clockProgress = 0;
    splitSecond = 0;
    
    if (UIDelegate != nil) {
        int clockAdjust = [UIDelegate playerReset];
        clockProgress = clockAdjust;
    } else {
        //If we're detached from the user interface, let the renderer know that it needs
        //to regenerate the score's generative elements.
        if ([rendererDelegate respondsToSelector:@selector(regenerate)]) {
            [rendererDelegate regenerate];
        }
    }
    
    //Resume polling the list of connected clients
    if (isMaster) {
        [playerServer resumeBroadcastingClientInfo];
    }
}

- (void)playerSeekTo:(CGFloat)location
{
    //TODO: There are some interesting ordering assumptions here from the original code.
    //TODO: Check that these are still valid.
    [clock invalidate];
    
    //Since clock resolution is only gauranteed to the second, round our value.
    clockProgress = (int)roundf(location * clockDuration);
    splitSecond = 0;
    
    if (clockEnabled) {
        if (clockProgress < 0 && (playerState == kPlaying || playerState == kPaused)) {
            //Don't allow the score to move outside of the playback area if playing
            clockProgress = 0;
        }
    }
    
    //Check if we hit the end of the score in our seek operation.
    BOOL ended = NO;
    if ((playerState == kPlaying || playerState == kPaused) && clockProgress == clockDuration) {
        playerState = kStopped;
        ended = YES;
    }
    
    //Make any UI and renderer changes.
    [UIDelegate playerSeekTo:self.clockLocation endReachedWhilePlaying:ended];
    
    //Then restart our clock.
    if (clockEnabled) {
        if (playerState == kPlaying) {
            [self startClock];
        }
    }
    
    //Or resume broadcasting the client list.
    if (ended && isMaster) {
        [playerServer resumeBroadcastingClientInfo];
    }
}

- (void)playerSeekFinishedAfterResync:(BOOL)sync
{
    [UIDelegate playerSeekFinishedAfterResync:sync];
}

- (void)playerStopAt:(CGFloat)location
{
    playerState = kPaused;
    [UIDelegate playerStop];
    //Make sure that we're rounded to the nearest second with a seek operation.
    //(This will also stop our clock.)
    [self playerSeekTo:location];
    [self playerSeekFinishedAfterResync:NO];
}

- (void)playerSetScoreDuration:(CGFloat)duration
{
    //Get our current location so we can keep it consistent after the change.
    [durationChangeLock lock];
    CGFloat location = self.clockLocation;
    
    //Seeking will be enough to update the UI.
    if ([rendererDelegate respondsToSelector:@selector(changeDuration:currentLocation:)]) {
        //Check if there's an adjustmant to the duration or location.
        clockDuration = [rendererDelegate changeDuration:duration currentLocation:&location];
    } else if ([rendererDelegate respondsToSelector:@selector(changeDuration:)]) {
        clockDuration = duration;
        [rendererDelegate changeDuration:duration];
    } else {
        //In the case that a renderer doesn't need to do anything to accommodate a clock change.
        clockDuration = duration;
    }
    [self playerSeekTo:location];
    [durationChangeLock unlock];
}

- (void)sendNetworkMessage:(OSCMessage *)message
{
    //If we're the master then we send the network message directly to the server.
    //Otherwise we send it through the connection to the primary server.
    if (isMaster) {
        [playerServer sendNetworkMessage:message];
    } else {
        //The connections array shouldn't be empty if we're here, but check for safety.
        if ([connections count] > 0) {
            [[connections objectAtIndex:0] sendNetworkMessage:message];
        } else {
            NSLog(@"Danger Will Robinson!");
        }
    }
}

- (void)messageReceived:(OSCMessage *)message overConnection:(Connection *)connection
{
    //Each message processing branch should check that the arguments provided are of the expected type.
    //If not then the message should be discarded.
    //All messages should have at least one address component.
    
    //IMPORTANT: The code that checks whether messages are valid relies on logic operator short
    //circuiting to function correctly. (Without this you will get out of bounds exceptions.)
    if ([message.address count] < 1) {
        return;
    }
    
    //If we're displaying a terminal error then don't process any messages.
    //TODO: Investigate whether we should still do this.
    if (UIDelegate.alertShown) {
        return;
    }
    
    //For the most part, we can ignore which connection the message comes over. The secondary server is set up to
    //not pass messages on to the client devices. (We may change this assumption for added safety later on.)

    if ([[message.address objectAtIndex:0] isEqualToString:@"Ping"]) {
        [message setAddressWithString:@"/Pong"];
        double delta = [[NSDate date] timeIntervalSinceDate:ntpReferenceDate];
        SInt32 *ptr = (SInt32 *)&delta;
        [message addIntegerArgument:*ptr];
        [message addIntegerArgument:*(ptr + 1)];
        //NSLog(@"Ints: %i, %i", *ptr, *(ptr + 1));
        [self sendNetworkMessage:message];
    }
    if ([[message.address objectAtIndex:0] isEqualToString:@"Control"] && [message.address count] >= 2) {
        //This is a generic control message that the player should handle
        if ([[message.address objectAtIndex:1] isEqualToString:@"Play"]) {
            //Check that we're not already playing.
            if ((playerState == kPlaying) || isStatic) {
                return;
            }
            [self playerPlayWithAudio:YES];
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"Reset"]) {
            [self playerReset];
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"Seek"]) {
            if (![message.typeTag isEqualToString:@",f"]) {
                return;
            }
            [self playerSeekTo:[[message.arguments objectAtIndex:0] floatValue]];
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"SeekFinished"]) {
            [self playerSeekFinishedAfterResync:NO];
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"Pause"]) {
            if (![message.typeTag isEqualToString:@",f"]) {
                return;
            }
            //Check that pausing is possible.
            if (!isPausable || playerState != kPlaying) {
                return;
            }
            [self playerStopAt:[[message.arguments objectAtIndex:0] floatValue]];
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"SetDuration"]) {
            if (![message.typeTag isEqualToString:@",f"] || playerState != kStopped) {
                return;
            }
            if ([[message.arguments objectAtIndex:0] floatValue] <= 0 || !allowClockChange) {
                //Only allow changes to positive duration values for the moment.
                return;
            }
            [self playerSetScoreDuration:[[message.arguments objectAtIndex:0] floatValue]];
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"SetOptions"]) {
            if (message.typeTag.length < 2) {
                return;
            }
            //New options to be passed to the current renderer.
            if ([rendererDelegate respondsToSelector:@selector(setOptions:)]) {
                [message setAddressWithString:@"/Options"];
                [rendererDelegate setOptions:message];
            }
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"CueLightRed"]) {
            if ([UIDelegate respondsToSelector:@selector(showCueLight:)]) {
                [UIDelegate showCueLight:[UIColor redColor]];
            }
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"CueLightGreen"]) {
            if ([UIDelegate respondsToSelector:@selector(showCueLight:)]) {
                [UIDelegate showCueLight:[UIColor greenColor]];
            }
        }
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"Renderer"]  && [message.address count] >= 2) {
        //This is data that needs to be passed to the current renderer.
        //(Strip the "Renderer" identifier first.)
        if ([rendererDelegate respondsToSelector:@selector(receiveMessage:)]) {
            [message stripFirstAddressComponent];
            [rendererDelegate receiveMessage:message];
        }
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"Status"]) {
        if (awaitingStatus) {
            if (![message.typeTag hasPrefix:@",ssssiff"]) {
                return;
            }
            
            //Check that we're running the same score. This is only checked against the score name and type
            //at present, but versioning support may be added at a later date.
            NSString *errorMessage;
            if (!([[message.arguments objectAtIndex:0] isEqualToString:currentScore.scoreName] && [[message.arguments objectAtIndex:1] isEqualToString:currentScore.composerFullText] && [[message.arguments objectAtIndex:2] isEqualToString:currentScore.scoreType])) {
                errorMessage = @"Score mismatch. Please make sure that the iPad you are attempting to connect to is running the same score.";
            } else if (!([[message.arguments objectAtIndex:3] isEqualToString:currentScore.version])) {
                errorMessage = @"Score version mismatch. Please make sure that all iPads have the same version of the score installed.";
            }
            
            if (errorMessage != nil) {
                [self disconnect];
                awaitingStatus = NO;
                [UIDelegate networkErrorWithMessage:errorMessage toStandAlone:NO];
                [UIDelegate allowAnnotation:true];
                return;
            }
            
            //See if we have options to set
            if ([message.arguments count] > 8 && [message.typeTag hasPrefix:@",ssssiffs"]) {
                if ([[message.arguments objectAtIndex:7] isEqualToString:@"CurrentOptions"] && [rendererDelegate respondsToSelector:@selector(setOptions:)]) {
                    //Copy our message arguments into a new message.
                    OSCMessage *options = [[OSCMessage alloc] init];
                    [options appendAddressComponent:@"Options"];
                    [options appendArgumentsFromMessage:message];
                    for (int i = 0; i < 8; i++) {
                        //Remove the first argument each time.
                        [options removeArgumentAtIndex:0];
                    }
                    [rendererDelegate setOptions:options];
                }
            }
            
            //Perform initial synch while stopped. If the master is playing then start
            //playback and synch properly on the next tick event.
            
            //The following lines cause the seek action to happen instantly, without animation
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            CGFloat duration = [[message.arguments objectAtIndex:6] floatValue];
            CGFloat location = [[message.arguments objectAtIndex:5] floatValue];
            if (clockDuration != duration) {
                clockDuration = duration;
                if ([rendererDelegate respondsToSelector:@selector(changeDuration:currentLocation:)]) {
                    //Because we're seeking we don't need to adjust the location here.
                    //(Use the loc variable as a throw away.)
                    CGFloat loc = location;
                    [rendererDelegate changeDuration:duration currentLocation:&loc];
                } else if ([rendererDelegate respondsToSelector:@selector(changeDuration:)]) {
                    [rendererDelegate changeDuration:duration];
                }
            }
            
            [self playerSeekTo:location];
            [CATransaction commit];
            
            if ([[message.arguments objectAtIndex:4] intValue] == kPlaying) {
                [self playerPlayWithAudio:NO];
                syncNextTick = allowSyncToTick;
            } else if ([[message.arguments objectAtIndex:4] intValue] == kPaused) {
                playerState = kPaused;
            }
            [self playerSeekFinishedAfterResync:YES];
            [UIDelegate setInitialState:playerState fromNetwork:YES];
            awaitingStatus = NO;
        }
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"Tick"]){
        if (syncNextTick) {
            if (![message.typeTag isEqualToString:@",f"]) {
                return;
            }
            [self playerSeekTo:[[message.arguments objectAtIndex:0] floatValue]];
            syncNextTick = NO;
        }
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"Master"] && [message.address count] >= 2 && isMaster) {
        //This is a message for the master device
        if ([[message.address objectAtIndex:1] isEqualToString:@"GetStatus"]) {
            //Returns the player status to a new client
            OSCMessage *response = [[OSCMessage alloc] init];
            [response appendAddressComponent:@"Status"];
            [response addStringArgument:currentScore.scoreName];
            [response addStringArgument:currentScore.composerFullText];
            [response addStringArgument:currentScore.scoreType];
            [response addStringArgument:currentScore.version];
            [response addIntegerArgument:playerState];
            [response addFloatArgument:self.clockLocation];
            [response addFloatArgument:clockDuration];
            //If our score supports options, we need to append the current options to our status.
            if ([rendererDelegate respondsToSelector:@selector(getOptions)]) {
                OSCMessage *options = [rendererDelegate getOptions];
                [response addStringArgument:@"CurrentOptions"];
                [response appendArgumentsFromMessage:options];
            }
            [self sendNetworkMessage:response];
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"BlobTest"]) {
            if (![message.typeTag isEqualToString:@",b"]) {
                return;
            }
            NSString *blobString = [NSString stringWithUTF8String:[[message.arguments objectAtIndex:0] bytes]];
            if ([blobString isEqualToString:@"Hello"]) {
                OSCMessage *response = [[OSCMessage alloc] init];
                [response appendAddressComponent:@"External"];
                [response appendAddressComponent:@"BlobTest"];
                [response addBlobArgument:[@"Ahoy hoy" dataUsingEncoding:NSUTF8StringEncoding]];
                [self sendNetworkMessage:response];
            }
        }
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"Server"] && [message.address count] >= 2) {
        //This is a message from the server. Some of these commands should not be received by the master.
        if ([[message.address objectAtIndex:1] isEqualToString:@"ClientList"] && playerState == kStopped) {
            //Check that we have an even number of strings.
            NSString *argTypes = [message.typeTag substringFromIndex:1];
            NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"s"] invertedSet];
            if (([argTypes rangeOfCharacterFromSet:invalidTags].location != NSNotFound) || ([argTypes length] % 2 == 1)) {
                return;
            }
            
            [networkDevices removeAllObjects];
            for (int i = 0; i < [message.arguments count]; i += 2) {
                [networkDevices addObject:[[NSMutableArray alloc] initWithObjects:[message.arguments objectAtIndex:i], [message.arguments objectAtIndex:(i + 1)], nil]];
            }
            networkStatusDelegate.networkDevices = networkDevices;
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"ScoreList"]) {
            if (playerServer.localScoreList == nil) {
                //We don't support setting the common score list if our local list doesn't exist.
                return;
            }
            //Check that we have the right number of strings (and only strings).
            NSString *argTypes = [message.typeTag substringFromIndex:1];
            NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"s"] invertedSet];
            if (([argTypes rangeOfCharacterFromSet:invalidTags].location != NSNotFound) || ([argTypes length] % 4 != 0)) {
                return;
            }
            if ([argTypes length] == 0) {
                commonScores = nil;
            } else {
                commonScores = [[NSMutableArray alloc] init];
                for (int i = 0; i < [argTypes length]; i+= 4) {
                    [commonScores addObject:[NSArray arrayWithObjects:[message.arguments objectAtIndex:i], [message.arguments objectAtIndex:i + 1], [message.arguments objectAtIndex:i + 2], [message.arguments objectAtIndex:i + 3], nil]];
                }
            }
            networkStatusDelegate.availableScores = commonScores;
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"RequestRejected"]) {
            //TODO: Write more code here.
            [UIDelegate errorWithTitle:@"Score Unavailable" message:@"The requested score has become unavailable. Most likely, an iPad without the score just joined the network."];
            return;

        } else if ([[message.address objectAtIndex:1] isEqualToString:@"ProtocolVersion"] && !isMaster) {
            //If we were reconnecting because of a network unreachable error, this is where we
            //need to return various UI elements to their proper state.
            [UIDelegate awaitingNetwork:NO];
            BOOL protocolError = NO;
            //For once we don't want to just silently discard a malformed message. If the server isn't
            //giving us the result we expect then we are likely trying to connect to an incompatible version.
            if (![message.typeTag isEqualToString:@",s"]) {
                protocolError = YES;
            } else {
                //If the message is valid then check the protocol version
                NSInteger protocolVersion = [[[message.arguments objectAtIndex:0] stringByReplacingOccurrencesOfString:@"Decibel Networking Protocol v" withString:@""] integerValue];
                if (protocolVersion != NETWORK_PROTOCOL_VERSION) {
                    protocolError = YES;
                }
            }
            if (protocolError) {
                //Network protocol mismatch. Close connection.
                if ([connections count] > 0) {
                    [connections makeObjectsPerformSelector:@selector(close)];
                    [connections removeAllObjects];
                    isMaster = YES;
                    rendererDelegate.isMaster = YES;
                    [UIDelegate networkErrorWithMessage:@"Network protocol version mismatch. Unable to connect.\n\n(Please make sure all iPads are running the same version of the ScorePlayer app.)" toStandAlone:NO];
                    if (playerServer != nil) {
                        [playerServer start];
                    }
                }
            } else {
                //Send our device name to the server
                OSCMessage *response = [[OSCMessage alloc] init];
                [response appendAddressComponent:@"Server"];
                [response appendAddressComponent:@"RegisterDevice"];
                [response addStringArgument:[NSString stringWithFormat:@"Decibel Networking Protocol v%li", (long)NETWORK_PROTOCOL_VERSION]];
                [response addStringArgument:identifier];
                [response addStringArgument:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
                [self sendNetworkMessage:response];
            }
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"ConnectionOK"] && !isMaster) {
            //Handshake completed. Get the status of the current score from the server if this is from the primary.
            if ([connections indexOfObjectIdenticalTo:connection] == 0) {
                isMaster = NO;
                rendererDelegate.isMaster = NO;
                OSCMessage *message = [[OSCMessage alloc] init];
                [message appendAddressComponent:@"Master"];
                [message appendAddressComponent:@"GetStatus"];
                [self sendNetworkMessage:message];
            }
            //Then register our list of scores with the server if we have one. (Whether primary or secondary.)
            if (playerServer.localScoreList != nil) {
                OSCMessage *message = [[OSCMessage alloc] init];
                [message appendAddressComponent:@"Server"];
                [message appendAddressComponent:@"RegisterScores"];
                for (int i = 0; i < [playerServer.localScoreList count]; i++) {
                    for (int j = 0; j < 4; j++) {
                        [message addStringArgument:[[playerServer.localScoreList objectAtIndex:i] objectAtIndex:j]];
                    }
                }
                [connection sendNetworkMessage:message];
            }
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"MakeSecondary"] && !isMaster) {
            //Start up a secondary server
            OSCMessage *message = [playerServer startSecondary:connection.localAddress ignoreBonjourAddress:connectedManually];
            if (message == nil) {
                //The server failed to start. We should handle this in a more robust way,
                //but for the moment we'll just silently give up.
                return;
            } else {
                //If succesful, notify the primary server.
                [self sendNetworkMessage:message];
            }
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"CancelSecondary"] && playerServer.isSecondary) {
            //Something has gone wrong in registering our secondary server. Shut it down.
            [playerServer stop];
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"SecondaryServer"]) {
            if (![message.typeTag isEqualToString:@",si"]) {
                return;
            }
            //Don't connect to the secondary if we're the master. (And definitely don't connect to
            //ourself if we're the secondary.)
            if (!(isMaster || playerServer.isSecondary)) {
                Connection *connection = [[Connection alloc] initWithHostAddress:[message.arguments objectAtIndex:0] port:[[message.arguments objectAtIndex:1] intValue]];
                [connection connectWithDelegate:self withTimeout:-1];
                [connections addObject:connection];
                
                //Register the device with the secondary
                OSCMessage *response = [[OSCMessage alloc] init];
                [response appendAddressComponent:@"Server"];
                [response appendAddressComponent:@"RegisterDevice"];
                [response addStringArgument:[NSString stringWithFormat:@"Decibel Networking Protocol v%li", (long)NETWORK_PROTOCOL_VERSION]];
                [response addStringArgument:identifier];
                [response addStringArgument:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
                [connection sendNetworkMessage:response];
            }
        } else if (([[message.address objectAtIndex:1] isEqualToString:@"RegisteredExternals"] || [[message.address objectAtIndex:1] isEqualToString:@"UnregisteredExternals"]) && playerServer.isSecondary) {
            //We're the secondary server, and the primary server has accepted or closed connections
            //from external OSC capable devices. Notify our local server.
            [playerServer sendNetworkMessage:message];
        }
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"Score"] && [message.address count] >= 2) {
        if ([[message.address objectAtIndex:1] isEqualToString:@"Load"]) {
            if (![message.typeTag isEqualToString:@",ssss"]) {
                return;
            }
            
            NSUInteger index = [availableScores indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                Score *score = (Score *)obj;
                return [[message.arguments objectAtIndex:0] isEqualToString:score.scoreName] && [[message.arguments objectAtIndex:1] isEqualToString:score.composerFullText] && [[message.arguments objectAtIndex:2] isEqualToString:score.scoreType] && [[message.arguments objectAtIndex:3] isEqualToString:score.version];
            }];
            
            if (index == NSNotFound) {
                //We don't have the requested score. Disconnect.
                [self disconnect];
                if (playerState != kStopped) {
                    [self reset];
                }
                [UIDelegate errorWithTitle:@"Score Not Found" message:@"The requested score file could not be found on this device."];
                return;
            } else {
                //Clear the cache to free up memory. (This won't free up resources used by the current
                //score, but will clear any remnants from previous scores.)
                [Renderer clearCache];
                [self loadScore:[availableScores objectAtIndex:index]];
                OSCMessage *response = [[OSCMessage alloc] init];
                [response appendAddressComponent:@"Server"];
                [response appendAddressComponent:@"LoadOK"];
                [self sendNetworkMessage:response];
                
                //We also need to update our own server name, so that it's valid if we're needed as a secondary
                //or if we disconnect and resume publishing our own server later.
                [playerServer changeName:[message.arguments objectAtIndex:0]];
            }
        }
    }
}

- (void)attemptReconnection
{
    [reconnectionTimer.userInfo reconnectWithDelegate:self];
}

- (void)disableReconnection
{
    retries = 0;
}

- (void)disconnect
{
    //Close any connections and restart our server if it's not running
    [reconnectionTimer invalidate];
    isMaster = YES;
    [connections makeObjectsPerformSelector:@selector(close)];
    [connections removeAllObjects];
    rendererDelegate.isMaster = YES;
    
    if (playerServer.portNumber > 0) {
        //This disconnects all clients connected to the server and makes it the primary.
        [playerServer disconnectClients];
    } else {
        [playerServer start];
    }
}


- (void)tick
{
    if (clockDuration == 0) {
        return;
    }
    
    //Increment the clock
    if (splitSecondMode) {
        clockProgress += splitSecond;
        splitSecond++;
        splitSecond %= 2;
    } else {
        clockProgress++;
    }
    
    BOOL finished = NO;
    if (clockProgress >= clockDuration && clockDuration > 0) {
        [clock invalidate];
        clockProgress = clockDuration;
        playerState = kStopped;
        finished = YES;
    }
    
    //Send a tick across the network
    if (isNetworked && isMaster && !splitSecond) {
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"Tick"];
        [message addFloatArgument:self.clockLocation];
        [self sendNetworkMessage:message];
    }
    
    [UIDelegate tick:clockProgress tock:splitSecond noMoreClock:finished];
    
    if (finished && isMaster) {
        [playerServer resumeBroadcastingClientInfo];
    }
}

- (void)startClock
{
    //Invalidate first so we don't end up with multiple timers.
    [clock invalidate];
    if (clockProgress < 0) {
        //Make sure we're not in a pre playback area of the score.
        clockProgress = 0;
    }
    if (clockDuration != 0) {
        if (splitSecondMode) {
            clock = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        } else {
            clock = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        }
    }
}

#pragma mark - PlayerServer2 delegate

- (void)receivedNetworkMessage:(OSCMessage *)message
{
    if (isNetworked) {
        //Received a message for processing from our own server.
        [self messageReceived:message overConnection:nil];
    }
}

- (void)publishingFailed
{
    //Our server failed to start properly.
    //Display error message and fall back to stand alone mode.
    isNetworked = NO;
    [UIDelegate networkErrorWithMessage:@"Unable to publish server. Falling back to stand alone player." toStandAlone:YES];
}

#pragma mark - Connection delegate

- (void)receivedNetworkMessage:(OSCMessage *)message overConnection:(Connection *)sourceConnection
{
    //Pass the connection details on because we need check to see whether the message is
    //coming from our primary or secondary server for handshake purposes.
    if (isNetworked) {
        [self messageReceived:message overConnection:sourceConnection];
    }
}

- (void)connectionTerminated:(Connection *)sourceConnection withError:(NSError *)error
{
    //If we've been disconnected because the network was unreachable right at the start of the connection
    //attempt this may be because the device is waiting to generate a link local address. Try to reconnect.
    if ([error.domain isEqualToString:@"NSPOSIXErrorDomain"] && error.code == ENETUNREACH) {
        if (!(isMaster || playerServer.isSecondary) && retries > 0) {
            [reconnectionTimer invalidate];
            retries--;
            reconnectionTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(attemptReconnection) userInfo:sourceConnection repeats:NO];
            [UIDelegate awaitingNetwork:YES];
            return;
        }
    }
    
    [sourceConnection close];
    [connections removeObject:sourceConnection];
    //If this was our only connection and we're not the secondary then resume broadcasting our own server.
    //(This shouldn't be possible, but we'll have code to handle it just in case.)
    if ([connections count] == 0) {
        if (!(isMaster || playerServer.isSecondary)) {
            isMaster = YES;
            rendererDelegate.isMaster = YES;
            [UIDelegate networkErrorWithMessage:@"Lost connection to server." toStandAlone:NO];
            //If our own server isn't running, start it up.
            if (playerServer.portNumber == 0) {
                [playerServer start];
            }
        } else if (playerServer.isSecondary) {
            //Otherwise, if we're the secondary it's time to take over
            isMaster = YES;
            [playerServer makePrimary];
            rendererDelegate.isMaster = YES;
        }
    }
}

#pragma mark - NetworkConnection delegate

- (void)connectToServer:(NSString *)hostName onPort:(NSUInteger)port withTimeout:(NSInteger)timeout
{
    //We just make the connection here. We don't do anything to get the status of the server or register
    //our device. This is done after we receive the protocol version and complete the initial network handshake.
    //(We also hold off on notifying the renderer of the change until this is all completed.)
    isMaster = NO;
    [playerServer stop];
    [networkDevices removeAllObjects];
    
    Connection *connection = [[Connection alloc] initWithHostAddress:hostName port:port];
    if ([connection connectWithDelegate:self withTimeout:timeout]) {
        [UIDelegate allowAnnotation:false];
        [connections addObject:connection];
        isNetworked = YES;
        awaitingStatus = YES;
        retries = 30;
    } else {
        [self connectionTerminated:connection withError:nil];
    }
}

- (void)saveLastManualAddress:(NSString *)address
{
    lastNetworkAddress.address = address;
}

- (void)requestScoreLoad:(NSArray *)scoreInfo
{
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Server"];
    [message appendAddressComponent:@"LoadRequest"];
    for (int i = 0; i < [scoreInfo count]; i++) {
        [message addStringArgument:[scoreInfo objectAtIndex:i]];
    }
    [self sendNetworkMessage:message];
    networkStatusDelegate = nil;
}

#pragma mark - RendererMessaging delegate

- (BOOL)sendData:(OSCMessage *)message
{
    if (isNetworked) {
        //We prepend the message address with the label "Renderer" unless it is intended for an external device.
        if (!([message.address count] > 0 && [[message.address objectAtIndex:0] isEqualToString:@"External"])) {
            [message prependAddressComponent:@"Renderer"];
        }
        [self sendNetworkMessage:message];
        return YES;
    } else {
        //If we're not networked then send the data message locally. This way, renderers can be coded
        //to respond to network messages, without needing to know the state of the network.
        if (!([message.address count] > 0 && [[message.address objectAtIndex:0] isEqualToString:@"External"])) {
            [rendererDelegate receiveMessage:message];
        }
        return NO;
    }
}

#pragma mark - RendererOptions delegate

- (OSCMessage *)getOptions
{
    if ([rendererDelegate respondsToSelector:@selector(getOptions)]) {
        return [rendererDelegate getOptions];
    } else {
        return nil;
    }
}

- (void)setOptions:(OSCMessage *)newOptions
{
    if (newOptions == nil) {
        return;
    }
    if (isNetworked) {
        [newOptions setAddressWithString:@"/Control/SetOptions"];
        [self sendNetworkMessage:newOptions];
    } else if ([rendererDelegate respondsToSelector:@selector(setOptions:)]) {
        [rendererDelegate setOptions:newOptions];
    }
}

@end

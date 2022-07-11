//
//  PlayerServer2.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 8/11/2014.
//  Copyright (c) 2014 Decibel. All rights reserved.
//

#import "PlayerServer2.h"
#import "AppDelegate.h"
#import <errno.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import "OSCMessage.h"

@interface PlayerServer2 ()

- (BOOL)serverStart;
- (void)processServerMessage:(OSCMessage *)message from:(Connection *)sourceConnection isLocal:(BOOL)local;
- (void)promoteNewSecondary:(Connection *)connection;
- (void)handshakeTimeOut:(NSTimer *)timeOut;
- (void)secondaryTimeOut:(NSTimer *)timeOut;
- (void)loadResponseTimeOut;

- (BOOL)startBonjour;
- (void)stopBonjour;
- (NSString *)serverNameFromScoreName:(NSString *)scoreName deviceName:(NSString *)deviceName;
- (void)sayGoodbyeAndShutdown:(BOOL)shutdown;

- (NSArray *)getCommonScores;
- (void)loadScore:(NSArray *)scoreInfo;
- (void)checkIfLoadComplete;
- (void)broadCastInfo;

- (void)loadComplete;

- (OSCMessage *)getClientListMessage;
- (OSCMessage *)getScoreListMessage;

- (BOOL)isIPv4Address:(NSString *)address;
- (NSString *)getIPv4ForInterfaceWithIPv6Address:(NSString *)address;
- (void)sendExternalMessage:(OSCMessage *)message toHost:(NSString *)address port:(int)port;

@end

@implementation PlayerServer2 {
    NSNetService *publisher;
    NSNetService *udpPublisher;
    NSNetService *resolver;
    NSString *service;
    NSString *udpService;
    NSString *preferredServerName;
    NSString *deviceName;
    NSString *hostName;
    NSString *hostAddress;
    NSString *ipv4Address;
    NSUInteger preferredPortNumber;
    NSUInteger udpPortNumber;
    NSUInteger protocolVersion;
    NSUInteger publisherRetries;
    NSMutableArray *timeOuts;
    
    //Arrays storing device names and app version numbers
    NSMutableArray *serverInfo;
    //NSMutableArray *clientList;
    
    //An array of the actual connection objects
    NSMutableArray *clients;
    NSMutableDictionary *externals;
    NSTimer *infoBroadcast;
    
    GCDAsyncSocket *listeningSocket;
    GCDAsyncUdpSocket *udpSocket;
    
    //Variables related to our backup server
    Connection *secondaryConnection;
    NSString *secondaryAddress;
    NSUInteger secondaryPort;
    NSTimer *secondaryTimeOut;
    NSMutableArray *secondaryBlacklist;
    
    //Variables relating to score loading
    NSArray *commonScores;
    BOOL commonScoresUpdated;
    BOOL loadInProgress;
    NSUInteger loadConfirmationCount;
    NSTimer *loadResponseTimeOut;
    
    NSLock *dictionaryLock;
    
    NSDate *ntpReferenceDate;
}

@synthesize serverName, portNumber, isSecondary, delegate;

- (id)initWithName:(NSString *)name deviceName:(NSString *)devName serviceName:(NSString *)serviceName preferredPort:(NSUInteger)preferredPort protocolVersion:(NSInteger)netProtocolVersion
{
    //If we don't have all our necessary parameters, return nil.
    if (!name || !serviceName || preferredPort > 65535) {
        return nil;
    }
    
    self = [super init];
    deviceName = devName;
    preferredServerName = [self serverNameFromScoreName:name deviceName:deviceName];
    service = [NSString stringWithFormat:@"_%@._tcp.", serviceName];
    udpService = [NSString stringWithFormat:@"_%@._udp.", serviceName];
    
    hostName = nil;
    hostAddress = nil;
    ipv4Address = nil;
    preferredPortNumber = preferredPort;
    portNumber = 0;
    udpPortNumber = 0;
    protocolVersion = netProtocolVersion;
    serverInfo = [[NSMutableArray alloc] init];
    [serverInfo addObject:[NSString stringWithFormat:@"%@ (Server)", deviceName]];
    [serverInfo addObject:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];

    clients = [[NSMutableArray alloc] init];
    timeOuts = [[NSMutableArray alloc] init];
    externals = [[NSMutableDictionary alloc] init];
    commonScoresUpdated = NO;
    loadInProgress = NO;
    loadConfirmationCount = 0;
    
    isSecondary = NO;
    secondaryConnection = nil;
    secondaryAddress = nil;
    secondaryPort = 0;
    secondaryBlacklist = [[NSMutableArray alloc] init];
    
    listeningSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    listeningSocket.IPv4PreferredOverIPv6 = NO;
    
    udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    
    dictionaryLock = [[NSLock alloc] init];
    ntpReferenceDate = [OSCMessage ntpReferenceDate];
    
    return self;
}

- (void)setLocalScoreList:(NSArray *)scoreList
{
    if ([scoreList count] > 0) {
        localScoreList = scoreList;
    } else {
        localScoreList = nil;
    }
    commonScores = [self getCommonScores];
}

- (NSArray *)localScoreList
{
    return localScoreList;
}

- (NSUInteger)clientsCount
{
    return [clients count];
}

- (BOOL)start
{
    if (![self serverStart]) {
        return NO;
    }
    
    //Publish service using bonjour
    publisherRetries = 0;
    serverName = preferredServerName;
    if (![self startBonjour]) {
        [self stop];
        return NO;
    }
    
    //Make sure we're the primary server.
    isSecondary = NO;
    
    //Set up our client info broadcast timer.
    [self resumeBroadcastingClientInfo];
    return YES;
}

- (OSCMessage *)startSecondary:(NSString *)address ignoreBonjourAddress:(BOOL)ignoreLocal
{
    if (![self serverStart]) {
        return nil;
    }
    
    isSecondary = YES;
    hostAddress = address;
    if (![self isIPv4Address:hostAddress]) {
        ipv4Address = [self getIPv4ForInterfaceWithIPv6Address:hostAddress];
    } else {
        ipv4Address = nil;
    }
    //Return a message with our kernel assigned port number for the player to send to the server.
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Server"];
    [message appendAddressComponent:@"SecondaryPort"];
    [message addIntegerArgument:portNumber];
    //Previously only the port number was sent, and the address was taken from the connection details
    //held on the primary server. We want the option to be able to override it here though, so that we
    //can send through a hostname or IPv4 address rather than any IPv6 address we might be using.
    //Recently MacOS and iOS have been giving route unreachable errors with link local IPv6 addresses if
    //the interface is not explicitly specified, and this prevents connection to our secondary server.
    //Hopefully this can be removed sometime in the future.
    
    //Only override this though if we haven't manually specified our connection address.
    //(We're unlikely to be using a link local IPv6 address in this case.)
    if (!ignoreLocal) {
        if (hostName != nil) {
            [message addStringArgument:hostName];
        } else if (ipv4Address != nil) {
            [message addStringArgument:ipv4Address];
        } else {
            //Use as a last resort
            [message addStringArgument:hostAddress];
        }
    }
    return message;
}

- (void)stop
{
    [timeOuts makeObjectsPerformSelector:@selector(invalidate)];
    [secondaryTimeOut invalidate];
    [self suspendBroadcastingClientInfo];
    
    if (portNumber == 0) {
        //The server is already stopped.
        return;
    }
    
    //Send a goodbye signal to all of our externals if we're the master.
    if (!isSecondary) {
        [self sayGoodbyeAndShutdown:YES];
    }
    
    //Close our listening socket. Closing of the UDP socket is managed by our AppDelegate.
    listeningSocket.delegate = nil;
    [listeningSocket disconnect];
    
    //Set our port to 0 to show that the server isn't running.
    portNumber = 0;
    udpPortNumber = 0;
    
    //Stop bonjour
    if (!isSecondary) {
        [self stopBonjour];
    }
    
    //Close connections to all clients
    [clients makeObjectsPerformSelector:@selector(close)];
    [clients removeAllObjects];
    [dictionaryLock lock];
    [externals removeAllObjects];
    [dictionaryLock unlock];
    commonScores = [self getCommonScores];
    
    //Reset secondary server variables
    isSecondary = NO;
    secondaryConnection = nil;
    secondaryAddress = nil;
    secondaryPort = 0;
    [secondaryBlacklist removeAllObjects];
    
    loadInProgress = NO;
    loadConfirmationCount = 0;
}

- (void)suspendBroadcastingClientInfo
{
    if (infoBroadcast != nil) {
        [infoBroadcast invalidate];
    }
}

- (void)resumeBroadcastingClientInfo
{
    [infoBroadcast invalidate];
    infoBroadcast = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(broadCastInfo) userInfo:nil repeats:YES];
}

- (void)changeName:(NSString *)name
{
    //Called to change the name of our secondary or dormant server if there's a score load event.
    //(The primary server takes care of this without intervention from the player view.)
    if (!isSecondary && portNumber != 0) {
        return;
    }
    
    //Bonjour shouldn't be running, but stop it in case it is. (This should only happen if the
    //primary server goes down during a load event and our secondary takes over.)
    BOOL publishing = NO;
    if (publisher != nil) {
        [self stopBonjour];
        publishing = YES;
    }
    
    preferredServerName = [self serverNameFromScoreName:name deviceName:deviceName];
    serverName = preferredServerName;
    
    if (publishing) {
        [self startBonjour];
    }
}

- (void)makePrimary
{
    isSecondary = NO;
    
    //Publish our server
    publisherRetries = 0;
    serverName = preferredServerName;
    [self startBonjour];
    
    //Establish a new secondary server (if there are any other peers)
    [self promoteNewSecondary:nil];
    [self resumeBroadcastingClientInfo];
    
    //Alert our externals that there's a new server then clear the list.
    //Externals will need to respond to this message by re-registering.
    [dictionaryLock lock];
    NSDictionary *oldExternals = [NSDictionary dictionaryWithDictionary:externals];
    [externals removeAllObjects];
    [dictionaryLock unlock];
    
    if ((hostAddress != nil) && (udpPortNumber != 0)) {
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"External"];
        [message appendAddressComponent:@"NewServer"];
        [message addStringArgument:hostAddress];
        [message addIntegerArgument:udpPortNumber];
        
        OSCMessage *ipv4message;
        if (ipv4Address != nil) {
            ipv4message = [[OSCMessage alloc] init];
            [ipv4message appendAddressComponent:@"External"];
            [ipv4message appendAddressComponent:@"NewServer"];
            [ipv4message addStringArgument:ipv4Address];
            [ipv4message addIntegerArgument:udpPortNumber];
        }
        
        for (NSString *address in oldExternals) {
            for (int i = 0; i < [[oldExternals objectForKey:address] count]; i++) {
                int port = [[[oldExternals objectForKey:address] objectAtIndex:i] intValue];
                if (ipv4Address != nil && [self isIPv4Address:address]) {
                    [self sendExternalMessage:ipv4message toHost:address port:port];
                } else {
                    [self sendExternalMessage:message toHost:address port:port];
                }
            }
        }
    }
}

- (void)disconnectClients
{
    //Used when a server wants to disconnect from the current networked iPads
    if (!isSecondary) {
        [self sayGoodbyeAndShutdown:NO];
    }
    [clients makeObjectsPerformSelector:@selector(close)];
    [clients removeAllObjects];
    [dictionaryLock lock];
    [externals removeAllObjects];
    [dictionaryLock unlock];
    [secondaryBlacklist removeAllObjects];
    commonScores = [self getCommonScores];
    
    if (isSecondary) {
        //We need to republish our server.
        isSecondary = NO;
        publisherRetries = 0;
        serverName = preferredServerName;
        [self startBonjour];
        [self resumeBroadcastingClientInfo];
    }
}

- (void)sendNetworkMessage:(OSCMessage *)message
{
    if ([message.address count] < 1) {
        //No routing information. Discard message.
        return;
    }
    if ([[message.address objectAtIndex:0] isEqualToString:@"Server"] || [[message.address objectAtIndex:0] isEqualToString:@"Pong"]) {
        //Message is from the master to the server. Process here.
        [self processServerMessage:message from:nil isLocal:YES];
    } else if (!isSecondary) {
        //Otherwise, send broadcast message to the clients (currently that's all we're implementing)
        //But only if we're the primary server. Also, don't pass on messages meant only for external devices.
        if (![[message.address objectAtIndex:0] isEqualToString:@"External"]) {
            //If a load is in progress, only pass on specific messages.
            if (!loadInProgress || [[message.address objectAtIndex:0] isEqualToString:@"Score"] || [[message.address objectAtIndex:0] isEqualToString:@"Renderer"]) {
                [clients makeObjectsPerformSelector:@selector(sendNetworkMessage:) withObject:message];
                //And include our delegate, the master player if not a ping
                if (![[message.address objectAtIndex:0] isEqualToString:@"Ping"]) {
                    [delegate receivedNetworkMessage:message];
                }
            }
        }
        
        //Pass selected message types on to external devices.
        if ([[message.address objectAtIndex:0] isEqualToString:@"External"] || [[message.address objectAtIndex:0] isEqualToString:@"Control"] || [[message.address objectAtIndex:0] isEqualToString:@"Status"] || [[message.address objectAtIndex:0] isEqualToString:@"Tick"] || [[message.address objectAtIndex:0] isEqualToString:@"Score"]) {
            [dictionaryLock lock];
            for (NSString* address in externals) {
                for (int i = 0; i < [[externals objectForKey:address] count]; i++) {
                    int port = [[[externals objectForKey:address] objectAtIndex:i] intValue];
                    [self sendExternalMessage:message toHost:address port:port];
                }
            }
            [dictionaryLock unlock];
        }
    }
}

- (void)sendPing
{
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Ping"];
    //Split our 64 bit float into 2 integers.
    double delta = [[NSDate date] timeIntervalSinceDate:ntpReferenceDate];
    UInt32 *ptr = (UInt32 *)&delta;
    [message addIntegerArgument:*ptr];
    [message addIntegerArgument:*(ptr + 1)];
    [self sendNetworkMessage:message];
}

- (BOOL)serverStart
{
    NSError *error;
    
    if (portNumber != 0) {
        //Our server is already running.
        return YES;
    }
    
    listeningSocket.delegate = self;
    if (![listeningSocket acceptOnPort:preferredPortNumber error:&error]) {
        //We weren't able to bind to our preferred port. Have the kernel assign us one.
        [listeningSocket acceptOnPort:0 error:&error];
    }
    
    //If there is an error, return.
    if (error != nil) {
        return NO;
    }
    
    portNumber = listeningSocket.localPort;
    
    //Attempt to create a udp port for externals and start listening on it.
    udpSocket.delegate = self;
    if (![udpSocket bindToPort:portNumber error:&error]) {
        [udpSocket bindToPort:0 error:&error];
    }
    
    error = nil;
    if (![udpSocket beginReceiving:&error]) {
        [udpSocket close];
    }
    
    if (error == nil) {
        udpPortNumber = udpSocket.localPort;
    }
    
    return YES;
}

- (void)processServerMessage:(OSCMessage *)message from:(Connection *)sourceConnection isLocal:(BOOL)local
{
    //Check if we have a ping response first
    if ([message.address count] == 1 && [[message.address objectAtIndex:0] isEqualToString:@"Pong"]) {
        if (![message.typeTag isEqualToString:@",iiii"]) {
            return;
        }
        
        CGFloat now = [[NSDate date] timeIntervalSinceDate:ntpReferenceDate];
        double startTime, returnTime;
        SInt32 *ptr = (SInt32 *)&startTime;
        *ptr = [[message.arguments objectAtIndex:0] intValue];
        *(ptr + 1) = [[message.arguments objectAtIndex:1] intValue];
        ptr = (SInt32 *)&returnTime;
        *ptr = [[message.arguments objectAtIndex:2] intValue];
        *(ptr + 1) = [[message.arguments objectAtIndex:3] intValue];
        //NSLog(@"Ints: %i, %i", *ptr, *(ptr + 1));
        
        CGFloat delta1 = returnTime - startTime;
        CGFloat delta2 = now - returnTime;
        CGFloat offset = (delta1 - delta2) / 2;
        NSLog(@"%f, %f, %f", startTime, returnTime, now);
        NSLog(@"Deltas: %f, %f", delta1, delta2);
        NSLog(@"Total: %f", now - startTime);
        NSLog(@"Offset: %f", offset);
    }
    
    //There should always be a method specified in a server message.
    if ([message.address count] < 2) {
        return;
    }
    
    //Process messages meant for both primary and secondary servers first;
    
    if (sourceConnection == nil) {
        //Messages specifically from the master or externals.
        if ([[message.address objectAtIndex:1] isEqualToString:@"RegisteredExternals"] && isSecondary && local) {
            //We're receiving a list of connected externals from the primary server. Save them for later.
            //(This is local because it comes via our PlayerViewController)
            if (message.typeTag.length % 2 == 0) {
                return;
            }
            
            for (int i = 1; i < [message.typeTag length]; i += 2) {
                if (![[message.typeTag substringWithRange:NSMakeRange(i, 2)] isEqualToString:@"si"]) {
                    return;
                }
            }
            
            for (int i = 0; i < [message.arguments count]; i += 2) {
                //Check that our port number is valid.
                if ([[message.arguments objectAtIndex:(i + 1)] intValue] < 1 || [[message.arguments objectAtIndex:(i + 1)] intValue] > 65535) {
                    continue;
                }
                [dictionaryLock lock];
                if ([externals objectForKey:[message.arguments objectAtIndex:i]] == nil) {
                    [externals setObject:[NSMutableArray arrayWithObject:[message.arguments objectAtIndex:(i + 1)]] forKey:[message.arguments objectAtIndex:i]];
                } else if ([[externals objectForKey:[message.arguments objectAtIndex:i]] indexOfObject:[message.arguments objectAtIndex:(i + 1)]] == NSNotFound){
                    //Safety check to make sure that we don't add duplicate entries.
                    [[externals objectForKey:[message.arguments objectAtIndex:i]] addObject:[message.arguments objectAtIndex:(i + 1)]];
                }
                [dictionaryLock unlock];
            }
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"UnregisteredExternals"] && isSecondary && local) {
            //We're receiving a list of externals to unregister. This will likely only ever be one at a time,
            //but leave the possibility of unregistering multiple externals at once.
            if (message.typeTag.length % 2 == 0) {
                return;
            }
            
            for (int i = 1; i < [message.typeTag length]; i += 2) {
                if (![[message.typeTag substringWithRange:NSMakeRange(i, 2)] isEqualToString:@"si"]) {
                    return;
                }
            }
            
            for (int i = 0; i < [message.arguments count]; i += 2) {
                [dictionaryLock lock];
                if ([externals objectForKey:[message.arguments objectAtIndex:i]] != nil) {
                    [[externals objectForKey:[message.arguments objectAtIndex:i]] removeObject:[message.arguments objectAtIndex:(i + 1)]];
                    if ([[externals objectForKey:[message.arguments objectAtIndex:i]] count] == 0) {
                        [externals removeObjectForKey:[message.arguments objectAtIndex:i]];
                    }
                }
                [dictionaryLock unlock];
            }
        }
    } else {
        //Messages specifically from clients
        if ([[message.address objectAtIndex:1] isEqualToString:@"RegisterDevice"]) {
            BOOL protocolError = NO;
            if (![message.typeTag isEqualToString:@",sss"]) {
                protocolError = YES;
            } else {
                NSInteger protocolVersionNumber = [[[message.arguments objectAtIndex:0] stringByReplacingOccurrencesOfString:@"Decibel Networking Protocol v" withString:@""] integerValue];
                if (protocolVersionNumber != protocolVersion) {
                    protocolError = YES;
                }
            }
            
            //We need to invalidate the handshake timer whether our connection is successful or not.
            //(We will either close or keep the connection as needed in the following block of code.)
            for (int i = 0; i < [timeOuts count]; i++) {
                NSTimer *timeOut = [timeOuts objectAtIndex:i];
                if (timeOut.userInfo == sourceConnection) {
                    [timeOut invalidate];
                    [timeOuts removeObject:timeOut];
                }
            }
            
            if (protocolError) {
                //The client is not using the right version of the network protocol. Disconnect.
                [sourceConnection close];
                [clients removeObject:sourceConnection];
            } else {
                sourceConnection.deviceName = [message.arguments objectAtIndex:1];
                sourceConnection.playerVersion = [message.arguments objectAtIndex:2];
                
                //Send ConnectionOK message to indicate handshake is complete.
                message = [[OSCMessage alloc] init];
                [message appendAddressComponent:@"Server"];
                [message appendAddressComponent:@"ConnectionOK"];
                [sourceConnection sendNetworkMessage:message];
                
                if (!isSecondary) {
                    //If we don't already have a secondary server (ie, this is the first client that is connecting)
                    //then we make them the secondary server.
                    if (secondaryConnection == nil) {
                        [self promoteNewSecondary:sourceConnection];
                    } else if (secondaryPort != 0 && secondaryAddress != nil) {
                        //Otherwise notify them of our secondary server if we have the port available.
                        //(If this hasn't yet arrived we will send the notification through later).
                        message = [[OSCMessage alloc] init];
                        [message appendAddressComponent:@"Server"];
                        [message appendAddressComponent:@"SecondaryServer"];
                        [message addStringArgument:secondaryAddress];
                        [message addIntegerArgument:secondaryPort];
                        [sourceConnection sendNetworkMessage:message];
                    }
                }
            }
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"RegisterScores"] && localScoreList != nil) {
            //Only store the client score list if we have a local list to compare against.
            NSString *typeTag = [message.typeTag substringFromIndex:1];
            NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"s"] invertedSet];
            if (([typeTag rangeOfCharacterFromSet:invalidTags].location != NSNotFound) || ([typeTag length] % 4 != 0)) {
                return;
            }

            NSMutableArray *scoreList = [[NSMutableArray alloc] init];
            for (int i = 0; i < [typeTag length]; i+= 4) {
                //Create an array out of the score info to compare it to the contents of our local score array.
                NSArray *currentScoreInfo = [NSArray arrayWithObjects:[message.arguments objectAtIndex:i], [message.arguments objectAtIndex:i + 1], [message.arguments objectAtIndex:i + 2], [message.arguments objectAtIndex:i + 3], nil];
                NSUInteger index = [localScoreList indexOfObject:currentScoreInfo];
                if (index != NSNotFound) {
                    //Save the object from our local list (and not the newly created one) so that
                    //we can do an address comparisson later.
                    [scoreList addObject:[localScoreList objectAtIndex:index]];
                }
            }
            if ([scoreList count] > 0) {
                sourceConnection.scoreList = [NSArray arrayWithArray:scoreList];
                commonScores = [self getCommonScores];
            }
        }
    }
    
    //Beyond this point there are no further message types that a secondary server should process
    if (isSecondary) {
        return;
    }
    
    if (sourceConnection == nil) {
        //Messages from externals (and potentially our master in the future).
        if ([[message.address objectAtIndex:1] isEqualToString:@"RegisterExternal"] && !local) {
            BOOL protocolError = NO;
            BOOL badProtocolVersion = NO;
            if (![message.typeTag isEqualToString:@",sis"]) {
                protocolError = YES;
            } else {
                NSInteger protocolVersionNumber = [[[message.arguments objectAtIndex:0] stringByReplacingOccurrencesOfString:@"Decibel Networking Protocol v" withString:@""] integerValue];
                if (protocolVersionNumber != protocolVersion) {
                    badProtocolVersion = YES;
                }
                if ([[message.arguments objectAtIndex:1] intValue] < 1 || [[message.arguments objectAtIndex:1] intValue] > 65535) {
                    //Bad return port value.
                    protocolError = YES;
                }
            }
            
            //Add the address of our external to the list, and send notification.
            if (!protocolError && badProtocolVersion) {
                OSCMessage *response = [[OSCMessage alloc] init];
                [response appendAddressComponent:@"Server"];
                [response appendAddressComponent:@"BadProtocolVersion"];
                [response addStringArgument:[NSString stringWithFormat:@"Expected v%lu", (unsigned long)protocolVersion]];
                [self sendExternalMessage:response toHost:[message.arguments objectAtIndex:2] port:[[message.arguments objectAtIndex:1] intValue]];
            } else if (!protocolError) {
                [dictionaryLock lock];
                if ([externals objectForKey:[message.arguments objectAtIndex:2]] == nil) {
                    [externals setObject:[NSMutableArray arrayWithObject:[message.arguments objectAtIndex:1]] forKey:[message.arguments objectAtIndex:2]];
                } else if ([[externals objectForKey:[message.arguments objectAtIndex:2]] indexOfObject:[message.arguments objectAtIndex:1]] == NSNotFound) {
                    [[externals objectForKey:[message.arguments objectAtIndex:2]] addObject:[message.arguments objectAtIndex:1]];
                }
                [dictionaryLock unlock];
                OSCMessage *response = [[OSCMessage alloc] init];
                [response appendAddressComponent:@"Server"];
                [response appendAddressComponent:@"RegistrationOK"];
                [self sendExternalMessage:response toHost:[message.arguments objectAtIndex:2] port:[[message.arguments objectAtIndex:1] intValue]];
                
                //Also notify our secondary that there is an external.
                if (secondaryConnection != nil) {
                    response = [[OSCMessage alloc] init];
                    [response appendAddressComponent:@"Server"];
                    [response appendAddressComponent:@"RegisteredExternals"];
                    [response addStringArgument:[message.arguments objectAtIndex:2]];
                    [response addIntegerArgument:[[message.arguments objectAtIndex:1] intValue]];
                    [secondaryConnection sendNetworkMessage:response];
                }
            }
        } else if ([[message.address objectAtIndex:1] isEqualToString:@"UnregisterExternal"] && !local) {
            if (![message.typeTag isEqualToString:@",is"]) {
                return;
            } else {
                //Remove our external
                [dictionaryLock lock];
                if ([externals objectForKey:[message.arguments objectAtIndex:1]] != nil) {
                    [[externals objectForKey:[message.arguments objectAtIndex:1]] removeObject:[message.arguments objectAtIndex:0]];
                    if ([[externals objectForKey:[message.arguments objectAtIndex:1]] count] == 0) {
                        [externals removeObjectForKey:[message.arguments objectAtIndex:1]];
                    }
                }
                [dictionaryLock unlock];
                
                //Also notify our secondary that we lost an external.
                if (secondaryConnection != nil) {
                    OSCMessage *alertSecondary = [[OSCMessage alloc] init];
                    [alertSecondary appendAddressComponent:@"Server"];
                    [alertSecondary appendAddressComponent:@"UnregisteredExternals"];
                    [alertSecondary addStringArgument:[message.arguments objectAtIndex:1]];
                    [alertSecondary addIntegerArgument:[[message.arguments objectAtIndex:0] intValue]];
                    [secondaryConnection sendNetworkMessage:alertSecondary];
                }
            }
        }
    } else {
        if ([[message.address objectAtIndex:1] isEqualToString:@"SecondaryPort"]) {
            if (!([message.typeTag isEqualToString:@",i"] || [message.typeTag isEqualToString:@",is"])) {
                return;
            }
            //Check that this is actually coming from our assigned secondary
            if (sourceConnection == secondaryConnection) {
                [secondaryTimeOut invalidate];
                
                //Find the address of the secondary server. Then set the port and notify the clients.
                if ([message.typeTag isEqualToString:@",is"]) {
                    secondaryAddress = [message.arguments objectAtIndex:1];
                } else {
                    secondaryAddress = secondaryConnection.peerAddress;
                }
                assert(secondaryAddress != nil);
                secondaryPort = [[message.arguments objectAtIndex:0] unsignedIntegerValue];
                secondaryConnection.deviceName = [NSString stringWithFormat:@"%@ (Secondary)", secondaryConnection.deviceName];
                
                OSCMessage *message = [[OSCMessage alloc] init];
                [message appendAddressComponent:@"Server"];
                [message appendAddressComponent:@"SecondaryServer"];
                [message addStringArgument:secondaryAddress];
                [message addIntegerArgument:secondaryPort];
                //Broadcast to all clients. The seconary server will ignore the message
                //at the processing stage.
                [clients makeObjectsPerformSelector:@selector(sendNetworkMessage:) withObject:message];
                
                //Notify our secondary of any external devices that are connected.
                if ([externals count] > 0) {
                    message = [[OSCMessage alloc] init];
                    [message appendAddressComponent:@"Server"];
                    [message appendAddressComponent:@"RegisteredExternals"];
                    [dictionaryLock lock];
                    for (NSString* address in externals) {
                        for (int i = 0; i < [[externals objectForKey:address] count]; i++) {
                            int port = [[[externals objectForKey:address] objectAtIndex:i] intValue];
                            [message addStringArgument:address];
                            [message addIntegerArgument:port];
                        }
                    }
                    [dictionaryLock unlock];
                    [secondaryConnection sendNetworkMessage:message];
                }
                commonScores = [self getCommonScores];
            }
        }
    }
    
    //Process common messages here
    if ([[message.address objectAtIndex:1] isEqualToString:@"GetClientList"]) {
        //WARNING: Deprecated for client connections. This may be removed at some stage in the future.
        OSCMessage *response = [self getClientListMessage];
        //We only want the response going to the machine that requested it
        if (sourceConnection == nil) {
            if (local) {
                [delegate receivedNetworkMessage:response];
            } else if ([message.typeTag isEqualToString:@",s"]) {
                //From one of our externals.
                NSArray *portList = [externals objectForKey:[message.arguments objectAtIndex:0]];
                for (int i = 0; i < [portList count]; i++) {
                    int port = [[portList objectAtIndex:i] intValue];
                    [self sendExternalMessage:response toHost:[message.arguments objectAtIndex:0] port:port];
                }
            }
        } else {
            [sourceConnection sendNetworkMessage:response];
        }
    } else if ([[message.address objectAtIndex:1] isEqualToString:@"GetScoreList"]) {
        OSCMessage *response = [self getScoreListMessage];
        //Use the same code as above for routing
        if (sourceConnection == nil) {
            if (local) {
                [delegate receivedNetworkMessage:response];
            } else if ([message.typeTag isEqualToString:@",s"]) {
                //From one of our externals.
                NSArray *portList = [externals objectForKey:[message.arguments objectAtIndex:0]];
                for (int i = 0; i < [portList count]; i++) {
                    int port = [[portList objectAtIndex:i] intValue];
                    [self sendExternalMessage:response toHost:[message.arguments objectAtIndex:0] port:port];
                }
            }
        } else {
            [sourceConnection sendNetworkMessage:response];
        }
    } else if ([[message.address objectAtIndex:1] isEqualToString:@"LoadRequest"]) {
        //First check that we have a score matching the request.
        BOOL badRequest = NO;
        NSUInteger index;
        if (![message.typeTag hasPrefix:@",ssss"] || commonScores == nil) {
            badRequest = YES;
        } else {
            NSArray *scoreInfo = [NSArray arrayWithObjects:[message.arguments objectAtIndex:0], [message.arguments objectAtIndex:1], [message.arguments objectAtIndex:2], [message.arguments objectAtIndex:3], nil];
            index = [commonScores indexOfObject:scoreInfo];
            if (index == NSNotFound) {
                badRequest = YES;
            }
        }
        
        OSCMessage *response = [[OSCMessage alloc] init];
        [response appendAddressComponent:@"Server"];
        if (sourceConnection == nil && !local) {
            if (badRequest) {
                [response appendAddressComponent:@"RequestRejected"];
                if ([message.typeTag isEqualToString:@",sssss"]) {
                    [response addStringArgument:@"Score not available"];
                } else {
                    [response addStringArgument:@"Incorrectly formatted request"];
                }
            } else {
                [response appendAddressComponent:@"RequestOK"];
            }
            NSArray *portList = [externals objectForKey:[message.arguments lastObject]];
            for (int i = 0; i < [portList count]; i++) {
                int port = [[portList objectAtIndex:i] intValue];
                [self sendExternalMessage:response toHost:[message.arguments objectAtIndex:4] port:port];
            }
        } else if (badRequest) {
            [response appendAddressComponent:@"RequestRejected"];
            [response addStringArgument:@"Score not available"];
            [sourceConnection sendNetworkMessage:response];
        }
        
        if (badRequest) {
            return;
        }
        
        //Initial checks passed. It is on (like Donkey Kong)!
        [self loadScore:[commonScores objectAtIndex:index]];
    } else if ([[message.address objectAtIndex:1] isEqualToString:@"LoadOK"]) {
        //Check that this hasn't come from an external.
        if (sourceConnection == nil && !local) {
            return;
        }
        loadConfirmationCount++;
        [self checkIfLoadComplete];
    }
}

- (void)promoteNewSecondary:(Connection *)connection
{
    //Reset secondary port and address
    secondaryPort = 0;
    secondaryAddress = nil;
    secondaryConnection = connection;
    [secondaryTimeOut invalidate];
    
    //If the caller hasn't explicitly specified a connection for our secondary,
    //send a message to the next in line (if there is anyone else in line).
    if (secondaryConnection == nil) {
        for (int i = 0; i < [clients count]; i++) {
            if ((((Connection *)[clients objectAtIndex:i]).deviceName != nil) && ![secondaryBlacklist containsObject:[clients objectAtIndex:i]]) {
                secondaryConnection = [clients objectAtIndex:i];
                i = (int)[clients count];
            }
        }
    }
    
    if (secondaryConnection != nil) {
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"Server"];
        [message appendAddressComponent:@"MakeSecondary"];
        [secondaryConnection sendNetworkMessage:message];
        secondaryTimeOut = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(secondaryTimeOut:) userInfo:connection repeats:NO];
    }
}

- (void)handshakeTimeOut:(NSTimer *)timeOut
{
    //Our client didn't complete the handshake in a reasonable time. Disconnect.
    Connection *connection = timeOut.userInfo;
    [connection close];
    [clients removeObject:connection];
    [timeOuts removeObject:timeOut];
}

- (void)secondaryTimeOut:(NSTimer *)timeOut
{
    //Cancel our timed out secondary, and blacklist it if the connection is still active.
    Connection *connection = timeOut.userInfo;
    if (connection != nil) {
        [secondaryBlacklist addObject:connection];
    }
    
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Server"];
    [message appendAddressComponent:@"CancelSecondary"];
    [connection sendNetworkMessage:message];
    
    //Then promote the next in line.
    [self promoteNewSecondary:nil];
}

- (void)loadResponseTimeOut
{
    //We shouldn't be here. Either we should have received enough load confirmations from our clients,
    //or we should have been notified that they disconnected and adjusted our target. But we don't live
    //in a perfect world, so once a certain time has elapsed, assume all clients have either loaded the
    //new score or died a mysterious and horrible death.
    if (!loadInProgress) {
        return;
    }
    
    [self loadComplete];
}

- (BOOL)startBonjour
{
    if (portNumber == 0) {
        //If our socket hasn't been set up this shouldn't have been called yet
        return NO;
    }
    
    if (publisherRetries == 0) {
        publisher = [[NSNetService alloc] initWithDomain:@"" type:service name:serverName port:(int)portNumber];
    } else {
        publisher = [[NSNetService alloc] initWithDomain:@"" type:service name:[NSString stringWithFormat:@"%@(%lu)", serverName, (unsigned long)publisherRetries] port:(int)portNumber];
    }
    if (publisher == nil) {
        return NO;
    }
    
    //Publish our service via bonjour
    publisher.delegate = self;
    [publisher scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [publisher publishWithOptions:NSNetServiceNoAutoRename];
    
    return YES;
}

- (void)stopBonjour
{
    if (publisher != nil) {
        //Stop bonjour and remove the netService object from the run loop
        [publisher stop];
        [publisher removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
    
    if (udpPublisher != nil) {
        [udpPublisher stop];
        [udpPublisher removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (NSString *)serverNameFromScoreName:(NSString *)scoreName deviceName:(NSString *)deviceName
{
    //Limit the size of the server name to less than 63 characters. (As required by bonjour.)
    if (scoreName.length > 29) {
        scoreName = [scoreName substringToIndex:29];
    }
    if (deviceName.length > 29) {
        deviceName = [deviceName substringToIndex:29];
    }
    return [NSString stringWithFormat:@"%@.%@", scoreName, deviceName];
}

- (void)sayGoodbyeAndShutdown:(BOOL)shutdown
{
    //Send a goodbye message to our externals
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Server"];
    [message appendAddressComponent:@"Bye!"];
    
    //If we're shutting down, offload this task to our AppDelegate so that it can finish
    //independant of the server object (which is about to implode).
    [dictionaryLock lock];
    if (shutdown) {
        AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
        [appDelegate manageUdpShutdown:udpSocket goodbyeMessage:message destinations:externals];
    } else {
        //Handle it ourselves
        for (NSString* address in externals) {
            for (int i = 0; i < [[externals objectForKey:address] count]; i++) {
                int port = [[[externals objectForKey:address] objectAtIndex:i] intValue];
                [self sendExternalMessage:message toHost:address port:port];
            }
        }
    }
    [dictionaryLock unlock];
}

- (NSArray *)getCommonScores
{
    commonScoresUpdated = YES;
    
    //Firstly, if we have no local score list then the result is always nil here.
    if (localScoreList == nil) {
        return nil;
    }
    
    //Usually if a client hasn't registered a list of scores, we ignore them, and don't let their lack of registration
    //affect the available list. We make a special case for the secondary, however. If we don't have a list from them
    //then we don't allow score changes.
    if (secondaryConnection != nil && secondaryConnection.scoreList == nil) {
        return nil;
    }
    
    NSArray *smallestList = localScoreList;
    NSMutableArray *registeredLists = [[NSMutableArray alloc] initWithObjects:localScoreList, nil];
    NSMutableArray *commonScoreList = [[NSMutableArray alloc] init];
    for (int i = 0; i < [clients count]; i++) {
        if (((Connection *)[clients objectAtIndex:i]).scoreList != nil) {
            if ([((Connection *)[clients objectAtIndex:i]).scoreList count] < [smallestList count]) {
                smallestList = ((Connection *)[clients objectAtIndex:i]).scoreList;
            }
            [registeredLists addObject:((Connection *)[clients objectAtIndex:i]).scoreList];
        }
    }
    
    if ([registeredLists count] == 1) {
        return localScoreList;
    }
    
    //Use our smallest list to find all common scores.
    [registeredLists removeObjectIdenticalTo:smallestList];
    for (int i = 0; i < [smallestList count]; i++) {
        BOOL include = YES;
        for (int j = 0; j < [registeredLists count]; j++) {
            if ([[registeredLists objectAtIndex:j] indexOfObjectIdenticalTo:[smallestList objectAtIndex:i]] == NSNotFound) {
                include = NO;
                j = (int)[registeredLists count];
            }
        }
        if (include) {
            [commonScoreList addObject:[smallestList objectAtIndex:i]];
        }
    }
    
    if ([commonScoreList count] == 0) {
        return nil;
    } else {
        return [NSArray arrayWithArray:commonScoreList];
    }
}

- (void)loadScore:(NSArray *)scoreInfo
{
    //First suspend publishing and set the load in progress flag.
    loadInProgress = YES;
    loadConfirmationCount = 0;
    [self stopBonjour];
    [self suspendBroadcastingClientInfo];
    
    //Cancel any pending connections.
    for (int i = 0; i < [timeOuts count]; i++) {
        NSTimer *timeout = (NSTimer *)[timeOuts objectAtIndex:i];
        [timeout.userInfo close];
        [timeout invalidate];
    }
    [timeOuts removeAllObjects];
    
    //Update our server name.
    preferredServerName = [self serverNameFromScoreName:[scoreInfo objectAtIndex:0] deviceName:deviceName];
    serverName = preferredServerName;
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Score"];
    [message appendAddressComponent:@"Load"];
    for (int i = 0; i < [scoreInfo count]; i++) {
        [message addStringArgument:[scoreInfo objectAtIndex:i]];
    }
    [self sendNetworkMessage:message];
    [loadResponseTimeOut invalidate];
    loadResponseTimeOut = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(loadResponseTimeOut) userInfo:nil repeats:NO];
    
    //The rest of the loading code is handled when the clients respond.
}

- (void)checkIfLoadComplete
{
    if (!loadInProgress) {
        return;
    }
    
    if (loadConfirmationCount == [clients count] + 1) {
        [loadResponseTimeOut invalidate];
        [self loadComplete];
    }
}

- (void)broadCastInfo
{
    //We shouldn't be broadcasting client info if we're the secondary.
    if (isSecondary) {
        [infoBroadcast invalidate];
        return;
    }
    OSCMessage *message = [self getClientListMessage];
    [clients makeObjectsPerformSelector:@selector(sendNetworkMessage:) withObject:message];
    [delegate receivedNetworkMessage:message];
    if (commonScoresUpdated) {
        message = [self getScoreListMessage];
        [clients makeObjectsPerformSelector:@selector(sendNetworkMessage:) withObject:message];
        [delegate receivedNetworkMessage:message];
        commonScoresUpdated = NO;
    }
}

- (void)loadComplete
{
    loadInProgress = NO;
    [self startBonjour];
    [self resumeBroadcastingClientInfo];
    
    //Notify our externals that the score loading process has finished.
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Server"];
    [message appendAddressComponent:@"LoadComplete"];

    [dictionaryLock lock];
    for (NSString *address in externals) {
        for (int i = 0; i < [[externals objectForKey:address] count]; i++) {
            int port = [[[externals objectForKey:address] objectAtIndex:i] intValue];
            [self sendExternalMessage:message toHost:address port:port];
        }
    }
    [dictionaryLock unlock];
}

- (OSCMessage *)getClientListMessage
{
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Server"];
    [message appendAddressComponent:@"ClientList"];
    for (int i = 0; i < [serverInfo count]; i++) {
        [message addStringArgument:[serverInfo objectAtIndex:i]];
    }
    for (int i = 0; i < [clients count]; i++) {
        if ((((Connection *)[clients objectAtIndex:i]).deviceName != nil) && (((Connection *)[clients objectAtIndex:i]).deviceName != nil)) {
            [message addStringArgument:((Connection *)[clients objectAtIndex:i]).deviceName];
            [message addStringArgument:((Connection *)[clients objectAtIndex:i]).playerVersion];
        }
    }
    return message;
}

- (OSCMessage *)getScoreListMessage
{
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Server"];
    [message appendAddressComponent:@"ScoreList"];
    for (int i = 0; i < [commonScores count]; i++) {
        for (int j = 0; j < 4; j++) {
            [message addStringArgument:[[commonScores objectAtIndex:i] objectAtIndex:j]];
        }
    }
    return message;
}

- (BOOL)isIPv4Address:(NSString *)address
{
    //Check if we have an IPv4 address here.
    struct in_addr addr;
    return inet_pton(AF_INET, [address UTF8String], &addr) == 1;
}

- (NSString *)getIPv4ForInterfaceWithIPv6Address:(NSString *)address
{
    NSMutableDictionary *interfaces = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *addresses = [[NSMutableDictionary alloc] init];
    
    struct ifaddrs *ifaces = NULL;
    struct ifaddrs *current_addr = NULL;
    //Retrieve the current interfaces and loop through them if succesful.
    if (getifaddrs(&ifaces) == 0) {
        current_addr = ifaces;
        while(current_addr != NULL) {
            if(current_addr->ifa_addr->sa_family == AF_INET || current_addr->ifa_addr->sa_family == AF_INET6) {
                NSString *interface = [NSString stringWithUTF8String:current_addr->ifa_name];
                NSString *addrString = nil;
                
                //Create dictionaries to map IPv4 addresses to interface names
                //and interface names to IPv6 addresses.
                if(current_addr->ifa_addr->sa_family == AF_INET) {
                    char addr[INET_ADDRSTRLEN];
                    addrString = [NSString stringWithUTF8String:inet_ntop(AF_INET, &((struct sockaddr_in *)current_addr->ifa_addr)->sin_addr, addr, INET_ADDRSTRLEN)];
                    [addresses setObject:addrString forKey:interface];
                } else {
                    char addr[INET6_ADDRSTRLEN];
                    addrString = [NSString stringWithUTF8String:inet_ntop(AF_INET6, &((struct sockaddr_in6 *)current_addr->ifa_addr)->sin6_addr, addr, INET6_ADDRSTRLEN)];
                    [interfaces setObject:interface forKey:addrString];
                }
            }
            //Move our pointer to the next address.
            current_addr = current_addr->ifa_next;
        }
    }
    freeifaddrs(ifaces);
    
    //Return the IPv4 address that corresponds to our IPv6 interface.
    return [addresses objectForKey:[interfaces objectForKey:address]];
}

- (void)sendExternalMessage:(OSCMessage *)message toHost:(NSString *)address port:(int)port
{
    if ([address hasPrefix:@"fe80::"]) {
        //If we have a link local address, send via our wifi interface.
        //(We should have a better way of finding this rather than assuming it will be en0.)
        address = [address stringByAppendingString:@"%en0"];
    }
    [udpSocket sendData:[message messageAsDataWithHeader:NO] toHost:address port:port withTimeout:-1 tag:0];
}

#pragma mark - GCDAsyncSocket delegate

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    if (sock != listeningSocket) {
        //Make sure this is coming from our listening socket.
        return;
    }
    
    Connection *connection = [[Connection alloc] initWithSocket:newSocket];
    
    //Close the socket if the conneciton fails to initialize.
    //Otherwise open the connection and register the new client in our array.
    if (connection == nil) {
        newSocket.delegate = nil;
        [newSocket disconnect];
    } else {
        assert([connection connectWithDelegate:self withTimeout:-1]);
        assert(connection != nil);
        
        //If we're loading the client shouldn't have been able to connect.
        if (loadInProgress) {
            [connection close];
            return;
        } else {
            [clients addObject:connection];
        }
        
        if (!isSecondary) {
            //Let the client know what protocol version we're running. This initiates the initial handshake.
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"Server"];
            [message appendAddressComponent:@"ProtocolVersion"];
            [message addStringArgument:[NSString stringWithFormat:@"Decibel Networking Protocol v%lu", (unsigned long)protocolVersion]];
            [connection sendNetworkMessage:message];
        }
        
        //Start a timer to make sure that the handshake is completed within a reasonable time.
        //Otherwise the connection is dropped.
        
        NSTimer *timeOut = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(handshakeTimeOut:) userInfo:connection repeats:NO];
        [timeOuts addObject:timeOut];
    }
}

#pragma mark - GCDAsyncUdpSocket delegate
- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data fromAddress:(NSData *)address withFilterContext:(id)filterContext
{
    if (sock != udpSocket) {
        //We shouldn't be here
        return;
    }
    
    if ([[NSString stringWithUTF8String:[data bytes]] isEqualToString:@"#bundle"]) {
        //We have a bundle and need to process it.
        NSArray *messages = [OSCMessage processBundle:data];
        if (messages == nil) {
            //If we get a malformed message then alert the receiver.
            //Currenly these are silently ignored.
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"Malformed"];
            [self receivedNetworkMessage:message overConnection:nil];
        } else {
            for (int i = 0; i < [messages count]; i++) {
                //If this is a message for the server to respond to, add our address data.
                if ([((OSCMessage *)[messages objectAtIndex:i]).address count] >= 1 && [[((OSCMessage *)[messages objectAtIndex:i]).address objectAtIndex:0] isEqualToString:@"Server"]) {
                    [[messages objectAtIndex:i] addStringArgument:[GCDAsyncUdpSocket hostFromAddress:address]];
                }
                
                //Unless this is a registration message, check that our message is coming from one of our registered externals.
                if (([((OSCMessage *)[messages objectAtIndex:i]).address count] >= 2 && [[((OSCMessage *)[messages objectAtIndex:i]).address objectAtIndex:0] isEqualToString:@"Server"] && [[((OSCMessage *)[messages objectAtIndex:i]).address objectAtIndex:1] isEqualToString:@"RegisterExternal"]) || ([externals objectForKey:[GCDAsyncUdpSocket hostFromAddress:address]] != nil)) {
                    [self receivedNetworkMessage:[messages objectAtIndex:i] overConnection:nil];
                }
            }
        }
    } else {
        //We have an individual message. Process as above.
        OSCMessage *message = [[OSCMessage alloc] initWithData:data];
        if (message == nil) {
            message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"Malformed"];
        } else {
            if ([message.address count] >= 1 && [[message.address objectAtIndex:0] isEqualToString:@"Server"]) {
                [message addStringArgument:[GCDAsyncUdpSocket hostFromAddress:address]];
            }
            if (([message.address count] >= 2 && [[message.address objectAtIndex:0] isEqualToString:@"Server"] && [[message.address objectAtIndex:1] isEqualToString:@"RegisterExternal"]) || ([externals objectForKey:[GCDAsyncUdpSocket hostFromAddress:address]] != nil)) {
                [self receivedNetworkMessage:message overConnection:nil];
            }
        }
    }
}

#pragma mark - Connection delegate

- (void)receivedNetworkMessage:(OSCMessage *)message overConnection:(Connection *)sourceConnection
{
    //Perform checks to see if the message conforms to the most basic standards
    //(At least one address component.)
    if ([message.address count] < 1) {
        return;
    }
    
    //Check to see if the message is intended for the server object to process
    //If not, broadcast to all clients
    if ([[message.address objectAtIndex:0] isEqualToString:@"Server"] || [[message.address objectAtIndex:0] isEqualToString:@"Pong"]) {
        [self processServerMessage:message from:sourceConnection isLocal:NO];
    } else {
        if ((sourceConnection != nil && sourceConnection.deviceName == nil)) {
            //Client has not completed handshake. Don't pass on any other messages.
            return;
        }
        if (sourceConnection == nil) {
            //Also limit the sort of messages that external devices can send.
            if (!([[message.address objectAtIndex:0] isEqualToString:@"Control"] || [[message.address objectAtIndex:0] isEqualToString:@"Renderer"] || [[message.address objectAtIndex:0] isEqualToString:@"Master"])) {
                return;
            }
        }
        [self sendNetworkMessage:message];
    }
}

- (void)connectionTerminated:(Connection *)sourceConnection withError:(NSError *)error
{
    //Client disconnected. Remove from the client list and close the connection.
    [sourceConnection close];
    BOOL secondaryLost = (sourceConnection == secondaryConnection);
    
    [clients removeObject:sourceConnection];
    [secondaryBlacklist removeObject:sourceConnection];
    commonScores = [self getCommonScores];
    
    if (loadInProgress) {
        [self checkIfLoadComplete];
    }
    
    if (secondaryLost) {
        //If we've lost the current secondary server then deal with it here
        [self promoteNewSecondary:nil];
    }
}

#pragma mark - NSNetService delegate

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
    //Something went wrong while publishing the server. If there's a collision then we should try republishing
    //with a diffenernt server name.
    
    if (sender == publisher) {
        int errorCode = [[errorDict valueForKey:NSNetServicesErrorCode] intValue];
        if (errorCode == NSNetServicesCollisionError) {
            [self stopBonjour];
            publisherRetries++;
            publisher = [[NSNetService alloc] initWithDomain:@"" type:service name:[NSString stringWithFormat:@"%@(%lu)", serverName, (unsigned long)publisherRetries] port:(int)portNumber];
            publisher.delegate = self;
            [publisher publishWithOptions:NSNetServiceNoAutoRename];
        } else {
            [self stopBonjour];
            [self stop];
            [delegate publishingFailed];
        }
    } else if (sender == udpPublisher) {
        [udpPublisher stop];
        [udpPublisher removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)netServiceDidPublish:(NSNetService *)sender
{
    if (sender == publisher) {
        //In case we had to change name because of a collision update the server name.
        serverName = sender.name;
        //Get our local host name using our service details.
        resolver = [[NSNetService alloc] initWithDomain:@"local." type:service name:serverName port:(int)portNumber];
        resolver.delegate = self;
        [resolver resolveWithTimeout:5];
        
        //Since we succesfully published our tcp port, publish the udp port for any externals using the same server name.
        if (udpPortNumber != 0) {
            udpPublisher = [[NSNetService alloc] initWithDomain:@"" type:udpService name:serverName port:(int)udpPortNumber];
            if (udpPublisher != nil) {
                udpPublisher.delegate = self;
                [udpPublisher scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
                [udpPublisher publishWithOptions:NSNetServiceNoAutoRename];
            }
        }
    }
}

- (void)netServiceDidStop:(NSNetService *)sender
{
    if (sender == publisher) {
        publisher.delegate = nil;
        publisher = nil;
    } else if (sender == udpPublisher) {
        udpPublisher.delegate = nil;
        udpPublisher = nil;
    }
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    if (sender == resolver) {
        hostName = resolver.hostName;
        resolver.delegate = nil;
        resolver = nil;
    }
    
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary<NSString *,NSNumber *> *)errorDict
{
    if (sender == resolver) {
        hostName = nil;
        resolver.delegate = nil;
        resolver = nil;
    }
}

@end

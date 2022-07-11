//
//  PlayerServer2.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 8/11/2014.
//  Copyright (c) 2014 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GCDAsyncSocket.h"
#import "GCDAsyncUdpSocket.h"
#import "Connection.h"

@class OSCMessage;

@protocol PlayerServer2Delegate <NSObject>

@required
- (void)receivedNetworkMessage:(OSCMessage *)message;
- (void)publishingFailed;

@end

@interface PlayerServer2 : NSObject <NSNetServiceDelegate, GCDAsyncSocketDelegate, GCDAsyncUdpSocketDelegate, ConnectionDelegate> {
    NSString *serverName;
    NSUInteger portNumber;
    BOOL isSecondary;
    NSArray *localScoreList;
    id<PlayerServer2Delegate> delegate;
}

@property (nonatomic, readonly) NSString *serverName;
@property (nonatomic, readonly) NSUInteger portNumber;
@property (nonatomic, readonly) NSUInteger clientsCount;
@property (nonatomic, readonly) BOOL isSecondary;
@property (nonatomic, strong) NSArray *localScoreList;
@property (nonatomic, strong) id<PlayerServer2Delegate> delegate;

- (id)initWithName:(NSString *)name deviceName:(NSString *)devName serviceName:(NSString *)serviceName preferredPort:(NSUInteger)preferredPort protocolVersion:(NSInteger)netProtocolVersion;

- (BOOL)start;
- (OSCMessage *)startSecondary:(NSString *)host ignoreBonjourAddress:(BOOL)ignoreLocal;
- (void)makePrimary;
- (void)disconnectClients;
- (void)stop;

- (void)suspendBroadcastingClientInfo;
- (void)resumeBroadcastingClientInfo;

- (void)changeName:(NSString *)name;

- (void)sendNetworkMessage:(OSCMessage *)message;

//Testing only
- (void)sendPing;

@end

//
//  Connection.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 20/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GCDAsyncSocket.h"

@class Connection;
@class OSCMessage;

@protocol ConnectionDelegate <NSObject>

@required
- (void)receivedNetworkMessage:(OSCMessage *)message overConnection:(Connection *)sourceConnection;
- (void)connectionTerminated:(Connection *)sourceConnection withError:(NSError *)error;

@end

@interface Connection : NSObject <GCDAsyncSocketDelegate> {
    NSString *peerAddress;
    NSString *localAddress;
    id<ConnectionDelegate> delegate;
    
    NSString *deviceName;
    NSString *playerVersion;
    NSArray *scoreList;
}

@property (nonatomic, strong) id<ConnectionDelegate> delegate;
@property (nonatomic, readonly) NSString *peerAddress;
@property (nonatomic, readonly) NSString *localAddress;
@property (nonatomic, strong) NSString *deviceName;
@property (nonatomic, strong) NSString *playerVersion;
@property (nonatomic, strong) NSArray *scoreList;

//The server initialises with a socket, and the client with an address and port
- (id)initWithSocket:(GCDAsyncSocket *)connectionSocket;
- (id)initWithHostAddress:(NSString *)hostAddress port:(NSUInteger)hostPort;

- (BOOL)connectWithDelegate:(id)connectionDelegate withTimeout:(NSInteger)timeout;
- (BOOL)reconnectWithDelegate:(id)connectionDelegate;
- (void)close;

- (void)sendNetworkMessage:(OSCMessage *)message;

@end

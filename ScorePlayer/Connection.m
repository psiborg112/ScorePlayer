//
//  Connection.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 20/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "Connection.h"
#import "OSCMessage.h"

@interface Connection ()

- (void)reset;

@end

@implementation Connection {
    GCDAsyncSocket *socket;
    NSString *host;
    NSUInteger port;
    
    SInt32 messageLength;
}

@synthesize peerAddress, localAddress, delegate, deviceName, playerVersion, scoreList;

- (id)initWithSocket:(GCDAsyncSocket *)connectionSocket
{
    self = [super init];
    socket = connectionSocket;
    host = nil;
    [self reset];
    if (socket == nil) {
        return nil;
    }
    peerAddress = socket.connectedHost;
    localAddress = socket.localHost;
    
    return self;
}

- (id)initWithHostAddress:(NSString *)hostAddress port:(NSUInteger)hostPort
{
    self = [super init];
    host = hostAddress;
    port = hostPort;
    socket = nil;
    [self reset];
    return self;
}

- (void)reset
{
    //Reset variables to initial values
    delegate = nil;
    peerAddress = nil;
    localAddress = nil;
    deviceName = nil;
    playerVersion = nil;
    scoreList = nil;
    messageLength = -1;
}

- (BOOL)connectWithDelegate:(id)connectionDelegate withTimeout:(NSInteger)timeout
{
    delegate = connectionDelegate;
    
    if (socket != nil) {
        socket.delegate = self;
        socket.delegateQueue = dispatch_get_main_queue();
        socket.IPv4PreferredOverIPv6 = NO;
        [socket readDataToLength:sizeof(SInt32) withTimeout:-1 tag:0];
    } else if (host != nil) {
        NSError *error;
        socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
        socket.IPv4PreferredOverIPv6 = NO;
        if (timeout > 0) {
            [socket connectToHost:host onPort:port withTimeout:timeout error:&error];
        } else {
            [socket connectToHost:host onPort:port error:&error];
        }
        if (error != nil) {
            return NO;
        }
    } else {
        //No connection information passed.
        return NO;
    }

    return YES;
}

- (BOOL)reconnectWithDelegate:(id)connectionDelegate
{
    //This should only be called by client devices that have already attempted a connection.
    if (host == nil || socket == nil) {
        return NO;
    }
    
    delegate = connectionDelegate;
    
    NSError *error;
    socket.delegate = self;
    [socket connectToHost:host onPort:port error:&error];
    if (error != nil) {
        return NO;
    }
    
    return YES;
}

- (void)close;
{
    //Close our socket and clean up
    [socket disconnect];
}

- (void)sendNetworkMessage:(OSCMessage *)message
{
    //The returned data already includes the length of the message content as a header
    NSData *data = [message messageAsDataWithHeader:YES];
    
    [socket writeData:data withTimeout:-1 tag:0];
}

#pragma mark - GCDAsyncSocket delegate

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    //Get our first message header.
    [socket readDataToLength:sizeof(SInt32) withTimeout:-1 tag:0];
    peerAddress = sock.connectedHost;
    localAddress = sock.localHost;
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    [delegate connectionTerminated:self withError:err];
    socket.delegate = nil;
    
    //Reset other variables
    [self reset];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    if (messageLength == -1) {
        //We're processing a header.
        [data getBytes:&messageLength length:sizeof(SInt32)];
        messageLength = OSSwapBigToHostInt32(messageLength);
        [socket readDataToLength:messageLength withTimeout:-1 tag:0];
    } else {
        //Message content.
        if ([data length] < messageLength) {
            //Something has gone horribly wrong here. Close the connection and alert the delegate.
            [self close];
            return;
        }
        NSData *rawData = [NSData dataWithBytes:[data bytes] length:messageLength];
        OSCMessage *message = [[OSCMessage alloc] initWithData:rawData];
        if (message == nil) {
            //If we get a malformed message then alert the receiver.
            //Currenly these are silently ignored.
            message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"Malformed"];
        }
        [delegate receivedNetworkMessage:message overConnection:self];
        
        //Get our next header.
        messageLength = -1;
        [socket readDataToLength:sizeof(SInt32) withTimeout:-1 tag:0];
    }
}

@end

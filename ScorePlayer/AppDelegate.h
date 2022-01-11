//
//  AppDelegate.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "GCDAsyncUdpSocket.h"

@class OSCMessage;

@interface AppDelegate : UIResponder <UIApplicationDelegate, GCDAsyncUdpSocketDelegate>

@property (strong, nonatomic) UIWindow *window;

- (void)manageUdpShutdown:(GCDAsyncUdpSocket *)socket goodbyeMessage:(OSCMessage *)message destinations:(NSMutableDictionary *)destinations;

@end

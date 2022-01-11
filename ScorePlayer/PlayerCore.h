//
//  PlayerCore.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 20/2/20.
//  Copyright (c) 2020 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Renderer.h"
#import "PlayerServer2.h"
#import "Network.h"

@class score;

@interface PlayerCore : NSObject <PlayerServer2Delegate, ConnectionDelegate, NetworkConnectionDelegate, RendererMessaging, RendererOptions> {
    BOOL isPausable;
    BOOL isStatic;
    PlayerState playerState;
    Score *currentScore;
    BOOL isMaster;
    
    BOOL clockEnabled;
    BOOL allowClockChange;
    CGFloat clockDuration;
    int clockProgress;
    BOOL splitSecondMode;
    
    NSString *identifier;
    
    __weak id<RendererDelegate> rendererDelegate;
    id<NetworkStatus> networkStatusDelegate;
}

extern const NSInteger NETWORK_PROTOCOL_VERSION;

@property (nonatomic) BOOL isPausable;
@property (nonatomic) BOOL isStatic;
@property (nonatomic, readonly) PlayerState playerState;
@property (nonatomic, strong) Score *currentScore;
@property (nonatomic, readonly) BOOL isMaster;
@property (nonatomic) BOOL clockEnabled;
@property (nonatomic) BOOL allowClockChange;
@property (nonatomic) CGFloat clockDuration;
@property (nonatomic, readonly) int clockProgress;
@property (nonatomic, readonly) CGFloat clockLocation;
@property (nonatomic) BOOL splitSecondMode;
@property (nonatomic) BOOL allowSyncToTick;
@property (nonatomic, strong, readonly) NSString *identifier;
@property (nonatomic, weak) id<RendererDelegate> rendererDelegate;
@property (nonatomic, strong) id<NetworkStatus> networkStatusDelegate;

- (id)initWithScore:(Score *)score delegate:(__weak id<PlayerUIDelegate>)delegate;

- (BOOL)initializeServerWithServiceName:(NSString *)serviceName identifier:(NSString *)identifier;
- (void)registerScoreList:(NSArray *)list;
- (void)loadScore:(Score *)score;
- (void)shutdown;
- (void)sendPing;
- (CGFloat)detach:(BOOL)detached;

- (void)play;
- (void)pause;
- (void)reset;
- (void)seekTo:(CGFloat)location;
- (void)seekFinished;
- (void)setScoreDuration:(CGFloat)duration;

- (void)stopClockWithStateUpdate:(BOOL)updateState;
- (void)resetClock;

- (void)attemptSync;
- (void)prepareNetworkStatusView:(id<NetworkStatus>)viewController;

@end

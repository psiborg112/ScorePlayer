//
//  Network.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/11/2014.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

@protocol NetworkConnectionDelegate <NSObject>

@required
@property (nonatomic) BOOL connectedManually;
- (void)connectToServer:(NSString *)hostName onPort:(NSUInteger)port withTimeout:(NSInteger)timeout;
- (void)saveLastManualAddress:(NSString *)address;
- (void)disconnect;
- (void)requestScoreLoad:(NSArray *)scoreInfo;

@end

@protocol NetworkStatus <NSObject>

@required
@property (nonatomic, strong) NSArray *networkDevices;
@property (nonatomic, strong) NSArray *availableScores;
@property (nonatomic, strong) NSString *serviceName;
@property (nonatomic, strong) NSString *serverNamePrefix;
@property (nonatomic, strong) NSString *localServerName;
@property (nonatomic, strong) NSString *lastAddress;
@property (nonatomic) BOOL connected;
@property (nonatomic) BOOL allowScoreChange;
@property (nonatomic, weak) id<NetworkConnectionDelegate> networkConnectionDelegate;

@end

@protocol UpdateDelegate <NSObject>

@required
- (void)downloadedUpdatesToDirectory:(NSString *)downloadDirectory;

@optional
- (void)finishedUpdating;

@end

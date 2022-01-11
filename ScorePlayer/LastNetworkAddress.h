//
//  LastNetworkAddress.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 2/11/16.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LastNetworkAddress : NSObject

@property (nonatomic, strong) NSString *address;

+ (id)sharedNetworkAddress;

@end

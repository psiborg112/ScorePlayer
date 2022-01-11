//
//  LastNetworkAddress.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 2/11/16.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "LastNetworkAddress.h"

@implementation LastNetworkAddress

@synthesize address;

+ (id)sharedNetworkAddress
{
    static id sharedNetworkAddress = nil;
    
    if (sharedNetworkAddress == nil) {
        sharedNetworkAddress = [[self alloc] init];
    }
    
    return sharedNetworkAddress;
}

@end

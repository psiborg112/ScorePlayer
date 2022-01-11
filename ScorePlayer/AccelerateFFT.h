//
//  accelerateFFT.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/05/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>

@interface AccelerateFFT : NSObject

@property (nonatomic, readonly) UInt32 nSamples;

- (id)initForNumberOfSamples:(UInt32)nSamples;
- (UInt32)getBufferSize;
- (BOOL)performFFTOnSamples:(Float32 *)samples numberOfSamples:(UInt32)nSamples withOutput:(Float32 *)output outputSize:(UInt32)outputSize;

@end

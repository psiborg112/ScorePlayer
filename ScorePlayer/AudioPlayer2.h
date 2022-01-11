//
//  AudioPlayer2.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/05/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioPlayerProtocol.h"

@class Spectrogram;

static const int kBufferCount = 3;

//Custom struct used to store everything needed for our callback function.
typedef struct {
    AudioStreamBasicDescription dataFormat;
    AudioStreamBasicDescription outputFormat;
    ExtAudioFileRef file;
    ExtAudioFileRef oldFile;
    UInt64 frames;
    UInt64 lastSeekFrame;
    AudioBufferList *bufferLists[kBufferCount];
    int currentBuffer;
    int bufferLocation;
    UInt32 bufferBytesUsed[kBufferCount];
    UInt32 bufferSize;
    BOOL interleaved;
    BOOL isRunning;
    BOOL seekBeyondEOF;
    int currentWriteBuffer;
    int currentWriteCount;
    int fadeOutState;
    AudioUnit outputUnit;
    NSCondition *writeCondition;
    NSCondition *fadeCondition;
} AudioFileBuffers;

@interface AudioPlayer2 : NSObject <AudioPlayer>

@property (nonatomic, weak) id<AudioPlayerDelegate> delegate;

- (Spectrogram *)getSpectrogramForChannel:(NSUInteger)channel;
- (Spectrogram *)getSpectrogramForChannel:(NSUInteger)channel withSamplesPerFFT:(UInt32)samples;

@end

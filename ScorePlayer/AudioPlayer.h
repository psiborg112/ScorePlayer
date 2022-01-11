//
//  AudioPlayer.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/11/2014.
//  Copyright (c) 2014 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioPlayerProtocol.h"

static const int kBufferCount = 3;

typedef struct {
    AudioStreamBasicDescription dataFormat;
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[kBufferCount];
    AudioFileID audioFile;
    UInt32 bufferSize;
    SInt64 currentPacket;
    UInt32 numPacketsToRead;
    AudioStreamPacketDescription *packetDescs;
    bool isRunning;
    bool seekAfterEnd;
} AQPlayerState;

@interface AudioPlayer : NSObject <AudioPlayer>

@end

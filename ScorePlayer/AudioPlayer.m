//
//  AudioPlayer.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/11/2014.
//  Copyright (c) 2014 Decibel. All rights reserved.
//

#import "AudioPlayer.h"

static const UInt32 MAXBUFFERSIZE = 0x40000;
static const UInt32 MINBUFFERSIZE = 0x4000;

@interface AudioPlayer ()

- (UInt32)calculateBufferSize:(AudioStreamBasicDescription)ASBDesc maxPacketSize:(UInt32)maxPacketSize seconds:(Float64)seconds;
+ (void)fillBuffersForAudioQueue:(AQPlayerState *)aqState bufferRef:(AudioQueueBufferRef) inBuffer;

@end

@implementation AudioPlayer {
    AQPlayerState aqState;
    Float64 duration;
    UInt64 packetCount;
}

- (void)dealloc
{
    //Clean up our audio queue and free the memory we allocated for the description arrays.
    AudioQueueDispose(aqState.queue, true);
    AudioFileClose(aqState.audioFile);
    free(aqState.packetDescs);
}

- (UInt32)calculateBufferSize:(AudioStreamBasicDescription)ASBDesc maxPacketSize:(UInt32)maxPacketSize seconds:(Float64)seconds
{
    UInt32 outBufferSize;
    if (ASBDesc.mFramesPerPacket != 0) {
        Float64 numPacketsForTime = ASBDesc.mSampleRate / ASBDesc.mFramesPerPacket * seconds;
        outBufferSize = numPacketsForTime * maxPacketSize;
    } else {
        //If frames per packet is 0 then the codec doesn't know the relationship between packets and time.
        //Return a default value.
        outBufferSize = MAXBUFFERSIZE > maxPacketSize ? MAXBUFFERSIZE : maxPacketSize;
    }
    
    //Clamp to our range.
    if (outBufferSize > MAXBUFFERSIZE && outBufferSize > maxPacketSize) {
        outBufferSize = MAXBUFFERSIZE;
    } else if (outBufferSize < MINBUFFERSIZE) {
        outBufferSize = MINBUFFERSIZE;
    }
    
    return outBufferSize;
}

+ (void)fillBuffersForAudioQueue:(AQPlayerState *)aqState bufferRef:(AudioQueueBufferRef)inBuffer
{
    UInt32 numBytesReadFromFile = aqState->bufferSize;
    UInt32 numPackets = aqState->numPacketsToRead;
    
    //Read packets from the audio file. If data was read enqueue the buffer, otherwise stop the queue.
    AudioFileReadPacketData(aqState->audioFile, false, &numBytesReadFromFile, aqState->packetDescs, aqState->currentPacket, &numPackets, inBuffer->mAudioData);
    if (numPackets > 0) {
        inBuffer->mAudioDataByteSize = numBytesReadFromFile;
        if (aqState->packetDescs) {
            AudioQueueEnqueueBuffer(aqState->queue, inBuffer, numPackets, aqState->packetDescs);
        } else {
            AudioQueueEnqueueBuffer(aqState->queue, inBuffer, 0, aqState->packetDescs);
        }
        aqState->currentPacket += numPackets;
    } else {
        AudioQueueStop(aqState->queue, false);
        aqState->isRunning = false;
    }
}

#pragma mark - AudioPlayer delegate

- (id)initWithAudioFile:(NSString *)fileName withOptions:(NSDictionary *)options;
{
    //This version of the audio plaer does not take any options, so any argument passed is discarded.
    
    self = [super init];
    NSURL *audioURL = [NSURL fileURLWithPath:fileName];
    //Open our audio file.
    //OSStatus result = (We sholud probably use this for error checking later.)
    AudioFileOpenURL((__bridge CFURLRef)audioURL, kAudioFileReadPermission, 0, &aqState.audioFile);
    
    //Get our audio format.
    UInt32 dataFormatSize = sizeof(aqState.dataFormat);
    AudioFileGetProperty(aqState.audioFile, kAudioFilePropertyDataFormat, &dataFormatSize, &aqState.dataFormat);
    
    //Create our audio playback queue, and set buffer size.
    AudioQueueNewOutput(&aqState.dataFormat, &outputBufferCallBack, &aqState, CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &aqState.queue);
    UInt32 maxPacketSize;
    UInt32 propertySize = sizeof(maxPacketSize);
    Float64 bufferLength = 0.25;
    AudioFileGetProperty(aqState.audioFile, kAudioFilePropertyPacketSizeUpperBound, &propertySize, &maxPacketSize);
    aqState.bufferSize = [self calculateBufferSize:aqState.dataFormat maxPacketSize:maxPacketSize seconds:bufferLength];
    aqState.numPacketsToRead = aqState.bufferSize / maxPacketSize;
    
    //Get the length of the audio file and the total number of packets.
    propertySize = sizeof(duration);
    AudioFileGetProperty(aqState.audioFile, kAudioFilePropertyEstimatedDuration, &propertySize, &duration);
    propertySize = sizeof(packetCount);
    AudioFileGetProperty(aqState.audioFile, kAudioFilePropertyAudioDataPacketCount, &propertySize, &packetCount);
    
    //Allocate memory for packet description arrays.
    BOOL isFormatVBR = (aqState.dataFormat.mBytesPerPacket == 0 || aqState.dataFormat.mFramesPerPacket == 0);
    if (isFormatVBR) {
        aqState.packetDescs = (AudioStreamPacketDescription *)malloc(aqState.numPacketsToRead * sizeof(AudioStreamPacketDescription));
    } else {
        aqState.packetDescs = NULL;
    }
    
    //Set magic cookie for queue if needed. (Conains information used by the decoder to handle compressed formats.)
    UInt32 cookieSize = sizeof(UInt32);
    
    BOOL noCookie = AudioFileGetPropertyInfo(aqState.audioFile, kAudioFilePropertyMagicCookieData, &cookieSize, NULL);
    
    if (!noCookie && cookieSize) {
        char *magicCookie = (char *)malloc(cookieSize);
        AudioFileGetProperty(aqState.audioFile, kAudioFilePropertyMagicCookieData, &cookieSize, magicCookie);
        AudioQueueSetProperty(aqState.queue, kAudioQueueProperty_MagicCookie, magicCookie, cookieSize);
        free (magicCookie);
    }
    
    //Allocate buffers
    aqState.currentPacket = 0;
    for (int i = 0; i < kBufferCount; i++) {
        AudioQueueAllocateBuffer(aqState.queue, aqState.bufferSize, &aqState.buffers[i]);
        [AudioPlayer fillBuffersForAudioQueue:&aqState bufferRef:aqState.buffers[i]];
    }
    
    //Set gain
    Float32 gain = 1.0;
    AudioQueueSetParameter(aqState.queue, kAudioQueueParam_Volume, gain);
    
    aqState.seekAfterEnd = false;
    return self;
}

- (void)play;
{
    if (!(aqState.seekAfterEnd || aqState.isRunning)) {
        aqState.isRunning = true;
        AudioQueueStart(aqState.queue, NULL);
    }
}

- (void)stopWithReset:(BOOL)reset;
{
    //Stop the audio queue and prepare for the file to be replayed.
    AudioQueueStop(aqState.queue, true);
    aqState.isRunning = false;
    if (reset) {
        aqState.currentPacket = 0;
        for (int i = 0; i < kBufferCount; i++) {
            [AudioPlayer fillBuffersForAudioQueue:&aqState bufferRef:aqState.buffers[i]];
        }
        aqState.seekAfterEnd = false;
    }
}

- (void)seekToTime:(int)time
{
    if (aqState.isRunning) {
        AudioQueueStop(aqState.queue, true);
        aqState.isRunning = false;
    }
    //The method we're using to find the current packet might need revision.
    //(It should work for any format where there is a direct link between the number of frames and the number
    //of packets. This includes CBR and VBR files, but not VFR files.)
    Float64 location = (Float64)time / duration;
    aqState.currentPacket = (SInt64)(location * packetCount);
    if (aqState.currentPacket >= packetCount) {
        aqState.seekAfterEnd = true;
    } else {
        aqState.seekAfterEnd = false;
        for (int i = 0; i < kBufferCount; i++) {
            [AudioPlayer fillBuffersForAudioQueue:&aqState bufferRef:aqState.buffers[i]];
        }
    }
}

#pragma mark - AudioQueueOutput callback

static void outputBufferCallBack (void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    //Check the audio queue player state, and return if it's not running.
    if (!(((AQPlayerState *)aqData)->isRunning)) {
        return;
    } else {
        [AudioPlayer fillBuffersForAudioQueue:(AQPlayerState *)aqData bufferRef:inBuffer];
    }
}

@end

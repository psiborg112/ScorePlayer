//
//  AudioPlayerProtocol.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 31/05/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import "AudioPlayerProtocol.h"

@implementation AudioPlayerProtocol

+ (AudioStreamBasicDescription)createOutputDescription:(BOOL)interleaved
{
    //Create the stream description for our output. (Use LPCM 32 bit floating point.)
    AudioStreamBasicDescription outputDescription;
    outputDescription.mFormatID = kAudioFormatLinearPCM;
    outputDescription.mFormatFlags = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsFloat;
    if (!interleaved) {
        outputDescription.mFormatFlags |= kAudioFormatFlagIsNonInterleaved;
    }
    outputDescription.mSampleRate = 44100;
    outputDescription.mChannelsPerFrame = 2;
    outputDescription.mBitsPerChannel = 32;
    outputDescription.mBytesPerPacket = (outputDescription.mBitsPerChannel / 8);
    if (interleaved) {
        outputDescription.mBytesPerPacket *= outputDescription.mChannelsPerFrame;
    }
    outputDescription.mFramesPerPacket = 1;
    outputDescription.mBytesPerFrame = outputDescription.mBytesPerPacket;
    return outputDescription;
}

+ (BOOL)createOutputUnit:(AudioUnit *)io withAudioFormat:(AudioStreamBasicDescription)format withCallback:(AURenderCallbackStruct *)callbackStruct forInput:(BOOL)input
{
    //Create a component description for our audio unit output.
    AudioComponentDescription outputDescription;
    outputDescription.componentType = kAudioUnitType_Output;
    outputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    outputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    outputDescription.componentFlags = 0;
    outputDescription.componentFlagsMask = 0;
    
    //Get our audio component from the description and create our output unit.
    AudioComponent outputComponent = AudioComponentFindNext(NULL, &outputDescription);
    if (AudioComponentInstanceNew(outputComponent, io) != noErr) {
        return NO;
    }
    
    //Change the audio format used by the audio unit (on bus 0 for output, 1 for input).
    //Then set up our callback and enable or disable the input or output as needed.
    UInt32 enabled = 1;
    OSStatus err = noErr;
    err |= AudioUnitSetProperty(*io, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, sizeof(format));
    err |= AudioUnitSetProperty(*io, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format));
    if (input) {
        err |= AudioUnitSetProperty(*io, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Output, 1, callbackStruct, sizeof(callbackStruct));
        err |= AudioUnitSetProperty(*io, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, sizeof(enabled));
        enabled = 0;
        err |= AudioUnitSetProperty(*io, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enabled, sizeof(enabled));
    } else {
        //By default, output is enabled and input is disabled, so we only need to set up the callback here.
        err |= AudioUnitSetProperty(*io, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, callbackStruct, sizeof(*callbackStruct));
    }
    if (err != noErr) {
        return NO;
    }
    
    //Don't initialize the audio unit here in case the calling function wishes to make further changes to it.
    return YES;
}

+ (AudioBufferList *)createBufferListWithBuffersOfSize:(UInt32)size forFormat:(AudioStreamBasicDescription)format
{
    //Create our audio buffers. Because AudioBufferLists only define one buffer we have to manually allocate
    //memory when we want the option of using a non interleaved format.
    AudioBufferList *bufferList;
    if (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) {
        bufferList = malloc(sizeof(AudioBufferList) + (sizeof(AudioBuffer) * format.mChannelsPerFrame - 1));
        bufferList->mNumberBuffers = format.mChannelsPerFrame;
        for (int i = 0; i < bufferList->mNumberBuffers; i++) {
            Float32 *buffer = malloc(size);
            bufferList->mBuffers[i].mNumberChannels = 1;
            bufferList->mBuffers[i].mDataByteSize = size;
            bufferList->mBuffers[i].mData = buffer;
        }
    } else {
        bufferList = malloc(sizeof(AudioBufferList));
        Float32 *buffer = malloc(size);
        bufferList->mNumberBuffers = 1;
        bufferList->mBuffers[0].mNumberChannels = format.mChannelsPerFrame;
        bufferList->mBuffers[0].mDataByteSize = size;
        bufferList->mBuffers[0].mData = buffer;
    }
    
    return bufferList;
}

@end
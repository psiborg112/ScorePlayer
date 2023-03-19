//
//  AudioPlayer.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/05/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import "AudioPlayer2.h"
#import "AccelerateFFT.h"
#import "Spectrogram.h"

const CGFloat BUFFER_LENGTH = 0.25;

@interface AudioPlayer2 ()

- (BOOL)openAudioFile:(NSString *)fileName;
- (void)checkPlaybackStatus;
+ (void)fillBufferNumber:(uint)bufferIndex ofBufferSet:(AudioFileBuffers *)buffers;
+ (void)clearBufferNumber:(uint)bufferIndex ofBufferSet:(AudioFileBuffers *)buffers;
+ (void)applyFadeIn:(uint)numSamples onBufferNumber:(uint)bufferIndex ofBufferSet:(AudioFileBuffers *)buffers;

@end

@implementation AudioPlayer2 {
    AudioFileBuffers audioBuffers;
    //Float64 sampleRateRatio;
    NSDictionary *playerOptions;
    NSTimer *checkPlayback;
}

@synthesize delegate;

- (Spectrogram *)getSpectrogramForChannel:(NSUInteger)channel
{
    return [self getSpectrogramForChannel:channel withSamplesPerFFT:2048];
}

- (Spectrogram *)getSpectrogramForChannel:(NSUInteger)channel withSamplesPerFFT:(UInt32)fftSamples
{
    //Firstly, check that we're not currently playing our audio file, and that we're not using an interleaved format.
    if (audioBuffers.isRunning || audioBuffers.interleaved) {
        return nil;
    }
    
    //And that that our number of samples is a power of two.
    if ((fftSamples == 0) || ((fftSamples & (fftSamples - 1)) != 0)) {
        return nil;
    }
    
    //Also check that our choice of channel is valid. Otherwise use the first channel.
    if (channel >= audioBuffers.outputFormat.mChannelsPerFrame) {
        channel = 0;
    }
    
    //Create a holding buffer to read our audio data into.
    ExtAudioFileSeek(audioBuffers.file, 0);
    UInt32 bufferSize = audioBuffers.outputFormat.mSampleRate * audioBuffers.outputFormat.mBytesPerFrame * 10;
    UInt32 frameCount = bufferSize / audioBuffers.outputFormat.mBytesPerFrame;
    AudioBufferList *holdingBuffers = [AudioPlayerProtocol createBufferListWithBuffersOfSize:bufferSize forFormat:audioBuffers.outputFormat];
    
    UInt32 fftBufferSize = fftSamples * sizeof(Float32);
    Float32 *fftBuffer = malloc(fftBufferSize);
    Float32 *fftResult = malloc(fftBufferSize / 2);
    BOOL reachedEOF = NO;
    int remainder = 0;
    int remaining;
    
    AccelerateFFT *fft = [[AccelerateFFT alloc] initForNumberOfSamples:fftSamples];
    Spectrogram *spectrogram = [[Spectrogram alloc] init];
    
    //Now start reading our file and perform a fft on it.
    while (!reachedEOF) {
        for (int i = 0; i < holdingBuffers->mNumberBuffers; i++) {
            holdingBuffers->mBuffers[i].mDataByteSize = bufferSize;
        }
        ExtAudioFileRead(audioBuffers.file, &frameCount, holdingBuffers);
        UInt32 bytesRead = frameCount * audioBuffers.outputFormat.mBytesPerFrame;
        remaining = bytesRead;
        if (frameCount == 0) {
            reachedEOF = YES;
            remaining = remainder;
        }
        
        while (remaining > 0) {
            if (reachedEOF) {
                //We've reached the end. Pad our buffer with zeros.
                //(Type cast to char* so that our pointer arithmetic is in bytes.)
                memset((char *)fftBuffer + remainder, 0, fftBufferSize - remainder);
                remaining = 0;
                remainder = 0;
            } else if (remainder > 0) {
                //We have a remainder from the last file read. Take this into account when filling the fft buffer.
                memcpy((char *)fftBuffer + remainder, holdingBuffers->mBuffers[channel].mData, fftBufferSize - remainder);
                remaining -= fftBufferSize - remainder;
                remainder = 0;
            } else if (remaining < fftBufferSize) {
                //If we have less than a full fft buffer left, store the remainder in the fft buffer before
                //we loop to get more data.
                memcpy(fftBuffer, holdingBuffers->mBuffers[channel].mData + bytesRead - remaining, remaining);
                remainder = remaining;
                remaining = 0;
            } else {
                memcpy(fftBuffer, holdingBuffers->mBuffers[channel].mData + bytesRead - remaining, fftBufferSize);
                remaining -= fftBufferSize;
            }
            
            if (remainder == 0) {
                //Don't perform an fft here if we only have a remainder being stored in our buffer.
                [fft performFFTOnSamples:fftBuffer numberOfSamples:fftSamples withOutput:fftResult outputSize:fftBufferSize / 2];
                [spectrogram addDataColumn:[NSData dataWithBytes:fftResult length:fftBufferSize / 2]];
            }
        }
    }
    
    //Clean up. Restore the previous audio position (the last one seeked to) and free memory.
    ExtAudioFileSeek(audioBuffers.file, audioBuffers.lastSeekFrame);
    audioBuffers.currentWriteBuffer = 0;
    for (int i = 0; i < kBufferCount; i++) {
        [AudioPlayer2 fillBufferNumber:i ofBufferSet:&audioBuffers];
    }
    
    fft = nil;
    for (int i = 0; i < holdingBuffers->mNumberBuffers; i++) {
        free(holdingBuffers->mBuffers[i].mData);
    }
    free(holdingBuffers);
    free(fftBuffer);
    free(fftResult);
    
    spectrogram.sampleRate = audioBuffers.outputFormat.mSampleRate;
    return spectrogram;
}

- (BOOL)openAudioFile:(NSString *)fileName
{
    if (fileName == nil) {
        return NO;
    }
    
    NSURL *audioURL = [NSURL fileURLWithPath:fileName];
    //Open our audio file. Return if we encounter an error.
    if (ExtAudioFileOpenURL((__bridge CFURLRef)audioURL, &audioBuffers.file) != noErr) {
        return NO;
    }
    
    //Find out the number of frames in our audio file as well as information about its format.
    UInt32 dataSize = sizeof(audioBuffers.frames);
    if (ExtAudioFileGetProperty(audioBuffers.file, kExtAudioFileProperty_FileLengthFrames, &dataSize, &audioBuffers.frames) != noErr) {
        return NO;
    }
    dataSize = sizeof(audioBuffers.dataFormat);
    if (ExtAudioFileGetProperty(audioBuffers.file, kExtAudioFileProperty_FileDataFormat, &dataSize, &audioBuffers.dataFormat) != noErr) {
        return NO;
    }
    
    //Set the format to convert to for our audio output.
    if (ExtAudioFileSetProperty(audioBuffers.file, kExtAudioFileProperty_ClientDataFormat, sizeof(audioBuffers.outputFormat), &audioBuffers.outputFormat) != noErr) {
        return NO;
    }
    
    //Work out the ratio between the file and output sample rates.
    //sampleRateRatio = audioBuffers.outputFormat.mSampleRate / audioBuffers.dataFormat.mSampleRate;

    return YES;
}

- (void)checkPlaybackStatus
{
    if (!audioBuffers.isRunning) {
        [checkPlayback invalidate];
        [delegate audioPlaybackFinished];
    }
}

+ (void)fillBufferNumber:(uint)bufferIndex ofBufferSet:(AudioFileBuffers *)buffers
{
    if (bufferIndex >= kBufferCount) {
        return;
    }
    
    if (buffers->currentWriteCount >= kBufferCount - 1) {
        //Something has gone terribly wrong. We're waiting on writes to all of our other buffers and
        //are about to start writing into the one we're currently playing back from. Shut. It. Down!
        AudioOutputUnitStop(buffers->outputUnit);
        buffers->isRunning = NO;
        //Don't do anything else to change the state of the buffers: let the player deal with that
        //following the next UI interaction.
        return;
    } else {
        buffers->currentWriteCount++;
    }
    
    //Makes sure ExtAudioFileRead cannot be called concurrently.
    [buffers->writeCondition lock];
    while (buffers->currentWriteBuffer != bufferIndex) {
        [buffers->writeCondition wait];
    }
    
    //Reset the size of the buffers. (ExtAudioFileRead not only adjusts the frameCount, but it alters the value of
    //mDataByteSize and clamps to this in subsequent reads. This causes an issue at the end of the file if left unchecked.)
    for (int i = 0; i < buffers->bufferLists[bufferIndex]->mNumberBuffers; i++) {
        buffers->bufferLists[bufferIndex]->mBuffers[i].mDataByteSize = buffers->bufferSize;
    }
    UInt32 frameCount = buffers->bufferSize / buffers->outputFormat.mBytesPerFrame;
    ExtAudioFileRead(buffers->file, &frameCount, buffers->bufferLists[bufferIndex]);
    buffers->bufferBytesUsed[bufferIndex] = frameCount * buffers->outputFormat.mBytesPerFrame;
    buffers->currentWriteBuffer++;
    buffers->currentWriteBuffer %= kBufferCount;
    buffers->currentWriteCount--;
    [buffers->writeCondition broadcast];
    [buffers->writeCondition unlock];
}

+ (void)clearBufferNumber:(uint)bufferIndex ofBufferSet:(AudioFileBuffers *)buffers
{
    if (bufferIndex >= kBufferCount) {
        return;
    }
    for (int i = 0; i < buffers->bufferLists[bufferIndex]->mNumberBuffers; i++) {
        memset(buffers->bufferLists[bufferIndex]->mBuffers[i].mData, 0, buffers->bufferSize);
    }
}

+ (void)applyFadeIn:(uint)numSamples onBufferNumber:(uint)bufferIndex ofBufferSet:(AudioFileBuffers *)buffers
{
    if (bufferIndex >= kBufferCount || numSamples > buffers->bufferSize / sizeof(Float32)) {
        return;
    }
    
    for (int i = 0; i < buffers->bufferLists[bufferIndex]->mNumberBuffers; i++) {
        Float32 *buffer = buffers->bufferLists[bufferIndex]->mBuffers[i].mData;
        for (int i = 0; i < numSamples; i++) {
            buffer[i] = buffer[i] *= (Float32)i / (Float32)numSamples;
        }
    }
}

- (void)dealloc
{
    ExtAudioFileDispose(audioBuffers.file);
    ExtAudioFileDispose(audioBuffers.oldFile);
    for (int i = 0; i < kBufferCount; i++) {
        if (audioBuffers.bufferLists[i]) {
            for (int j = 0; j < audioBuffers.bufferLists[i]->mNumberBuffers; j++) {
                free(audioBuffers.bufferLists[i]->mBuffers[j].mData);
            }
            free(audioBuffers.bufferLists[i]);
        }
    }
    
    AudioComponentInstanceDispose(audioBuffers.outputUnit);
}

#pragma mark - AudioPlayer delegate

- (id)initWithAudioFile:(NSString *)fileName withOptions:(NSDictionary *)options
{
    self = [super init];
    
    //Store our options for later use.
    playerOptions = options;
    if ([[options objectForKey:@"interleaved"] boolValue]) {
        audioBuffers.interleaved = YES;
    } else {
        audioBuffers.interleaved = NO;
    }
    
    //Set the format to convert to for our audio output.
    audioBuffers.outputFormat = [AudioPlayerProtocol createOutputDescription:audioBuffers.interleaved];

    if (![self openAudioFile:fileName]) {
        return nil;
    }
    
    //Create our audio buffers.
    audioBuffers.bufferSize = audioBuffers.outputFormat.mSampleRate * audioBuffers.outputFormat.mBytesPerFrame * BUFFER_LENGTH;
    audioBuffers.currentWriteBuffer = 0;
    audioBuffers.currentWriteCount = 0;
    for (int i = 0; i < kBufferCount; i++) {
        audioBuffers.bufferLists[i] =  [AudioPlayerProtocol createBufferListWithBuffersOfSize:audioBuffers.bufferSize forFormat:audioBuffers.outputFormat];
    }
    
    audioBuffers.writeCondition = [NSCondition new];
    audioBuffers.fadeCondition = [NSCondition new];
    
    //Fill our buffers.
    audioBuffers.isRunning = NO;
    [self stopWithReset:YES];
    
    //Set up our callback function and create our output unit.
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = &OutputRenderCallback;
    callbackStruct.inputProcRefCon = &audioBuffers;
    
    if (![AudioPlayerProtocol createOutputUnit:&audioBuffers.outputUnit withAudioFormat:audioBuffers.outputFormat withCallback:&callbackStruct forInput:NO]) {
        return nil;
    }
    
    //Initialize our output unit.
    if (AudioUnitInitialize(audioBuffers.outputUnit) != noErr) {
        return nil;
    }
    
    return self;
}

- (void)play;
{
    if (!(audioBuffers.isRunning || audioBuffers.seekBeyondEOF)) {
        AudioOutputUnitStart(audioBuffers.outputUnit);
        audioBuffers.isRunning = YES;
        
        if (delegate != nil) {
            checkPlayback = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(checkPlaybackStatus) userInfo:nil repeats:YES];
        }
    }
}

- (void)stopWithReset:(BOOL)reset;
{
    [checkPlayback invalidate];
    if (audioBuffers.isRunning) {
        //Instead of stopping the audio here, set a flag to let our callback function know it should fade out.
        audioBuffers.fadeOutState = 1;
        //AudioOutputUnitStop(audioBuffers.outputUnit);
        //audioBuffers.isRunning = NO;
        
        //Wait for our fade out to occur before we write to any buffers.
        [audioBuffers.fadeCondition lock];
        while (audioBuffers.fadeOutState != 2) {
            [audioBuffers.fadeCondition wait];
        }
        [audioBuffers.fadeCondition unlock];
        
        AudioOutputUnitStop(audioBuffers.outputUnit);
        audioBuffers.isRunning = NO;
        audioBuffers.fadeOutState = 0;
    }
    
    if (reset) {
        //Check that there aren't still any buffer writes happening.
        [audioBuffers.writeCondition lock];
        while (audioBuffers.currentWriteCount > 0) {
            [audioBuffers.writeCondition wait];
        }
        [audioBuffers.writeCondition unlock];
        
        ExtAudioFileSeek(audioBuffers.file, 0);
    
        audioBuffers.currentWriteBuffer = 0;
        for (int i = 0; i < kBufferCount; i++) {
            [AudioPlayer2 fillBufferNumber:i ofBufferSet:&audioBuffers];
        }
        [AudioPlayer2 applyFadeIn:128 onBufferNumber:0 ofBufferSet:&audioBuffers];
        
        audioBuffers.lastSeekFrame = 0;
        audioBuffers.currentBuffer = 0;
        audioBuffers.bufferLocation = 0;
        audioBuffers.seekBeyondEOF = NO;
    }
}

- (void)seekToTime:(int)time
{
    if (audioBuffers.isRunning) {
        [self stopWithReset:NO];
    }
    
    //Work out what frame we should seek to based on our file's sample rate.
    SInt64 frame = time * audioBuffers.dataFormat.mSampleRate;
    if (frame < audioBuffers.frames) {
        //Check that there aren't still any buffer writes happening.
        [audioBuffers.writeCondition lock];
        while (audioBuffers.currentWriteCount > 0) {
            [audioBuffers.writeCondition wait];
        }
        [audioBuffers.writeCondition unlock];
        
        ExtAudioFileSeek(audioBuffers.file, frame);
        
        audioBuffers.currentWriteBuffer = 0;
        for (int i = 0; i < kBufferCount; i++) {
            [AudioPlayer2 fillBufferNumber:i ofBufferSet:&audioBuffers];
        }
        [AudioPlayer2 applyFadeIn:128 onBufferNumber:0 ofBufferSet:&audioBuffers];
        
        audioBuffers.lastSeekFrame = frame;
        audioBuffers.currentBuffer = 0;
        audioBuffers.bufferLocation = 0;
        audioBuffers.seekBeyondEOF = NO;
    } else {
        //If we're trying to seek beyond the end of the file, we should disable further actions.
        //(Until we either reset the player, or seek within the bounds of the file.)
        audioBuffers.seekBeyondEOF = YES;
    }
}

- (void)loadAudioFile:(NSString *)fileName
{
    //Stop our player if we're running.
    if (audioBuffers.isRunning) {
        [self stopWithReset:NO];
    }
    
    //Keep a reference to our current audio file so that we don't delete it
    //before the fade out has finished happening. (And close the previous old file.)
    ExtAudioFileDispose(audioBuffers.oldFile);
    audioBuffers.oldFile = audioBuffers.file;
    
    if (![self openAudioFile:fileName]) {
        //If we didn't load properly set variables to prevent playback or seek.
        audioBuffers.frames = 0;
        audioBuffers.seekBeyondEOF = YES;
    }
}

#pragma mark - OutputRender callback

static OSStatus OutputRenderCallback (void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
    AudioFileBuffers *buffers = (AudioFileBuffers *)inRefCon;
    int inNumberBytes = inNumberFrames * buffers->outputFormat.mBytesPerFrame;
    int remainingBytes = inNumberBytes;
    UInt32 bufferBytesAvailable = buffers->bufferBytesUsed[buffers->currentBuffer] - buffers->bufferLocation;
    int currentBuffer = buffers->currentBuffer;
    
    if (buffers->fadeOutState == 2) {
        //See if we've already performed a fade out and zero our buffer.
        for (int i = 0; i < ioData->mNumberBuffers; i++) {
            memset(ioData->mBuffers[i].mData, 0, remainingBytes);
        }
        return noErr;
    }
    
    //First check if we've reached our end of file. If we have, stop our output unit.
    if (buffers->bufferBytesUsed[currentBuffer] == 0) {
        AudioOutputUnitStop(buffers->outputUnit);
        buffers->isRunning = NO;
        buffers->seekBeyondEOF = YES;
        buffers->fadeOutState = 0;
        return noErr;
    }
    
    //Fill the output unit buffer from our current buffer.
    while (remainingBytes > 0) {
        UInt32 copyBytes = remainingBytes < bufferBytesAvailable ? remainingBytes : bufferBytesAvailable;

        for (int i = 0; i < ioData->mNumberBuffers; i++) {
            memcpy(ioData->mBuffers[i].mData + inNumberBytes - remainingBytes, buffers->bufferLists[currentBuffer]->mBuffers[i].mData + buffers->bufferLocation, copyBytes);
        }
        buffers->bufferLocation = buffers->bufferLocation + copyBytes;
        remainingBytes -= copyBytes;
        //If we've reached the end of our current buffer switch to the next one, and detect if we've reached EOF.
        //Don't update the local currentBuffer variable yet: we need to use it to update the recently emptied buffer.
        if (buffers->bufferLocation == buffers->bufferBytesUsed[currentBuffer]) {
            buffers->currentBuffer = (buffers->currentBuffer + 1) % 3;
            buffers->bufferLocation = 0;
            buffers->bufferBytesUsed[currentBuffer] = 0;
            bufferBytesAvailable = buffers->bufferBytesUsed[buffers->currentBuffer];
            
            //Check for EOF, and zero our remaining bytes if detected.
            if (buffers->bufferBytesUsed[buffers->currentBuffer] == 0) {
                for (int i = 0; i < ioData->mNumberBuffers; i++) {
                    memset(ioData->mBuffers[i].mData + inNumberBytes - remainingBytes, 0, remainingBytes);
                }
                remainingBytes = 0;
            } else {
                //Refill the spent buffer in a background thread.
                //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                    [AudioPlayer2 fillBufferNumber:currentBuffer ofBufferSet:buffers];
                });
            }
            
            currentBuffer = buffers->currentBuffer;
        }
    }
    
    //Check if we need to fade out and stop.
    if (buffers->fadeOutState == 1) {
        [buffers->fadeCondition lock];
        for (int i = 0; i < ioData->mNumberBuffers; i++) {
            Float32 *buffer = ioData->mBuffers[i].mData;
            for (int j = 0; j < inNumberFrames; j++) {
                buffer[j] *= (Float32)(inNumberFrames - j) / (Float32)inNumberFrames;
            }
        }
        buffers->fadeOutState = 2;
        [buffers->fadeCondition signal];
        [buffers->fadeCondition unlock];
    }
    
    return noErr;
}

@end

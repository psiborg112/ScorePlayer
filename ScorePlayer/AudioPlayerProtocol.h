//
//  AudioPlayerProtocol.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 9/05/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@protocol AudioPlayerDelegate <NSObject>

@required
- (void)audioPlaybackFinished;

@end

@protocol AudioRecorderDelegate <NSObject>

@required
- (void)audioRecordingFinished:(BOOL)allowPlayback;

@optional
- (void)audioPlaybackFinished;

@end

@protocol AudioPlayer <NSObject>

@required
- (id)initWithAudioFile:(NSString *)fileName withOptions:(NSDictionary *)options;
- (void)play;
- (void)stopWithReset:(BOOL)reset;
- (void)seekToTime:(int)time;

@optional
@property (nonatomic, weak) id<AudioPlayerDelegate> delegate;
- (void)loadAudioFile:(NSString *)fileName;

@end

@interface AudioPlayerProtocol : NSObject

+ (AudioStreamBasicDescription)createOutputDescription:(BOOL)interleaved;
+ (BOOL)createOutputUnit:(AudioUnit *)io withAudioFormat:(AudioStreamBasicDescription)format withCallback:(AURenderCallbackStruct *)callbackStruct forInput:(BOOL)input;
+ (AudioBufferList *)createBufferListWithBuffersOfSize:(UInt32)size forFormat:(AudioStreamBasicDescription)format;

@end

//
//  Score.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Score : NSObject {
    NSString *scoreName;
    NSMutableArray *composers;
    NSString *scoreType;
    NSInteger variationNumber;
    CGFloat originalDuration;
    NSInteger startOffset;
    NSInteger readLineOffset;
    NSString *fileName;
    NSMutableArray *parts;
    NSString *prefsFile;
    NSString *instructions;
    NSString *audioFile;
    NSMutableArray *audioParts;
    BOOL allowsOptions;
    BOOL askForIdentifier;
    UIColor *backgroundColour;
    NSString *scorePath;
    NSString *annotationsPathOverride;
    NSString *version;
}

@property (nonatomic, copy) NSString *scoreName;
@property (nonatomic) NSMutableArray *composers;
@property (nonatomic, readonly) NSString *composerFullText;
@property (nonatomic, readonly) NSString *composerSurnames;
@property (nonatomic, copy) NSString *scoreType;
@property (nonatomic) NSInteger variationNumber;
@property (nonatomic) CGFloat originalDuration;
@property (nonatomic) NSInteger startOffset;
@property (nonatomic) NSInteger readLineOffset;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic) NSMutableArray *parts;
@property (nonatomic, copy) NSString *prefsFile;
@property (nonatomic, copy) NSString *instructions;
@property (nonatomic, copy) NSString *audioFile;
@property (nonatomic) NSMutableArray *audioParts;
@property (nonatomic) BOOL allowsOptions;
@property (nonatomic) BOOL askForIdentifier;
@property (nonatomic, copy) UIColor *backgroundColour;
@property (nonatomic, copy) NSString *scorePath;
@property (nonatomic, copy) NSString *annotationsPathOverride;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *formatVersion;

@end

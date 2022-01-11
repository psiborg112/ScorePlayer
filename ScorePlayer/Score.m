//
//  Score.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "Score.h"

@interface Score ()

- (NSString *)nameStringWithSurnameOnly:(BOOL) surnames;

@end

@implementation Score

@synthesize scoreName, composers, scoreType, variationNumber, originalDuration, startOffset, readLineOffset, fileName, parts, prefsFile, instructions, audioFile, audioParts, allowsOptions, askForIdentifier, backgroundColour, scorePath, annotationsPathOverride, version, formatVersion;

- (id)init {
    //Set some sensible defaults for optional values
    self = [super init];
    if (self) {
        variationNumber = 0;
        startOffset = 0;
        readLineOffset = 150;
        allowsOptions = NO;
        askForIdentifier = NO;
        composers = [[NSMutableArray alloc] init];
        parts = [[NSMutableArray alloc] init];
        audioParts = [[NSMutableArray alloc] init];
        backgroundColour = [UIColor whiteColor];
        version = @"0";
        formatVersion = @"1";
    }
    return self;
}

- (NSString *)composerFullText
{
    return [self nameStringWithSurnameOnly:NO];
}

- (NSString *)composerSurnames
{
    return [self nameStringWithSurnameOnly:YES];
}

- (NSString *)nameStringWithSurnameOnly:(BOOL)surnames
{
    if ([composers count] < 1) {
        return nil;
    }
    
    NSMutableString *nameString = [[NSMutableString alloc] init];
    if (!surnames && ![[[composers objectAtIndex:0] objectAtIndex:1] isEqualToString:@""]) {
        [nameString appendFormat:@"%@ ", [[composers objectAtIndex:0] objectAtIndex: 1]];
    }
    
    [nameString appendString:[[composers objectAtIndex:0] objectAtIndex: 0]];
    
    if ([composers count] > 2) {
        [nameString appendString:@","];
    }
    
    for (int i = 1; i < [composers count] - 1; i++) {
        if (!surnames && ![[[composers objectAtIndex:i] objectAtIndex:1] isEqualToString:@""]) {
            [nameString appendFormat:@" %@", [[composers objectAtIndex:i] objectAtIndex: 1]];
        }
        [nameString appendFormat:@" %@,", [[composers objectAtIndex:i] objectAtIndex: 0]];
    }
    
    if ([composers count] > 1) {
        [nameString appendString:@" and "];
        if (!surnames && ![[[composers objectAtIndex:[composers count] - 1] objectAtIndex:1] isEqualToString:@""]) {
            [nameString appendFormat:@"%@ ", [[composers objectAtIndex:[composers count] - 1] objectAtIndex: 1]];
        }
        [nameString appendString:[[composers objectAtIndex:[composers count] - 1] objectAtIndex: 0]];
    }
    
    return [NSString stringWithString:nameString];
}

@end

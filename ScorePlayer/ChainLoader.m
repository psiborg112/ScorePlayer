//
//  ChainLoader.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 30/08/2015.
//  Copyright (c) 2015 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "ChainLoader.h"
#import "Score.h"
//#import "OSCMessage.h"

@interface ChainLoader ()

- (void)processPreferences;

@end

@implementation ChainLoader {
    Score *score;
    CALayer *canvas;
    NSMutableArray *scores;
    NSMutableArray *startTimes;
    
    NSXMLParser *xmlParser;
    NSMutableString *currentString;
    BOOL isData;
    BOOL prefsLoaded;
    BOOL awaitingPrefs;
    BOOL badPrefs;
    NSString *errorMessage;
    
    BOOL opusLoaded;
    BOOL awaitingOpus;
    
    __weak id<RendererUI> UIDelegate;
}

- (void)processPreferences
{
    //If we already know there's an error in the opus or preferences file then we don't need to
    //perform additional checks.
    if (!badPrefs) {
        //Firstly we need to check the suitability of each score.
        //For the moment, we're just using the first two, but will eventually extend this further.
        if ([scores count] < 2) {
            badPrefs = YES;
            errorMessage = @"Not enough scores defined";
        } else {
            for (int i = 0; i < 2; i++) {
                //Check that we're not loading a chainloaded score. (There will be no chain-ception!)
                if ([((Score *)[scores objectAtIndex:0]).scoreType isEqualToString:@"Chainloader"]) {
                    badPrefs = YES;
                    errorMessage = @"Bad score type";
                }
            }
        }
        
        if ([startTimes count] < 1) {
            badPrefs = YES;
            errorMessage = @"Malformed preferences file.";
        } else {
            NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"self" ascending:YES];
            [startTimes sortUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        }
    }
    
    prefsLoaded = YES;
    if (awaitingPrefs) {
        [self reset];
        awaitingPrefs = NO;
    }
    
}

#pragma mark - Renderer delegate

- (void)setIsMaster:(BOOL)master
{
    isMaster = master;
}

- (BOOL)isMaster
{
    return isMaster;
}

+ (RendererFeatures)getRendererRequirements
{
    return kFileName | kPrefsFile | kPositiveDuration;
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    
    score = scoreData;
    canvas = playerCanvas;
    UIDelegate = UIDel;
    UIDelegate.clockVisible = NO;
    
    opusLoaded = NO;
    prefsLoaded = NO;
    
    awaitingOpus = NO;
    NSData *xmlScore = [[NSData alloc] initWithContentsOfFile:[score.scorePath stringByAppendingPathComponent:score.fileName]];
    OpusParser *parser = [[OpusParser alloc] initWithData:xmlScore scorePath:score.scorePath timeOut:5 asScoreComponent:YES];
    parser.delegate = self;
    
    NSData *prefsData = [[NSData alloc] initWithContentsOfFile:[score.scorePath stringByAppendingPathComponent:score.prefsFile]];
    xmlParser = [[NSXMLParser alloc] initWithData:prefsData];
    isData = NO;
    awaitingPrefs = NO;
    xmlParser.delegate = self;
    [xmlParser parse];
    
    return self;
}

- (void)reset
{
    
}

#pragma mark - OpusParser delegate

- (void)parserFinished:(id)parser withScores:(NSMutableArray *)newScores;
{
    ((OpusParser *)parser).delegate = nil;
    scores = newScores;
    opusLoaded = YES;
    if (awaitingOpus) {
        [self processPreferences];
    }
}

- (void)parserError:(id)parser
{
    ((OpusParser *)parser).delegate = nil;
    badPrefs = YES;
    errorMessage = @"The collection of scores to be chainloaded is damaged.";
    opusLoaded = YES;
    if (awaitingOpus) {
        [self processPreferences];
    }
}


#pragma mark - NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if ([elementName isEqualToString:@"starttime"]){
        isData = YES;
        currentString = nil;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (isData) {
        if (currentString == nil) {
            currentString = [[NSMutableString alloc] initWithString:string];
        } else {
            [currentString appendString:string];
        }
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if ([elementName isEqualToString:@"starttime"]) {
        NSInteger time = [currentString integerValue];
        if (time > 0) {
            [startTimes addObject:[NSNumber numberWithInteger:time]];
        }
    }
    isData = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    parser.delegate = nil;
    xmlParser = nil;
    if (!opusLoaded) {
        awaitingOpus = YES;
    } else {
        [self processPreferences];
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    badPrefs = YES;
    errorMessage = @"Damaged preferences file.";
    parser.delegate = nil;
    xmlParser = nil;
    if (!opusLoaded) {
        awaitingOpus = YES;
    } else {
        [self processPreferences];
    }
}

@end

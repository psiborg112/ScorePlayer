//
//  OpusParser.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 4/11/2014.
//  Copyright (c) 2014 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol OpusParserDelegate <NSObject>

@required
- (void)parserFinished:(id)parser withScores:(NSMutableArray *)scores;
- (void)parserError:(id)parser;

@end

@interface OpusParser : NSObject <NSXMLParserDelegate> {
    NSString *thumbnailPath;
    NSString *annotationsPath;
    NSString *scorePath;
    NSString *updateURL;
    NSString *opusVersion;
    NSString *formatVersion;
    id<OpusParserDelegate> delegate;
}

@property (nonatomic, strong) NSString *thumbnailPath;
@property (nonatomic, strong) NSString *annotationsPath;
@property (nonatomic, strong) NSString *scorePath;
@property (nonatomic, strong) NSString *updateURL;
@property (nonatomic, strong) NSString *opusVersion;
@property (nonatomic, strong) NSString *formatVersion;
@property (nonatomic, strong) id<OpusParserDelegate> delegate;

- (id)initWithData:(NSData *)xmlData scorePath:(NSString *)path timeOut:(int)time asScoreComponent:(BOOL)subScore;
- (void)startParse;

+ (BOOL)isValidURL:(NSString *)url;

@end

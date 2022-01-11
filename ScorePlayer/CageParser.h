//
//  CageParser.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 24/12/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

@class OSCMessage;

@protocol CageParserDelegate <NSObject>

@required
- (void)parserFinishedWithResult:(OSCMessage *)data;
- (void)parserError;

@end

@interface CageParser : NSObject <NSXMLParserDelegate> {
    id<CageParserDelegate> delegate;
}

@property (nonatomic, strong) id<CageParserDelegate> delegate;

- (id)initWithVaritionNumber:(NSInteger)variationNumber prefsData:(NSData *)prefsData;
- (void)startParse;

@end

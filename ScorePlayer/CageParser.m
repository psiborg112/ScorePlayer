//
//  CageParser.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 24/12/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import "CageParser.h"
#import "OSCMessage.h"

@implementation CageParser {
    NSInteger variation;
    
    NSXMLParser *xmlParser;
    NSData *data;
    NSMutableString *currentString;
    BOOL isData;
    BOOL ignoreSection;
    int processingVariation;
    
    //Storage variables
    CGFloat variation1Duration;
    CGFloat variation2Duration;
    CGFloat variation5Duration;
    int performers;
    
    int minDuration[2];
    int maxDuration[2];
    int density[2];
    
    NSMutableArray *objectNumbers;
}

@synthesize delegate;

- (id)initWithVaritionNumber:(NSInteger)variationNumber prefsData:(NSData *)prefsData
{
    self = [super init];
    
    //Set initial values
    variation1Duration = 0;
    variation2Duration = 0;
    variation5Duration = 0;
    performers = 6;
    
    for (int i = 0; i < 2; i++) {
        minDuration[i] = 500;
        maxDuration[i] = 5000;
    }
    density[0] = 5;
    density[1] = 3;
    
    objectNumbers = [[NSMutableArray alloc] initWithObjects:[NSNumber numberWithInt:2], [NSNumber numberWithInt:3], [NSNumber numberWithInt:3], [NSNumber numberWithInt:3], nil];
    
    variation = variationNumber;
    data = prefsData;
    return self;
}

- (void)startParse
{
    xmlParser = [[NSXMLParser alloc] initWithData:data];
    
    isData = NO;
    xmlParser.delegate = self;
    [xmlParser parse];
}

#pragma mark - NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if ([elementName isEqualToString:@"completevariations"]) {
        //We're in a section dealing with the complete variations. Currently this just involves setting
        //the duration of those variations that have a non-static score.
        processingVariation = -1;
        if (variation == -1) {
            ignoreSection = NO;
        } else {
            ignoreSection = YES;
        }
    } else if ([elementName hasPrefix:@"variation"]) {
        processingVariation = [[elementName substringFromIndex:[elementName length] - 1] intValue];
        //Only process the section if it is for the relevant variation number.
        if (processingVariation == variation || variation == -1) {
            ignoreSection = NO;
        } else {
            ignoreSection = YES;
        }
    } else if (!ignoreSection) {
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
    if ([elementName isEqualToString:@"completevariations"] || [elementName hasPrefix:@"variation"]) {
        ignoreSection = NO;
    }
    
    if (ignoreSection) {
        return;
    }
    
    //Assign data to storage variables
    if (processingVariation == -1) {
        if ([elementName isEqualToString:@"duration1"]) {
            if ([currentString intValue] > 0) {
                variation1Duration = [currentString intValue];
            }
        } else if ([elementName isEqualToString:@"duration2"]) {
            if ([currentString intValue] > 0) {
                variation2Duration = [currentString intValue];
            }
        } else if ([elementName isEqualToString:@"duration5"]) {
            if ([currentString intValue] > 0) {
                variation5Duration = [currentString intValue];
            }
        } else if ([elementName isEqualToString:@"performers"]) {
            performers = [currentString intValue];
            if (performers < 1) {
                performers = 1;
            } else if (performers > 6) {
                performers = 6;
            }
        }
    } else if (processingVariation == 1 || processingVariation == 2) {
        if ([elementName isEqualToString:@"minevent"]) {
            int minEvent = [currentString intValue];
            if (minEvent < 100) {
                minEvent = 100;
            }
            minDuration[processingVariation - 1] = minEvent;
        } else if ([elementName isEqualToString:@"maxevent"]) {
            int maxEvent = [currentString intValue];
            if (maxEvent > 10000) {
                maxEvent = 100000;
            }
            maxDuration[processingVariation - 1] = maxEvent;
        } else if ([elementName isEqualToString:@"density"]) {
            int dense = [currentString intValue];
            if (dense < 1) {
                dense = 1;
            } else if (dense > 4 + processingVariation) {
                dense = 4 + processingVariation;
            }
            density[processingVariation - 1] = dense;
        }
    } else if (processingVariation == 6) {
        if ([elementName isEqualToString:@"systems"]) {
            int systems = [currentString intValue];
            if (systems < 1) {
                systems = 1;
            } else if (systems > 5) {
                systems = 5;
            }
            [objectNumbers removeObjectAtIndex:0];
            [objectNumbers insertObject:[NSNumber numberWithInt:systems] atIndex:0];
        } else if ([elementName isEqualToString:@"sources"]) {
            int sources = [currentString intValue];
            if (sources < 1) {
                sources = 1;
            } else if (sources > 10) {
                sources = 10;
            }
            [objectNumbers removeObjectAtIndex:1];
            [objectNumbers insertObject:[NSNumber numberWithInt:sources] atIndex:1];
        } else if ([elementName isEqualToString:@"speakers"]) {
            int speakers = [currentString intValue];
            if (speakers < 1) {
                speakers = 1;
            } else if (speakers > 10) {
                speakers = 10;
            }
            [objectNumbers removeObjectAtIndex:2];
            [objectNumbers insertObject:[NSNumber numberWithInt:speakers] atIndex:2];
        } else if ([elementName isEqualToString:@"components"]) {
            int components = [currentString intValue];
            if (components < 1) {
                components = 1;
            } else if (components > 10) {
                components = 10;
            }
            [objectNumbers removeObjectAtIndex:3];
            [objectNumbers insertObject:[NSNumber numberWithInt:components] atIndex:3];
        }
    }
    
    isData = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    //Check a few potential bounds issues
    for (int i = 0; i < 2; i++) {
        if (maxDuration[i] < minDuration[i]) {
            maxDuration[i] = minDuration[i];
        }
    }
    
    OSCMessage *result = [[OSCMessage alloc] init];
    [result appendAddressComponent:@"Options"];
    
    if (variation == -1) {
        [result addFloatArgument:variation1Duration];
        [result addFloatArgument:variation2Duration];
        [result addFloatArgument:variation5Duration];
        [result addIntegerArgument:performers];
    }
    if (variation == 1 || variation == -1) {
        [result addIntegerArgument:minDuration[0]];
        [result addIntegerArgument:maxDuration[0]];
        [result addIntegerArgument:density[0]];
    }
    if (variation == 2 || variation == -1) {
        [result addIntegerArgument:minDuration[1]];
        [result addIntegerArgument:maxDuration[1]];
        [result addIntegerArgument:density[1]];
    }
    if (variation == 6 || variation == -1) {
        for (int i = 0; i < [objectNumbers count]; i++) {
            [result addIntegerArgument:[[objectNumbers objectAtIndex:i] intValue]];
        }
    }
    
    parser.delegate = nil;
    xmlParser = nil;
    
    [delegate parserFinishedWithResult:result];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    parser.delegate = nil;
    xmlParser = nil;
    [delegate parserError];
}

@end

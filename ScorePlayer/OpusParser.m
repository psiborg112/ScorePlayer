//
//  OpusParser.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 4/11/2014.
//  Copyright (c) 2014 Decibel. All rights reserved.
//

#import "OpusParser.h"
#import "Score.h"
#import "Renderer.h"

@interface OpusParser ()

- (void)hangCheck;

@end

@implementation OpusParser {
    NSMutableArray *scores;
    Score *currentScore;
    NSFileManager *fileManager;
    NSXMLParser *xmlParser;
    NSTimer *watchdog;
    int timeOut;
    NSMutableString *currentString;
    Class rendererClass;
    BOOL isScoreProperty;
    BOOL scoreInvalid;
    BOOL isSubScore;
}

@synthesize thumbnailPath, annotationsPath, scorePath, updateURL, opusVersion, formatVersion, delegate;

- (id)initWithData:(NSData *)xmlData scorePath:(NSString *)path timeOut:(int)time asScoreComponent:(BOOL)subScore
{
    self = [super init];
    scorePath = path;
    timeOut = time;
    isSubScore = subScore;
    scores = [[NSMutableArray alloc] init];
    fileManager = [NSFileManager defaultManager];
    if (xmlData != nil) {
        xmlParser = [[NSXMLParser alloc] initWithData:xmlData];
    }
    isScoreProperty = NO;
    xmlParser.delegate = self;
    return self;
}

- (void)startParse
{
    //Trying to resolve the DTD file currently just gives an error.
    //xmlParser.shouldResolveExternalEntities = YES;
    if (xmlParser != nil) {
        watchdog = [NSTimer scheduledTimerWithTimeInterval:timeOut target:self selector:@selector(hangCheck) userInfo:nil repeats:NO];
        [xmlParser parse];
    } else {
        [delegate parserError:self];
    }
}

- (void)hangCheck
{
    [xmlParser abortParsing];
}

+ (BOOL)isValidURL:(NSString *)url
{
    //Use NSDataDetector to see if the entire length of our URL qualifies as a link.
    if ([url length] > 0) {
        NSError *error = nil;
        NSDataDetector *dataDetector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:&error];
        if (dataDetector && !error) {
            NSRange entireRange = NSMakeRange(0, [url length]);
            NSRange linkRange = [dataDetector rangeOfFirstMatchInString:url options:0 range:entireRange];
            if (NSEqualRanges(entireRange, linkRange)) {
                return YES;
            }
        }
    }
    
    return NO;
}

#pragma mark - NSXMLParser delegate
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict {
    
    if ([elementName isEqualToString:@"opus"]) {
        //This is our collection object which maps to the scores array. Since this is already
        //initialised, our work here is done.
        return;
    } else if ([elementName isEqualToString:@"score"]) {
        //A new score object
        currentScore = [[Score alloc] init];
        scoreInvalid = NO;
    } else {
        //Anything else is a property of the score.
        isScoreProperty = YES;
        currentString = nil;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (isScoreProperty) {
        if (currentString == nil) {
            currentString = [[NSMutableString alloc] initWithString:string];
        } else {
            [currentString appendString:string];
        }
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if ([elementName isEqualToString:@"opus"]) {
        return;
    } else if ([elementName isEqualToString:@"score"]) {
        //We need to check that the current score is valid and then add it to our scores collection.
        //Check that it has at least a name, composer (if needed) and renderer type.
        if ((!isSubScore && (currentScore.scoreName == nil || [currentScore.composers count] == 0)) || currentScore.scoreType == nil) {
            scoreInvalid = YES;
        }
        
        if (!scoreInvalid) {
            //Check that the score defined in the XML source has all the reqired data.
            RendererFeatures capabilities = kBasic;
            if (currentScore.variationNumber != 0) {
                capabilities |= kVariations;
            }
            if (currentScore.originalDuration != 0) {
                capabilities |= kNonZeroDuration;
            }
            if (currentScore.originalDuration > 0) {
                capabilities |= kPositiveDuration;
            }
            if (currentScore.fileName != nil) {
                capabilities |= kFileName;
            }
            if ([currentScore.parts count] > 0) {
                capabilities |= kParts;
            }
            if (currentScore.prefsFile != nil) {
                capabilities |= kPrefsFile;
            }
            //The ability to use an identifier isn't conditional on the score file.
            capabilities |= kUsesIdentifier;
            capabilities |= kUsesScaledCanvas;
            
            RendererFeatures requirements = (RendererFeatures)[rendererClass getRendererRequirements];
            if ((requirements & capabilities) != requirements) {
                scoreInvalid = YES;
            }
            
            if (currentScore.allowsOptions) {
                Class optionsClass = NSClassFromString([currentScore.scoreType stringByAppendingString:@"Options"]);
                if (optionsClass == nil || !([optionsClass conformsToProtocol:@protocol(RendererOptionsView)] && [optionsClass isSubclassOfClass:[UIView class]])) {
                    currentScore.allowsOptions = NO;
                }
            }
            
            if (!(requirements & kUsesIdentifier)) {
                currentScore.askForIdentifier = NO;
            }
            
            //If no audio file is specified, or the number of audio parts doesn't
            //match the number of notation parts, then we should ignore them.
            if (currentScore.audioFile == nil || ([currentScore.audioParts count] != [currentScore.parts count])) {
                [currentScore.audioParts removeAllObjects];
            }
        }
        
        if (!scoreInvalid) {
            //Add a reference to the score's directory. We'll need this to load files later.
            currentScore.scorePath = scorePath;
            [scores addObject:currentScore];
            
            if (annotationsPath != nil) {
                currentScore.annotationsPathOverride = [annotationsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", currentScore.composerFullText, currentScore.scoreName]];
            }
            
            //Check if our score has a thumbnail and if not generate it.
            NSString *fileName = [NSString stringWithFormat:@".%@.%@.thumbnail.png", currentScore.composerFullText, currentScore.scoreName];
            fileName = [fileName stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
            fileName = [fileName stringByReplacingOccurrencesOfString:@":" withString:@"."];
            if (thumbnailPath != nil) {
                //We have to save thumbnails for the built in scores to an alternative location.
                fileName = [thumbnailPath stringByAppendingPathComponent:fileName];
            } else {
                fileName = [scorePath stringByAppendingPathComponent:fileName];
            }
            BOOL generateThumbnail = ![fileManager fileExistsAtPath:fileName];
            //Need to add a fix for Big Clock previews generated before the advent of dark mode
            if (!generateThumbnail && [currentScore.scoreType isEqualToString:@"BigClock"]) {
                NSDictionary *attributes = [fileManager attributesOfItemAtPath:fileName error:nil];
                if (attributes != nil) {
                    NSDate *creationDate = [attributes objectForKey:NSFileCreationDate];
                    //2019-09-21, 07:00:00 UTC
                    if ([creationDate compare:[NSDate dateWithTimeIntervalSince1970:1569049200]] == NSOrderedAscending) {
                        generateThumbnail = YES;
                    }
                }
            }
            
            if (generateThumbnail) {
                if ([rendererClass respondsToSelector:@selector(generateThumbnailForScore:ofSize:)]) {
                    UIImage *thumbnail = [rendererClass generateThumbnailForScore:currentScore ofSize:(CGSizeMake(88, 66))];
                    if (thumbnail != nil) {
                        [UIImagePNGRepresentation(thumbnail) writeToFile:fileName atomically:YES];
                    }
                }
            }
        }
        currentScore = nil;
        return;
    }
    //If there is no currentScore then there should be no legitimate reason to set any properties.
    //The only things we should check for are opus wide options.
    if (currentScore == nil) {
        if ([elementName isEqualToString:@"updateurl"]) {
            //Do some preliminary checks on the supplied URL to make sure it isn't completely insane.
            //NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:currentString]];
            //if ([NSURLConnection canHandleRequest:request]) {
            if ([OpusParser isValidURL:currentString]) {
                updateURL = [NSString stringWithString:currentString];
            }
        } else if ([elementName isEqualToString:@"version"]) {
            if (currentString != nil) {
                opusVersion = [NSString stringWithString:currentString];
            }
        } else if ([elementName isEqualToString:@"formatversion"]) {
            if (currentString != nil) {
                formatVersion = [NSString stringWithString:currentString];
            }
        }
        isScoreProperty = NO;
        return;
    }
    if ([elementName isEqualToString:@"name"]) {
        currentScore.scoreName = [NSString stringWithString:currentString];
    } else if ([elementName isEqualToString:@"composer"]) {
        //Multiple composers for a work should be separated by a semicolon. The parser will assume that the
        //final space separates given names from surnames. This can be overruled by entering the composer in
        //the format "Surname, Firstname".
        NSArray *composers = [currentString componentsSeparatedByString:@";"];
        for (int i = 0; i < [composers count]; i++) {
            NSString *composer = [[composers objectAtIndex:i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *firstName, *lastName;
            NSRange split = [composer rangeOfString:@","];
            if (split.location != NSNotFound) {
                firstName = [[composer substringFromIndex:split.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                lastName = [[composer substringToIndex:split.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            } else {
                split = [composer rangeOfString:@" " options:NSBackwardsSearch];
                if (split.location != NSNotFound) {
                    firstName = [composer substringToIndex:split.location];
                    lastName = [composer substringFromIndex:split.location + 1];
                } else {
                    firstName = @"";
                    lastName = composer;
                }
            }
            [currentScore.composers addObject:[NSArray arrayWithObjects:lastName, firstName, nil]];
        }
    } else if ([elementName isEqualToString:@"type"]) {
        currentScore.scoreType = [NSString stringWithString:currentString];
        //Check to see that the renderer type is valid. We do this by checking that it refers to a class
        //that properly implements the RendererDelegate protocol.
        rendererClass = NSClassFromString(currentScore.scoreType);
        if (rendererClass == nil || ![rendererClass conformsToProtocol:@protocol(RendererDelegate)]) {
            scoreInvalid = YES;
        }
    } else if ([elementName isEqualToString:@"variation"]) {
        currentScore.variationNumber = [currentString integerValue];
    } else if ([elementName isEqualToString:@"duration"]) {
        currentScore.originalDuration = [currentString floatValue];
    } else if ([elementName isEqualToString:@"startoffset"]) {
        currentScore.startOffset = [currentString integerValue];
    } else if ([elementName isEqualToString:@"readoffset"]) {
        currentScore.readLineOffset = [currentString integerValue];
    } else if ([elementName isEqualToString:@"filename"]) {
        currentScore.fileName = [NSString stringWithString:currentString];
        //Check that the file actually exists. (If not set scoreInvalid)
        if (![fileManager fileExistsAtPath:[scorePath stringByAppendingPathComponent:currentScore.fileName]]) {
            scoreInvalid = YES;
        }
    } else if ([elementName isEqualToString:@"prefsfile"]) {
        currentScore.prefsFile = [NSString stringWithString:currentString];
        //Check that the file actually exists. (If not set scoreInvalid)
        if (![fileManager fileExistsAtPath:[scorePath stringByAppendingPathComponent:currentScore.prefsFile]]) {
            scoreInvalid = YES;
        }
    } else if ([elementName isEqualToString:@"instructions"]) {
        //Check that the file actually exists. (If not, then ignore and leave the property unset)
        if ([fileManager fileExistsAtPath:[scorePath stringByAppendingPathComponent:currentString]]) {
            currentScore.instructions = [NSString stringWithString:currentString];
        }
    } else if ([elementName isEqualToString:@"audiofile"]) {
        //Check that the file actually exists. (If not, then ignore and leave the property unset)
        if ([fileManager fileExistsAtPath:[scorePath stringByAppendingPathComponent:currentString]]) {
            currentScore.audioFile = [NSString stringWithString:currentString];
        }
    } else if ([elementName isEqualToString:@"options"]) {
        if (currentString != nil && [currentString caseInsensitiveCompare:@"yes"] == NSOrderedSame) {
            currentScore.allowsOptions = YES;
        }
    } else if ([elementName isEqualToString:@"part"]) {
        //Check that the part exists first
        if ([fileManager fileExistsAtPath:[scorePath stringByAppendingPathComponent:currentString]]) {
            [currentScore.parts addObject:[NSString stringWithString:currentString]];
        }
    } else if ([elementName isEqualToString:@"audiopart"]) {
        if ([fileManager fileExistsAtPath:[scorePath stringByAppendingPathComponent:currentString]]) {
            [currentScore.audioParts addObject:[NSString stringWithString:currentString]];
        }
    } else if ([elementName isEqualToString:@"manualidentifier"]) {
        if (currentString != nil && [currentString caseInsensitiveCompare:@"yes"] == NSOrderedSame) {
            currentScore.askForIdentifier = YES;
        }
    } else if ([elementName isEqualToString:@"backgroundrgb"]) {
        NSArray *colour = [currentString componentsSeparatedByString:@","];
        //Check that we have three colour components in our array
        if ([colour count] == 3) {
            CGFloat r = [[colour objectAtIndex:0] intValue] & 255;
            CGFloat g = [[colour objectAtIndex:1] intValue] & 255;
            CGFloat b = [[colour objectAtIndex:2] intValue] & 255;
            currentScore.backgroundColour = [UIColor colorWithRed:(r / 255) green:(g / 255) blue:(b / 255) alpha:1];
        }
    }
    isScoreProperty = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    [watchdog invalidate];
    //Don't allow the update URL to be set if a version hasn't been provided with the score file.
    if (opusVersion == nil) {
        updateURL = nil;
    } else {
        for (int i = 0; i < [scores count]; i++) {
            ((Score *)[scores objectAtIndex:i]).version = opusVersion;
        }
    }
    if (formatVersion != nil) {
        for (int i = 0; i < [scores count]; i++) {
            ((Score *)[scores objectAtIndex:i]).formatVersion = formatVersion;
        }
    }
    [delegate parserFinished:self withScores:scores];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    //NSString *error;
    //error = [parseError localizedDescription];
    [watchdog invalidate];
    [delegate parserError:self];
}

@end

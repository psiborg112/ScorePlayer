//
//  Loaded.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 8/04/2015.
//  Copyright (c) 2015 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "Loaded.h"
#import "Score.h"
#import "OSCMessage.h"

@interface Loaded ()

- (void)changePart:(NSInteger)relativeChange;
- (NSMutableArray *)generateOrder;
- (NSMutableArray *)generateOrderForDuration:(NSInteger)duration;
- (OSCMessage *)generateHeadlineMessageAsNew:(BOOL)new;
- (void)initLayers;
- (void)resizeLayers;

@end

@implementation Loaded {
    Score *score;
    CALayer *canvas;
    
    NSString *panelFileName;
    CGSize panelImageSize;
    NSInteger rows;
    CALayer *panel;
    CALayer *mainDisplay;
    UILabel *partNameDisplay;
    NSMutableArray *partNames;
    NSInteger currentPart;
    NSString *titleCard;
    
    UILabel *headlineDisplay;
    NSInteger textWidth;
    NSMutableArray *headlines;
    NSMutableArray *headlineOrder;
    NSString *fontName;
    CGFloat fontSize;
    BOOL allowRepeats;
    
    NSInteger headlineTime;
    BOOL clicked;
    NSInteger selectedRow;
    
    NSXMLParser *xmlParser;
    NSMutableString *currentString;
    BOOL isData;
    BOOL prefsLoaded;
    NSCondition *prefsCondition;
    BOOL badPrefs;
    NSString *errorMessage;
    xmlLocation currentPrefs;
    
    BOOL hasData;
    
    __weak id<RendererUI> UIDelegate;
    __weak id<RendererMessaging> messagingDelegate;
}

- (void)changePart:(NSInteger)relativeChange
{
    NSInteger newPart = currentPart + relativeChange;
    if (newPart > (NSInteger)[score.parts count]) {
        newPart = 0;
    } else if (newPart < 0) {
        newPart = [score.parts count];
    }
    
    if ((mainDisplay.contents != nil) && (selectedRow != 0)) {
        //We're displaying material rather than headlines. Update for our new part.
        UIImage *image;
        if (newPart == 0) {
            image = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:[score.fileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", (int)selectedRow]]]];
        } else {
            image = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:[[score.parts objectAtIndex:newPart - 1] stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", (int)selectedRow]]]];
        }
        mainDisplay.contents = (id)image.CGImage;
    }
    
    //Update our part text.
    if ([partNames count] > currentPart) {
        partNameDisplay.text = [partNames objectAtIndex:newPart];
    } else {
        partNameDisplay.text = @"";
    }
    
    currentPart = newPart;
}

- (NSMutableArray *)generateOrder
{
    return [self generateOrderForDuration:UIDelegate.clockDuration];
}

- (NSMutableArray *)generateOrderForDuration:(NSInteger)duration
{
    NSMutableArray *order = [[NSMutableArray alloc] init];
    
    if (allowRepeats) {
        NSInteger remaining = duration;
        while (remaining > 0) {
            int headlineNumber = arc4random_uniform((uint)[headlines count]);
            [order addObject:[NSNumber numberWithInt:headlineNumber]];
            remaining -= headlineTime;
        }
    } else {
        NSMutableArray *indexes = [[NSMutableArray alloc] init];
        for (int i = 0; i < [headlines count]; i++) {
            [indexes addObject:[NSNumber numberWithInt:i]];
        }
        for (int i = 0; i < duration; i += headlineTime) {
            //Safety check. (Should never be an issue.)
            if ([indexes count] > 0) {
                int index = arc4random_uniform((uint)[indexes count]);
                [order addObject:[indexes objectAtIndex:index]];
                [indexes removeObjectAtIndex:index];
            }
       }
    }
    
    return order;
}

- (OSCMessage *)generateHeadlineMessageAsNew:(BOOL)new
{
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Headlines"];
    if (new) {
        [message addStringArgument:@"New"];
    } else {
        [message addStringArgument:@"Refresh"];
    }
    
    for (int i = 0; i < [headlineOrder count]; i++) {
        [message addIntegerArgument:[[headlineOrder objectAtIndex:i] integerValue]];
    }
    
    return message;
}

- (void)initLayers
{
    partNameDisplay = [[UILabel alloc] init];
    partNameDisplay.textColor = [UIColor blackColor];
    partNameDisplay.font = [UIFont fontWithName:@"ArialMT" size:36 * UIDelegate.cueLightScale];
    partNameDisplay.textAlignment = NSTextAlignmentLeft;
    if ([partNames count] > 0) {
        partNameDisplay.text = [partNames objectAtIndex:0];
    }
    
    UIImage *panelImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:panelFileName]];
    panel = [CALayer layer];
    panelImageSize = panelImage.size;
    panel.contents = (id)panelImage.CGImage;
    
    mainDisplay = [CALayer layer];
    mainDisplay.contentsGravity = kCAGravityResizeAspect;
    mainDisplay.backgroundColor = [UIColor whiteColor].CGColor;
    
    headlineDisplay = [[UILabel alloc] init];
    headlineDisplay.textColor = [UIColor blackColor];
    headlineDisplay.font = [UIFont fontWithName:fontName size:fontSize];
    headlineDisplay.numberOfLines = 0;
    headlineDisplay.lineBreakMode = NSLineBreakByWordWrapping;
    headlineDisplay.textAlignment = NSTextAlignmentLeft;
    //headlineDisplay.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.15];
    
    [canvas addSublayer:panel];
    [canvas addSublayer:mainDisplay];
    [canvas addSublayer:partNameDisplay.layer];
}

- (void)resizeLayers
{
    NSInteger margin = 15;
    NSInteger partTextHeight = 55 * UIDelegate.cueLightScale;
    NSInteger workingHeight = canvas.bounds.size.height - LOWER_PADDING + 10 - partTextHeight;
    
    partNameDisplay.frame = CGRectMake(margin, margin - 5, canvas.bounds.size.width, partTextHeight);
    CGFloat panelScale = (workingHeight - (2 * margin)) / panelImageSize.height;
    panel.frame = CGRectMake(canvas.bounds.size.width - margin - (panelImageSize.width * panelScale), margin + partTextHeight, panelImageSize.width * panelScale, panelImageSize.height * panelScale);
    
    mainDisplay.frame = CGRectMake(margin, margin + partTextHeight, canvas.bounds.size.width - (3 * margin) - panel.bounds.size.width, workingHeight - (2 * margin));
    
    textWidth = mainDisplay.bounds.size.width - (4 * margin);
    headlineDisplay.frame = CGRectMake(2 * margin, 2 * margin, textWidth, mainDisplay.bounds.size.height - (4 * margin));
    if (headlineDisplay.text != nil) {
        [headlineDisplay sizeToFit];
    }
}

#pragma mark - Renderer delegate

- (void)setIsMaster:(BOOL)master
{
    isMaster = master;
    
    if (!isMaster) {
        //Get the order of our headlines.
        hasData = NO;
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"HeadlineRequest"];
        [messagingDelegate sendData:message];
    }
}

- (BOOL)isMaster
{
    return isMaster;
}

+ (RendererFeatures)getRendererRequirements
{
    return kPositiveDuration | kFileName | kPrefsFile | kUsesIdentifier;
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    
    isMaster = YES;
    score = scoreData;
    canvas = playerCanvas;
    UIDelegate = UIDel;
    messagingDelegate = messagingDel;
    
    UIDelegate.clockVisible = NO;
    
    partNames = [[NSMutableArray alloc] init];
    headlines = [[NSMutableArray alloc] init];
    fontName = @"TimesNewRomanPSMT";
    fontSize = 84;
    rows = 0;
    headlineTime = 0;
    currentPart = 0;
    
    //TODO: Make this part of our preference file
    allowRepeats = NO;
    
    //Load our preferences
    NSData *prefsData = [[NSData alloc] initWithContentsOfFile:[score.scorePath stringByAppendingPathComponent:score.prefsFile]];
    xmlParser = [[NSXMLParser alloc] initWithData:prefsData];
    
    isData = NO;
    currentPrefs = kTopLevel;
    prefsLoaded = NO;
    prefsCondition = [NSCondition new];
    badPrefs = NO;
    xmlParser.delegate = self;
    [xmlParser parse];
    
    hasData = YES;
    
    return self;
}

- (void)reset
{
    selectedRow = 0;
    
    [prefsCondition lock];
    while (!prefsLoaded) {
        [prefsCondition wait];
    }
    [prefsCondition unlock];
    
    if (badPrefs) {
        [UIDelegate badPreferencesFile:errorMessage];
        return;
    }
    
    if (isMaster) {
        headlineOrder = [self generateOrder];
        [messagingDelegate sendData:[self generateHeadlineMessageAsNew:YES]];
    }
    mainDisplay.sublayers = nil;
    if (titleCard != nil) {
        mainDisplay.contents = (id)[Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:titleCard]].CGImage;
    } else {
        mainDisplay.contents = nil;
    }
}

- (void)play
{
    //Show our initial headline.
    mainDisplay.contents = nil;
    headlineDisplay.text = [headlines objectAtIndex:[[headlineOrder objectAtIndex:(UIDelegate.clockProgress / headlineTime)] intValue]];
    headlineDisplay.frame = CGRectMake(headlineDisplay.frame.origin.x, headlineDisplay.frame.origin.y, textWidth, headlineDisplay.frame.size.height);
    [headlineDisplay sizeToFit];
    if (headlineDisplay.layer.superlayer != mainDisplay) {
        [mainDisplay addSublayer:headlineDisplay.layer];
    }
    clicked = NO;
    
    if (isMaster) {
        //If we're the master, send a message to any potential external that will be
        //projecting the headlines.
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"External"];
        [message appendAddressComponent:@"Projector"];
        [message addIntegerArgument:[[headlineOrder objectAtIndex:(UIDelegate.clockProgress / headlineTime)] intValue]];
        [message addStringArgument:[headlines objectAtIndex:[[headlineOrder objectAtIndex:(UIDelegate.clockProgress / headlineTime)] intValue]]];
        [messagingDelegate sendData:message];
    }
}

- (void)rotate
{
    [self resizeLayers];
}

- (CGFloat)changeDuration:(CGFloat)duration currentLocation:(CGFloat *)location
{
    //If we're not allowing repeats, make sure that our score isn't too long.
    if (!allowRepeats && (duration > ([headlines count] * headlineTime))) {
        duration = [headlines count] * headlineTime;
    }
    
    if (isMaster) {
        headlineOrder = [self generateOrderForDuration:duration];
        [messagingDelegate sendData:[self generateHeadlineMessageAsNew:YES]];
    }
    
    return duration;
}

- (void)receiveMessage:(OSCMessage *)message
{
    if (isMaster) {
        if ([message.address count] < 1) {
            return;
        }
        if ([[message.address objectAtIndex:0] isEqualToString:@"HeadlineRequest"]) {
            [messagingDelegate sendData:[self generateHeadlineMessageAsNew:NO]];
        }
    } else {
        if ([[message.address objectAtIndex:0] isEqualToString:@"Headlines"]) {
            if (![message.typeTag hasPrefix:@",s"]) {
                return;
            }
            if (!hasData || [[message.arguments objectAtIndex:0] isEqualToString:@"New"]) {
                //First check that we have the right number and type of arguments.
                NSString *typeTag = [message.typeTag substringFromIndex:2];
                NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"i"] invertedSet];
                if ([typeTag rangeOfCharacterFromSet:invalidTags].location != NSNotFound) {
                    return;
                }
                for (int i = 1; i < [message.arguments count]; i++) {
                    //Check that none of the headline numbers are out of bounds.
                    int index = [[message.arguments objectAtIndex:i] intValue];
                    if ((index < 0) || (index >= [headlines count])) {
                        return;
                    }
                }
                headlineOrder = [[NSMutableArray alloc] initWithArray:message.arguments];
                [headlineOrder removeObjectAtIndex:0];
            }
        }
    }
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    if (finished) {
        mainDisplay.sublayers = nil;
        if (titleCard != nil) {
            mainDisplay.contents = (id)[Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:titleCard]].CGImage;
        } else {
            mainDisplay.contents = nil;
        }
        return;
    }
    
    if (progress % headlineTime == 0) {
        //Display the next slide
        mainDisplay.contents = nil;
        headlineDisplay.text = [headlines objectAtIndex:[[headlineOrder objectAtIndex:(progress / headlineTime)] intValue]];
        headlineDisplay.frame = CGRectMake(headlineDisplay.frame.origin.x, headlineDisplay.frame.origin.y, textWidth, headlineDisplay.frame.size.height);
        [headlineDisplay sizeToFit];
        if (headlineDisplay.layer.superlayer != mainDisplay) {
            [mainDisplay addSublayer:headlineDisplay.layer];
        }
        clicked = NO;
        
        if (isMaster) {
            //If we're the master, send a message to any potential external that will be
            //projecting the headlines.
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"External"];
            [message appendAddressComponent:@"Projector"];
            [message addIntegerArgument:[[headlineOrder objectAtIndex:(progress / headlineTime)] intValue]];
            [message addStringArgument:[headlines objectAtIndex:[[headlineOrder objectAtIndex:(progress / headlineTime)] intValue]]];
            [messagingDelegate sendData:message];
        }
    }
}

- (void)swipeUp {
    if ([score.parts count] > 0) {
        [self changePart:1];
        [UIDelegate partChangedToPart:currentPart];
    }
}

- (void)swipeDown {
    if ([score.parts count] > 0) {
        [self changePart:-1];
        [UIDelegate partChangedToPart:currentPart];
    }
}

- (void)tapAt:(CGPoint)location
{
    //We've already made our choice
    if (clicked || UIDelegate.playerState != kPlaying) {
        return;
    }
    
    if (location.x > panel.frame.origin.x && location.x < (panel.frame.origin.x + panel.frame.size.width) && location.y > panel.frame.origin.y && location.y < (panel.frame.origin.y + panel.frame.size.height)) {
        location.x -= panel.frame.origin.x;
        location.y -= panel.frame.origin.y;
        selectedRow = ceilf(location.y * rows / panel.frame.size.height);
        BOOL clickBait = floorf(location.x * 2 / panel.frame.size.width);
        
        if (clickBait) {
            //Notify our associated external
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"External"];
            [message appendAddressComponent:UIDelegate.playerID];
            [message appendAddressComponent:@"ClickBait"];
            [messagingDelegate sendData:message];
        }
        
        UIImage *image;
        if (currentPart == 0) {
            image = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:[score.fileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", (int)selectedRow]]]];
        } else {
            image = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:[[score.parts objectAtIndex:currentPart - 1] stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", (int)selectedRow]]]];
        }
        mainDisplay.contents = (id)image.CGImage;
        [headlineDisplay.layer removeFromSuperlayer];
        clicked = YES;
    }
}

#pragma mark NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    //Determine which section of the preferences file we're in, and only parse elements that belong.
    if (currentPrefs == kTopLevel) {
        if ([elementName isEqualToString:@"panel"]) {
            currentPrefs = kPanel;
        } else if ([elementName isEqualToString:@"partnames"]) {
            currentPrefs = kPartNames;
        } else if ([elementName isEqualToString:@"duration"] || [elementName isEqualToString:@"headline"] || [elementName hasPrefix:@"font"] || [elementName isEqualToString:@"titlecard"]) {
            isData = YES;
            currentString = nil;
        }
    } else {
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
    //Read our preferences. We should do basic checks on completing each section, but will check that
    //we have all our necessary resource files once parsing has completed.
    
    switch (currentPrefs) {
        case kTopLevel:
            if ([elementName isEqualToString:@"duration"]) {
                headlineTime = [currentString integerValue];
            } else if ([elementName isEqualToString:@"headline"]) {
                [headlines addObject:[NSString stringWithString:currentString]];
            } else if ([elementName isEqualToString:@"fontsize"]) {
                fontSize = [currentString floatValue];
            } else if ([elementName isEqualToString:@"fontname"]) {
                UIFont *font = [UIFont fontWithName:currentString size:fontSize];
                if (font != nil) {
                    fontName = currentString;
                }
            } else if ([elementName isEqualToString:@"titlecard"]) {
                titleCard = [NSString stringWithString:currentString];
            }
            break;
            
        case kPanel:
            if ([elementName isEqualToString:@"filename"]) {
                panelFileName = [NSString stringWithString:currentString];
            } else if ([elementName isEqualToString:@"rows"]) {
                rows = [currentString integerValue];
            } else if ([elementName isEqualToString:@"panel"]) {
                if (rows <= 0) {
                    badPrefs = YES;
                    errorMessage = @"Invalid number of rows in side panel.";
                }
                currentPrefs = kTopLevel;
            }
            break;
            
        case kPartNames:
            if ([elementName isEqualToString:@"score"]) {
                if ([partNames count] <= [score.parts count]) {
                    [partNames insertObject:[NSString stringWithString:currentString] atIndex:0];
                }
            } else if ([elementName isEqualToString:@"part"]) {
                if ([partNames count] <= [score.parts count]) {
                    [partNames addObject:[NSString stringWithString:currentString]];
                }
            } else if ([elementName isEqualToString:@"partnames"])
                currentPrefs = kTopLevel;
            break;
            
        default:
            break;
    }
    
    isData = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    //Check basic conditions.
    if ((rows == 0) || (headlineTime <= 0) || [headlines count] == 0) {
        badPrefs = YES;
        errorMessage = @"Missing options in preference file.";
    }
    
    //Check that we have all of our necessary image files.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:[score.scorePath stringByAppendingPathComponent:panelFileName]]) {
        badPrefs = YES;
        errorMessage = @"Unable to find panel image file.";
    }
    
    //Check that we have enough images in the parts.
    for (int i = 1; i <= rows; i++) {
        NSString *fileName = [score.scorePath stringByAppendingPathComponent:[score.fileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i]]];
        if (![fileManager fileExistsAtPath:fileName]) {
            badPrefs = YES;
            errorMessage = @"Missing images in score file.";
            i = (int)rows + 1;
        }
        for (int j = 0; j < [score.parts count]; j++) {
            fileName =[score.scorePath stringByAppendingPathComponent:[[score.parts objectAtIndex:j] stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i]]];
            if (![fileManager fileExistsAtPath:fileName]) {
                badPrefs = YES;
                errorMessage = @"Missing images in score file.";
                i = (int)rows + 1;
                j = (int)[score.parts count];
            }
        }
    }
    
    //If we're not allowing repeats, make sure that our score isn't too long.
    if (!allowRepeats && (UIDelegate.clockDuration > ([headlines count] * headlineTime))) {
        UIDelegate.clockDuration = [headlines count] * headlineTime;
    }
    
    if ((titleCard != nil) && ![fileManager fileExistsAtPath:[score.scorePath stringByAppendingPathComponent:titleCard]]) {
        titleCard = nil;
    }
    
    if (titleCard != nil) {
        //Use the titlecard to create a thumbnail. It's not ideal to do it here, but it saves us having to parse
        //this preferences file elsewhere.
        NSString *fileName = [NSString stringWithFormat:@".%@.%@.thumbnail.png", score.composerFullText, score.scoreName];
        fileName = [fileName stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
        fileName = [fileName stringByReplacingOccurrencesOfString:@":" withString:@"."];
        fileName = [score.scorePath stringByAppendingPathComponent:fileName];
        if (![fileManager fileExistsAtPath:fileName]) {
            UIImage *thumbnail = [Renderer defaultThumbnail:[score.scorePath stringByAppendingPathComponent:titleCard] ofSize:(CGSizeMake(88, 66))];
            [UIImagePNGRepresentation(thumbnail) writeToFile:fileName atomically:YES];
        }
    }
    
    if (!badPrefs) {
        [self initLayers];
        [self resizeLayers];
    }
    
    [prefsCondition lock];
    prefsLoaded = YES;
    [prefsCondition signal];
    [prefsCondition unlock];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    badPrefs = YES;
    errorMessage = @"Damaged preferences file.";
    parser.delegate = nil;
    xmlParser = nil;
    [prefsCondition lock];
    prefsLoaded = YES;
    [prefsCondition signal];
    [prefsCondition unlock];
}

@end

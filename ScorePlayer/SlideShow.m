//
//  SlideShow.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/08/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "SlideShow.h"
#import "Score.h"
#import "OSCMessage.h"

@interface SlideShow ()

- (void)displaySlide:(int)slideNumber;
- (void)changePart:(NSInteger)relativeChange;
- (NSMutableArray *)getChangesForPart:(NSInteger)partNumber;
- (int)getCurrentSlideForPart:(NSInteger)partNumber atPosition:(int)progress;
- (BOOL)checkNumberOfSlidesForPart:(NSInteger)partNumber;
- (void)setUpAnnotationMask;

@end

@implementation SlideShow {
    Score *score;
    CALayer *canvas;
    CALayer *annotationLayer;
    CALayer *annotationLayerA;
    CALayer *annotationLayerB;
    CALayer *annotationMaskLayer;
    
    int *currentSlide;
    NSInteger *slideCount;
    CALayer *slideLayerA;
    CALayer *slideLayerB;
    CALayer *splitLine;
    NSMutableArray *changes;
    NSMutableDictionary *partChanges;
    NSMutableArray *currentChanges;
    NSInteger currentPart;
    BOOL wrapAround;
    BOOL hasSlideNumber;
    BOOL splitMode;
    BOOL linkedParts;
    
    NSString *annotationsDirectory;
    NSString *annotationsFileName;
    NSString *annotationsFileNameB;
    
    NSXMLParser *xmlParser;
    NSMutableString *currentString;
    BOOL isData;
    BOOL partDefinition;
    BOOL prefsLoaded;
    NSCondition *prefsCondition;
    BOOL badPrefs;
    NSString *errorMessage;
    
    __weak id<RendererUI> UIDelegate;
    __weak id<RendererMessaging> messagingDelegate;
}

- (void)displaySlide:(int)slideNumber
{
    //The displaySlide function uses the currentPart variable, so make sure this is up to date before calling.
    if (slideNumber > slideCount[currentPart] || slideNumber < 1) {
        //Invalid argument
        return;
    }
    
    NSString *baseFileName;
    if (currentPart == 0) {
        baseFileName = [score.scorePath stringByAppendingPathComponent:[score.fileName stringByDeletingPathExtension]];
    } else {
        baseFileName = [score.scorePath stringByAppendingPathComponent:[[score.parts objectAtIndex:currentPart - 1] stringByDeletingPathExtension]];
    }
    NSString *newFileName, *newFileNameB;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    //Try for a png file first, otherwise we've got a jpg.
    if ([fileManager fileExistsAtPath:[baseFileName stringByReplacingOccurrencesOfString:@"_1" withString:[NSString stringWithFormat:@"_%i.png" , slideNumber]]]) {
        newFileName = [baseFileName stringByReplacingOccurrencesOfString:@"_1" withString:[NSString stringWithFormat:@"_%i.png" , slideNumber]];
    } else {
        newFileName = [baseFileName stringByReplacingOccurrencesOfString:@"_1" withString:[NSString stringWithFormat:@"_%i.jpg" , slideNumber]];
    }
    
    if (splitMode) {
        if ([fileManager fileExistsAtPath:[baseFileName stringByReplacingOccurrencesOfString:@"_1" withString:[NSString stringWithFormat:@"_%i.png" , slideNumber + 1]]]) {
            newFileNameB = [baseFileName stringByReplacingOccurrencesOfString:@"_1" withString:[NSString stringWithFormat:@"_%i.png" , slideNumber + 1]];
        } else {
            newFileNameB = [baseFileName stringByReplacingOccurrencesOfString:@"_1" withString:[NSString stringWithFormat:@"_%i.jpg" , slideNumber + 1]];
        }
    }
    
    if (annotationsDirectory != nil) {
        annotationsFileName = [[annotationsDirectory stringByAppendingPathComponent:[baseFileName lastPathComponent]] stringByAppendingPathExtension:@"png"];
        if (splitMode) {
            annotationsFileNameB = [annotationsFileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i." , slideNumber + 1]];
        }
        annotationsFileName = [annotationsFileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i." , slideNumber]];
    }
    
    //Now load the image into our layer
    canvas.sublayers = nil;
    UIImage *slideImage = [Renderer cachedImage:newFileName];
    UIImage *slideImageB;
    if (splitMode) {
        slideImageB = [Renderer cachedImage:newFileNameB];
    }
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (splitMode) {
        if (slideNumber % 2 == 1) {
            slideLayerA.contents = (id)slideImage.CGImage;
            slideLayerB.contents = (id)slideImageB.CGImage;
            annotationLayerA.contents = (id)[UIImage imageWithContentsOfFile:annotationsFileName].CGImage;
            annotationLayerB.contents = (id)[UIImage imageWithContentsOfFile:annotationsFileNameB].CGImage;
        } else {
            slideLayerA.contents = (id)slideImageB.CGImage;
            slideLayerB.contents = (id)slideImage.CGImage;
            annotationLayerA.contents = (id)[UIImage imageWithContentsOfFile:annotationsFileNameB].CGImage;
            annotationLayerB.contents = (id)[UIImage imageWithContentsOfFile:annotationsFileName].CGImage;
            
            //Swap our names so that B always refers to our bottom panel.
            NSString *nameSwap = annotationsFileName;
            annotationsFileName = annotationsFileNameB;
            annotationsFileNameB = nameSwap;
        }
    } else {
        slideLayerA.contents = (id)slideImage.CGImage;
        if (annotationsDirectory != nil) {
            annotationLayer.contents = (id)[UIImage imageWithContentsOfFile:annotationsFileName].CGImage;
        }
    }
    [CATransaction commit];
    
    [canvas addSublayer:slideLayerA];
    if (splitMode) {
        [canvas addSublayer:slideLayerB];
        [canvas addSublayer:splitLine];
    }
    [canvas addSublayer:annotationLayer];
    
    if (linkedParts && UIDelegate.clockDuration <= 0) {
        currentSlide[0] = slideNumber;
    } else {
        currentSlide[currentPart] = slideNumber;
    }
}

- (void)changePart:(NSInteger)relativeChange
{
    NSInteger newPart = currentPart + relativeChange;
    if (newPart > (NSInteger)[score.parts count]) {
        newPart = 0;
    } else if (newPart < 0) {
        newPart = [score.parts count];
    }
    
    currentPart = newPart;
    if (UIDelegate.clockDuration > 0) {
        //The tick function only checks for changes in the current part.
        //As a result, the current slide must be updated when changing parts.
        currentChanges = [self getChangesForPart:currentPart];
        int newSlide = [self getCurrentSlideForPart:currentPart atPosition:UIDelegate.clockProgress];
        [self displaySlide:newSlide];
    } else {
        if (linkedParts) {
            [self displaySlide:currentSlide[0]];
        } else {
            [self displaySlide:currentSlide[currentPart]];
        }
    }
}

- (NSMutableArray *)getChangesForPart:(NSInteger)partNumber
{
    if (partNumber > [score.parts count] || UIDelegate.clockDuration <= 0) {
        return nil;
    }
    
    if ([partChanges objectForKey:[NSNumber numberWithInteger:partNumber]] != nil) {
        return [partChanges objectForKey:[NSNumber numberWithInteger:partNumber]];
    } else {
        return changes;
    }
}

- (int)getCurrentSlideForPart:(NSInteger)partNumber atPosition:(int)progress
{
    //This should not be called in non timed mode. For now, just return the first slide.
    if (UIDelegate.clockDuration <= 0) {
        return 1;
    }
    
    int slide = 1;
    
    while (slide < slideCount[partNumber] && [[[self getChangesForPart:partNumber] objectAtIndex:slide - 1] intValue] <= progress) {
        slide++;
    }
    return slide;
}

- (BOOL)checkNumberOfSlidesForPart:(NSInteger)partNumber
{
    //If our part number is 0, check all of the parts.
    if (partNumber == 0) {
        for (int i = 0; i < [score.parts count]; i++) {
            if (slideCount[i + 1] != slideCount[0]) {
                return NO;
            }
        }
        return YES;
    } else {
        //Otherwise check the specific part. (Index starting at 1.)
        if (partNumber <= [score.parts count]) {
            return (slideCount[partNumber] == slideCount[0]);
        } else {
            return NO;
        }
    }
}

- (void)setUpAnnotationMask
{
    annotationMaskLayer.frame = annotationLayer.frame;
    CALayer *maskA = [CALayer layer];
    maskA.frame = annotationLayerA.frame;
    maskA.backgroundColor = [UIColor blackColor].CGColor;
    CALayer *maskB = [CALayer layer];
    maskB.frame = annotationLayerB.frame;
    maskB.backgroundColor = [UIColor blackColor].CGColor;
    [annotationMaskLayer addSublayer:maskA];
    [annotationMaskLayer addSublayer:maskB];
}

#pragma mark - UIDelegate

- (void)setIsMaster:(BOOL)master
{
    isMaster = master;
    if (!(isMaster || UIDelegate.clockDuration > 0)) {
        //We need to send a request to find out which slide we're on.
        hasSlideNumber = NO;
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"SlideNumberRequest"];
        [messagingDelegate sendData:message];
    }
}

- (BOOL)isMaster {
    return isMaster;
}

+ (RendererFeatures)getRendererRequirements
{
    return kFileName;
}

+ (UIImage *)generateThumbnailForScore:(Score *)score ofSize:(CGSize)size
{
    return [Renderer defaultThumbnail:[score.scorePath stringByAppendingPathComponent:score.fileName] ofSize:size];
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    
    isMaster = YES;
    score = scoreData;
    canvas = playerCanvas;
    UIDelegate = UIDel;
    messagingDelegate = messagingDel;
    UIDelegate.allowClockChange = NO;
    hasSlideNumber = YES;
    prefsLoaded = NO;
    prefsCondition = [NSCondition new];
    badPrefs = NO;
    currentPart = 0;
    
    //By default, don't go back to the start from the last slide
    //(Will add a way to configure this later.)
    wrapAround = NO;
    
    //Split mode is only implemented for timed mode at the moment.
    splitMode = NO;
    
    //If we have parts in non timed mode, assume that all of the parts are split in the same way.
    linkedParts = YES;
    
    //Set up the slide layer
    slideLayerA = [CALayer layer];
    
    //Leave space for the location slider if we're running in timed mode.
    if (UIDelegate.clockDuration <= 0) {
        slideLayerA.frame = CGRectMake(0, 0, canvas.bounds.size.width, canvas.bounds.size.height - UIDelegate.navigationHeight - UIDelegate.statusHeight - LOWER_PADDING);\
    } else {
        slideLayerA.frame = CGRectMake(0, 0, canvas.bounds.size.width, canvas.bounds.size.height - LOWER_PADDING);
        //Also set up our annotation layer in timed mode.
        annotationLayer = [CALayer layer];
        annotationLayer.frame = slideLayerA.frame;
    }
    slideLayerA.contentsGravity = kCAGravityResizeAspect;
    
    //Determine how many images we have. (Slides can be .png or .jpg files.)
    if (!slideCount) {
        slideCount = malloc(sizeof(NSInteger) * ([score.parts count] + 1));
    }
    slideCount[0] = 1;
    NSString *baseFileName = [score.scorePath stringByAppendingPathComponent:[score.fileName stringByDeletingPathExtension]];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    while ([fileManager fileExistsAtPath:[baseFileName stringByReplacingOccurrencesOfString:@"_1" withString:[NSString stringWithFormat:@"_%i.png" , (int)slideCount[0] + 1]]] || [fileManager fileExistsAtPath:[baseFileName stringByReplacingOccurrencesOfString:@"_1" withString:[NSString stringWithFormat:@"_%i.jpg" , (int)slideCount[0] + 1]]]) {
        slideCount[0]++;
    }
    //Do the same thing for any parts we might have.
    for (int i = 0; i < [score.parts count]; i++) {
        slideCount[i + 1] = 0;
        baseFileName = [score.scorePath stringByAppendingPathComponent:[[score.parts objectAtIndex:i] stringByDeletingPathExtension]];
        while ([fileManager fileExistsAtPath:[baseFileName stringByReplacingOccurrencesOfString:@"_1" withString:[NSString stringWithFormat:@"_%i.png" , (int)slideCount[i + 1] + 1]]] || [fileManager fileExistsAtPath:[baseFileName stringByReplacingOccurrencesOfString:@"_1" withString:[NSString stringWithFormat:@"_%i.jpg" , (int)slideCount[i + 1] + 1]]]) {
            slideCount[i + 1]++;
        }
    }
    
    if (!currentSlide) {
        currentSlide = malloc(sizeof(int) * ([score.parts count] + 1));
    }
    
    //Load additional options and the change times from our preferences file.
    if (UIDelegate.clockDuration > 0 && (score.prefsFile == nil)) {
        //If we're in timed mode we need a preferences file.
        badPrefs = YES;
        errorMessage = @"Missing preferences file.";
    } else if (score.prefsFile != nil) {
        changes = [[NSMutableArray alloc] init];
        currentChanges = changes;
        NSString *prefsFile = [score.scorePath stringByAppendingPathComponent:score.prefsFile];
        NSData *prefsData = [[NSData alloc] initWithContentsOfFile:prefsFile];
        xmlParser = [[NSXMLParser alloc] initWithData:prefsData];
        
        isData = NO;
        partDefinition = NO;
        xmlParser.delegate = self;
        [xmlParser parse];
    } else {
        prefsLoaded = YES;
        //Check if we have parts. If we do, make sure we have the right number of slides for each part.
        if ([score.parts count] > 0 && ![self checkNumberOfSlidesForPart:0]) {
            badPrefs = YES;
            errorMessage = @"Parts have mismatching number of slides.";
        }
    }
    
    return self;
}

- (void)close
{
    free(slideCount);
    free(currentSlide);
}

- (void)reset
{
    [prefsCondition lock];
    while (!prefsLoaded) {
        [prefsCondition wait];
    }
    [prefsCondition unlock];
    
    if (badPrefs) {
        [UIDelegate badPreferencesFile:errorMessage];
        return;
    }
    
    if (UIDelegate.clockDuration <= 0) {
        [UIDelegate setStaticScoreUI];
    }
    
    //Reset all currentSlide variables.
    for (int i = 0; i <= [partChanges count]; i++) {
        currentSlide[i] = 1;
    }
    
    [self displaySlide:1];
}

- (void)play
{
    //Don't need to do anything here. It's all handled by the tick function.
}

- (void)stop
{
    //See above.
}

- (void)seek:(CGFloat)location
{
    if (UIDelegate.clockDuration <= 0) {
        //This shouldn't be getting called.
        return;
    }

    int newSlide = [self getCurrentSlideForPart:currentPart atPosition:roundf(location * UIDelegate.clockDuration)];
    
    if (newSlide != currentSlide[currentPart]) {
        [self displaySlide:newSlide];
    }
}

- (void)rotate
{
    //Resize here for our new orientation.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (UIDelegate.clockDuration <= 0) {
        slideLayerA.frame = CGRectMake(0, 0, canvas.bounds.size.width, canvas.bounds.size.height - UIDelegate.navigationHeight - UIDelegate.statusHeight - LOWER_PADDING);
    } else {
        if (splitMode) {
            slideLayerA.frame = CGRectMake(0, 0, canvas.bounds.size.width, (canvas.bounds.size.height - LOWER_PADDING) / 2);
            slideLayerB.frame = CGRectMake(0, slideLayerA.bounds.size.height, canvas.bounds.size.width, slideLayerA.bounds.size.height);
            splitLine.position = CGPointMake(0, slideLayerA.bounds.size.height);
            annotationLayerA.frame = CGRectMake(0, 0, slideLayerA.bounds.size.width, slideLayerA.bounds.size.height - 2);
            annotationLayerB.frame = CGRectMake(0, slideLayerB.frame.origin.y + 2, slideLayerB.bounds.size.width, slideLayerB.bounds.size.height - 2);
            
            annotationMaskLayer.sublayers = nil;
            [self setUpAnnotationMask];
        } else {
            slideLayerA.frame = CGRectMake(0, 0, canvas.bounds.size.width, canvas.bounds.size.height - LOWER_PADDING);
            annotationLayer.frame = slideLayerA.frame;
        }
    }
    [CATransaction commit];
}

- (void)receiveMessage:(OSCMessage *)message
{
    if (UIDelegate.clockDuration > 0) {
        //We shouldn't be using network messages in timed mode.
        return;
    }
    
    if ([message.address count] < 1) {
        return;
    }
    
    //Process messages to change the current slide whether we're the master or not.
    if ([[message.address objectAtIndex:0] isEqualToString:@"DisplaySlide"]) {
        NSString *typeTag = [message.typeTag substringFromIndex:1];
        NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"i"] invertedSet];
        if ([typeTag rangeOfCharacterFromSet:invalidTags].location != NSNotFound) {
            return;
        }
        
        //If our parts are linked we don't need to worry about which part we're currently displaying.
        if (linkedParts && typeTag.length == 1) {
            [self displaySlide:[[message.arguments objectAtIndex:0] intValue]];
        } else if (!linkedParts) {
            //Otherwise we do. Update the display if needed, or simply the associated array member.
            int index;
            if (typeTag.length == 1) {
                index = 0;
            } else if (typeTag.length == 2) {
                index = [[message.arguments objectAtIndex:1] intValue];
            } else {
                return;
            }
            
            if (currentPart == index) {
                [self displaySlide:[[message.arguments objectAtIndex:0] intValue]];
            } else {
                currentSlide[index] = [[message.arguments objectAtIndex:0] intValue];
            }
        }
    }
    
    //If we're the master, also process requests to get the current slide number.
    if (isMaster) {
        if ([[message.address objectAtIndex:0] isEqualToString:@"SlideNumberRequest"]) {
            OSCMessage *response = [[OSCMessage alloc] init];
            [response appendAddressComponent:@"CurrentSlide"];
            [response addIntegerArgument:currentSlide[0]];
            if (!linkedParts && ([score.parts count] > 0)) {
                for (int i = 1; i <= [score.parts count]; i++) {
                    [response addIntegerArgument:currentSlide[i]];
                }
            }
            [messagingDelegate sendData:response];
        }
    } else {
        //If we're waiting for a slide number, process that request here
        if (!hasSlideNumber && [[message.address objectAtIndex:0] isEqualToString:@"CurrentSlide"]) {
            NSString *typeTag = [message.typeTag substringFromIndex:1];
            NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"i"] invertedSet];
            if ([typeTag rangeOfCharacterFromSet:invalidTags].location != NSNotFound) {
                return;
            }
            
            if (linkedParts && typeTag.length == 1) {
                [self displaySlide:[[message.arguments objectAtIndex:0] intValue]];
                hasSlideNumber = YES;
            } else if (!linkedParts && (typeTag.length == [score.parts count] + 1)) {
                for (int i = 0; i <= [score.parts count]; i++) {
                    if (currentPart == i) {
                        [self displaySlide:[[message.arguments objectAtIndex:i] intValue]];
                    } else {
                        currentSlide[i] = [[message.arguments objectAtIndex:i] intValue];
                    }
                }
                hasSlideNumber = YES;
            }
        }
    }
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    if (UIDelegate.clockDuration <= 0) {
        //We shouldn't be here
        return;
    }
    
    //If we're on the last slide our work here is done
    if (currentSlide[currentPart] == slideCount[currentPart]) {
        return;
    }
    
    if (progress >= [[currentChanges objectAtIndex:currentSlide[currentPart] - 1] intValue]) {
        [self displaySlide:currentSlide[currentPart] + 1];
    }
}

- (UIImage *)currentAnnotationImage
{
    CGSize sizeWithoutPadding = CGSizeMake(canvas.bounds.size.width, canvas.bounds.size.height - LOWER_PADDING);
    UIGraphicsBeginImageContextWithOptions(canvas.bounds.size, NO, 1);
    UIImage *content = [UIImage imageWithContentsOfFile:annotationsFileName];
    if (!splitMode) {
        [content drawInRect:CGRectMake(0, 0, sizeWithoutPadding.width, sizeWithoutPadding.height)];
    } else {
        [content drawInRect:CGRectMake(0, 0, sizeWithoutPadding.width, (sizeWithoutPadding.height / 2) - 2)];
        content = [UIImage imageWithContentsOfFile:annotationsFileNameB];
        [content drawInRect:CGRectMake(0, (sizeWithoutPadding.height / 2) + 2, sizeWithoutPadding.width, (sizeWithoutPadding.height / 2) - 2)];
    }
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (CALayer *)currentAnnotationMask
{
    return annotationMaskLayer;
}

- (void)saveCurrentAnnotation:(UIImage *)image
{
    //Use our landscape size for our saved image.
    CGSize landscapeSize = CGSizeMake(MAX(canvas.bounds.size.width, canvas.bounds.size.height), MIN(canvas.bounds.size.width, canvas.bounds.size.height));
    CGSize sizeWithoutPadding = CGSizeMake(landscapeSize.width, landscapeSize.height - roundf(LOWER_PADDING * canvas.bounds.size.width / landscapeSize.width));
    
    if (!splitMode) {
        UIGraphicsBeginImageContextWithOptions(sizeWithoutPadding, NO, 1);
        [image drawInRect:CGRectMake(0, 0, landscapeSize.width, landscapeSize.height)];
        UIImage *annotations = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        annotationLayer.contents = (id)annotations.CGImage;
        [UIImagePNGRepresentation(annotations) writeToFile:annotationsFileName atomically:YES];
    } else {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(sizeWithoutPadding.width, (sizeWithoutPadding.height / 2) - 2), NO, 1);
        [image drawInRect:CGRectMake(0, 0, landscapeSize.width, landscapeSize.height)];
        UIImage *annotations = UIGraphicsGetImageFromCurrentImageContext();
        annotationLayerA.contents = (id)annotations.CGImage;
        [UIImagePNGRepresentation(annotations) writeToFile:annotationsFileName atomically:YES];
        [image drawInRect:CGRectMake(0, (-sizeWithoutPadding.height / 2) - 2, landscapeSize.width, landscapeSize.height) blendMode:kCGBlendModeCopy alpha:1];
        annotations = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        annotationLayerB.contents = (id)annotations.CGImage;
        [UIImagePNGRepresentation(annotations) writeToFile:annotationsFileNameB atomically:YES];
    }
}

- (void)hideSavedAnnotations:(BOOL)hide
{
    if (hide) {
        annotationLayer.opacity = 0;
    } else {
        annotationLayer.opacity = 1;
    }
}


- (void)swipeUp
{
    if ([score.parts count] > 0) {
        [self changePart:1];
        [UIDelegate partChangedToPart:currentPart];
    }
}

- (void)swipeDown
{
    if ([score.parts count] > 0) {
        [self changePart:-1];
        [UIDelegate partChangedToPart:currentPart];
    }
}

- (void)swipeLeft
{
    //We don't need to deal with manual slide changes in timed mode.
    if (UIDelegate.clockDuration > 0) {
        return;
    }
    
    int newSlide;
    int index = 0;
    
    if (!linkedParts) {
        index = (int)currentPart;
    }
    
    if (currentSlide[index] == slideCount[index]) {
        if (wrapAround) {
            newSlide = 1;
        } else {
            return;
        }
    } else {
        newSlide = currentSlide[index] + 1;
    }
    
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"DisplaySlide"];
    [message addIntegerArgument:newSlide];
    if (!linkedParts && (index != 0)) {
        [message addIntegerArgument:index];
    }
    [messagingDelegate sendData:message];
}

- (void)swipeRight
{
    if (UIDelegate.clockDuration > 0) {
        return;
    }
    
    int newSlide;
    int index = 0;
    
    if (!linkedParts) {
        index = (int)currentPart;
    }

    if (currentSlide[index] == 1) {
        if (wrapAround) {
            newSlide = (int)slideCount[index];
        } else {
            return;
        }
    } else {
        newSlide = currentSlide[index] - 1;
    }
    
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"DisplaySlide"];
    [message addIntegerArgument:newSlide];
    if (!linkedParts && (index != 0)) {
        [message addIntegerArgument:index];
    }
    [messagingDelegate sendData:message];
}

#pragma mark - NSXMLparser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if ([elementName isEqualToString:@"change"] || [elementName isEqualToString:@"split"] || [elementName isEqualToString:@"linkedparts"]) {
        isData = YES;
        currentString = nil;
    } else if ([elementName isEqualToString:@"part"] && UIDelegate.clockDuration > 0) {
        partDefinition = YES;
        currentPart = 0;
        currentChanges = [[NSMutableArray alloc] init];
        if (partChanges == nil) {
            partChanges = [[NSMutableDictionary alloc] init];
        }
    } else if (partDefinition && [elementName isEqualToString:@"number"]) {
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
    //Make sure we only process options relevant to whether we're in timed mode or not.
    if ([elementName isEqualToString:@"change"] && UIDelegate.clockDuration > 0) {
        int change = [currentString intValue];
        
        //Check that we don't have more changes than available slides, and that the next change
        //occurs after the previous one.
        if ([currentChanges count] < slideCount[currentPart] - 1 && change > [[currentChanges lastObject] intValue]) {
            [currentChanges addObject:[NSNumber numberWithInt:change]];
        }
    } else if ([elementName isEqualToString:@"split"]) {
        if (currentString != nil && [currentString caseInsensitiveCompare:@"yes"] == NSOrderedSame && UIDelegate.clockDuration > 0) {
            splitMode = YES;
        }
    } else if ([elementName isEqualToString:@"linkedparts"]) {
        if (currentString != nil && [currentString caseInsensitiveCompare:@"no"] == NSOrderedSame && UIDelegate.clockDuration <= 0) {
            linkedParts = NO;
        }
    } else if ([elementName isEqualToString:@"number"] && partDefinition) {
        currentPart = [currentString integerValue];
    } else if ([elementName isEqualToString:@"part"] && partDefinition) {
        if (currentPart == 0) {
            badPrefs = YES;
            errorMessage = @"Missing part number.";
        } else if ([partChanges objectForKey:[NSNumber numberWithInteger:currentPart]] != nil) {
            badPrefs = YES;
            errorMessage = @"Duplicate part definition.";
        } else {
            [partChanges setObject:currentChanges forKey:[NSNumber numberWithInteger:currentPart]];
        }
        partDefinition = NO;
        currentChanges = changes;
    }
    isData = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    //Most of our final set up only needs to happen in timed mode.
    if (UIDelegate.clockDuration > 0) {
        //Set up split mode if we have at least two slides for each part.
        if (splitMode && !badPrefs) {
            for (int i = 0; i <= [score.parts count]; i++) {
                if (slideCount[0] < 2) {
                    splitMode = NO;
                    i = (int)[score.parts count] + 1;
                }
            }
        }
        
        if (splitMode && !badPrefs) {
            //Reduce slidecount by one and make sure we don't have too many changes.
            for (int i = 0; i <= [score.parts count]; i++) {
                slideCount[i]--;
                
                currentChanges = [self getChangesForPart:i];
                if (i != 0 && currentChanges == changes) {
                    //If we don't have part specific changes for a given part, make sure that it
                    //has the same number of slides as our score.
                    if (![self checkNumberOfSlidesForPart:i]) {
                        badPrefs = YES;
                        errorMessage = @"Parts without separate definitions have mismatching numbers of slides.";
                        i = (int)[score.parts count] + 1;
                    }
                }
                
                if ([currentChanges count] == slideCount[i]) {
                    [currentChanges removeLastObject];
                }
            }
            
            slideLayerB = [CALayer layer];
            slideLayerA.frame = CGRectMake(0, 0, canvas.bounds.size.width, (canvas.bounds.size.height - LOWER_PADDING) / 2);
            slideLayerB.frame = CGRectMake(0, slideLayerA.bounds.size.height, canvas.bounds.size.width, slideLayerA.bounds.size.height);
            slideLayerB.contentsGravity = kCAGravityResizeAspect;
            
            //Set up our split annotation layers
            annotationLayerA = [CALayer layer];
            annotationLayerA.frame = CGRectMake(0, 0, slideLayerA.bounds.size.width, slideLayerA.bounds.size.height - 2);
            //annotationLayerA.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.15].CGColor;
            annotationLayerB = [CALayer layer];
            annotationLayerB.frame = CGRectMake(0, slideLayerB.frame.origin.y + 2, slideLayerB.bounds.size.width, slideLayerB.bounds.size.height - 2);
            //annotationLayerB.backgroundColor = [UIColor colorWithRed:0 green:0 blue:1 alpha:0.15].CGColor;
            [annotationLayer addSublayer:annotationLayerA];
            [annotationLayer addSublayer:annotationLayerB];
            
            annotationMaskLayer = [CALayer layer];
            [self setUpAnnotationMask];
            
            splitLine = [CALayer layer];
            splitLine.frame = CGRectMake(0, 0, MAX(canvas.bounds.size.width, canvas.bounds.size.height), 4);
            splitLine.anchorPoint = CGPointMake(0, 0.5);
            splitLine.position = CGPointMake(0, slideLayerA.bounds.size.height);
            splitLine.backgroundColor = [UIColor blackColor].CGColor;
        }
        
        if (!badPrefs) {
            for (int i = 0; i <= [score.parts count]; i++) {
                currentChanges = [self getChangesForPart:i];
                if ([currentChanges count] < slideCount[i] - 1) {
                    //Drop any slides that won't be shown from the tally.
                    slideCount[i] = [currentChanges count] + 1;
                }
            }
        }
        
        if (!badPrefs) {
            //Only enable annotations in timed mode for the moment.
            annotationsDirectory = [Renderer getAnnotationsDirectoryForScore:score];
            if (annotationsDirectory != nil) {
                UIDelegate.canAnnotate = YES;
            }
        }
        currentPart = 0;
        currentChanges = changes;
    } else if (linkedParts && ![self checkNumberOfSlidesForPart:0]) {
        badPrefs = YES;
        errorMessage = @"Parts have mismatching number of slides.";
    }
    
    [prefsCondition lock];
    prefsLoaded = YES;
    [prefsCondition signal];
    [prefsCondition unlock];
    parser.delegate = nil;
    xmlParser = nil;
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

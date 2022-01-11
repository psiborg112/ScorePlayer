//
//  ScrollScore.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 13/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "ScrollScore.h"
#import "Score.h"
#import "OSCMessage.h"

@interface ScrollScore ()

- (void)animate;
- (void)enableHighResTimer:(BOOL)enabled;
- (void)enableHighResTimer:(BOOL)enabled withSpeedMultiplier:(CGFloat)speed;
- (void)changePart:(NSInteger)relativeChange;
- (void)randomizeMiddleForDuration:(CGFloat)duration;
- (OSCMessage *)createFragmentsMessageAsNew:(BOOL)new;
- (void)jumpToNextFragment;
- (void)countIn;
- (void)sendScrollerData;
- (BOOL)setAnnotationsDirectory;
- (void)initLayers;

@end

@implementation ScrollScore {
    Score *score;
    CALayer *superCanvas;
    CALayer *canvas;
    CALayer *readLine;
    CALayer *middleIndicator;
    CGFloat middleIndicatorRadius;
    ScrollOrientation orientation;
    //CALayer *scroller;
    id<ScrollerDelegate> scroller;
    NSString *scrollerType;
    NSMutableDictionary *scrollerOptions;
    CGFloat maxScaleFactor;
    CGFloat scoreScaleFactor;
    
    BOOL isTiled;
    NSInteger numberOfTiles;

    NSTimer *highRes;
    NSInteger pixelsPerShift;
    BOOL firstLoad;
    NSTimer *countIn;
    int countRemaining;
    
    CGFloat oldDuration;
    NSInteger middleDuration;
    BOOL liminumMode;
    BOOL juanitaMode;
    int minFragmentLength;
    int maxFragmentLength;
    CGFloat minFragmentSpeed;
    CGFloat maxFragmentSpeed;
    int pauseLength;
    int direction;
    int currentSection;
    
    //To be able to detach the renderer, a working and up to date copy of
    //these variables are kept.
    CGFloat graphicDuration;
    CGFloat newGraphicDuration;
    NSMutableArray *workingSectionBoundaries;
    NSMutableArray *workingFragments;
    NSMutableArray *latestSectionBoundaries;
    NSMutableArray *latestFragments;
    
    int fragmentIndex;
    int nextFragmentChange;
    BOOL hasData;
    BOOL awaitingSeek;
    BOOL hasScrollerData;
    NSTimer *retryDataRequest;
    int retries;
    
    CGFloat newMinimumSliderValue;

    NSInteger currentPart;
    NSInteger yOffset;
    NSInteger startOffset;
    NSInteger initOffset;
    NSInteger readLineOffset;
    NSInteger padding;
    
    ReadLineStyle readLineStyle;
    ReadLineAlignment readLineAlignment;
    UIColor *readLineColour;
    NSString *readLineImageName;
    CGSize readLineImageSize;
    BOOL hideReadLine;
    
    NSXMLParser *xmlParser;
    NSMutableString *currentString;
    BOOL isData;
    BOOL prefsLoaded;
    NSCondition *prefsCondition;
    BOOL badPrefs;
    NSString *errorMessage;
    xmlLocation currentPrefs;
    
    BOOL syncNextTick;
    
    __weak id<RendererUI> UIDelegate;
    __weak id<RendererMessaging> messagingDelegate;
}

- (void)animate
{
    //Calculate the new x coordinate of the scoller. Do this before actually moving the layer
    //so that we can check that we're not going to overshoot the final position if moving multiple
    //pixels as a time.
    int scrollerX = scroller.x - (direction * pixelsPerShift);
    //scroller.position = CGPointMake(scroller.position.x - (direction * pixelsPerShift), yOffset);
    switch (currentSection) {
        case 0:
            if (scrollerX <= readLineOffset - scroller.width) {
                scroller.x = readLineOffset - scroller.width;
                if (!(liminumMode || juanitaMode)) {
                    [self enableHighResTimer:NO];
                }
            } else {
                scroller.x = scrollerX;
            }
            break;
        case 1:
            scroller.x = scrollerX;
            break;
        case 2:
            if (scrollerX >= readLineOffset - startOffset) {
                scroller.x = readLineOffset - startOffset;
                [self enableHighResTimer:NO];
            } else {
                scroller.x = scrollerX;
            }
            break;
        default:
            break;
    }
}

- (void)enableHighResTimer:(BOOL)enabled
{
    [self enableHighResTimer:enabled withSpeedMultiplier:1];
}

- (void)enableHighResTimer:(BOOL)enabled withSpeedMultiplier:(CGFloat)speed
{
    if (speed == 0) {
        //We shouldn't be here.
        return;
    }
    
    if (enabled) {
        //If our high resolution timer already exists, invalidate it.
        if (highRes != nil) {
            [highRes invalidate];
        }
        highRes = [NSTimer scheduledTimerWithTimeInterval:(pixelsPerShift * graphicDuration / ((scroller.width - startOffset) * speed)) target:self selector:@selector(animate) userInfo:nil repeats:YES];
    } else {
        if (highRes != nil) {
            [highRes invalidate];
            highRes = nil;
        }
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
    
    int originalWidth = ([scroller originalSize]).width;
    //int originalHeight = ([scroller originalSize]).height;
    
    //Get our current position before changing any dimensions. This is offset to the left by the distance
    //to the reading line to optimize calculations.
    CGFloat unscaledPosition = ((scroller.x - readLineOffset) * originalWidth / scroller.width);
    
    [self enableHighResTimer:NO];
    [scroller.background removeAllAnimations];
    
    //Hide the scroller while we change the image and resize. (This also creates a crossfade effect.)
    if (scroller.background.superlayer == canvas) {
        [scroller.background removeFromSuperlayer];
    }
    
    //Make sure none of the size or position changes we're about to perform are animated
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    NSString *scrollerImageName;
    if (newPart == 0) {
        scrollerImageName = [score.scorePath stringByAppendingPathComponent:score.fileName];
    } else {
        scrollerImageName = [score.scorePath stringByAppendingPathComponent:[score.parts objectAtIndex:(newPart - 1)]];
    }
    [scroller changePart:scrollerImageName];
    
    //Code to resize image if its height is too big. Make sure we store the original dimensions
    //for later use and include a bit of padding for the controls in the calculations.
    
    //originalWidth = ([scroller originalSize]).width;
    int originalHeight = ([scroller originalSize]).height;
    
    int position = unscaledPosition;
    startOffset = score.startOffset;
    
    //In certain circumstances we scale up our image to make sure the new screen sizes
    //act like the old 1024 x 768 size.
    scoreScaleFactor = (canvas.bounds.size.height - padding) / originalHeight;
    scoreScaleFactor = scoreScaleFactor > maxScaleFactor ? maxScaleFactor : scoreScaleFactor;
    scroller.height = originalHeight * scoreScaleFactor;
    position = (int)roundf(unscaledPosition * scoreScaleFactor);
    startOffset = (int)roundf(score.startOffset * scoreScaleFactor);
    yOffset = ((canvas.bounds.size.height - padding) - scroller.height) / 2;
    scroller.x = position + readLineOffset;
    scroller.y = yOffset;
    [canvas insertSublayer:scroller.background below:readLine];
    [CATransaction commit];
    
    if (UIDelegate.playerState == kPlaying) {
        if (currentSection == 0 || currentSection == 2) {
            [self enableHighResTimer:YES];
            syncNextTick = YES;
        } else if (currentSection == 1) {
            if ([[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:4] floatValue] > 0) {
                [self enableHighResTimer:YES withSpeedMultiplier:[[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:4] floatValue]];
                syncNextTick = YES;
            }
        }
    }
    
    currentPart = newPart;
}

- (void)randomizeMiddleForDuration:(CGFloat)duration
{
    latestFragments = [[NSMutableArray alloc] init];
    NSInteger remaining = middleDuration;
    int nextChange = newGraphicDuration;
    int originalWidth = ([scroller originalSizeOfImages:[score.scorePath stringByAppendingPathComponent:score.fileName]]).width;
    
    //Leave some time for the final pause if needed
    remaining -= pauseLength;
    
    //Generate enough fragments to last the duration of the middle section.
    //(Use the original dimensions. We'll scale them where necessary.)
    while (remaining > 0) {
        NSInteger fragmentLength;
        
        remaining -= pauseLength;
        if (remaining < maxFragmentLength) {
            fragmentLength = remaining;
        } else {
            fragmentLength = (arc4random_uniform((maxFragmentLength - minFragmentLength) + 1)) + minFragmentLength;
        }
        remaining -= fragmentLength;
        
        //Check that the remaining time is bigger than the pause length. If not, then add it to our
        //current fragment.
        if (remaining <= pauseLength) {
            fragmentLength += remaining;
            remaining = 0;
        }
        
        int fragmentDirection = (2 * (int)arc4random_uniform(2)) - 1;
        CGFloat fragmentSpeed = (arc4random_uniform((int)roundf(100 * (maxFragmentSpeed - minFragmentSpeed)) + 1)) / 100.0 + minFragmentSpeed;
        //Limit the range of the randomly generated point to an area within the playable score that
        //won't take us beyond the bounds of the score for the current fragment length.
        
        int randBounds = ceilf((originalWidth - score.startOffset) - (originalWidth * fragmentLength * fragmentSpeed / newGraphicDuration));
        if (randBounds < 0) {
            randBounds = 0;
        }
        int startPoint = arc4random_uniform(randBounds);
        if (fragmentDirection == 1) {
            startPoint += score.startOffset;
        } else {
            startPoint = originalWidth - startPoint;
        }
        //Store where the fragment lies on the location slider to make seeking easier
        CGFloat fragmentLocation = nextChange / duration;
        
        //Add a fragment for any pause first
        if (pauseLength > 0) {
            NSMutableArray *currentFragment = [[NSMutableArray alloc] init];
            [currentFragment addObject:[NSNumber numberWithInt:pauseLength]];
            [currentFragment addObject:[NSNumber numberWithInt:fragmentDirection]];
            [currentFragment addObject:[NSNumber numberWithInt:startPoint]];
            [currentFragment addObject:[NSNumber numberWithFloat:fragmentLocation]];
            [currentFragment addObject:[NSNumber numberWithFloat:0]];
            [latestFragments addObject:currentFragment];
            
            nextChange += pauseLength;
            fragmentLocation = nextChange / duration;
        }
        
        NSMutableArray *currentFragment = [[NSMutableArray alloc] init];
        [currentFragment addObject:[NSNumber numberWithInteger:fragmentLength]];
        [currentFragment addObject:[NSNumber numberWithInt:fragmentDirection]];
        [currentFragment addObject:[NSNumber numberWithInt:startPoint]];
        [currentFragment addObject:[NSNumber numberWithFloat:fragmentLocation]];
        [currentFragment addObject:[NSNumber numberWithFloat:fragmentSpeed]];
        [latestFragments addObject:currentFragment];
        
        nextChange += fragmentLength;
    }
    
    //Add final pause if necessary.
    if (pauseLength > 0) {
        NSMutableArray *currentFragment = [[NSMutableArray alloc] init];
        [currentFragment addObject:[NSNumber numberWithInt:pauseLength]];
        [currentFragment addObject:[NSNumber numberWithInt:-1]];
        [currentFragment addObject:[NSNumber numberWithInt:originalWidth]];
        [currentFragment addObject:[NSNumber numberWithFloat:(newGraphicDuration + middleDuration - pauseLength) / duration]];
        [currentFragment addObject:[NSNumber numberWithFloat:0]];
        [latestFragments addObject:currentFragment];
    }
    
    if (!detached || workingFragments == nil) {
        workingFragments = latestFragments;
    }
}

- (OSCMessage *)createFragmentsMessageAsNew:(BOOL)new
{
    //New/Refresh
    //Create our fragments message.
    OSCMessage *message = [[OSCMessage alloc] init];
    [message appendAddressComponent:@"Fragments"];
    if (new) {
        [message addStringArgument:@"New"];
    } else {
        [message addStringArgument:@"Refresh"];
    }
    for (int i = 0; i < [latestFragments count]; i++) {
        [message addIntegerArgument:[[[latestFragments objectAtIndex:i] objectAtIndex:0] intValue]];
        [message addIntegerArgument:[[[latestFragments objectAtIndex:i] objectAtIndex:1] intValue]];
        [message addIntegerArgument:[[[latestFragments objectAtIndex:i] objectAtIndex:2] intValue]];
        [message addFloatArgument:[[[latestFragments objectAtIndex:i] objectAtIndex:3] floatValue]];
        [message addFloatArgument:[[[latestFragments objectAtIndex:i] objectAtIndex:4] floatValue]];
    }
    return message;
}

- (void)jumpToNextFragment
{
    [self enableHighResTimer:NO];
    [scroller.background removeAllAnimations];
    
    if (scroller.background.superlayer == canvas) {
        [scroller.background removeFromSuperlayer];
    }
    
    fragmentIndex++;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    CGFloat speed = 1;
    if (fragmentIndex < [workingFragments count]) {
        nextFragmentChange += [[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:0] intValue];
        direction = [[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:1] intValue];
        int x = -[[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:2] intValue];
        x *= scroller.width / ([scroller originalSizeOfImages:[score.scorePath stringByAppendingPathComponent:score.fileName]]).width;
        x += readLineOffset;
        scroller.x = x;
        speed = [[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:4] floatValue];
        currentSection = 1;
    } else {
        //If we're beyond the number of available fragments then jump to the start of the final section
        scroller.x = readLineOffset - scroller.width;
        currentSection = 2;
        direction = -1;
    }
    
    [CATransaction commit];
    
    [canvas insertSublayer:scroller.background below:readLine];
    if (currentSection == 1) {
        if (middleIndicator.superlayer != canvas) {
            [canvas addSublayer:middleIndicator];
        }
        if (speed == 0) {
            countRemaining = pauseLength * 2;
            countIn = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(countIn) userInfo:nil repeats:YES];
        }
    } else {
        [middleIndicator removeFromSuperlayer];
    }
    
    if (speed > 0) {
        [self enableHighResTimer:YES withSpeedMultiplier:speed];
        syncNextTick = YES;
    }
}

- (void)countIn
{
    middleIndicator.opacity = countRemaining % 2;
    countRemaining--;
    if (countRemaining == 0) {
        [countIn invalidate];
    }
}

- (void)sendScrollerData
{
    //Use this to retry retrieving scroller specific data every second if it's uninitialised on our first attempt.
    OSCMessage *response = [scroller getData];
    if (response == nil && retries > 0) {
        retries--;
        retryDataRequest = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(sendScrollerData) userInfo:nil repeats:NO];
    } else {
        [response prependAddressComponent:@"ScrollerData"];
        [messagingDelegate sendData:response];
    }
}

- (BOOL)setAnnotationsDirectory
{
    scroller.annotationsDirectory = [Renderer getAnnotationsDirectoryForScore:score];
    if (scroller.annotationsDirectory == nil) {
        return NO;
    } else {
        return YES;
    }
}

- (void)initLayers
{
    //Rotate the canvas if necessary
    if (orientation != kHorizontal) {
        canvas.bounds = CGRectMake(0, 0, superCanvas.bounds.size.height, superCanvas.bounds.size.width);
        padding = 0;
        if (orientation == kUp) {
            [canvas setValue:[NSNumber numberWithFloat: 90.0 / 180.0 * M_PI] forKeyPath:@"transform.rotation.z"];
        } else {
            [canvas setValue:[NSNumber numberWithFloat: -90.0 / 180.0 * M_PI] forKeyPath:@"transform.rotation.z"];
        }
    }
    
    //Reading line
    if (score.readLineOffset < 0) {
        //If the reading line position is negative then it represents a percentage
        readLineOffset = (int)roundf(canvas.bounds.size.width * fabs((CGFloat)score.readLineOffset) / 100);
    } else {
        //Otherwise it's a fixed value
        readLineOffset = score.readLineOffset;
    }
    readLine = [CALayer layer];
    //Keep the width of our reading line consistent between different screen sizes.
    //(Based on the original 1024 x 768 version.)
    readLine.frame = CGRectMake(0, 0, 4 * UIDelegate.cueLightScale, MAX(canvas.bounds.size.width, canvas.bounds.size.height));
    readLine.anchorPoint = CGPointMake(0.5 * readLineAlignment, 0);
    readLine.position = CGPointMake(readLineOffset, 0);
    if (readLineStyle == kDefaultLine) {
        readLine.backgroundColor = [UIColor orangeColor].CGColor;
    } else if (readLineStyle == kCustomColour) {
        readLine.backgroundColor = readLineColour.CGColor;
    } else if (readLineStyle == kCustomImage) {
        //If we're using a custom image for the reading line then load our image.
        UIImage *readLineImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:readLineImageName]];
        readLine.contents = (id)readLineImage.CGImage;
        readLineImageSize = readLineImage.size;
        
        CGFloat scaleFactor = (canvas.bounds.size.height - padding) / readLineImageSize.height;
        scaleFactor = scaleFactor > maxScaleFactor ? maxScaleFactor : scaleFactor;
        readLine.bounds = CGRectMake(0, 0, readLineImageSize.width * scaleFactor, readLineImageSize.height * scaleFactor);
        readLine.position = CGPointMake(readLine.position.x, (canvas.bounds.size.height - padding - readLine.bounds.size.height) / 2);
    }
    
    //Load image to be scrolled
    [scroller changePart:[score.scorePath stringByAppendingPathComponent:score.fileName]];
    //Run the changePart function here with an argument of 0 to invoke the resize code.
    [self changePart:0];
    
    if (liminumMode || juanitaMode) {
        //We need to generate data for the middle section
        [self randomizeMiddleForDuration:UIDelegate.clockDuration];
        
        //And set up the middle section indicator
        middleIndicator = [CALayer layer];
        middleIndicator.frame = CGRectMake(0, 0, middleIndicatorRadius * 2, middleIndicatorRadius * 2);
        middleIndicator.cornerRadius = middleIndicatorRadius;
        middleIndicator.backgroundColor = [UIColor redColor].CGColor;
        middleIndicator.position = CGPointMake(canvas.bounds.size.width - (10 + middleIndicatorRadius), 10 + middleIndicatorRadius);
    }
}

#pragma mark - Renderer delegate

- (void)setIsMaster:(BOOL)master
{
    isMaster = master;
    
    if (juanitaMode && !isMaster) {
        //If we're in juanita mode we need to get the data for the middle section.
        hasData = NO;
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"FragmentsRequest"];
        [messagingDelegate sendData:message];
    }
    
    if ([[scroller class] requiresData] && !isMaster) {
        //Our scroller requires data generated at launch. Send a request for it.
        hasScrollerData = NO;
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"ScrollerDataRequest"];
        [messagingDelegate sendData:message];
    }
}

- (BOOL)isMaster
{
    return isMaster;
}

- (void)setDetached:(BOOL)isDetached
{
    detached = isDetached;
    if (!detached) {
        //Point our working arrays to the latest ones.
        workingFragments = latestFragments;
        workingSectionBoundaries = latestSectionBoundaries;
        graphicDuration = newGraphicDuration;
        if (newMinimumSliderValue != 0) {
            //And fix our slider if needed.
            UIDelegate.sliderMinimumValue = newMinimumSliderValue;
            newMinimumSliderValue = 0;
        }
    }
}

- (BOOL)detached
{
    return detached;
}

+ (RendererFeatures)getRendererRequirements
{
    return kPositiveDuration | kFileName;
}

+ (UIImage *)generateThumbnailForScore:(Score *)score ofSize:(CGSize)size
{
    //Make image double resolution for retina screens.
    CGFloat screenScale = [[UIScreen mainScreen] scale];
    size = CGSizeMake(size.width * screenScale, size.height * screenScale);
    
    UIImage *image = [UIImage imageWithContentsOfFile:[score.scorePath stringByAppendingPathComponent:score.fileName]];
    UIGraphicsBeginImageContext(size);
    CGFloat scaleFactor = size.height / image.size.height;
    //Position our image from the start offset so that we see the actual score and not just instructions.
    [image drawInRect:CGRectMake(-(CGFloat)score.startOffset * scaleFactor, 0, image.size.width * scaleFactor, size.height)];
    CGFloat position = (image.size.width - (CGFloat)score.startOffset) * scaleFactor;
    
    if (position < size.width) {
        //Someone may have created a score with ridiculously small tiles... Sigh...
        NSFileManager *fileManager = [NSFileManager defaultManager];
        int i = 2;
        while (position < size.width) {
            NSString *fileName = [score.scorePath stringByAppendingPathComponent:[score.fileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i." , i]]];
            if (![fileManager fileExistsAtPath:fileName]) {
                //We tried.
                break;
            }
            UIImage *image = [UIImage imageWithContentsOfFile:fileName];
            [image drawInRect:CGRectMake(position, 0, image.size.width * scaleFactor, size.height)];
            position += image.size.width * scaleFactor;
            i++;
        }
    }
    UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return thumbnail;
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    
    isMaster = YES;
    score = scoreData;
    superCanvas = playerCanvas;
    canvas = [CALayer layer];
    canvas.bounds = CGRectMake(0, 0, superCanvas.bounds.size.width, superCanvas.bounds.size.height);
    canvas.position = CGPointMake(superCanvas.bounds.size.width / 2, superCanvas.bounds.size.height / 2);

    [superCanvas addSublayer:canvas];
    padding = LOWER_PADDING;
    
    UIDelegate = UIDel;
    messagingDelegate = messagingDel;
    UIDelegate.allowClockVisibilityChange = YES;
    UIDelegate.resetViewOnFinish = NO;
    firstLoad = YES;
    syncNextTick = NO;
    oldDuration = UIDelegate.clockDuration;
    scrollerType = @"TiledScroller";
    
    //Maximum scale factor to use to emulate our old geometry behaviour.
    maxScaleFactor = UIDelegate.cueLightScale;
    scoreScaleFactor = 1;
    middleIndicatorRadius = 20 * UIDelegate.cueLightScale;
    currentPart = 0;
    
    prefsLoaded = NO;
    prefsCondition = [NSCondition new];
    badPrefs = NO;
    liminumMode = NO;
    juanitaMode = NO;
    isTiled = NO;
    orientation = kHorizontal;
    hasData = YES;
    awaitingSeek = NO;
    hasScrollerData = YES;
    graphicDuration = 0;
    newGraphicDuration = 0;
    middleDuration = 0;
    minFragmentLength = 0;
    maxFragmentLength = 0;
    minFragmentSpeed = 1;
    maxFragmentSpeed = 1;
    pauseLength = 0;
    numberOfTiles = 1;
    readLineStyle = kDefaultLine;
    readLineAlignment = kAlignCentre;
    hideReadLine = NO;
    
    detached = NO;
    newMinimumSliderValue = 0;
    
    //Load any advanced preferances if the necessary file exists
    
    if (score.prefsFile != nil) {
        NSString *prefsFile = [score.scorePath stringByAppendingPathComponent:score.prefsFile];
        NSData *prefsData = [[NSData alloc] initWithContentsOfFile:prefsFile];
        xmlParser = [[NSXMLParser alloc] initWithData:prefsData];
            
        isData = NO;
        currentPrefs = kTopLevel;
        xmlParser.delegate = self;
        [xmlParser parse];
    } else {
        prefsLoaded = YES;
        
        //Set up the appropriate scroller. (Which is otherwise done once the parser finishes.)
        Class scrollerClass = NSClassFromString(scrollerType);
        scroller = [[scrollerClass alloc] initWithTiles:numberOfTiles options:nil];
        UIDelegate.canAnnotate = [self setAnnotationsDirectory];
        scroller.orientation = orientation;
    }
    
    if ([scroller respondsToSelector:@selector(setCanvasSize:)]) {
        //TODO: check if we need to use the supercanvas once we add vertical scrollers to the mix.
        scroller.canvasSize = canvas.bounds.size;
    }
    
    return self;
}

- (void)close
{
    [self enableHighResTimer:NO];
    [countIn invalidate];
    [retryDataRequest invalidate];
}

- (void)reset
{
    //This function should not be called. It's just included so the renderer
    //conforms to the protocol.
    CGFloat offset;
    [self reset:&offset];
}

- (void)reset:(CGFloat *)locationOffset
{
    [self enableHighResTimer:NO];
    [countIn invalidate];
    [scroller.background removeAllAnimations];
    
    //If we're still loading any preferences from the xml file then we need to wait for them.
    //(We'll be signaled to continue once the parser has finished running.)
    
    [prefsCondition lock];
    while (!prefsLoaded) {
        [prefsCondition wait];
    }
    [prefsCondition unlock];
    
    if (badPrefs) {
        [UIDelegate badPreferencesFile:errorMessage];
        return;
    }
    
    if (firstLoad) {
        //Perform this here rather than in the initRenderer method, because we need to have
        //loaded any advanced preferences
        [self initLayers];
        
        //If there are parts, check that they are the same width as the score.
        if ([score.parts count]  && [[scroller class] allowsParts]) {
            int width = [Renderer getImageSize:[score.scorePath stringByAppendingString:score.fileName]].width;
            for (int i = 0; i < [score.parts count]; i++) {
                if ([Renderer getImageSize:[score.scorePath stringByAppendingString:[score.parts objectAtIndex:i]]].width != width) {
                    [UIDelegate badPreferencesFile:@"Mismatching image sizes. Widths of score and parts must be the same."];
                    return;
                }
            }
        }
        
        //If we're not in "liminum mode," the duration of our graphic is the same as the total duration
        latestSectionBoundaries = [[NSMutableArray alloc] init];
        if (!(liminumMode || juanitaMode)) {
            graphicDuration = UIDelegate.clockDuration;
            newGraphicDuration = graphicDuration;
            [latestSectionBoundaries addObject:[NSNumber numberWithFloat:1]];
        } else {
            [latestSectionBoundaries addObject:[NSNumber numberWithFloat:(graphicDuration / UIDelegate.clockDuration)]];
            [latestSectionBoundaries addObject:[NSNumber numberWithFloat:((UIDelegate.clockDuration - graphicDuration) / UIDelegate.clockDuration)]];
        }
        //Given this is first load, make sure we unconditionally populate the
        //working copy of the section boundaries.
        workingSectionBoundaries = latestSectionBoundaries;
        
        //Adjust the slider so that zero falls at the start offset
        if (score.startOffset != 0) {
            UIDelegate.sliderMinimumValue = score.startOffset / ((CGFloat)(score.startOffset - ([scroller originalSizeOfImages:[score.scorePath stringByAppendingPathComponent:score.fileName]]).width) * (UIDelegate.clockDuration / graphicDuration));
        }

        //Set initial offest. The Score should either be placed at the reading line if there is no
        //start offset, or as far to the left of screen as possible if there is.
        if (startOffset > readLineOffset) {
            //Hide the reading line if the score has an instruction area.
            initOffset = readLineOffset;
            readLine.opacity = 0;
        } else {
            initOffset = startOffset;
        }
        
        scroller.x = readLineOffset - initOffset;
        if (startOffset > 0) {
            *locationOffset = UIDelegate.sliderMinimumValue * (startOffset - initOffset) / startOffset;
        } else {
            *locationOffset = UIDelegate.sliderMinimumValue;
        }
        
        //Round to the nearest second for UI consistency.
        *locationOffset = roundf(*locationOffset * UIDelegate.clockDuration) / UIDelegate.clockDuration;
        
        if (startOffset > 0) {
            //Ensure consistency with our rounding using a seek operation. (This will also
            //dispaly the reading line in the case that the location has been rounded up to 0.)
            [self seek:*locationOffset];
        }
        
        //Finally, check to see if moving only one pixel at a time will result in too high a frame rate.
        pixelsPerShift = ceilf(((scroller.width - startOffset) / graphicDuration) / MAX_SCROLLER_FRAMERATE);
        if (pixelsPerShift < 1) {
            pixelsPerShift = 1;
        }
        //NSLog(@"%i, %f", (int)pixelsPerShift, ((scroller.width - startOffset) / (graphicDuration * pixelsPerShift)));
        
        firstLoad = NO;
    } else {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        scroller.x = readLineOffset - startOffset;
        readLine.opacity = !hideReadLine;
        [CATransaction commit];
    }
    
    currentSection = 0;
    if (liminumMode || juanitaMode) {
        fragmentIndex = -1;
        nextFragmentChange = graphicDuration;
    }
    direction = 1;
    
    canvas.sublayers = nil;
    [canvas addSublayer:readLine];
	[canvas insertSublayer:scroller.background below:readLine];
}

- (void)play
{
    if (currentSection == 0 || currentSection == 2) {
        [self enableHighResTimer:YES];
    } else if (currentSection == 1) {
        if ([[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:4] floatValue] > 0) {
            [self enableHighResTimer:YES withSpeedMultiplier:[[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:4] floatValue]];
        }
    }
}

- (void)stop
{
    [self enableHighResTimer:NO];
    [countIn invalidate];
}

- (void)seek:(CGFloat)location
{
    //Return if we're still waiting for fragment data.
    if (juanitaMode && !isMaster && !hasData) {
        awaitingSeek = YES;
        return;
    }
    
    //Hide the reading line if we're in the instruction area.
    if (location < 0) {
        readLine.opacity = 0;
    } else {
        readLine.opacity = !hideReadLine;
    }
    
    //If the count in timer is active we need to reset it
    if (countIn.isValid) {
        [countIn invalidate];
        countRemaining = 1;
        [self countIn];
    }

    //Stop our high resolution timer for the moment.
    if (UIDelegate.playerState == kPlaying) {
        [self enableHighResTimer:NO];
    }
    
     //Now actually perform the seek operation
    if (!(juanitaMode || liminumMode) || location < [[workingSectionBoundaries objectAtIndex:0] floatValue]) {
        scroller.x = readLineOffset - startOffset - (location * (scroller.width - startOffset) * (UIDelegate.clockDuration / graphicDuration));
        currentSection = 0;
        direction = 1;
        if (middleIndicator.superlayer == canvas) {
            [middleIndicator removeFromSuperlayer];
        }
        if (liminumMode || juanitaMode) {
            fragmentIndex = -1;
            nextFragmentChange = graphicDuration;
        }
        
        //Restart the timer. This should be the last thing done in each code path.
        if (UIDelegate.playerState == kPlaying) {
            [self enableHighResTimer:YES];
        }
    } else if (location >= [[workingSectionBoundaries objectAtIndex:0] floatValue] && location < [[workingSectionBoundaries objectAtIndex:1] floatValue]) {
        fragmentIndex = 0;
        nextFragmentChange = graphicDuration;
        while (fragmentIndex < [workingFragments count] && [[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:3] floatValue] <= location) {
            nextFragmentChange += [[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:0] intValue];
            fragmentIndex++;
        }
        //It shouldn't be possible for the fragment index to be zero here, but check just in case something
        //has gone horribly wrong.
        if (fragmentIndex > 0) {
            fragmentIndex--;
        }
        
        direction = [[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:1] intValue];
        NSInteger x = [[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:2] intValue];
        if (score.startOffset != 0) {
            x *= startOffset / (CGFloat)score.startOffset;
        }
        x += direction * roundf((scroller.width - startOffset) * (location - [[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:3] floatValue]) * (UIDelegate.clockDuration / graphicDuration) * [[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:4] floatValue]);
        x = readLineOffset - x;
        scroller.x = x;
        currentSection = 1;
        if (UIDelegate.playerState == kPlaying && [[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:4] floatValue] > 0) {
            [self enableHighResTimer:YES withSpeedMultiplier:[[[workingFragments objectAtIndex:fragmentIndex] objectAtIndex:4] floatValue]];
            syncNextTick = YES;
        }
        
        if (middleIndicator.superlayer != canvas) {
            [canvas addSublayer:middleIndicator];
        }
    } else {
        scroller.x = readLineOffset - startOffset - ((1 - location) * (scroller.width - startOffset) * (UIDelegate.clockDuration / graphicDuration));
        currentSection = 2;
        direction = -1;
        if (middleIndicator.superlayer == canvas) {
            [middleIndicator removeFromSuperlayer];
        }
        
        if (UIDelegate.playerState == kPlaying) {
            [self enableHighResTimer:YES];
        }
    }
}

- (CGFloat)changeDuration:(CGFloat)duration currentLocation:(CGFloat *)location
{
    if (!(liminumMode || juanitaMode)) {
        newGraphicDuration = duration;
        if (!detached) {
            graphicDuration = newGraphicDuration;
        }
    } else {
        duration = roundf(duration);
        //Set a limit on how small the score can be. (The graphic duration must be at least as
        //long as the generated middle section.)
        if (duration < middleDuration * 3) {
            duration = middleDuration * 3;
        }
        if ((int)duration % 2 != middleDuration % 2) {
            duration += 1;
        }
        newGraphicDuration = (duration - middleDuration) / 2;
        latestSectionBoundaries = [[NSMutableArray alloc] init];
        [latestSectionBoundaries addObject:[NSNumber numberWithFloat:(newGraphicDuration / duration)]];
        [latestSectionBoundaries addObject:[NSNumber numberWithFloat:((duration - newGraphicDuration) / duration)]];
        if (!detached) {
            graphicDuration = newGraphicDuration;
            workingSectionBoundaries = latestSectionBoundaries;
        }
            
        //If we're in liminum mode we also need to change the minimum slider value
        if (score.startOffset != 0) {
            newMinimumSliderValue = score.startOffset / ((CGFloat)(score.startOffset - ([scroller originalSizeOfImages:[score.scorePath stringByAppendingPathComponent:score.fileName]]).width) * (duration / newGraphicDuration));
            if (!detached) {
                UIDelegate.sliderMinimumValue = newMinimumSliderValue;
            }
        }
            
        //Regenerate the data for the middle section
        if (liminumMode) {
            [self randomizeMiddleForDuration:duration];
        } else if (juanitaMode && isMaster) {
            [self randomizeMiddleForDuration:duration];
            
            OSCMessage *message = [self createFragmentsMessageAsNew:YES];
            [messagingDelegate sendData:message];
        }
            
        //Now we need to keep ourselves in an equivalent part of the score.
        switch (currentSection) {
            case 0:
                //These equations aren't pretty, but they work
                *location = (2 * newGraphicDuration * *location * oldDuration) / (duration * (oldDuration - middleDuration));
                break;
            case 1:
                *location = 0.5 + ((*location - 0.5) * oldDuration / duration);
                break;
            case 2:
                *location = 1 - (2 * newGraphicDuration * (1 - *location) * oldDuration) / (duration * (oldDuration - middleDuration));
                break;
            default:
                break;
        }
    }
    oldDuration = duration;
    
    //Check the pixels per shift setting as well now that we've changed our duration.
    pixelsPerShift = ceilf(((scroller.width - startOffset) / graphicDuration) / MAX_SCROLLER_FRAMERATE);
    if (pixelsPerShift < 1) {
        pixelsPerShift = 1;
    }
    
    return duration;
}

- (void)rotate
{
    //What's wrong with just leaving the device one way up? Why must you complicate my life?!?
    //Also, this code will probably break synch. If you're rotating your score while it's
    //playing then frankly you deserve synch issues.
    if (orientation != kHorizontal) {
        canvas.bounds = CGRectMake(0, 0, superCanvas.bounds.size.height, superCanvas.bounds.size.width);
    } else {
        canvas.bounds = CGRectMake(0, 0, superCanvas.bounds.size.width, superCanvas.bounds.size.height);
    }
    canvas.position = CGPointMake(superCanvas.bounds.size.width / 2, superCanvas.bounds.size.height / 2);
    if ([scroller respondsToSelector:@selector(setCanvasSize:)]) {
        scroller.canvasSize = superCanvas.bounds.size;
    }
    
    int height = scroller.height;
    int position = scroller.x - readLineOffset; //Offset left by the distance to the reading line. Adjusted at the last moment.

    int originalWidth = ([scroller originalSize]).width;
    int originalHeight = ([scroller originalSize]).height;
    
    //Scale our image to fit the new screen height.
    BOOL resized = NO;
    CGFloat scaleFactor = (canvas.bounds.size.height - padding) / originalHeight;
    scaleFactor = scaleFactor > maxScaleFactor ? maxScaleFactor : scaleFactor;
    if (scaleFactor != scoreScaleFactor) {
        resized = YES;
        scoreScaleFactor = scaleFactor;
        height = originalHeight * scaleFactor;
        //Unscaled position is offset to the left by the distance to the reading line to optimize calculations
        CGFloat unscaledPosition = position * originalWidth / scroller.width;
        position = (int)roundf(unscaledPosition * scaleFactor);
        startOffset = (int)roundf(score.startOffset * scaleFactor);
    }
    
    //Change the position of the reading line if it's represented as a percentage.
    BOOL repositioned = NO;
    if (score.readLineOffset < 0) {
        repositioned = YES;
        readLineOffset = (int)roundf(canvas.bounds.size.width * fabs((CGFloat)score.readLineOffset) / 100);
        readLine.position = CGPointMake(readLineOffset, 0);
    }
    
    //If our reading line is a custom image, check to see whether we need to resize it.
    if (readLineStyle == kCustomImage) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CGFloat scaleFactor = (canvas.bounds.size.height - padding) / readLineImageSize.height;
        scaleFactor = scaleFactor > maxScaleFactor ? maxScaleFactor : scaleFactor;
        readLine.bounds = CGRectMake(0, 0, readLineImageSize.width * scaleFactor, readLineImageSize.height * scaleFactor);
        readLine.position = CGPointMake(readLine.position.x, (canvas.bounds.size.height - padding - readLine.bounds.size.height) / 2);
        [CATransaction commit];
    }
    
    //Check to see if we need to recenter the score.
    BOOL recentred = NO;
    NSInteger offset = ((canvas.bounds.size.height - padding) - height) / 2;
    if (offset != yOffset) {
        recentred = YES;
        yOffset = offset;
    }
    
    //Make the necessary adjustments.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (resized) {
        scroller.height = height;
    }
    if (resized || repositioned) {
        scroller.x = position + readLineOffset;
    }
    if (resized || recentred) {
        scroller.y = yOffset;
    }
    [CATransaction commit];
    
    //Now to fix the timer if the score is playing.
    //(You know that image from 1984 of a boot stamping on a human face forever?
    //That's what I want to do to you if you're causing this particular snippet of code to execute.)
    if (UIDelegate.playerState == kPlaying) {
        [self enableHighResTimer:NO];
        highRes = [NSTimer scheduledTimerWithTimeInterval:(pixelsPerShift * graphicDuration / (scroller.width - startOffset)) target:self selector:@selector(animate) userInfo:nil repeats:YES];
        //If we're the master, synch to the player clock. (If we're not we'll be synched to the network
        //clock by the player.)
        if (isMaster) {
            syncNextTick = YES;
        }
    }
    
    if (middleIndicator != nil) {
        middleIndicator.position = CGPointMake(canvas.bounds.size.width - (10 + middleIndicatorRadius), 10 + middleIndicatorRadius);
    }
}

- (void)receiveMessage:(OSCMessage *)message
{
    //Only process messages if we're in juanita mode or if our scroller needs data.
    //(Check this on a per message basis.)
    
    if (isMaster) {
        if ([message.address count] < 1) {
            return;
        }
        if ([[message.address objectAtIndex:0] isEqualToString:@"FragmentsRequest"] && juanitaMode) {
            OSCMessage *response = [self createFragmentsMessageAsNew:NO];
            [messagingDelegate sendData:response];
        } else if ([[message.address objectAtIndex:0] isEqualToString:@"ScrollerDataRequest"] && [[scroller class] requiresData]) {
            if ([scroller respondsToSelector:@selector(getData)]) {
                retries = 5;
                [self sendScrollerData];
            }
        }
    } else {
        if ([[message.address objectAtIndex:0] isEqualToString:@"Fragments"] && juanitaMode) {
            if (![message.typeTag hasPrefix:@",s"]) {
                return;
            }
            if (!hasData || [[message.arguments objectAtIndex:0] isEqualToString:@"New"]) {
                //Check we have the right data structure to create an array.
                if ([message.typeTag length] % 5 != 2) {
                    return;
                }
                for (int i = 2; i < [message.typeTag length]; i += 5) {
                    if (![[message.typeTag substringWithRange:NSMakeRange(i, 5)] isEqualToString:@"iiiff"]) {
                        return;
                    }
                }
                
                latestFragments = [[NSMutableArray alloc] init];
                for (int i = 1; i < [message.arguments count]; i += 5) {
                    NSMutableArray *currentFragment = [[NSMutableArray alloc] initWithCapacity:5];
                    [currentFragment addObject:[message.arguments objectAtIndex:i]];
                    [currentFragment addObject:[message.arguments objectAtIndex:(i + 1)]];
                    [currentFragment addObject:[message.arguments objectAtIndex:(i + 2)]];
                    [currentFragment addObject:[message.arguments objectAtIndex:(i + 3)]];
                    [currentFragment addObject:[message.arguments objectAtIndex:(i + 4)]];
                    [latestFragments addObject:currentFragment];
                }
                if (!detached || workingFragments == nil) {
                    workingFragments = latestFragments;
                }
                hasData = YES;
                
                //If we're waiting on new fragments before seeking, seek now.
                //(This shouldn't happen, but include for safety.)
                if (awaitingSeek) {
                    [self seek:UIDelegate.clockLocation];
                    awaitingSeek = NO;
                }
            }
        } else if ([[message.address objectAtIndex:0] isEqualToString:@"ScrollerData"] && [[scroller class] requiresData]) {
            if (!hasScrollerData && [scroller respondsToSelector:@selector(setData:)]) {
                [message stripFirstAddressComponent];
                [scroller setData:message];
                hasScrollerData = YES;
            }
        }
    }
}

- (void)tick:(int)progress tock:(int)splitSecond noMoreClock:(BOOL)finished
{
    if (splitSecond == 1) {
        return;
    }
    
    if (isTiled) {
        if (scroller.loadOccurred) {
            syncNextTick = YES;
            scroller.loadOccurred = NO;
        }
    }
    
    if (syncNextTick) {
        [self seek:(progress / UIDelegate.clockDuration)];
        syncNextTick = NO;
    }
    
    if (liminumMode || juanitaMode) {
        if (progress == nextFragmentChange) {
            [self jumpToNextFragment];
        }
    }
    
    if ([scroller respondsToSelector:@selector(tick:tock:noMoreClock:)]) {
        [scroller tick:progress tock:splitSecond noMoreClock:finished];
    }
}

- (void)attemptSync
{
    syncNextTick = YES;
}

- (UIImage *)currentAnnotationImage
{
    //No checks on these - all of these methods had to exist for annotation to be enabled.
    //(Add safety chack later if really desired.)
    return [scroller currentAnnotationImage];
}

- (CALayer *)currentAnnotationMask
{
    //Except for this one. This one is optional.
    if ([scroller respondsToSelector:@selector(currentAnnotationMask)]) {
        return [scroller currentAnnotationMask];
    } else {
        return nil;
    }
}

- (void)saveCurrentAnnotation:(UIImage *)image
{
    [scroller saveCurrentAnnotation:image];
}

- (void)hideSavedAnnotations:(BOOL)hide
{
    [scroller hideSavedAnnotations:hide];
}

- (void)swipeUp
{
    //Disable part switching if the player is currently playing the middle section (synch issues).
    /*if (delegate.playerState == kPlaying && currentSection == 1) {
        return;
    }*/
    if ([score.parts count] > 0 && [[scroller class] allowsParts]) {
        [self changePart:1];
        [UIDelegate partChangedToPart:currentPart];
    }
}

- (void)swipeDown
{
    /*if (delegate.playerState == kPlaying && currentSection == 1) {
        return;
    }*/
    if ([score.parts count] > 0 && [[scroller class] allowsParts]) {
        [self changePart:-1];
        [UIDelegate partChangedToPart:currentPart];
    }
}

- (void)tapAt:(CGPoint)location
{
    int touchWidth = 30;
    if (readLine.frame.size.width > 60) {
        touchWidth = readLine.frame.size.width / 2;
    }
    
    if ((location.x < readLineOffset - touchWidth) || (location.x > readLineOffset + touchWidth) || UIDelegate.clockLocation < 0) {
        //Only hide the reading line if the touch is in a region surrounding it, and if we're not in the
        //instruction area. If it's already hidden we need to show it no matter where the screen is tapped.
        if (!hideReadLine) {
            return;
        }
    }
    
    hideReadLine = !hideReadLine;
    if (hideReadLine) {
        readLine.opacity = 0;
    } else {
        readLine.opacity = 1;
    }
}

#pragma mark - NSXMLparser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    //Determine which section of the preferences file we're in, and only parse elements that belong.
    if (currentPrefs == kTopLevel) {
        if ([elementName isEqualToString:@"liminummode"] || [elementName isEqualToString:@"juanitamode"]){
            currentPrefs = kScrollerMode;
        } else if ([elementName isEqualToString:@"tiled"]) {
            currentPrefs = kTiles;
        } else if ([elementName isEqualToString:@"playhead"]) {
            currentPrefs = kReadLine;
        } else if ([elementName isEqualToString:@"scrollermodule"]) {
            currentPrefs = kModule;
        } else if ([elementName isEqualToString:@"vertical"]) {
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
    switch (currentPrefs) {
        case kTopLevel:
            if ([elementName isEqualToString:@"vertical"]) {
                if (currentString != nil && [currentString caseInsensitiveCompare:@"up"] == NSOrderedSame) {
                    orientation = kUp;
                } else if (currentString != nil && [currentString caseInsensitiveCompare:@"down"] == NSOrderedSame) {
                    orientation = kDown;
                }
            }
            break;
            
        case kScrollerMode:
            if ([elementName isEqualToString:@"middleduration"]) {
                middleDuration = [currentString integerValue];
            } else if ([elementName isEqualToString:@"minfragment"]) {
                minFragmentLength = [currentString intValue];
            } else if ([elementName isEqualToString:@"maxfragment"]) {
                maxFragmentLength = [currentString intValue];
            } else if ([elementName isEqualToString:@"minspeed"]) {
                if ([currentString floatValue] > 0) {
                    minFragmentSpeed = [currentString floatValue];
                }
            } else if ([elementName isEqualToString:@"maxspeed"]) {
                if ([currentString floatValue] > 0) {
                    maxFragmentSpeed = [currentString floatValue];
                }
            } else if ([elementName isEqualToString:@"pauselength"]) {
                pauseLength = [currentString intValue];
            } else if ([elementName isEqualToString:@"liminummode"]) {
                //Check that we have all the data we need to enable liminum mode
                if (middleDuration > 0 && minFragmentLength > 0 && maxFragmentLength > 0) {
                    liminumMode = YES;
                }
                currentPrefs = kTopLevel;
            } else if ([elementName isEqualToString:@"juanitamode"]) {
                if (middleDuration > 0 && minFragmentLength > 0 && maxFragmentLength > 0) {
                    juanitaMode = YES;
                }
                currentPrefs = kTopLevel;
            }
            break;
            
        case kReadLine:
            if ([elementName isEqualToString:@"rgb"]) {
                NSArray *colour = [currentString componentsSeparatedByString:@","];
                //If a custom image has already been specified for the reading line, then we have
                //no need for a custom colour.
                if (readLineStyle != kCustomImage) {
                    //Check that we have three colour components in our array
                    if ([colour count] == 3) {
                        CGFloat r = [[colour objectAtIndex:0] intValue] & 255;
                        CGFloat g = [[colour objectAtIndex:1] intValue] & 255;
                        CGFloat b = [[colour objectAtIndex:2] intValue] & 255;
                        readLineColour = [UIColor colorWithRed:(r / 255) green:(g / 255) blue:(b / 255) alpha:1];
                        readLineStyle = kCustomColour;
                    }
                }
            } else if ([elementName isEqualToString:@"image"]) {
                readLineImageName = currentString;
                //Check that the image file exists
                NSFileManager *fileManager = [NSFileManager defaultManager];
                if ([fileManager fileExistsAtPath:[score.scorePath stringByAppendingPathComponent:readLineImageName]]) {
                    readLineStyle = kCustomImage;
                }
            } else if ([elementName isEqualToString:@"align"]) {
                if (currentString != nil) {
                    if ([currentString caseInsensitiveCompare:@"left"] == NSOrderedSame) {
                        readLineAlignment = kAlignLeftEdge;
                    } else if ([currentString caseInsensitiveCompare:@"right"] == NSOrderedSame) {
                        readLineAlignment = kAlignRightEdge;
                    }
                }
            } else if ([elementName isEqualToString:@"playhead"]) {
                //Checks have already been performed by this stage.
                currentPrefs = kTopLevel;
            }
            break;
            
        case kModule:
            if ([elementName isEqualToString:@"name"]) {
                scrollerType = currentString;
            } else if ([elementName isEqualToString:@"tiles"]) {
                numberOfTiles = [currentString integerValue];
            } else if ([elementName isEqualToString:@"scrollermodule"]) {
                //Perform necessary module checks.
                Class scrollerClass = NSClassFromString(scrollerType);
                if (scrollerClass == nil || ![scrollerClass conformsToProtocol:@protocol(ScrollerDelegate)]) {
                    badPrefs = YES;
                    errorMessage = @"Invalid scroller type specified";
                } else {
                    NSArray *requiredOptions = [scrollerClass requiredOptions];
                    for (int i = 0; i < [requiredOptions count]; i++) {
                        if (![scrollerOptions objectForKey:[requiredOptions objectAtIndex:i]]) {
                            badPrefs = YES;
                            errorMessage = @"Missing options for specified scroller module.";
                            i = (int)[requiredOptions count];
                        }
                    }
                }
                //Check whether we've spefied the default TiledScroller and set isTiled appropriately
                if ([scrollerType isEqualToString:@"TiledScroller"] && numberOfTiles > 1) {
                    isTiled = YES;
                }
                currentPrefs = kTopLevel;
            } else {
                //Anything else is treated as a scroller option.
                if (scrollerOptions == nil) {
                    scrollerOptions = [[NSMutableDictionary alloc] init];
                }
                [scrollerOptions setObject:[NSString stringWithString:currentString] forKey:elementName];
            }
            break;
            
        case kTiles:
            if ([elementName isEqualToString:@"tiles"]) {
                numberOfTiles = [currentString integerValue];
            } else if ([elementName isEqualToString:@"tiled"]) {
                //Check that the number of tiles has been specified and enable tiled mode.
                if (numberOfTiles > 1) {
                    isTiled = YES;
                }
                currentPrefs = kTopLevel;
            }
            break;
            
        default:
            break;
    }
    
    isData = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    //If we're in liminum or juanita mode, we need the score duration to be an integer which is even
    //or odd based on the length of the middle section.
    if (liminumMode || juanitaMode) {
        CGFloat duration = roundf(UIDelegate.clockDuration);
        if ((int)duration % 2 != middleDuration % 2) {
            UIDelegate.clockDuration = duration + 1;
        }
        graphicDuration = (UIDelegate.clockDuration - middleDuration) / 2;
        newGraphicDuration = graphicDuration;
    }
    
    //If we're a tiled score, we need to check that all of our images actually exist.
    //(Also check to make sure that they're all the same width.)
    if (isTiled) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        int width = [Renderer getImageSize:[score.scorePath stringByAppendingPathComponent:score.fileName]].width;
        
        for (int i = 1; i <= numberOfTiles; i++) {
            NSString *fileName = [score.scorePath stringByAppendingPathComponent:[score.fileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i." , i]]];
            if (![fileManager fileExistsAtPath:fileName]) {
                badPrefs = YES;
                errorMessage = @"Missing images in score file.";
            } else if ([Renderer getImageSize:fileName].width != width) {
                badPrefs = YES;
                errorMessage = @"Mismatching tile dimensions. All image widths must be the same for tiled scores.";
            }
            
            if ([score.parts count] > 0) {
                for (int j = 0; j < [score.parts count]; j++) {
                    NSString *partFile = [score.scorePath stringByAppendingPathComponent:[[score.parts objectAtIndex:j] stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i." , i]]];
                    if (![fileManager fileExistsAtPath:partFile]) {
                        badPrefs = YES;
                        errorMessage = @"Missing images in score file.";
                    } else if ([Renderer getImageSize:partFile].width != width) {
                        badPrefs = YES;
                        errorMessage = @"Mismatching tile dimensions. All image widths must be the same for tiled scores.";
                    }
                }
            }
        }
    } else if (numberOfTiles > 1) {
        //Not a tiled score, but one that uses a set of images need to check that these exist.
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        for (int i = 2; i <= numberOfTiles; i++) {
            NSString *fileName = [score.scorePath stringByAppendingPathComponent:[score.fileName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i]]];
            if (![fileManager fileExistsAtPath:fileName]) {
                badPrefs = YES;
                errorMessage = @"Missing images in score file.";
            }
        }
    }
    
    //Set up the appropriate scroller.
    Class scrollerClass = NSClassFromString(scrollerType);
    scroller = [[scrollerClass alloc] initWithTiles:numberOfTiles options:scrollerOptions];
    if (scroller == nil) {
        //Something has gone wrong. (Most likely, the options provided were unusable.)
        badPrefs = YES;
        errorMessage = @"Bad options given for specified scroller module.";
    } else if ([scroller respondsToSelector:@selector(currentAnnotationImage)] && [scroller respondsToSelector:@selector(saveCurrentAnnotation:)] && [scroller respondsToSelector:@selector(hideSavedAnnotations:)] && [scroller respondsToSelector:@selector(setAnnotationsDirectory:)]) {
        UIDelegate.canAnnotate = [self setAnnotationsDirectory];
    }
    
    if ([scroller respondsToSelector:@selector(setOrientation:)]) {
        scroller.orientation = orientation;
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

//
//  Radar.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 1/9/17.
//  Copyright (c) 2017 Decibel. All rights reserved.
//

#import "Radar.h"
#import "Score.h"

@interface Radar ()

- (void)animate;
- (void)enableHighResTimer:(BOOL)enabled;
- (UIBezierPath *)getRadarSweepPathForAngle:(CGFloat)angle;
- (void)initLayers;

@end

@implementation Radar {
    Score *score;
    CALayer *canvas;
    CALayer *background;
    CAShapeLayer *radarSweep;
    UIColor *sweepColour;
    NSTimer *highRes;
    
    NSInteger lineLength;
    CGPoint origin;
    
    CGFloat anglePerFrame;
    CGFloat currentAngle;
    
    CGFloat angleOffset;
    CGFloat rotations;
    BOOL bidirectional;
    NSInteger currentDirection;
    
    NSXMLParser *xmlParser;
    NSMutableString *currentString;
    BOOL isData;
    BOOL prefsLoaded;
    NSCondition *prefsCondition;
    
    BOOL firstLoad;
    
    __weak id<RendererUI> UIDelegate;
}

@synthesize isMaster;

- (void)animate
{
    currentAngle += (anglePerFrame * currentDirection);
    radarSweep.path = [self getRadarSweepPathForAngle:(currentAngle + angleOffset)].CGPath;
    if (fabs(currentAngle) >= fabs(360 * rotations)) {
        if (bidirectional) {
            currentDirection = -1;
        } else {
            [self enableHighResTimer:NO];
        }
    } else if (bidirectional && ((anglePerFrame > 0 && currentAngle <= 0) || (anglePerFrame < 0 && currentAngle >= 0))) {
        [self enableHighResTimer:NO];
    }
}

- (void)enableHighResTimer:(BOOL)enabled
{
    if (enabled) {
        if (highRes == nil || !highRes.isValid) {
            //Don't start a new timer if there is already a valid high resolution timer running.
            highRes = [NSTimer scheduledTimerWithTimeInterval:(1.0 / RADAR_FRAMERATE) target:self selector:@selector(animate) userInfo:nil repeats:YES];
        }
    } else {
        if (highRes != nil) {
            [highRes invalidate];
            highRes = nil;
        }
    }
}

- (UIBezierPath *)getRadarSweepPathForAngle:(CGFloat)angle
{
    angle = (angle / 180.0) * M_PI;
    UIBezierPath *linePath = [UIBezierPath bezierPath];
    [linePath moveToPoint:CGPointMake(origin.x, origin.y)];
    [linePath addLineToPoint:CGPointMake(origin.x + (lineLength * sinf(angle)), origin.y - (lineLength * cosf(angle)))];
    return linePath;
}

- (void)initLayers
{
    UIImage *backgroundImage = [Renderer cachedImage:[score.scorePath stringByAppendingPathComponent:score.fileName]];
    background = [CALayer layer];
    background.frame = CGRectMake(0, 0, canvas.bounds.size.width, canvas.bounds.size.height);
    background.contentsGravity = kCAGravityResizeAspect;
    background.contents = (id)backgroundImage.CGImage;
    [canvas addSublayer:background];
    
    origin = CGPointMake(background.bounds.size.width / 2, background.bounds.size.height / 2);
    
    UIBezierPath *linePath = [UIBezierPath bezierPath];
    [linePath moveToPoint:CGPointMake(origin.x, origin.y)];
    [linePath addLineToPoint:CGPointMake(origin.x, origin.y - lineLength)];
    
    radarSweep = [CAShapeLayer layer];
    radarSweep.path = linePath.CGPath;
    radarSweep.lineWidth = 4 * UIDelegate.cueLightScale;
    radarSweep.strokeColor = sweepColour.CGColor;
    [canvas addSublayer:radarSweep];
}

#pragma mark - Renderer delegate

+ (RendererFeatures)getRendererRequirements
{
    return kFileName | kPositiveDuration;
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
    firstLoad = YES;
    UIDelegate = UIDel;

    angleOffset = 0;
    rotations = 1;
    bidirectional = NO;
    
    //For now we need to disable clock changes until we have the required code to handle it.
    //TODO: Write duration change code.
    UIDelegate.allowClockChange = NO;
    
    lineLength = sqrt(pow(canvas.bounds.size.width, 2) + pow(canvas.bounds.size.height, 2)) + 10;
    anglePerFrame = 360.0 * rotations / (UIDelegate.clockDuration * RADAR_FRAMERATE);
    
    prefsCondition = [NSCondition new];
    if (score.prefsFile != nil) {
        NSString *prefsFile = [score.scorePath stringByAppendingPathComponent:score.prefsFile];
        NSData *prefsData = [[NSData alloc] initWithContentsOfFile:prefsFile];
        xmlParser = [[NSXMLParser alloc] initWithData:prefsData];
        
        isData = NO;
        prefsLoaded = NO;
        xmlParser.delegate = self;
        [xmlParser parse];
    } else {
        prefsLoaded = YES;
    }
    
    return self;
}

- (void)reset
{
    [self enableHighResTimer:NO];
    currentAngle = 0;
    
    [prefsCondition lock];
    while (!prefsLoaded) {
        [prefsCondition wait];
    }
    [prefsCondition unlock];
    
    if (firstLoad) {
        [self initLayers];
        firstLoad = NO;
    }
    
    currentDirection = 1;
    radarSweep.path = [self getRadarSweepPathForAngle:(currentAngle + angleOffset)].CGPath;
}

- (void)stop
{
    [self enableHighResTimer:NO];
}

- (void)play
{
    [self enableHighResTimer:YES];
}

- (void)seek:(CGFloat)location
{
    if (UIDelegate.playerState == kPlaying) {
        [self enableHighResTimer:NO];
    }
    
    if (!bidirectional) {
        currentAngle = location * 360 * rotations;
    } else {
        if (location < 0.5) {
            currentAngle = location * 2 * 360 * rotations;
            currentDirection = 1;
        } else {
            currentAngle = (2 - location * 2) * 360 * rotations;
            currentDirection = -1;
        }
    }
    radarSweep.path = [self getRadarSweepPathForAngle:(currentAngle + angleOffset)].CGPath;
    if (UIDelegate.playerState == kPlaying) {
        [self enableHighResTimer:YES];
    }
}

- (void)rotate
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    background.frame = CGRectMake(0, 0, canvas.bounds.size.width, canvas.bounds.size.height);
    origin = CGPointMake(background.bounds.size.width / 2, background.bounds.size.height / 2);
    radarSweep.path = [self getRadarSweepPathForAngle:(currentAngle + angleOffset)].CGPath;
    [CATransaction commit];
}

#pragma mark - NSXMLParser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if ([elementName isEqualToString:@"startangle"] || [elementName isEqualToString:@"rotations"] || [elementName isEqualToString:@"sweeprgb"] || [elementName isEqualToString:@"bidirectional"]) {
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
    if ([elementName isEqualToString:@"startangle"]) {
        angleOffset = [currentString floatValue];
    } else if ([elementName isEqualToString:@"rotations"]) {
        //Make sure this is a non-zero value.
        if ([currentString floatValue] != 0) {
            rotations = [currentString floatValue];
            anglePerFrame = 360.0 * rotations / (UIDelegate.clockDuration * RADAR_FRAMERATE);
        }
    } else if ([elementName isEqualToString:@"sweeprgb"]) {
        NSArray *colour = [currentString componentsSeparatedByString:@","];
        //Check that we have three colour components in our array
        if ([colour count] == 3) {
            CGFloat r = [[colour objectAtIndex:0] intValue] & 255;
            CGFloat g = [[colour objectAtIndex:1] intValue] & 255;
            CGFloat b = [[colour objectAtIndex:2] intValue] & 255;
            sweepColour = [UIColor colorWithRed:(r / 255) green:(g / 255) blue:(b / 255) alpha:1];
        }
    } else if ([elementName isEqualToString:@"bidirectional"]) {
        if (currentString != nil && [currentString caseInsensitiveCompare:@"yes"] == NSOrderedSame) {
            bidirectional = YES;
        }
    }
    isData = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    if (bidirectional) {
        anglePerFrame *= 2;
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
    //If the preferences file is bad, just use the default options for the moment.
    //TODO: Actually deal with bad preferences properly.
    parser.delegate = nil;
    xmlParser = nil;
    
    [prefsCondition lock];
    prefsLoaded = YES;
    [prefsCondition signal];
    [prefsCondition unlock];
}

@end

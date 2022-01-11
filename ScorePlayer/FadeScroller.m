//
//  FadeScroller.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 22/02/2014.
//  Copyright (c) 2014 Decibel. All rights reserved.
//

#import "FadeScroller.h"
#import <QuartzCore/QuartzCore.h>
#import "Renderer.h"
#import "OSCMessage.h"

@interface FadeScroller()

- (void)setOpacities;

@end

@implementation FadeScroller {
    NSMutableArray *tileArray;
    NSMutableArray *positions;
    int *widths;
    
    int overlap;
    int fadeStart;
    int fadeEnd;
    BOOL autoWidth;
    
    CGSize originalSize;
    NSString *currentImageName;
    
    BOOL dataInitialised;
}

@synthesize width, numberOfTiles, background, loadOccurred;

- (void)setOpacities {
    //Our first tile is always opaque, no matter what its location is.
    ((CALayer *)[tileArray objectAtIndex:0]).opacity = 1;
    for (int i = 1; i < [tileArray count]; i++) {
        int position = background.position.x + ((CALayer *)[tileArray objectAtIndex:i]).position.x;
        if (position > fadeStart) {
            ((CALayer *)[tileArray objectAtIndex:i]).opacity = 0;
        } else if (position < fadeEnd) {
            ((CALayer *)[tileArray objectAtIndex:i]).opacity = 1;
        } else {
            ((CALayer *)[tileArray objectAtIndex:i]).opacity = 0.5 + cosf(M_PI * (CGFloat)(position - fadeEnd) / (CGFloat)(fadeStart - fadeEnd)) / 2.0;
        }
    }
}

- (void)dealloc
{
    free(widths);
}

#pragma mark - Scroller delegate

+ (BOOL)allowsParts
{
    return YES;
}

+ (BOOL)requiresData
{
    return YES;
}

+ (NSArray *)requiredOptions
{
    return [NSArray arrayWithObjects:@"width", @"overlap", @"fadestart", @"fadeend", nil];
}

- (id)initWithTiles:(NSInteger)tiles options:(NSMutableDictionary *)options
{
    self = [super init];
    
    //Check that our arguments are sane.
    if (tiles < 1) {
        tiles = 1;
    }
    
    numberOfTiles = tiles;
    loadOccurred = NO;
    width = [[options objectForKey:@"width"] intValue];
    overlap = [[options objectForKey:@"overlap"] intValue];
    fadeStart = [[options objectForKey:@"fadestart"] intValue];
    fadeEnd = [[options objectForKey:@"fadeend"] intValue];
    
    if (fadeStart < fadeEnd) {
        int temp = fadeEnd;
        fadeEnd = fadeStart;
        fadeStart = temp;
    }
    
    if (overlap < 1 || fadeStart == fadeEnd) {
        //Bad options. Abort!
        return nil;
    }
    
    if (width < 1) {
        width = 1;
        autoWidth = YES;
    } else {
        autoWidth = NO;
    }
    
    widths = malloc(sizeof(int) * numberOfTiles);
    
    //Set up the background layer.
    
    background = [CALayer layer];
    background.bounds = CGRectMake(0, 0, width, 1);
    background.anchorPoint = CGPointZero;
    background.position = CGPointZero;
    background.masksToBounds = YES;
    
    dataInitialised = NO;
    return self;
}

- (void)setHeight:(CGFloat)newHeight
{
    //Calculate the new width
    width = (int)roundf(originalSize.width * newHeight / originalSize.height);
    height = newHeight;
    
    //Resize the layers
    background.bounds = CGRectMake(0, 0, width, height);
    for (int i = 0; i < [tileArray count]; i++) {
        int tileWidth = (CGFloat)widths[[[[positions objectAtIndex:i] objectAtIndex:1] intValue] - 1] * height / originalSize.height;
        int position = [[[positions objectAtIndex:i] objectAtIndex:0] floatValue] * height / originalSize.height;
        ((CALayer *)[tileArray objectAtIndex:i]).bounds = CGRectMake(0, 0, tileWidth, height);
        ((CALayer *)[tileArray objectAtIndex:i]).position = CGPointMake(position, 0);
    }
}

- (CGFloat)height
{
    return height;
}

- (void)setX:(CGFloat)x
{
    [CATransaction begin];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    background.position = CGPointMake(x, background.position.y);
    [CATransaction commit];
    [self setOpacities];
}

- (CGFloat)x
{
    return background.position.x;
}

- (void)setY:(CGFloat)y
{
    background.position = CGPointMake(background.position.x, y);
}

- (CGFloat)y
{
    return background.position.y;
}

- (void)changePart:(NSString *)firstImageName
{
    currentImageName = firstImageName;
    
    if (tileArray == nil) {
        //First time loading this. We need to set up our tile order.
        tileArray = [[NSMutableArray alloc] init];
        positions = [[NSMutableArray alloc] init];
        
        //Get our image widths and take our height from our first image
        int minimumWidth = overlap * 2;
        height = [Renderer getImageSize:firstImageName].height;
        if (autoWidth) {
            width = 0;
        }
        
        for (int i = 1; i <= numberOfTiles; i++) {
            widths[i - 1] = [Renderer getImageSize:[firstImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i]]].width;
            if (widths[i - 1] < minimumWidth) {
                minimumWidth = widths[i - 1];
            }
            width += widths[i - 1];
        }
        background.bounds = CGRectMake(0, 0, width, height);
        
        //Our overlap should be no more than half the minimum width of our images
        //(TODO: additional safety checks might be needed to discard images below a certain threshold.)
        if (minimumWidth / 2 < overlap) {
            overlap = minimumWidth / 2;
        }
        if (autoWidth) {
            width -= overlap * (numberOfTiles - 1);
        }
        originalSize = CGSizeMake(width, height);
        
        int currentPosition = 0;
        if (autoWidth) {
            NSMutableArray *imageNumbers = [[NSMutableArray alloc] init];
            for (int i = 1; i <= numberOfTiles; i++) {
                [imageNumbers addObject:[NSNumber numberWithInt:i]];
            }
            for (int i = 1; i <= numberOfTiles; i++) {
                int index = arc4random_uniform((int)[imageNumbers count]);
                
                //Save position data and image number for each tile. (Indexing of image number starts at 1.)
                [positions addObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:currentPosition], [imageNumbers objectAtIndex:index], nil]];
                
                currentPosition += widths[[[imageNumbers objectAtIndex:index] intValue] - 1] - overlap;
                [imageNumbers removeObjectAtIndex:index];
            }
            
        } else {
            while (currentPosition < width) {
                int imageNumber = arc4random_uniform((int)numberOfTiles) + 1;
                [positions addObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:currentPosition], [NSNumber numberWithInt:imageNumber], nil]];
                
                currentPosition += widths[imageNumber - 1] - overlap;
            }

        }
        
        for (int i = 0; i < [positions count]; i ++) {
            CALayer *tile = [CALayer layer];
            tile.bounds = CGRectMake(0, 0, widths[[[[positions objectAtIndex:i] objectAtIndex:1] intValue] - 1], height);
            tile.anchorPoint = CGPointZero;
            tile.position = CGPointMake([[[positions objectAtIndex:i] objectAtIndex:0] intValue], 0);
            
            //Currently load all of the necessary images. We'll have to change this if we
            //run into memory issues.
            tile.contents = (id)[Renderer cachedImage:[firstImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", [[[positions objectAtIndex:i] objectAtIndex:1] intValue]]]].CGImage;
            tile.opacity = 0;
            
            [background addSublayer:tile];
            [tileArray addObject:tile];
        }
        
        [self setOpacities];
        dataInitialised = YES;
    } else {
        //Every other time. Load the images for the new part.
        //(Don't make any changes to the dimensions of the tile set.)
        for (int i = 0; i < [positions count]; i++) {
            CALayer *currentTile = [tileArray objectAtIndex:i];
            currentTile.contents = (id)[Renderer cachedImage:[firstImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", [[[positions objectAtIndex:i] objectAtIndex:1] intValue]]]].CGImage;
        }
        
        //No need to call setOpacities here, as the tiles should already be correctly configured.
        //[self setOpacities];
    }
}

- (CGSize)originalSizeOfImages:(NSString *)firstImageName
{
    //We currently load different parts into tiles without changing any dimensions from the initial load,
    //so this returns the same value as the originalSize method.
    return originalSize;
}

- (CGSize)originalSize
{
    return originalSize;
}

- (OSCMessage *)getData
{
    if (!dataInitialised) {
        return nil;
    }
    
    //Collate our position data
    OSCMessage *data = [[OSCMessage alloc] init];
    for (int i = 0; i < [positions count]; i++) {
        [data addIntegerArgument:[[[positions objectAtIndex:i] objectAtIndex:0] intValue]];
        [data addIntegerArgument:[[[positions objectAtIndex:i] objectAtIndex:1] intValue]];
    }
    return data;
}

- (void)setData:(OSCMessage *)data
{
    //We should probably do some more data validation here, but for the moment, check that we have an
    //even number of integers.
    NSString *typeTag = [data.typeTag substringFromIndex:1];
    NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"i"] invertedSet];
    if (([typeTag rangeOfCharacterFromSet:invalidTags].location != NSNotFound) || ([typeTag length] % 2 == 1)) {
        return;
    }
    
    //We shouldn't be here if firstload hasn't happened. (Something has gone horribly wrong. Abort!)
    if (tileArray == nil) {
        return;
    }
    
    //Store our positions.
    [positions removeAllObjects];
    for (int i = 0; i < [data.arguments count]; i += 2) {
        [positions addObject:[NSArray arrayWithObjects:[data.arguments objectAtIndex:i], [data.arguments objectAtIndex:i + 1], nil]];
    }
    
    //Then empty our tile array and recreate it.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    background.sublayers = nil;
    [tileArray removeAllObjects];
    [Renderer clearCache];
    
    for (int i = 0; i < [positions count]; i ++) {
        CALayer *tile = [CALayer layer];
        tile.bounds = CGRectMake(0, 0, widths[[[[positions objectAtIndex:i] objectAtIndex:1] intValue] - 1], originalSize.height);
        tile.anchorPoint = CGPointZero;
        tile.position = CGPointMake([[[positions objectAtIndex:i] objectAtIndex:0] intValue], 0);
        tile.contents = (id)[Renderer cachedImage:[currentImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", [[[positions objectAtIndex:i] objectAtIndex:1] intValue]]]].CGImage;
        tile.opacity = 0;
        
        [background addSublayer:tile];
        [tileArray addObject:tile];
    }
    
    //Fix opacities and height.
    [self setOpacities];
    [self setHeight:height];
    [CATransaction commit];
}

@end

//
//  TiledScroller.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 6/12/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "TiledScroller.h"
#import <QuartzCore/QuartzCore.h>
#import "Renderer.h"

@interface TiledScroller()

- (void)loadNeededTilesWithLargeChange:(BOOL)largeChange;
- (void)loadImage:(NSString *)imageName intoLayer:(CALayer *)layer inBackground:(BOOL)backgrounded;
- (NSRange)neededTilesForAnnotationOfWidth:(CGFloat)width;

@end

@implementation TiledScroller {
    NSMutableArray *tileArray;
    NSMutableArray *annotationTileArray;
    CALayer *annotationLayer;
    BOOL *tileLoaded;
    
    NSMutableDictionary *originalSize;
    
    CGFloat tileWidth;
    int currentTile;
    NSString *currentImageName;
    NSString *annotationImageName;
    NSInteger buffer;
    
    CGFloat scoreWidth;
    NSInteger yOffset;
    
    BOOL debug;
}

@synthesize width, numberOfTiles, background, loadOccurred, annotationsDirectory, canvasSize, orientation;

- (void)loadNeededTilesWithLargeChange:(BOOL)largeChange
{
    //This shouldn't be called if there is only one tile.
    if (numberOfTiles == 1) {
        return;
    }
    
    //Load the current tile if it hasn't loaded for some reason.
    //(For example, the user has scrolled too quickly through the score).
    if (!tileLoaded[currentTile]) {
        tileLoaded[currentTile] = YES;
        [self loadImage:[currentImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", currentTile + 1]] intoLayer:[tileArray objectAtIndex:currentTile] inBackground:NO];
        [self loadImage:[annotationImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", currentTile + 1]] intoLayer:[annotationTileArray objectAtIndex:currentTile] inBackground:NO];
    }
    
    //Load (or clear) the tiles in the back buffer.
    int bufferLength = abs((int)background.position.x) % (int)tileWidth;
    for (int i = currentTile - 1; i >= 0; i--) {
        if (bufferLength > buffer) {
            ((CALayer *)[tileArray objectAtIndex:i]).contents = nil;
            ((CALayer *)[annotationTileArray objectAtIndex:i]).contents = nil;
            tileLoaded[i] = NO;
        } else if (!tileLoaded[i]) {
            tileLoaded[i] = YES;
            //If we've had a seek, load in the foreground, otherwise load in the background to try
            //to minize any discruption to the speed of playback.
            [self loadImage:[currentImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i + 1]] intoLayer:[tileArray objectAtIndex:i] inBackground:!largeChange];
            [self loadImage:[annotationImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i + 1]] intoLayer:[annotationTileArray objectAtIndex:i] inBackground:!largeChange];
        }
        bufferLength += tileWidth;
    }
    
    //Load the tiles in the forward buffer.
    bufferLength = background.position.x + ((currentTile + 1) * tileWidth) - 1024;
    for (int i = currentTile + 1; i < numberOfTiles; i ++) {
        if (bufferLength > buffer) {
            ((CALayer *)[tileArray objectAtIndex:i]).contents = nil;
            ((CALayer *)[annotationTileArray objectAtIndex:i]).contents = nil;
            tileLoaded[i] = NO;
        } else if (!tileLoaded[i]) {
            tileLoaded[i] = YES;
            [self loadImage:[currentImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i + 1]] intoLayer:[tileArray objectAtIndex:i] inBackground:!largeChange];
            [self loadImage:[annotationImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", i + 1]] intoLayer:[annotationTileArray objectAtIndex:i] inBackground:!largeChange];
        }
        bufferLength += tileWidth;
    }
}

- (void)loadImage:(NSString *)imageName intoLayer:(CALayer *)layer inBackground:(BOOL)backgrounded
{
    if (backgrounded) {
        //Load the image from disk in the background.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            UIImage *image = [UIImage imageWithContentsOfFile:imageName];
            
            //Draw the image into a trivial (1x1) graphics context to make the load actually happen
            //(TODO: This may not be needed any more need to carry out additional tests.)
            UIGraphicsBeginImageContext(CGSizeMake(1,1));
            CGContextRef context = UIGraphicsGetCurrentContext();
            CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), [image CGImage]);
            UIGraphicsEndImageContext();
            
            dispatch_async(dispatch_get_main_queue(), ^{
                //[self->background removeAllAnimations];
                //[CATransaction begin];
                //[CATransaction setDisableActions:YES];
                layer.contents = (id)image.CGImage;
                self->loadOccurred = YES;
                //NSLog(@"bam!");
                //[CATransaction commit];
            });
        });
    } else {
        [background removeAllAnimations];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        UIImage *image = [UIImage imageWithContentsOfFile:imageName];
        layer.contents = (id)image.CGImage;
        loadOccurred = YES;
        [CATransaction commit];
    }
}

- (NSRange)neededTilesForAnnotationOfWidth:(CGFloat)width
{
    if (numberOfTiles > 1) {
        //Find out how many tiles are involved, and clamp our values.
        NSInteger startTile = -background.position.x / tileWidth;
        startTile = startTile > 0 ? startTile : 0;
        
        NSInteger endTile = ((width - background.position.x) / tileWidth);
        endTile = endTile > numberOfTiles - 1 ? numberOfTiles - 1 : endTile;
        
        NSInteger number = 1 + endTile - startTile;
        return NSMakeRange(startTile, number);
    } else {
        return NSMakeRange(0, 1);
    }
}

- (void)dealloc
{
    free(tileLoaded);
}

#pragma mark - Scroller delegate

+ (BOOL)allowsParts {
    return YES;
}

+ (BOOL)requiresData {
    return NO;
}

+ (NSArray *)requiredOptions
{
    return nil;
}

- (id)initWithTiles:(NSInteger)tiles options:(NSMutableDictionary *)options
{
    self = [super init];
    
    //Check that our arguments are sane.
    if (tiles < 1) {
        tiles = 1;
    }
    
    numberOfTiles = tiles;
    tileLoaded = malloc(sizeof(BOOL) * numberOfTiles);
    loadOccurred = NO;
    
    //Set up the necessary layers. At this stage we don't load the image (this is done with changePart).
    //Because of this we'll use placeholder dimensions.
    
    background = [CALayer layer];
    background.bounds = CGRectMake(0, 0, numberOfTiles, 1);
    background.anchorPoint = CGPointZero;
    background.position = CGPointZero;
    
    annotationLayer = [CALayer layer];
    annotationLayer.bounds = CGRectMake(0, 0, numberOfTiles, 1);
    annotationLayer.anchorPoint = CGPointZero;
    annotationLayer.position = CGPointZero;
    
    currentTile = 0;
    originalSize = [[NSMutableDictionary alloc] init];
    scoreWidth = 0;
    
    tileArray = [[NSMutableArray alloc] init];
    for (int i = 0; i < numberOfTiles; i++) {
        //The current code assumes that all tiles are of the same width.
        CALayer *tile = [CALayer layer];
        tile.bounds = CGRectMake(0, 0, 1, 1);
        tile.anchorPoint = CGPointZero;
        tile.position = CGPointMake(i, 0);
        [background addSublayer:tile];
        [tileArray addObject:tile];
    }
    
    debug = NO;
    annotationTileArray = [[NSMutableArray alloc] init];
    for (int i = 0; i < numberOfTiles; i++) {
        CALayer *annotationTile = [CALayer layer];
        annotationTile.bounds = CGRectMake(0, 0, 1, 1);
        annotationTile.anchorPoint = CGPointZero;
        annotationTile.position = CGPointMake(i, 0);
        if (debug) {
            annotationTile.backgroundColor = [UIColor colorWithRed:(i + 1) % 2 green:0 blue:i % 2 alpha:0.15].CGColor;
        }
        [annotationLayer addSublayer:annotationTile];
        [annotationTileArray addObject:annotationTile];
    }
    
    [background addSublayer:annotationLayer];
    
    //Set the desired pixel length on either side of the screen that should be buffered in.
    //This is currently hard coded.
    buffer = 4000;
    
    //If we're using more than one tile then we're likely dealing with a big score.
    //Clear any cached images in an attempt to avoid any memory issues.
    if (numberOfTiles > 1) {
        [Renderer clearCache];
    }
    
    yOffset = 0;
    
    return self;
}

- (void)setHeight:(CGFloat)newHeight
{
    //Calculate the new width
    tileWidth = (int)roundf(([[originalSize objectForKey:currentImageName] CGSizeValue]).width / numberOfTiles) * newHeight / ([[originalSize objectForKey:currentImageName] CGSizeValue]).height;
    width = tileWidth * numberOfTiles;
    height = newHeight;
    
    //Resize the layers
    background.bounds = CGRectMake(0, 0, width, height);
    annotationLayer.bounds = CGRectMake(0, 0, width, height);
    for (int i = 0; i < numberOfTiles; i++) {
        ((CALayer *)[tileArray objectAtIndex:i]).bounds = CGRectMake(0, 0, tileWidth, height);
        ((CALayer *)[tileArray objectAtIndex:i]).position = CGPointMake(i * tileWidth, 0);
        
        //We may have to adjust the height of these later so that they take up the full screen
        //if our score is centred, but we check this when the position of the background layer is moved.
        ((CALayer *)[annotationTileArray objectAtIndex:i]).bounds = CGRectMake(0, 0, tileWidth, height);
        ((CALayer *)[annotationTileArray objectAtIndex:i]).position = CGPointMake(i * tileWidth, 0);
    }
    
    if (numberOfTiles > 1) {
        [self loadNeededTilesWithLargeChange:YES];
    }
}

- (CGFloat)height
{
    return height;
}

- (void)setX:(CGFloat)x
{
    BOOL largeChange = (fabs(x - background.position.x) > 100);
    [CATransaction begin];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    background.position = CGPointMake(x, background.position.y);
    [CATransaction commit];
    
    if (numberOfTiles > 1) {
        currentTile = -background.position.x / (int)tileWidth;
        NSLog(@"%f, %f, %i, %i", x, -background.position.x, (int)tileWidth, currentTile);
        //Check bounds in case of LV. (Who creates a score that's so tiny anyway?)
        if (currentTile < 0) {
            currentTile = 0;
        } else if (currentTile >= numberOfTiles) {
            //In some rare instances the currentTile ends up out of bounds. Check for this.
            //(It usually happens when a score has its playhead positioned right against
            //the left edge of the screen.)
            currentTile = (int)numberOfTiles - 1;
        }
        [self loadNeededTilesWithLargeChange:largeChange];
    }
}

- (CGFloat)x
{
    return background.position.x;
}

- (void)setY:(CGFloat)y
{
    background.position = CGPointMake(background.position.x, y);
    
    //Check if we have a vertical offset.
    if (y > 0) {
        //Clamp the height of our annotation layer to landscape size or the original
        //image size. (Whichever is highest.)
        
        NSInteger maxHeight = (MIN(canvasSize.width, canvasSize.height) - LOWER_PADDING);
        NSInteger height = background.bounds.size.height;
        height = height > maxHeight ? height : maxHeight;
        
        annotationLayer.bounds = CGRectMake(0, 0, tileWidth * numberOfTiles, height);
        yOffset = (canvasSize.height - LOWER_PADDING - height) / 2;
        annotationLayer.position = CGPointMake(0, yOffset - y);
        //Make sure our annotation tiles fill the screen space.
        for (int i = 0; i < [annotationTileArray count]; i++) {
            ((CALayer *)[annotationTileArray objectAtIndex:i]).bounds = CGRectMake(0, 0, tileWidth, height);
        }
    } else {
        annotationLayer.position = CGPointMake(0, 0);
        yOffset = 0;
    }
}

- (CGFloat)y
{
    return background.position.y;
}

- (void)changePart:(NSString *)firstImageName
{
    currentImageName = firstImageName;
    annotationImageName = [[currentImageName lastPathComponent] stringByDeletingPathExtension];
    annotationImageName = [[annotationsDirectory stringByAppendingPathComponent:annotationImageName] stringByAppendingPathExtension:@"png"];
    
    for (int i = 0; i < numberOfTiles; i++) {
        ((CALayer *)[tileArray objectAtIndex:i]).contents = nil;
        tileLoaded[i] = NO;
    }
    
    UIImage *image, *annotationImage;
    if (numberOfTiles == 1) {
        image = [Renderer cachedImage:currentImageName];
        annotationImage = [UIImage imageWithContentsOfFile:annotationImageName];
    } else {
        image = [UIImage imageWithContentsOfFile:[currentImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", currentTile + 1]]];
        annotationImage = [UIImage imageWithContentsOfFile:[annotationImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", currentTile + 1]]];
    }
    
    //Update the necessary properties and store the original size for later use.
    width = image.size.width * numberOfTiles;
    height = image.size.height;
    tileWidth = image.size.width;
    
    //The player has been letting through scores with only one tile where the
    //parts are different widths. (And the creator hasn't been blocking their
    //creation as it should have. Work around this.)
    if (numberOfTiles == 1) {
        if (scoreWidth == 0) {
            scoreWidth = width;
        }
        if (width != scoreWidth) {
            width = scoreWidth;
            height = height * (scoreWidth / width);
        }
    }
    
    if ([originalSize objectForKey:currentImageName] == nil) {
        [originalSize setObject:[NSValue valueWithCGSize:CGSizeMake(width, height)] forKey:currentImageName];
    }
    
    //Load the image. We don't need to set the loadOccurred flag here.
    //(The player will assume that it needs to resynch if it is calling this method in the first place.)
    ((CALayer *)[tileArray objectAtIndex:currentTile]).contents = (id)image.CGImage;
    ((CALayer *)[annotationTileArray objectAtIndex:currentTile]).contents = (id)annotationImage.CGImage;
    tileLoaded[currentTile] = YES;
    
    //Resize the layers to match the image size.
    background.bounds = CGRectMake(0, 0, width, height);
    annotationLayer.bounds = CGRectMake(0, 0, width, height);
    for (int i = 0; i < numberOfTiles; i++) {
        ((CALayer *)[tileArray objectAtIndex:i]).bounds = CGRectMake(0, 0, tileWidth, height);
        ((CALayer *)[tileArray objectAtIndex:i]).position = CGPointMake(i * tileWidth, 0);
        
        ((CALayer *)[annotationTileArray objectAtIndex:i]).bounds = CGRectMake(0, 0, tileWidth, height);
        ((CALayer *)[annotationTileArray objectAtIndex:i]).position = CGPointMake(i * tileWidth, 0);
    }
    
    if (numberOfTiles > 1) {
        [self loadNeededTilesWithLargeChange:YES];
    }
}

- (CGSize)originalSizeOfImages:(NSString *)firstImageName
{
    return [[originalSize objectForKey:firstImageName] CGSizeValue];
}

- (CGSize)originalSize
{
    return [[originalSize objectForKey:currentImageName] CGSizeValue];
}

- (UIImage *)currentAnnotationImage
{
    NSRange tileRange;
    CGFloat imageScale;
    CGSize imageSize;
    
    if (orientation == kHorizontal) {
        tileRange = [self neededTilesForAnnotationOfWidth:canvasSize.width];
        imageScale = (annotationLayer.bounds.size.height) / (MIN(canvasSize.width, canvasSize.height) - LOWER_PADDING);
        imageSize = CGSizeMake(canvasSize.width, canvasSize.height);
    } else {
        tileRange = [self neededTilesForAnnotationOfWidth:canvasSize.height];
        imageScale = (annotationLayer.bounds.size.height) / MAX(canvasSize.width, canvasSize.height);
        imageSize = CGSizeMake(canvasSize.height, canvasSize.width);
    }
    
    UIGraphicsBeginImageContextWithOptions(imageSize, NO, 1);
    CGContextRef currentContext = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(currentContext, kCGInterpolationHigh);
    CGContextSetShouldAntialias(currentContext, NO);
    for (NSInteger i = tileRange.location; i < tileRange.location + tileRange.length; i++) {
        CGFloat startOffset = background.position.x + (tileWidth * i);
        UIImage *currentImage;
        if (numberOfTiles > 1) {
            currentImage = [UIImage imageWithContentsOfFile:[annotationImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", (int)i + 1]]];
        } else {
            currentImage = [UIImage imageWithContentsOfFile:annotationImageName];
        }

        if (currentImage != nil) {
            [currentImage drawInRect:CGRectMake(startOffset, yOffset, roundf(currentImage.size.width * imageScale), roundf(currentImage.size.height * imageScale))];
        }
    }
    
    UIImage *annotationImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    //Rotate our final image if necessary.
    if (orientation == kUp) {
        annotationImage = [Renderer rotateImage:annotationImage byRadians:M_PI_2];
    } else if (orientation == kDown) {
        annotationImage = [Renderer rotateImage:annotationImage byRadians:-M_PI_2];
    }
    
    return annotationImage;
}

- (CALayer *)currentAnnotationMask
{
    if (yOffset == 0 && background.position.x <= 0 && (background.position.x >= canvasSize.width - background.bounds.size.width)) {
        return nil;
    }
    //Add a mask to our annotation layer so that the user won't see anything that's
    //not going to be saved. (Both for narrow scores and at the starts and end of scores.)

    CALayer *maskLayer = [CALayer layer];
    maskLayer.frame = CGRectMake(0, 0, canvasSize.width, canvasSize.height);
    CALayer *mask = [CALayer layer];
    mask.anchorPoint = CGPointZero;
    if (orientation == kHorizontal) {
        mask.frame = CGRectMake(0, yOffset, canvasSize.width, canvasSize.height - LOWER_PADDING - (2 * yOffset));
    } else {
        mask.frame = CGRectMake(yOffset, 0, canvasSize.width - (2 * yOffset), canvasSize.height);
    }
    mask.backgroundColor = [UIColor blackColor].CGColor;
    if (background.position.x > 0) {
        if (orientation == kHorizontal) {
            mask.position = CGPointMake(background.position.x, mask.position.y);
        } else if (orientation == kUp) {
            mask.position = CGPointMake(mask.position.x, background.position.x);
        } else {
            mask.position = CGPointMake(mask.position.x, -background.position.x);
        }
    } else if (background.position.x < canvasSize.width - background.bounds.size.width) {
        if (orientation == kHorizontal) {
            mask.position = CGPointMake(background.position.x + background.bounds.size.width - canvasSize.width, mask.position.y);
        } else if (orientation == kUp) {
            mask.position = CGPointMake(mask.position.x, background.position.x + background.bounds.size.width - canvasSize.height);
        } else {
            mask.position = CGPointMake(mask.position.x, canvasSize.height - background.position.x - background.bounds.size.width);
        }
    }
    [maskLayer addSublayer:mask];
    return maskLayer;
}

- (void)saveCurrentAnnotation:(UIImage *)image
{
    CGFloat imageHeight;
    if (orientation == kHorizontal) {
        //Use an image size geared towards our landscape height.
        imageHeight = MIN(canvasSize.width, canvasSize.height) - LOWER_PADDING;
    } else {
        imageHeight = MAX(canvasSize.width, canvasSize.height);
        //Rotate our image.
        if (orientation == kDown) {
            image = [Renderer rotateImage:image byRadians:M_PI_2];
        } else {
            image = [Renderer rotateImage:image byRadians:-M_PI_2];
        }
    }
    
    NSRange tileRange = [self neededTilesForAnnotationOfWidth:image.size.width];
    CGFloat imageScale = imageHeight / annotationLayer.bounds.size.height;
    CGFloat imageWidth = roundf(tileWidth * imageScale);
    
    for (NSInteger i = tileRange.location; i < tileRange.location + tileRange.length; i++) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(imageWidth, imageHeight), NO, 1);
        CGContextRef currentContext = UIGraphicsGetCurrentContext();
        CGContextSetInterpolationQuality(currentContext, kCGInterpolationHigh);
        CGContextSetShouldAntialias(currentContext, NO);
        NSString *imageName;
        if (numberOfTiles > 1) {
            imageName = [annotationImageName stringByReplacingOccurrencesOfString:@"_1." withString:[NSString stringWithFormat:@"_%i.", (int)i + 1]];
        } else {
            imageName = annotationImageName;
        }
        //If our image already exists, load it and copy it into the graphics context.
        UIImage *currentImage = [UIImage imageWithContentsOfFile:imageName];
        if (currentImage != nil) {
            [currentImage drawInRect:CGRectMake(0, 0, imageWidth, imageHeight)];
        }
        
        CGFloat startOffset = roundf((-background.position.x - (tileWidth * i)) * imageScale);
        //Overwrite the part of our image contained on the screen.
        [image drawInRect:CGRectMake(startOffset, roundf(-yOffset * imageScale), roundf(image.size.width * imageScale), roundf(image.size.height * imageScale)) blendMode:kCGBlendModeCopy alpha:1];
        UIImage *currentTile = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        //Write our image to both the current annotation tile and to disk.
        ((CALayer *)[annotationTileArray objectAtIndex:i]).contents = (id)currentTile.CGImage;
        [UIImagePNGRepresentation(currentTile) writeToFile:imageName atomically:YES];
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

@end

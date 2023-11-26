//
//  OverlayScroller.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 25/9/2023.
//  Copyright (c) 2023 Decibel. All rights reserved.
//

#import "OverlayScroller.h"
#import "OverlayLayer.h"

@implementation OverlayScroller {
    
}

#pragma mark - Scroller delegate

- (id)initWithTiles:(NSInteger)tiles options:(NSMutableDictionary *)options
{
    self = [super initWithTiles:tiles options:options];
    
    for (NSString *key in options) {
        if ([[options objectForKey:key] isKindOfClass:[NSArray class]]) {
            NSArray *array = [options objectForKey:key];
            for (int i = 0; i < [array count]; i++) {
                NSLog(@"%@", [array objectAtIndex:i]);
            }
        }
    }
    
    return self;
}

+ (NSArray *)arrayTags
{
    return [NSArray arrayWithObject:@"overlays"];
}

+ (NSArray *)dictionaryTags
{
    return [NSArray arrayWithObject:@"overlay"];
}

@end

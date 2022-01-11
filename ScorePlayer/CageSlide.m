//
//  CageSlide.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 16/08/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import "CageSlide.h"

@implementation CageSlide {
    NSMutableArray *dots;
    NSMutableArray *lines;
    
    NSInteger width;
    NSInteger height;
}

- (NSInteger)dotCount
{
    return [dots count];
}

- (NSInteger)lineCount
{
    return [lines count];
}

- (id)initWithWidth:(NSInteger)slideWidth height:(NSInteger)slideHeight
{
    self = [super init];
    if (self) {
        dots = [[NSMutableArray alloc] init];
        lines = [[NSMutableArray alloc] init];
        width = slideWidth;
        height = slideHeight;
    }
    
    return self;
}

- (void)addDot:(Dot)dot
{
    [dots addObject:[NSValue value:&dot withObjCType:@encode(Dot)]];
}

- (void)addLine:(Line)line
{
    [lines addObject:[NSValue value:&line withObjCType:@encode(Line)]];
}

- (void)rotate
{
    //Rotates the slide clockwise by 90 degrees.
    NSMutableArray *newDots = [[NSMutableArray alloc] initWithCapacity:[dots count]];
    NSMutableArray *newLines = [[NSMutableArray alloc] initWithCapacity:[lines count]];
    
    for (int i = 0; i < [dots count]; i++) {
        Dot dot, newDot;
        [[dots objectAtIndex:i] getValue:&dot];
        newDot.location.x = height - dot.location.y;
        newDot.location.y = dot.location.x;
        newDot.events = dot.events;
        [newDots addObject:[NSValue value:&newDot withObjCType:@encode(Dot)]];
    }
    
    for (int i = 0; i < [lines count]; i++) {
        Line line, newLine;
        [[lines objectAtIndex:i] getValue:&line];
        newLine.start.x = height - line.start.y;
        newLine.start.y = line.start.x;
        newLine.end.x = height - line.end.y;
        newLine.end.y = line.end.x;
        [newLines addObject:[NSValue value:&newLine withObjCType:@encode(Line)]];
    }
    
    dots = newDots;
    lines = newLines;
}

- (void)flip
{
    //Flips the slide about the vertical axis.
    NSMutableArray *newDots = [[NSMutableArray alloc] initWithCapacity:[dots count]];
    NSMutableArray *newLines = [[NSMutableArray alloc] initWithCapacity:[lines count]];
    
    for (int i = 0; i < [dots count]; i++) {
        Dot dot;
        [[dots objectAtIndex:i] getValue:&dot];
        dot.location.x = width = dot.location.x;
        [newDots addObject:[NSValue value:&dot withObjCType:@encode(Dot)]];
    }
    
    for (int i = 0; i < [lines count]; i++) {
        Line line;
        [[lines objectAtIndex:i] getValue:&line];
        line.start.x = width - line.start.x;
        line.end.x = width - line.start.x;
        [newLines addObject:[NSValue value:&line withObjCType:@encode(Line)]];
    }
    
    dots = newDots;
    lines = newLines;
}

- (void)randomizeDotOrder
{
    NSMutableArray *newDots = [[NSMutableArray alloc] initWithCapacity:[dots count]];
    
    while ([dots count] > 0) {
        int index = arc4random_uniform((int)[dots count]);
        [newDots addObject:[dots objectAtIndex:index]];
        [dots removeObjectAtIndex:index];
    }
    
    dots = newDots;
}

- (void)randomizeLineOrder
{
    NSMutableArray *newLines = [[NSMutableArray alloc] initWithCapacity:[lines count]];
    
    while ([lines count] > 0) {
        int index = arc4random_uniform((int)[lines count]);
        [newLines addObject:[lines objectAtIndex:index]];
        [lines removeObjectAtIndex:index];
    }
    
    lines = newLines;
}

- (Dot)getDot:(uint)index
{
    if (index < [dots count]) {
        Dot dot;
        [[dots objectAtIndex:index] getValue:&dot];
        return dot;
    } else {
        return DotMake(0, 0, 0);
    }
}

- (Dot)getDotCentredZero:(uint)index
{
    //Returns the chosen dot with (0, 0) at the centre of the slide.
    if (index < [dots count]) {
        Dot dot;
        [[dots objectAtIndex:index] getValue:&dot];
        dot.location.x -= (int)(width / 2);
        dot.location.y -= (int)(height / 2);
        return dot;
    } else {
        return DotMake(0, 0, 0);
    }
}

- (Line)getLine:(uint)index
{
    if (index < [lines count]) {
        Line line;
        [[lines objectAtIndex:index] getValue:&line];
        return line;
    } else {
        return LineMake(0, 0, 0, 0);
    }
}

- (Line)getLineCentredZero:(uint)index
{
    //Returns the chosen line with (0, 0) at the centre of the slide.
    if (index < [lines count]) {
        Line line;
        [[lines objectAtIndex:index] getValue:&line];
        line.start.x -= (int)(width /2);
        line.start.y -= (int)(height / 2);
        line.end.x -= (int)(width / 2);
        line.end.y -= (int)(height / 2);
        return line;
    } else {
        return LineMake(0, 0, 0, 0);
    }
}

@end

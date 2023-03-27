//
//  CageSlide.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 16/08/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct {
    CGPoint start;
    CGPoint end;
} Line;

typedef struct {
    CGPoint location;
    NSInteger events;
} Dot;

static inline Line LineMake(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2)
{
    Line line;
    line.start.x = x1;
    line.start.y = y1;
    line.end.x = x2;
    line.end.y = y2;
    return line;
}

static inline Dot DotMake(CGFloat x, CGFloat y, NSInteger number)
{
    Dot dot;
    dot.location.x = x;
    dot.location.y = y;
    dot.events = number;
    return dot;
}

@interface CageSlide : NSObject

@property (nonatomic, readonly) NSInteger dotCount;
@property (nonatomic, readonly) NSInteger lineCount;

- (id)initWithWidth:(NSInteger)slideWidth height:(NSInteger)slideHeight;
- (void)addDot:(Dot)dot;
- (void)addLine:(Line)line;
- (void)rotate; //Clockwise
- (void)flip;
- (void)randomizeDotOrder;
- (void)randomizeLineOrder;

- (Dot)getDot:(uint)index;
- (Dot)getDotCentredZero:(uint)index;
- (Line)getLine:(uint)index;
- (Line)getLineCentredZero:(uint)index;

@end

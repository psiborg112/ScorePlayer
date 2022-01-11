//
//  Train.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 25/07/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "Train.h"

@implementation Train {
    CGPoint position;
}

//@synthesize currentPath, initialPathIndex, destinationIndex, direction, speed, movementVector, isMoving, atJunction, inEndZone, stopLength, junctionLength, waitTime, assignedPart, sprite;
@synthesize currentPath, initialPathIndex, destinationIndex, speed, movementVector, isMoving, atJunction, inEndZone, stopLength, junctionLength, waitTime, assignedPart, sprite;

- (id)initWithPart:(NSInteger)partIndex
{
    self = [super init];
    speed = 1;
    waitTime = 0;
    assignedPart = partIndex;
    inEndZone = NO;
    
    //Set up the train CALayer object
    sprite = [CALayer layer];
    sprite.frame = CGRectMake(0, 0, 20, 20);
    sprite.cornerRadius = 10;
    sprite.borderWidth = 3;
    sprite.borderColor = [UIColor blackColor].CGColor;
    sprite.backgroundColor = [UIColor whiteColor].CGColor;
    return self;
}

- (void)setPosition:(CGPoint)newPosition
{
    position = newPosition;
    if (sprite != nil) {
        sprite.position = position;
    }
}

- (CGPoint)position
{
    return position;
}

- (void)setDirection:(NSInteger)newDirection
{
    if (newDirection > 1 || direction < -1) {
        return;
    }
    direction = newDirection;
}

- (NSInteger)direction
{
    return direction;
}

- (void)move
{
    //Moves the train by adding one frame
    position = CGPointMake(position.x + movementVector.x, position.y + movementVector.y);
    sprite.position = position;
}

- (void)calculateVector
{
    if (CGPointEqualToPoint(position, [[currentPath objectAtIndex:destinationIndex] CGPointValue])) {
        movementVector = CGPointZero;
        return;
    }
    //Check to see if we're moving in a vertical line. (In which case we can't use arctan because
    //of a divide by zero.)
    if ([[currentPath objectAtIndex:destinationIndex] CGPointValue].x - position.x == 0) {
        if ([[currentPath objectAtIndex:destinationIndex] CGPointValue].y > position.y) {
            movementVector = CGPointMake(0, speed);
        } else {
            movementVector = CGPointMake(0, -speed);
        }
        return;
    } else {
        CGFloat angle = atan2f([[currentPath objectAtIndex:destinationIndex] CGPointValue].y - position.y, [[currentPath objectAtIndex:destinationIndex] CGPointValue].x - position.x);
        movementVector = CGPointMake(speed * cosf(angle), speed * sinf(angle));
    }
}

- (void)resetPosition {
    position = [[currentPath objectAtIndex:destinationIndex] CGPointValue];
    sprite.position = position;
}

@end

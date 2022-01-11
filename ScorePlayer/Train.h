//
//  Train.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 25/07/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Train : NSObject {
    __weak NSMutableArray *currentPath;
    NSInteger destinationIndex;
    NSInteger direction;
    CGFloat speed;
    CGPoint movementVector;
    BOOL isMoving;
    NSInteger atJunction;
    BOOL inEndZone;
    NSInteger waitTime;
    
    CALayer *sprite;
}

@property (nonatomic, weak) NSMutableArray *currentPath;
@property (nonatomic) NSInteger initialPathIndex;
@property (nonatomic) NSInteger destinationIndex;
@property (nonatomic) CGPoint position;
@property (nonatomic) NSInteger direction;
@property (nonatomic) CGFloat speed;
@property (nonatomic, readonly) CGPoint movementVector;
@property (nonatomic) BOOL isMoving;
@property (nonatomic) NSInteger atJunction;
@property (nonatomic) BOOL inEndZone;
@property (nonatomic) NSInteger stopLength;
@property (nonatomic) NSInteger junctionLength;
@property (nonatomic) NSInteger waitTime;
@property (nonatomic, readonly) NSInteger assignedPart;

@property (nonatomic, strong) CALayer *sprite;

- (id)initWithPart:(NSInteger)partIndex;
- (void)move;
- (void)calculateVector;
- (void)resetPosition;

@end

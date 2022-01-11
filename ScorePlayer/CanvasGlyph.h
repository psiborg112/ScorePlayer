//
//  CanvasGlyph.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/9/18.
//  Copyright (c) 2018 Decibel. All rights reserved.

#import "CanvasText.h"

@interface CanvasGlyph : CanvasText {
    NSString *glyphType;
    
    //These are used as storage variables by the CanvasStave class.
    CGFloat stavePosition;
    CanvasGlyph *accidental;
    NSMutableArray *ledgerLines;
    NSInteger duration;
}

@property (nonatomic, strong) NSString *glyphType;
@property (nonatomic) CGFloat stavePosition;
@property (nonatomic, strong) CanvasGlyph *accidental;
@property (nonatomic, strong) NSMutableArray *ledgerLines;
@property (nonatomic) NSInteger duration;

@end

//
//  CanvasStave.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 23/9/18.
//

#import "CanvasStave.h"
#import "CanvasGlyph.h"

@interface CanvasStave ()

- (NSArray *)getSortedClefPositions;
- (NSInteger)getIndexOfClefAtPosition:(NSInteger)position;
- (NSString *)activeClefForPosition:(NSInteger)position;
- (NSInteger)positionOfFirstNote;
- (void)adjustNotesForClefChangeFrom:(NSInteger)position to:(NSInteger)endPosition;

@end

@implementation CanvasStave {
    NSMutableArray *staveLines;
    NSMutableDictionary *clefGlyphs;
    NSMutableDictionary *noteGlyphs;
    
    NSMutableDictionary *clefs;
    NSMutableDictionary *notes;
    
    NSArray *clefPositionsSorted;
    
    int rgba[4];
}

@synthesize containerLayer, partNumber, parentLayer;

- (NSArray *)getSortedClefPositions
{
    //Return a sorted list of our clef positions so that we know how to draw notes, when they need to
    //change, and when clefs can be removed without causing ambiguity.
    NSArray *keys = [clefs allKeys];
    
    if ([keys count] < 1) {
        //Return nil if no clefs.
        return nil;
    }
    NSMutableArray *clefPositions = [[NSMutableArray alloc] init];
    for (int i = 0; i < [keys count]; i++) {
        [clefPositions addObject:[NSNumber numberWithInteger:[[keys objectAtIndex:i] integerValue]]];
    }
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES];
    return [clefPositions sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
}

- (NSInteger)getIndexOfClefAtPosition:(NSInteger)position
{
    NSInteger index;
    if ([clefPositionsSorted count] < 1) {
        return -1;
    }
    for (index = 0; index < [clefPositionsSorted count]; index++) {
        if (position == [[clefPositionsSorted objectAtIndex:index] integerValue]) {
            break;
        }
    }
    return index;
}

- (NSString *)activeClefForPosition:(NSInteger)position
{
    int index;
    for (index = 0; index < [clefPositionsSorted count]; index++) {
        if ([[clefPositionsSorted objectAtIndex:index] integerValue] > position) {
            break;
        }
    }
    
    if (index == 0) {
        return nil;
    } else {
        return [clefs objectForKey:[[clefPositionsSorted objectAtIndex:index - 1] stringValue]];
    }
}

- (NSInteger)positionOfFirstNote
{
    NSArray *keys = [notes allKeys];
    if ([keys count] < 1) {
        //Return the maximum value for an NSInteger.
        //This function shouldn't be called if this is the expected outcome. Check conditions first.
        return NSIntegerMax;
    }
    
    NSInteger lowestKey = [[keys objectAtIndex:0] integerValue];
    for (int i = 1; i < [keys count]; i++) {
        if ([[keys objectAtIndex:i] integerValue] < lowestKey) {
            lowestKey = [[keys objectAtIndex:i] integerValue];
        }
    }
    
    return lowestKey;
}

- (void)adjustNotesForClefChangeFrom:(NSInteger)position to:(NSInteger)endPosition
{
    //Adjust notes because of a clef change.
    NSArray *noteKeys = [notes allKeys];
    for (int i = 0; i < [noteKeys count]; i++) {
        NSInteger notePosition = [[noteKeys objectAtIndex:i] integerValue];
        if (notePosition >= position && notePosition < endPosition) {
            for (int j = 0; j < [[notes objectForKey:[noteKeys objectAtIndex:i]] count]; j++) {
                NSInteger noteDuration = ((CanvasGlyph *)[noteGlyphs objectForKey:[NSString stringWithFormat:@"%@:%@", [noteKeys objectAtIndex:i], [[notes objectForKey:[noteKeys objectAtIndex:i]] objectAtIndex:j]]]).duration;
                NSString *noteString = [[notes objectForKey:[noteKeys objectAtIndex:i]] objectAtIndex:j];
                [self removeNote:noteString atPosition:notePosition];
                [self addNote:noteString atPosition:notePosition ofDuration:noteDuration];
            }
        }
    }
}

#pragma mark CanvasObject delegate

- (id)initWithScorePath:(NSString *)path;
{
    self = [super init];
    containerLayer = [CALayer layer];
    containerLayer.anchorPoint = CGPointZero;
    containerLayer.masksToBounds = NO;
    
    for (int i = 0; i < 4; i++) {
        rgba[i] = 0;
    }
    
    //Set up our stave lines.
    staveLines = [[NSMutableArray alloc] init];
    for (int i = 0; i < 5; i ++) {
        CALayer *line = [CALayer layer];
        line.anchorPoint = CGPointMake(0, 0.5);
        line.position = CGPointZero;
        [containerLayer addSublayer:line];
        [staveLines addObject:line];
    }
    
    clefGlyphs = [[NSMutableDictionary alloc] init];
    noteGlyphs = [[NSMutableDictionary alloc] init];
    clefs = [[NSMutableDictionary alloc] init];
    notes = [[NSMutableDictionary alloc] init];
    
    [self setColour:@"0,0,0,255"];
    
    return self;
}

- (CALayer *)objectLayer
{
    return containerLayer;
}

- (void)setHidden:(BOOL)hidden
{
    containerLayer.hidden = hidden;
}

- (BOOL)hidden
{
    return containerLayer.hidden;
}

- (void)setPosition:(CGPoint)position
{
    containerLayer.position = position;
}

- (CGPoint)position
{
    return containerLayer.position;
}

- (void)setSize:(CGSize)size
{
    containerLayer.frame = CGRectMake(containerLayer.frame.origin.x, containerLayer.frame.origin.y, size.width, size.height);
    for (int i = 0; i < [staveLines count]; i++) {
        CALayer *line = [staveLines objectAtIndex:i];
        line.bounds = CGRectMake(0, 0, size.width, line.bounds.size.height);
        line.position = CGPointMake(0, i * (size.height) / 4.0);
    }
    
    NSArray *keys = [clefGlyphs allKeys];
    for (int i = 0; i < [keys count]; i++) {
        CanvasGlyph *currentClef = [clefGlyphs objectForKey:[keys objectAtIndex:i]];
        currentClef.fontSize = size.height;
        currentClef.position = CGPointMake(currentClef.position.x, currentClef.stavePosition * size.height);
    }
    
    keys = [noteGlyphs allKeys];
    for (int i = 0; i < [keys count]; i++) {
        CanvasGlyph *currentNote = [noteGlyphs objectForKey:[keys objectAtIndex:i]];
        currentNote.fontSize = size.height;
        currentNote.position = CGPointMake(currentNote.position.x, currentNote.stavePosition * size.height);
        if (currentNote.accidental != nil) {
            currentNote.accidental.fontSize = size.height;
            currentNote.accidental.position = CGPointMake(currentNote.position.x - (2 * size.height / 8.0) - (currentNote.size.width * currentNote.containerLayer.anchorPoint.x), currentNote.stavePosition * containerLayer.bounds.size.height);
        }
        for (int i = 0; i < [currentNote.ledgerLines count]; i++) {
            CALayer *ledgerLine = [currentNote.ledgerLines objectAtIndex:i];
            CGFloat position;
            if (currentNote.stavePosition < 0) {
                position = -(size.height / 4.0) * (CGFloat)(i + 1);
                
            } else {
                position = size.height + ((size.height / 4.0) * (CGFloat)(i + 1));
            }
            ledgerLine.position = CGPointMake(ledgerLine.position.x, position);
            ledgerLine.bounds = CGRectMake(0, 0, (4.5 * containerLayer.bounds.size.height / 8.0), ((CALayer *)[staveLines objectAtIndex:0]).bounds.size.height);
        }
    }
}

- (CGSize)size
{
    return CGSizeMake(containerLayer.bounds.size.width, containerLayer.bounds.size.height);
}

- (void)setColour:(NSString *)colour
{
    [Canvas colourString:colour toArray:rgba];
    for (int i = 0; i < [staveLines count]; i++) {
        ((CALayer *)[staveLines objectAtIndex:i]).backgroundColor = [UIColor colorWithRed:(rgba[0] / 255.0) green:(rgba[1] / 255.0) blue:(rgba[2] / 255.0) alpha:(rgba[3] / 255.0)].CGColor;
    }
}

- (NSString *)colour{
    return [NSString stringWithFormat:@"%i,%i,%i,%i", rgba[0], rgba[1], rgba[2], rgba[3]];
}

- (void)setOpacity:(CGFloat)opacity
{
    //Clamp value to between 0 and 1.
    opacity = opacity > 1 ? 1 : opacity;
    opacity = opacity < 0 ? 0 : opacity;
    containerLayer.opacity = opacity;
}

- (CGFloat)opacity
{
    return containerLayer.opacity;
}

- (void)setLineWidth:(NSInteger)lineWidth
{
    for (int i = 0; i < [staveLines count]; i++) {
        CALayer *line = [staveLines objectAtIndex:i];
        line.bounds = CGRectMake(0, 0, line.bounds.size.width, lineWidth);
    }
    
    NSArray *noteKeys = [noteGlyphs allKeys];
    for (int i = 0; i < [noteKeys count]; i++) {
        for (int j = 0; j < [((CanvasGlyph *)[noteGlyphs objectForKey:[noteKeys objectAtIndex:i]]).ledgerLines count]; j++) {
            CALayer *ledgerLine = [((CanvasGlyph *)[noteGlyphs objectForKey:[noteKeys objectAtIndex:i]]).ledgerLines objectAtIndex:j];
            ledgerLine.bounds = CGRectMake(ledgerLine.bounds.origin.x, ledgerLine.bounds.origin.y, ledgerLine.bounds.size.width, lineWidth);
        }
    }
}

- (NSInteger)lineWidth
{
    return ((CALayer *)[staveLines objectAtIndex:0]).bounds.size.height;
}

- (void)setClefCollection:(NSString *)clefCollection
{
    NSArray *collection = [clefCollection componentsSeparatedByString:@";"];
    for (int i = 0; i < [collection count]; i++) {
        //Add our clefs
        NSArray *clefData = [[collection objectAtIndex:i] componentsSeparatedByString:@","];
        //Allow the array to be bigger to leave room for future growth.
        if ([clefData count] >= 2) {
            [self setClef:[clefData objectAtIndex:1] atPosition:[[clefData objectAtIndex:0] integerValue]];
        }
    }
}

- (NSString *)clefCollection
{
    NSMutableString *result = [[NSMutableString alloc] init];
    NSArray *keys = [clefs allKeys];
    for (int i = 0; i < [keys count]; i++) {
        if (i == 0) {
            [result appendFormat:@"%@,%@", [keys objectAtIndex:i], [clefs objectForKey:[keys objectAtIndex:i]]];
        } else {
            [result appendFormat:@";%@,%@", [keys objectAtIndex:i], [clefs objectForKey:[keys objectAtIndex:i]]];
        }
    }
    return [NSString stringWithString:result];
}

- (void)setNoteCollection:(NSString *)noteCollection
{
    NSArray *collection = [noteCollection componentsSeparatedByString:@";"];
    for (int i = 0; i < [collection count]; i++) {
        //Add our clefs
        NSArray *noteData = [[collection objectAtIndex:i] componentsSeparatedByString:@","];
        //Allow the array to be bigger to leave room for future growth.
        if ([noteData count] >= 3) {
            [self addNote:[noteData objectAtIndex:1] atPosition:[[noteData objectAtIndex:0] integerValue] ofDuration:[[noteData objectAtIndex:2] integerValue]];
        }
    }
}

- (NSString *)noteCollection
{
    NSMutableString *result = [[NSMutableString alloc] init];
    NSArray *keys = [notes allKeys];
    BOOL firstEntry = YES;
    for (int i = 0; i < [keys count]; i++) {
        for (int j = 0; j < [[notes objectForKey:[keys objectAtIndex:i]] count]; j++) {
            if (firstEntry) {
                firstEntry = NO;
            } else {
                [result appendString:@";"];
            }
            CanvasGlyph *glyph = [noteGlyphs objectForKey:[NSString stringWithFormat:@"%@:%@", [keys objectAtIndex:i], [[notes objectForKey:[keys objectAtIndex:i]] objectAtIndex:j]]];
            [result appendFormat:@"%@,%@,%li", [keys objectAtIndex:i], [[notes objectForKey:[keys objectAtIndex:i]] objectAtIndex:j], (long)glyph.duration];
        }
    }
    return [NSString stringWithString:result];
}

- (NSString *)setClef:(NSString *)clef atPosition:(NSInteger)position
{
    CanvasGlyph *clefGlyph;
    NSString *key = [NSString stringWithFormat:@"%li", (long)position];
    if ([clefs objectForKey:key] != nil) {
        if ([[clefs objectForKey:key] isEqualToString:clef]) {
            //Nothing to do here - our clef is already set at this position.
            return nil;
        } else {
            clefGlyph = [clefGlyphs objectForKey:[NSString stringWithFormat:@"%li", (long)position]];
        }
    }
    
    //Check that our clef is one that we recognise.
    if (!([clef isEqualToString:@"alto"] || [clef isEqualToString:@"bass"] || [clef isEqualToString:@"treble"])) {
        return @"Unknown clef type";
    }
    
    //Set up the glyph if it doesn't exist.
    BOOL newClef = NO;
    if (clefGlyph == nil) {
        newClef = YES;
        clefGlyph = [[CanvasGlyph alloc] initWithScorePath:nil];
        clefGlyph.fontSize = containerLayer.bounds.size.height;
        [clefGlyphs setObject:clefGlyph forKey:key];
        [containerLayer addSublayer:clefGlyph.containerLayer];
    } else {
        [clefGlyph.containerLayer removeAllAnimations];
    }
    
    //And then draw our glyph.
    [clefs setObject:clef forKey:key];
    clefPositionsSorted = [self getSortedClefPositions];
    [CATransaction begin];
    [CATransaction setDisableActions:!newClef];
    if ([clef isEqualToString:@"alto"]) {
        clefGlyph.stavePosition = 0.5;
        clefGlyph.position = CGPointMake(position, clefGlyph.stavePosition * containerLayer.bounds.size.height);
        clefGlyph.glyphType = @"cClef";
    } else if ([clef isEqualToString:@"bass"]) {
        clefGlyph.stavePosition = 0.25;
        clefGlyph.position = CGPointMake(position, clefGlyph.stavePosition * containerLayer.bounds.size.height);
        clefGlyph.glyphType = @"fClef";
    } else if ([clef isEqualToString:@"treble"]) {
        clefGlyph.stavePosition = 0.75;
        clefGlyph.position = CGPointMake(position, clefGlyph.stavePosition * containerLayer.bounds.size.height);
        clefGlyph.glyphType = @"gClef";
    }
    [CATransaction commit];
    
    //Finally adjust any notes that are impacted by our clef change.
    NSInteger index = [self getIndexOfClefAtPosition:position];
    if (newClef == NO || (index > 0 && !([[clefs objectForKey:key] isEqualToString:[clefs objectForKey:[[clefPositionsSorted objectAtIndex:index - 1] stringValue]]]))) {
        //If we've added this clef at the beginning then there are no notes it could possibly change.
        //If we've replace the first clef, then we still need to do this.
        NSInteger endPosition;
        if (index + 1 < [clefPositionsSorted count]) {
            endPosition = [[clefPositionsSorted objectAtIndex:index + 1] integerValue];
        } else {
            endPosition = NSIntegerMax;
        }
        [self adjustNotesForClefChangeFrom:position to:endPosition];
    }
    
    return nil;
}

- (NSString *)removeClefAtPosition:(NSInteger)position
{
    //First check if our clef actually exists here.
    NSString *key = [NSString stringWithFormat:@"%li", (long)position];
    if ([clefs objectForKey:key] == nil) {
        return @"There is no clef at this location.";
    }
    
    //Find where our clef was in the sequence of clefs.
    NSInteger index = [self getIndexOfClefAtPosition:position];
    
    //Check if this is our first clef. If it is, we'll have to check if we can safely remove it.
    if (index == -1) {
        return @"An unexpected error has occured.";
    } else {
        //We only have to worry about this if there are actually notes on the stave.
        if ((index == 0) && ([notes count] > 0)) {
            if ([clefPositionsSorted count] < 2) {
                return @"Unable to remove clef without leaving ambiguous pitches on the stave.";
            } else {
                NSInteger firstNotePosition = [self positionOfFirstNote];
                if (firstNotePosition < [[clefPositionsSorted objectAtIndex:1] integerValue]) {
                    return @"Unable to remove clef without leaving ambiguous pitches on the stave.";
                }
            }
        }
    }
    
    //Now actually remove our clef.
    [clefs removeObjectForKey:key];
    [((CanvasGlyph *)[clefGlyphs objectForKey:key]).containerLayer removeFromSuperlayer];
    [clefGlyphs removeObjectForKey:key];
    clefPositionsSorted = [self getSortedClefPositions];
    
    if ([notes count] > 0) {
        //If our clef was the first clef then we've already checked that there are no notes that will
        //be left stranded by its removal. Nothing to do here. Also check that our previous clef isn't the
        //same as our removed clef.
        if (index > 0 && !([[clefs objectForKey:key] isEqualToString:[clefs objectForKey:[[clefPositionsSorted objectAtIndex:index - 1] stringValue]]])) {
            NSInteger endPosition;
            if (index < [clefPositionsSorted count]) {
                endPosition = [[clefPositionsSorted objectAtIndex:index] integerValue];
            } else {
                endPosition = NSIntegerMax;
            }
        
            //Remove and re-add any notes that were between our two clefs.
            [self adjustNotesForClefChangeFrom:position to:endPosition];
        }
    }
    
    return nil;
}

- (NSString *)addNote:(NSString *)noteString atPosition:(NSInteger)position ofDuration:(NSInteger)duration
{
    //First, check if our note already exists.
    NSString *simpleKey = [NSString stringWithFormat:@"%li", (long)position];
    NSString *compoundKey = [NSString stringWithFormat:@"%@:%@", simpleKey, noteString];
    
    if ([noteGlyphs objectForKey:compoundKey] != nil) {
        return @"A note already exits at this position.";
    }
    
    //Check if our position makes sense.
    if (clefPositionsSorted == nil || (position < [[clefPositionsSorted objectAtIndex:0] integerValue])) {
        return @"Note cannot be placed before the first clef on the stave.";
    }
    
    //Check if our note string makes sense.
    NSString *noteLetter = [[noteString substringToIndex:1] uppercaseString];
    //Check that our notename is valid.
    NSCharacterSet *noteCharacters = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFG"];
    if (![noteCharacters characterIsMember:[noteLetter characterAtIndex:0]]) {
        return @"Note should start with a letter name (ABCDEFG).";
    }
    
    //Check our octave is valid.
    NSCharacterSet *octaves = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    NSInteger octave;
    if ([octaves characterIsMember:[noteString characterAtIndex:[noteString length] - 1]]) {
        octave = [[noteString substringFromIndex:[noteString length] - 1] integerValue];
    } else {
        return @"Note octave needs to be a number from 0 to 9.";
    }
    
    //Check any additional modifiers are valid.
    NSString *accidentalGlyphType;
    NSString *modifier;
    if ([noteString length] > 2) {
        modifier = [[noteString substringWithRange:NSMakeRange(1, [noteString length] - 2)] lowercaseString];
        if ([modifier isEqualToString:@"##"]) {
            accidentalGlyphType = @"accidentalDoubleSharp";
        } else if ([modifier isEqualToString:@"#+"]) {
            accidentalGlyphType = @"accidentalThreeQuarterTonesSharpStein";
        } else if ([modifier isEqualToString:@"#"]) {
            accidentalGlyphType = @"accidentalSharp";
        } else if ([modifier isEqualToString:@"+"]) {
            accidentalGlyphType = @"accidentalQuarterToneSharpStein";
        } else if ([modifier isEqualToString:@"n"]) {
            accidentalGlyphType = @"accidentalNatural";
        } else if ([modifier isEqualToString:@"-"]) {
            accidentalGlyphType = @"accidentalQuarterToneFlatStein";
        } else if ([modifier isEqualToString:@"b"]) {
            accidentalGlyphType = @"accidentalFlat";
        } else if ([modifier isEqualToString:@"b-"]) {
            accidentalGlyphType = @"accidentalThreeQuarterTonesFlatZimmermann";
        } else if ([modifier isEqualToString:@"bb"]) {
            accidentalGlyphType = @"accidentalDoubleFlat";
        } else {
            return @"Unknown note modifier.";
        }
    }
    
    //Now get our glyph position. This should be the distance from the stave relative to our stave size.
    //Each note movement down or up is 1/8 the size of the stave. Work in integers initially.
    
    //C = 0, B = 6, start at octave 0 and number up in sequence.
    NSInteger staveStep = ([noteLetter characterAtIndex:0] - 60) % 7;
    staveStep += octave * 7;
    //Now find that relative to our current clef.
    NSString *activeClef = [self activeClefForPosition:position];
    if (activeClef == nil) {
        return @"An unexpected error has occurred.";
    } else if ([activeClef isEqualToString:@"alto"]) {
        //Top line is G4
        staveStep = 32 - staveStep;
    } else if ([activeClef isEqualToString:@"bass"]) {
        //Top line is A3
        staveStep = 26 - staveStep;
    } else if ([activeClef isEqualToString:@"treble"]) {
        //Top line is F5
        staveStep = 38 - staveStep;
    }
    
    //And get our glyph type.
    NSString *glyphType;
    switch (duration) {
        case -2:
            glyphType = @"noteheadHalf";
            break;
        case -1:
            glyphType = @"noteheadBlack";
            break;
        case 0:
            glyphType = @"noteheadDoubleWhole";
            break;
        case 1:
            glyphType = @"noteheadWhole";
            break;
        case 2:
            glyphType = @"noteHalf";
            break;
        case 4:
            glyphType = @"noteQuarter";
            break;
        case 8:
            glyphType = @"note8th";
            break;
        case 16:
            glyphType = @"note16th";
            break;
        case 32:
            glyphType = @"note32nd";
            break;
        default:
            return @"Invalid note duration.";
            break;
    }
    
    if (duration > 1) {
        if (staveStep > 4) {
            glyphType = [glyphType stringByAppendingString:@"Up"];
        } else {
            glyphType = [glyphType stringByAppendingString:@"Down"];
        }
    }
    
    //If we've made it this far, then we can start assembling our glyph and saving it for future reference.
    CanvasGlyph *noteGlyph = [[CanvasGlyph alloc] initWithScorePath:nil];
    noteGlyph.fontSize = containerLayer.bounds.size.height;
    noteGlyph.stavePosition = (CGFloat)staveStep / 8.0;
    noteGlyph.duration = duration;
    noteGlyph.glyphType = glyphType;
    noteGlyph.position = CGPointMake(position, noteGlyph.stavePosition * containerLayer.bounds.size.height);
    [containerLayer addSublayer:noteGlyph.containerLayer];
    [noteGlyphs setObject:noteGlyph forKey:compoundKey];
    if (modifier != nil) {
        noteString = [NSString stringWithFormat:@"%@%@%li", noteLetter, modifier, (long)octave];
    } else {
        noteString = [NSString stringWithFormat:@"%@%li", noteLetter, (long)octave];
    }
    if ([notes objectForKey:simpleKey] != nil) {
        [[notes objectForKey:simpleKey] addObject:noteString];
    } else {
        [notes setObject:[NSMutableArray arrayWithObject:noteString] forKey:simpleKey];
    }
    //Add an accidental if necessary.
    if (accidentalGlyphType != nil) {
        CanvasGlyph *accidentalGlyph = [[CanvasGlyph alloc] initWithScorePath:nil];
        noteGlyph.accidental = accidentalGlyph;
        accidentalGlyph.fontSize = containerLayer.bounds.size.height;
        accidentalGlyph.glyphType = accidentalGlyphType;
        accidentalGlyph.position = CGPointMake(position - (2 * containerLayer.bounds.size.height / 8.0) - (noteGlyph.size.width * noteGlyph.containerLayer.anchorPoint.x), noteGlyph.stavePosition * containerLayer.bounds.size.height);
        [containerLayer addSublayer:accidentalGlyph.containerLayer];
    }
    //And finally add ledger lines.
    if (staveStep < -1 || staveStep > 9) {
        NSInteger difference = (staveStep / labs(staveStep)) * 2;
        int start;
        if (staveStep < -1) {
            start = -2;
        } else {
            start = 10;
        }
        for (int i = start; abs(i) <= abs((int)staveStep); i += difference) {
            CALayer *ledgerLine = [CALayer layer];
            ledgerLine.bounds = CGRectMake(0, 0, (4.5 * containerLayer.bounds.size.height / 8.0), ((CALayer *)[staveLines objectAtIndex:0]).bounds.size.height);
            ledgerLine.position = CGPointMake(position, (CGFloat)i * containerLayer.bounds.size.height / 8.0);
            ledgerLine.backgroundColor = [UIColor blackColor].CGColor;
            [containerLayer addSublayer:ledgerLine];
            [noteGlyph.ledgerLines addObject:ledgerLine];
        }
    }
    
    return nil;
}

- (NSString *)addNotehead:(NSString *)noteString atPosition:(NSInteger)position filled:(BOOL)filled
{
    return [self addNote:noteString atPosition:position ofDuration:(filled - 2)];
}

- (NSString *)removeNote:(NSString *)noteString atPosition:(NSInteger)position
{
    //First check that our note actually exists.
    NSString *key = [NSString stringWithFormat:@"%li", (long)position];
    CanvasGlyph *noteGlyph = [noteGlyphs objectForKey:[NSString stringWithFormat:@"%@:%@", key, noteString]];
    if (noteGlyph == nil) {
        return @"There is no note at this location.";
    }
    
    [noteGlyph.containerLayer removeFromSuperlayer];
    if (noteGlyph.accidental != nil) {
        [noteGlyph.accidental.containerLayer removeFromSuperlayer];
    }
    for (int i = 0; i < [noteGlyph.ledgerLines count]; i++) {
        [[noteGlyph.ledgerLines objectAtIndex:i] removeFromSuperlayer];
    }
    [noteGlyphs removeObjectForKey:[NSString stringWithFormat:@"%@:%@", key, noteString]];
    
    NSMutableArray *noteList = [notes objectForKey:key];
    if ([noteList count] <= 1) {
        //If we're removing our last note at this position, remove the key.
        [notes removeObjectForKey:key];
    } else {
        [noteList removeObject:noteString];
    }
    return nil;
}

- (void)clear
{
    //Clean out all the dictionaries that we can at this point.
    clefPositionsSorted = nil;
    [clefs removeAllObjects];
    [notes removeAllObjects];
    NSArray *clefKeys = [clefGlyphs allKeys];
    NSArray *noteKeys = [noteGlyphs allKeys];
    
    //Remove our clefs then our notes.
    for (int i = 0; i < [clefKeys count]; i++) {
        [((CanvasGlyph *)[clefGlyphs objectForKey:[clefKeys objectAtIndex:i]]).containerLayer removeFromSuperlayer];
        [clefGlyphs removeObjectForKey:[clefKeys objectAtIndex:i]];
    }
    
    for (int i = 0; i < [noteKeys count]; i++) {
        CanvasGlyph *noteGlyph = [noteGlyphs objectForKey:[noteKeys objectAtIndex:i]];
        [noteGlyph.containerLayer removeFromSuperlayer];
        if (noteGlyph.accidental != nil) {
            [noteGlyph.accidental.containerLayer removeFromSuperlayer];
        }
        for (int j = 0; j < [noteGlyph.ledgerLines count]; j++) {
            [[noteGlyph.ledgerLines objectAtIndex:j] removeFromSuperlayer];
        }
        [noteGlyphs removeObjectForKey:[noteKeys objectAtIndex:i]];
    }
}

@end

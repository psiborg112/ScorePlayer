//
//  CanvasGlyph.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/9/18.
//

#import "CanvasGlyph.h"

@interface CanvasGlyph ()

- (void)initDictionaries;

@end

@implementation CanvasGlyph {
    NSMutableDictionary *anchorPoints;
    NSMutableDictionary *scaleFactors;
    NSMutableDictionary *glyphText;
    
    CGFloat glyphSize;
}

@synthesize stavePosition, accidental, ledgerLines, duration;

- (void)initDictionaries
{
    anchorPoints = [[NSMutableDictionary alloc] init];
    scaleFactors = [[NSMutableDictionary alloc] init];
    glyphText = [[NSMutableDictionary alloc] init];
    
    [glyphText setObject:@"\ue050" forKey:@"gClef"];
    [glyphText setObject:@"\ue062" forKey:@"fClef"];
    [glyphText setObject:@"\ue05c" forKey:@"cClef"];
    [glyphText setObject:@"\ue0a0" forKey:@"noteheadDoubleWhole"];
    [glyphText setObject:@"\ue0a2" forKey:@"noteheadWhole"];
    [glyphText setObject:@"\ue0a3" forKey:@"noteheadHalf"];
    [glyphText setObject:@"\ue0a4" forKey:@"noteheadBlack"];
    [glyphText setObject:@"\ue260" forKey:@"accidentalFlat"];
    [glyphText setObject:@"\ue261" forKey:@"accidentalNatural"];
    [glyphText setObject:@"\ue262" forKey:@"accidentalSharp"];
    [glyphText setObject:@"\ue263" forKey:@"accidentalDoubleSharp"];
    [glyphText setObject:@"\ue264" forKey:@"accidentalDoubleFlat"];
    [glyphText setObject:@"\ue280" forKey:@"accidentalQuarterToneFlatStein"];
    [glyphText setObject:@"\ue281" forKey:@"accidentalThreeQuarterTonesFlatZimmermann"];
    [glyphText setObject:@"\ue282" forKey:@"accidentalQuarterToneSharpStein"];
    [glyphText setObject:@"\ue283" forKey:@"accidentalThreeQuarterTonesSharpStein"];
    [glyphText setObject:@"\ue1d3" forKey:@"noteHalfUp"];
    [glyphText setObject:@"\ue1d4" forKey:@"noteHalfDown"];
    [glyphText setObject:@"\ue1d5" forKey:@"noteQuarterUp"];
    [glyphText setObject:@"\ue1d6" forKey:@"noteQuarterDown"];
    [glyphText setObject:@"\ue1d7" forKey:@"note8thUp"];
    [glyphText setObject:@"\ue1d8" forKey:@"note8thDown"];
    [glyphText setObject:@"\ue1d9" forKey:@"note16thUp"];
    [glyphText setObject:@"\ue1da" forKey:@"note16thDown"];
    [glyphText setObject:@"\ue1db" forKey:@"note32ndUp"];
    [glyphText setObject:@"\ue1dc" forKey:@"note32ndDown"];
    
    [anchorPoints setObject:[NSValue valueWithCGPoint:CGPointMake(0.28, 0.5)] forKey:@"note8thUp"];
    [anchorPoints setObject:[NSValue valueWithCGPoint:CGPointMake(0.28, 0.5)] forKey:@"note16thUp"];
    [anchorPoints setObject:[NSValue valueWithCGPoint:CGPointMake(0.28, 0.5)] forKey:@"note32ndUp"];
    
    [scaleFactors setObject:[NSNumber numberWithFloat:0.9] forKey:@"noteHalfUp"];
    [scaleFactors setObject:[NSNumber numberWithFloat:0.9] forKey:@"noteHalfDown"];
    [scaleFactors setObject:[NSNumber numberWithFloat:0.9] forKey:@"noteQuarterUp"];
    [scaleFactors setObject:[NSNumber numberWithFloat:0.9] forKey:@"noteQuarterDown"];
    [scaleFactors setObject:[NSNumber numberWithFloat:0.9] forKey:@"note8thUp"];
    [scaleFactors setObject:[NSNumber numberWithFloat:0.9] forKey:@"note8thDown"];
    [scaleFactors setObject:[NSNumber numberWithFloat:0.9] forKey:@"note16thUp"];
    [scaleFactors setObject:[NSNumber numberWithFloat:0.9] forKey:@"note16thDown"];
    [scaleFactors setObject:[NSNumber numberWithFloat:0.9] forKey:@"note32ndUp"];
    [scaleFactors setObject:[NSNumber numberWithFloat:0.9] forKey:@"note32ndDown"];}

#pragma mark CanvasObject delegate

- (id)initWithScorePath:(NSString *)path;
{
    self = [super initWithScorePath:path];
    //This default should be at the centre of the notehead or accidental, or for a clef, at the note
    //that it defines on the stave. (Shouldn't have to adjust for too many of the glyphs.)
    containerLayer.anchorPoint = CGPointMake(0.5, 0.5);
    
    paddingFactor = 1;
    [super setFont:@"Bravura"];
    [self initDictionaries];
    ledgerLines = [[NSMutableArray alloc] init];
    
    glyphSize = ((CATextLayer *)containerLayer).fontSize;
    
    return self;
}

- (void)setText:(NSString *)text
{
    //We shouldn't be setting the text here. Force people to use setGlyph instead.
    return;
}

- (void)setFont:(NSString *)newFont
{
    //We need to prevent the font from being changed here. (Do nothing.)
    return;
}

- (CGFloat)fontSize
{
    return glyphSize;
}

- (void)setFontSize:(CGFloat)fontSize
{
    glyphSize = fontSize;
    if ([scaleFactors objectForKey:glyphType] != nil) {
        fontSize *= [[scaleFactors objectForKey:glyphType] floatValue];
    }
    
    [super setFontSize:fontSize];
}

- (void)setPaddingFactor:(CGFloat)factor
{
    //Don't allow this to be changed here.
    return;
}

- (NSString *)glyphType
{
    return glyphType;
}

- (void)setGlyphType:(NSString *)glyph
{
    [self setGlyph:glyph];
}

- (BOOL)setGlyph:(NSString *)glyph
{
    if ([glyphText objectForKey:glyph] != nil) {
        glyphType = glyph;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if ([anchorPoints objectForKey:glyph] != nil) {
            containerLayer.anchorPoint = [[anchorPoints objectForKey:glyph] CGPointValue];
        } else {
            containerLayer.anchorPoint = CGPointMake(0.5, 0.5);
        }
        if ([scaleFactors objectForKey:glyph] != nil) {
            ((CATextLayer *)containerLayer).fontSize = glyphSize * [[scaleFactors objectForKey:glyph] floatValue];
        } else {
            ((CATextLayer *)containerLayer).fontSize = glyphSize;
        }
        [super setText:[glyphText objectForKey:glyph]];
        [CATransaction commit];
        return YES;
    } else {
        return NO;
    }
}

@end

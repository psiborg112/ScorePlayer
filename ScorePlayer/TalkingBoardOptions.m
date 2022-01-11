//
//  TalkingBoardOptions.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 30/03/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "TalkingBoardOptions.h"
#import "OSCMessage.h"

@implementation TalkingBoardOptions {
    NSMutableArray *planchettes;
    int originalPlanchettes;
    int maxPlanchettes;
}

@synthesize planchetteSlider, planchetteLabel;

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        maxPlanchettes = 6;
        planchettes = [NSMutableArray arrayWithCapacity:maxPlanchettes];
        NSMutableArray *colourArray = [Renderer getDecibelColours];
        
        for (int i = 0; i < maxPlanchettes; i++) {
            CALayer *planchette = [CALayer layer];
            planchette.frame = CGRectMake(0, 0, 120, 120);
            planchette.position = CGPointMake(80 + (76 * i), 120);
            planchette.cornerRadius = 60;
            planchette.borderWidth = 5;
            planchette.borderColor = ((UIColor *)[colourArray objectAtIndex:i]).CGColor;
            planchette.backgroundColor = [UIColor clearColor].CGColor;
            [planchettes addObject:planchette];
            
        }
        
        for (int i = 0; i < maxPlanchettes; i++) {
            [self.layer addSublayer:[planchettes objectAtIndex:i]];
        }
    }
    return self;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

- (IBAction)adjustPlanchettes
{
    planchetteSlider.value = roundf(planchetteSlider.value);
    planchetteLabel.text = [NSString stringWithFormat:@"%i", (int)planchetteSlider.value];
    
    for (int i = 0; i < maxPlanchettes; i++) {
        if (i < roundf(planchetteSlider.value)) {
            ((CALayer *)[planchettes objectAtIndex:i]).opacity = 1;
        } else {
            ((CALayer *)[planchettes objectAtIndex:i]).opacity = 0;
        }
    }
}

#pragma mark - RendererOptionsView delegate

- (BOOL)optionsChanged {
    if (roundf(planchetteSlider.value) != originalPlanchettes) {
        return YES;
    } else {
        return NO;
    }
}

- (OSCMessage *)getOptions
{
    OSCMessage *options = [[OSCMessage alloc] init];
    [options appendAddressComponent:@"Options"];
    [options addIntegerArgument:roundf(planchetteSlider.value)];
    return options;
}

- (void)setOptions:(OSCMessage *)newOptions
{
    if (![newOptions.typeTag isEqualToString:@",i" ]) {
        return;
    }
    originalPlanchettes = [[newOptions.arguments objectAtIndex:0] intValue];
    planchetteSlider.value = originalPlanchettes;
    planchetteLabel.text = [NSString stringWithFormat:@"%i", originalPlanchettes];
    
    for (int i = 0; i < maxPlanchettes; i++) {
        if (i < roundf(planchetteSlider.value)) {
            ((CALayer *)[planchettes objectAtIndex:i]).opacity = 1;
        } else {
            ((CALayer *)[planchettes objectAtIndex:i]).opacity = 0;
        }
    }
}

@end

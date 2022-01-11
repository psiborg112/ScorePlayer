//
//  CageOptions.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 30/07/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import "CageOptions.h"
#import "OSCMessage.h"

@implementation CageOptions {
    NSArray *sliderArray;
    NSArray *sliderTextArray;
    NSArray *stepperArray;
    NSArray *stepperLabelArray;
    
    OSCMessage *originalOptions;
    NSString *previousText[2];
}

@synthesize maxSlider, maxText, minSlider, minText, densityStepper, densityLabel;
@synthesize systemsStepper, systemsLabel, sourcesStepper, sourcesLabel, speakersStepper, speakersLabel, componentsStepper, componentsLabel;
@synthesize variation1, variation6, noOptions;

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        //Nothing to do here yet...
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

- (IBAction)sliderChanged:(UISlider *)sender
{
    NSUInteger index = [sliderArray indexOfObjectIdenticalTo:sender];
    ((UITextField *)[sliderTextArray objectAtIndex:index]).text = [NSString stringWithFormat:@"%i", (int)sender.value];
    
    //We need to make sure that our minimum and maximum values don't cross over
    if (index == 0) {
        //Minimum slider
        if (sender.value > ((UISlider *)([sliderArray objectAtIndex:index + 1])).value) {
            ((UISlider *)([sliderArray objectAtIndex:index + 1])).value = sender.value;
            ((UITextField *)[sliderTextArray objectAtIndex:index + 1]).text = [NSString stringWithFormat:@"%i", (int)sender.value];
        }
    } else {
        //Maximum slider
        if (sender.value < ((UISlider *)([sliderArray objectAtIndex:index - 1])).value) {
            ((UISlider *)([sliderArray objectAtIndex:index - 1])).value = sender.value;
            ((UITextField *)[sliderTextArray objectAtIndex:index - 1]).text = [NSString stringWithFormat:@"%i", (int)sender.value];
        }
    }
}

- (IBAction)stepperChange:(UIStepper *)sender
{
    NSUInteger index = [stepperArray indexOfObjectIdenticalTo:sender];
    ((UILabel *)[stepperLabelArray objectAtIndex:index]).text = [NSString stringWithFormat:@"%i", (int)sender.value];
}

#pragma mark - RendererOptionsView delegate

- (BOOL)optionsChanged
{
    if (![originalOptions.typeTag hasPrefix:@",i"]) {
        return NO;
    }
    
    BOOL changed = NO;
    switch ([[originalOptions.arguments objectAtIndex:0] intValue]) {
        case 1:
        case 2:
            if (![originalOptions.typeTag isEqualToString:@",iiii"]) {
                //Our original options were corrupted. Flag that they need to be fixed.
                changed = YES;
            } else {
                for (int i = 0; i < [sliderArray count]; i++) {
                    if ([[originalOptions.arguments objectAtIndex:i + 1] intValue] != (int)((UISlider *)[sliderArray objectAtIndex:i]).value) {
                        changed = YES;
                    }
                }
                if ([[originalOptions.arguments objectAtIndex:3] intValue] != (int)densityStepper.value) {
                    changed = YES;
                }
            }
            break;
        case 6:
            if (![originalOptions.typeTag isEqualToString:@",iiiii"]) {
                changed = YES;
            } else {
                for (int i = 0; i < [stepperArray count]; i++) {
                    if ([[originalOptions.arguments objectAtIndex:i + 1] intValue] != (int)((UIStepper *)[stepperArray objectAtIndex:i]).value) {
                        changed = YES;
                    }
                }
            }
            break;
        default:
            break;
    }
    
    return changed;
}

- (OSCMessage *)getOptions
{
    if (originalOptions == nil) {
        return nil;
    }
    
    OSCMessage *newOptions = [[OSCMessage alloc] init];
    [newOptions addIntegerArgument:[[originalOptions.arguments objectAtIndex:0] intValue]];
    
    switch ([[originalOptions.arguments objectAtIndex:0] intValue]) {
        case 1:
        case 2:
            [newOptions addIntegerArgument:minSlider.value];
            [newOptions addIntegerArgument:maxSlider.value];
            [newOptions addIntegerArgument:densityStepper.value];
            break;
        case 6:
            for (int i = 0; i < [stepperArray count]; i++) {
                [newOptions addIntegerArgument:(int)((UIStepper *)[stepperArray objectAtIndex:i]).value];
            }
            break;
        default:
            return nil;
            break;
    }
    
    return newOptions;
}

- (void)setOptions:(OSCMessage *)newOptions
{
    BOOL thereAreNoOptions = NO;
    
    //Work out whether there should actually be options for the given variation.
    if (![newOptions.typeTag hasPrefix:@",i"]) {
        thereAreNoOptions = YES;
    }
    
    if (!thereAreNoOptions) {
        switch ([[newOptions.arguments objectAtIndex:0] intValue]) {
            case 1:
            case 2:
                for (int i = 0; i < [variation1 count]; i++) {
                    [[variation1 objectAtIndex:i] setHidden:NO];
                }
                
                //Set up the necessary arrays to manage the user interface.
                sliderArray = [[NSArray alloc] initWithObjects:minSlider, maxSlider, nil];
                sliderTextArray = [[NSArray alloc] initWithObjects:minText, maxText, nil];
                stepperArray = [[NSArray alloc] initWithObjects:densityStepper, nil];
                stepperLabelArray = [[NSArray alloc] initWithObjects:densityLabel, nil];
                
                densityStepper.maximumValue = [[newOptions.arguments objectAtIndex:0] intValue] + 4;
                
                //If for some reason we don't have enough data, then do no processing and keep current values.
                if ([newOptions.typeTag isEqualToString:@",iiii"]) {
                    for (int i = 0; i < 2; i++) {
                        ((UISlider *)[sliderArray objectAtIndex:i]).value = [[newOptions.arguments objectAtIndex:i + 1] intValue];
                        ((UITextField *)[sliderTextArray objectAtIndex:i]).text = [NSString stringWithFormat:@"%i", (int)((UISlider *)([sliderArray objectAtIndex:i])).value];
                    }
                    densityStepper.value = [[newOptions.arguments objectAtIndex:3] intValue];
                    densityLabel.text = [NSString stringWithFormat:@"%i", (int)densityStepper.value];
                } else {
                    densityStepper.value = [[newOptions.arguments objectAtIndex:0] intValue] + 1;
                    densityLabel.text = [NSString stringWithFormat:@"%i", (int)densityStepper.value];
                }
                
                break;
            case 6:
                for (int i = 0; i < [variation6 count]; i++) {
                    [[variation6 objectAtIndex:i] setHidden:NO];
                }
                stepperArray = [[NSArray alloc] initWithObjects:systemsStepper, sourcesStepper, speakersStepper, componentsStepper, nil];
                stepperLabelArray = [[NSArray alloc] initWithObjects:systemsLabel, sourcesLabel, speakersLabel, componentsLabel, nil];
                
                if ([newOptions.typeTag isEqualToString:@",iiiii"]) {
                    for (int i = 0; i < 4; i++) {
                        ((UIStepper *)[stepperArray objectAtIndex:i]).value = [[newOptions.arguments objectAtIndex:i + 1] intValue];
                        ((UILabel *)[stepperLabelArray objectAtIndex:i]).text = [NSString stringWithFormat:@"%i", (int)((UIStepper *)[stepperArray objectAtIndex:i]).value];
                    }
                }

                break;
            default:
                thereAreNoOptions = YES;
                break;
        }
    }
    
    if (thereAreNoOptions) {
        for (int i = 0; i < [noOptions count]; i++) {
            [[noOptions objectAtIndex:i] setHidden:NO];
        }
    } else {
        //Save our original options to an array.
        originalOptions = newOptions;
    }
}

#pragma mark - UITextField delegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    NSCharacterSet *numbers = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    for (int i = 0; i < [string length]; i++) {
        unichar currentCharacter = [string characterAtIndex:i];
        if (![numbers characterIsMember:currentCharacter]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    previousText[[sliderTextArray indexOfObjectIdenticalTo:textField]] = textField.text;
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
    if ([textField.text isEqualToString:@""]) {
        textField.text = previousText[[sliderTextArray indexOfObjectIdenticalTo:textField]];
    } else {
        //Check Bounds
        if ([textField.text intValue] < 100) {
            textField.text = @"100";
        } else if ([textField.text intValue] > 10000) {
            textField.text = @"10000";
        }
        
        //Set relevant slider value
        NSUInteger index = [sliderTextArray indexOfObjectIdenticalTo:textField];
        ((UISlider *)([sliderArray objectAtIndex:index])).value = [textField.text intValue];
        
        //Check that our minimum and maximum values don't cross over
        if (index == 0) {
            //Minimum slider
            if (((UISlider *)([sliderArray objectAtIndex:index])).value > ((UISlider *)([sliderArray objectAtIndex:index + 1])).value) {
                ((UISlider *)([sliderArray objectAtIndex:index + 1])).value = ((UISlider *)([sliderArray objectAtIndex:index])).value;
                ((UITextField *)[sliderTextArray objectAtIndex:index + 1]).text = [NSString stringWithFormat:@"%i", (int)((UISlider *)([sliderArray objectAtIndex:index])).value];
            }
        } else {
            //Maximum slider
            if (((UISlider *)([sliderArray objectAtIndex:index])).value < ((UISlider *)([sliderArray objectAtIndex:index - 1])).value) {
                ((UISlider *)([sliderArray objectAtIndex:index - 1])).value = ((UISlider *)([sliderArray objectAtIndex:index])).value;
                ((UITextField *)[sliderTextArray objectAtIndex:index - 1]).text = [NSString stringWithFormat:@"%i", (int)((UISlider *)([sliderArray objectAtIndex:index])).value];
            }
        }
    }
    return YES;
}

@end

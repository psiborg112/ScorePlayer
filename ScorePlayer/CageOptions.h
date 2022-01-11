//
//  CageOptions.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 30/07/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Renderer.h"

@interface CageOptions : UIView <UITextFieldDelegate, RendererOptionsView>

@property (nonatomic, strong) IBOutlet UISlider *minSlider;
@property (nonatomic, strong) IBOutlet UITextField *minText;
@property (nonatomic, strong) IBOutlet UISlider *maxSlider;
@property (nonatomic, strong) IBOutlet UITextField *maxText;
@property (nonatomic, strong) IBOutlet UIStepper *densityStepper;
@property (nonatomic, strong) IBOutlet UILabel *densityLabel;

@property (nonatomic, strong) IBOutlet UIStepper *systemsStepper;
@property (nonatomic, strong) IBOutlet UILabel *systemsLabel;
@property (nonatomic, strong) IBOutlet UIStepper *sourcesStepper;
@property (nonatomic, strong) IBOutlet UILabel *sourcesLabel;
@property (nonatomic, strong) IBOutlet UIStepper *speakersStepper;
@property (nonatomic, strong) IBOutlet UILabel *speakersLabel;
@property (nonatomic, strong) IBOutlet UIStepper *componentsStepper;
@property (nonatomic, strong) IBOutlet UILabel *componentsLabel;

@property (nonatomic, strong) IBOutletCollection() NSArray *variation1;
@property (nonatomic, strong) IBOutletCollection() NSArray *variation6;
@property (nonatomic, strong) IBOutletCollection() NSArray *noOptions;

- (IBAction)sliderChanged:(UISlider *)sender;
- (IBAction)stepperChange:(UIStepper *)sender;

@end

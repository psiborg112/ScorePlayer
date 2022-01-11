//
//  OptionsViewController.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 30/03/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import "OptionsViewController.h"

@interface OptionsViewController ()

@end

@implementation OptionsViewController {
    id<RendererOptionsView> rendererOptionsView;
}

@synthesize optionsScrollView, className, rendererOptionsDelegate;

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    
    //Load the necessary nib file to create the options view.
    NSArray *nib = [[NSBundle mainBundle] loadNibNamed:className owner:self options:nil];
     
    for (int i = 0; i < [nib count]; i++) {
        if ([[nib objectAtIndex:i] isKindOfClass:(NSClassFromString(className))]) {
            rendererOptionsView = [nib objectAtIndex:i];
        }
    }
    
    [rendererOptionsView setOptions:[rendererOptionsDelegate getOptions]];
    
    optionsScrollView.contentSize = ((UIView *)rendererOptionsView).bounds.size;
    [optionsScrollView addSubview:(UIView *)rendererOptionsView];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [(UIView *)rendererOptionsView removeFromSuperview];
    rendererOptionsView = nil;
    rendererOptionsDelegate = nil;
}

- (BOOL)disablesAutomaticKeyboardDismissal {
    return NO;
}

- (IBAction)cancel
{
    [rendererOptionsDelegate setOptions:nil];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)ok
{
    if ([rendererOptionsView optionsChanged]) {
        [rendererOptionsDelegate setOptions:[rendererOptionsView getOptions]];
    } else {
        [rendererOptionsDelegate setOptions:nil];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

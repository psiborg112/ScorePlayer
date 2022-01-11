//
//  InstructionsViewController.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 14/12/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "InstructionsViewController.h"
#import "Renderer.h"

@interface InstructionsViewController ()

@end

@implementation InstructionsViewController

@synthesize instructionsView, instructionsFile;

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    UIImageView *instructionsImage = [[UIImageView alloc] initWithImage:[Renderer cachedImage:instructionsFile]];
    if (instructionsImage.image.size.width > 540) {
        instructionsImage.frame = CGRectMake(0, 0, 540, instructionsImage.image.size.height * 540.0 / instructionsImage.image.size.width);
    } else {
        instructionsImage.frame = CGRectMake(0, 0, instructionsImage.image.size.width, instructionsImage.image.size.height);
    }
    instructionsView.contentSize = CGSizeMake(instructionsImage.frame.size.width, instructionsImage.frame.size.height);
    [instructionsView addSubview:instructionsImage];
}

- (IBAction)close;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

//
//  AboutViewController.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 12/12/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "AboutViewController.h"

@interface AboutViewController ()

- (void)dismissAbout;
- (void)swipeLeft;
- (void)swipeRight;
- (void)swipeVertical;

@end

@implementation AboutViewController {
    NSInteger sequenceNumber;
    NSString *versionString;
}

@synthesize versionLabel, easterEgg;

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    UITapGestureRecognizer *dismiss = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissAbout)];
    [self.view addGestureRecognizer:dismiss];
    versionString = [versionLabel.text stringByAppendingString:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    versionLabel.text = versionString;
    
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
    UISwipeGestureRecognizer *swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeVertical)];
    UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeVertical)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeLeft.delegate = self;
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRight.delegate = self;
    swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
    swipeUp.delegate = self;
    swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
    swipeUp.delegate = self;
    [self.view addGestureRecognizer:swipeLeft];
    [self.view addGestureRecognizer:swipeRight];
    [self.view addGestureRecognizer:swipeUp];
    [self.view addGestureRecognizer:swipeDown];
    sequenceNumber = 0;
}

- (void)dismissAbout
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)swipeLeft
{
    if (sequenceNumber == 0 || sequenceNumber == 2 || sequenceNumber == 3) {
        sequenceNumber++;
        versionLabel.text = [NSString stringWithFormat:@"%@ (%i)", versionString, (int)sequenceNumber];
    } else {
        sequenceNumber = 0;
        versionLabel.text = versionString;
    }
}

- (void)swipeRight
{
    if (sequenceNumber == 1) {
        sequenceNumber++;
        versionLabel.text = [NSString stringWithFormat:@"%@ (%i)", versionString, (int)sequenceNumber];
    } else if (sequenceNumber == 4) {
        easterEgg.alpha = 0;
        easterEgg.hidden = NO;
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:0.5];
        easterEgg.alpha = 1;
        [UIView commitAnimations];
    } else {
        sequenceNumber = 0;
        versionLabel.text = versionString;
    }
}

- (void)swipeVertical {
    sequenceNumber = 0;
    versionLabel.text = versionString;
}

#pragma mark UIGestureRecognizer delegate

//Need to make sure our gesture recognizers still register now that there's this
//stupid swipe dismissal gesture. What the fuck were you thinking Apple? "Oh, no one
//could ever want to use a swipe gesture in a form."
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if (![otherGestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        return YES;
    } else {
        return NO;
    }
}

@end

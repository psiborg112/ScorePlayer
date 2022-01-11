//
//  AboutViewController.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 12/12/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AboutViewController : UIViewController <UIGestureRecognizerDelegate>

@property (nonatomic, strong) IBOutlet UILabel *versionLabel;
@property (nonatomic, strong) IBOutlet UIImageView *easterEgg;

@end

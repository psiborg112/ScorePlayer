//
//  InstructionsViewController.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 14/12/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface InstructionsViewController : UIViewController {
    NSString *instructionsFile;
}

@property (nonatomic, strong) IBOutlet UIScrollView *instructionsView;
@property (nonatomic, strong) NSString *instructionsFile;

- (IBAction)close;

@end

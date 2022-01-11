//
//  MainInstructionsViewController.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 15/05/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface MainInstructionsViewController : UIViewController <WKNavigationDelegate>

@property (nonatomic) BOOL navigationEnabled;
@property (nonatomic, strong) WKWebView *instructionsViewer;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *backButton;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *forwardButton;
@property (nonatomic, strong) IBOutlet UIToolbar *bottomBar;

- (IBAction)back;
- (IBAction)forward;
- (IBAction)close;

@end

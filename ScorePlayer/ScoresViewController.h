//
//  ScoresViewController.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "OpusParser.h"
#import "Network.h"

typedef enum {
    kChooseScore = 0,
    kManageImports = 1
} Mode;

@interface ScoresViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, OpusParserDelegate, UpdateDelegate, UITextFieldDelegate, UISearchBarDelegate>

@property (nonatomic, strong) IBOutlet UITableView *scoresTableView;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *changeModeButton;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *aboutButton;
@property (nonatomic, strong) IBOutlet UISearchBar *scoreSearch;

@property (nonatomic, strong) IBOutlet UIToolbar *bottomBar;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *instructionsButton;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *projectionButton;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *updateButton;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *dumpButton;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *dumpIndicator;

- (IBAction)changeMode;
- (IBAction)showInstructions;
- (IBAction)toggleProjectionMode;
- (IBAction)update;
- (IBAction)dump;

@end

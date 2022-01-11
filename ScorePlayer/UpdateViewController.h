//
//  UpdateViewController.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/6/17.
//  Copyright (c) 2017 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Network.h"

@interface UpdateViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, NSURLSessionDownloadDelegate> {
    NSMutableDictionary *updateAddresses;
    __weak id<UpdateDelegate> updateDelegate;
}

@property (nonatomic, strong) IBOutlet UITableView *availableUpdatesTable;
@property (nonatomic, strong) IBOutlet UINavigationItem *windowTitle;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *cancelButton;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *updateButton;
@property (nonatomic, strong) IBOutlet UIProgressView *updateProgress;
@property (nonatomic, strong) IBOutlet UILabel *statusLabel;

@property (nonatomic, strong) NSMutableDictionary *updateAddresses;
@property (nonatomic, weak) id<UpdateDelegate> updateDelegate;

- (IBAction)update;
- (IBAction)cancel;

@end

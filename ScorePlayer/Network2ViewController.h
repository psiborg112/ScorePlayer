//
//  Network2ViewController.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 9/11/2014.
//  Copyright (c) 2014 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Network.h"

typedef enum {
    kChooseServer = 0,
    kViewDevices = 1,
    kChooseScore = 2
} Mode;

@interface Network2ViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, NSNetServiceBrowserDelegate,  NSNetServiceDelegate, UITextFieldDelegate, UISearchBarDelegate, NetworkStatus> {
    NSString *serviceName;
    NSString *serverNamePrefix;
    NSArray *networkDevices;
    NSArray *availableScores;
    NSString *lastAddress;
    BOOL connected;
    BOOL allowScoreChange;
    
    __weak id<NetworkConnectionDelegate> networkConnectionDelegate;
}

@property (nonatomic, strong) IBOutlet UITableView *networkTableView;
@property (nonatomic, strong) IBOutlet UINavigationItem *windowTitle;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *disconnectButton;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *manualConnectionButton;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *scoreChangeButton;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *cancelButton;
@property (nonatomic, strong) IBOutlet UISearchBar *scoreSearch;
@property (nonatomic, strong) IBOutlet UIToolbar *bottomBar;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *tableLeadingConstraint;

@property (nonatomic, strong) NSString *serviceName;
@property (nonatomic, strong) NSString *serverNamePrefix;
@property (nonatomic, strong) NSArray *networkDevices;
@property (nonatomic, strong) NSArray *availableScores;
@property (nonatomic, strong) NSString *lastAddress;
@property (nonatomic) BOOL connected;
@property (nonatomic) BOOL allowScoreChange;

@property (nonatomic, weak) id<NetworkConnectionDelegate> networkConnectionDelegate;

- (IBAction)disconnect;
- (IBAction)manuallyConnect;
- (IBAction)viewScoreList;
- (IBAction)cancel;

@end

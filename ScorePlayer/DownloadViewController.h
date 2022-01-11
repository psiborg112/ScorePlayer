//
//  DownloadViewController.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 4/12/18.
//  Copyright (c) 2018 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Network.h"

@interface DownloadViewController : UIViewController <AVCaptureMetadataOutputObjectsDelegate, NSURLSessionTaskDelegate, NSURLSessionDownloadDelegate, UITextFieldDelegate> {
    __weak id<UpdateDelegate> downloadDelegate;
}

@property (nonatomic, strong) IBOutlet UIBarButtonItem *cancelButton;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *downloadButton;
@property (nonatomic, strong) IBOutlet UIProgressView *downloadProgress;
@property (nonatomic, strong) IBOutlet UILabel *statusLabel;
@property (nonatomic, strong) IBOutlet UILabel *scoreURLLabel;
@property (nonatomic, strong) IBOutlet UITextField *scoreURLField;
@property (nonatomic, strong) IBOutlet UIView *captureView;

@property (nonatomic, weak) id<UpdateDelegate> downloadDelegate;

- (IBAction)download;
- (IBAction)cancel;

@end

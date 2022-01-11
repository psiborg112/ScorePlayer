//
//  UpdateViewController.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 5/6/17.
//  Copyright (c) 2017 Decibel. All rights reserved.
//

#import "UpdateViewController.h"

@interface UpdateViewController ()

@end

@implementation UpdateViewController {
    CALayer *dimmer;
    BOOL checkComplete;
    NSString *updateDirectory;
    NSMutableArray *availableUpdates;
    NSMutableArray *selectedUpdates;
    __block NSInteger headersDownloaded;
    NSInteger currentDownload;
    NSInteger failCount;
    
    NSFileManager *fileManager;
    
    NSURLSession *headerSession;
    NSURLSession *downloadSession;
}

@synthesize availableUpdatesTable, windowTitle, cancelButton, updateButton, updateProgress, statusLabel, updateAddresses, updateDelegate;

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    updateButton.enabled = NO;
    checkComplete = NO;
    availableUpdates = [[NSMutableArray alloc] init];
    selectedUpdates = [[NSMutableArray alloc] init];
    
    //Get our update directory.
    fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if ([paths count] > 0) {
        NSString *directory = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"Updates"];
        if ([fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) {
            updateDirectory = directory;
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if ([updateDelegate respondsToSelector:@selector(finishedUpdating)]) {
        [updateDelegate finishedUpdating];
    }
    updateDelegate = nil;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    //Create our initial URL session.
    NSURLSessionConfiguration *headerSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    headerSessionConfig.timeoutIntervalForRequest = 2;
    //Make sure we always download our headers and don't use any cached responses.
    headerSessionConfig.requestCachePolicy = NSURLRequestReloadIgnoringCacheData;
    
    headerSession = [NSURLSession sessionWithConfiguration:headerSessionConfig];
    
    NSArray *scoreDirectories = [updateAddresses allKeys];
    NSMutableArray *dataTasks = [[NSMutableArray alloc] init];
    
    if ([scoreDirectories count] > 0) {
        headersDownloaded = 0;
        
        //Define the completion code to be used for all of our requests
        void (^completionBlock)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error){
            //Check that we received a valid HTTP response
            if (error == nil && [response isKindOfClass:[NSHTTPURLResponse class]] && [(NSHTTPURLResponse *)response statusCode] == 200) {
                //Check how long our response should be, and trim our received data to match if it is longer.
                //(Have sometimes been getting unexpected trailing characters in the received data.)
                long long expectedLength = response.expectedContentLength;
                if (expectedLength > data.length) {
                    expectedLength = data.length;
                }
                //stringWithUTF8String will crash if our data is 0 bytes in length, so check for safety.
                //(Don't return here as we still need to check if there are more headers to download.)
                if (expectedLength > 0) {
                    NSData *trimmed = [NSData dataWithBytes:[data bytes] length:(NSUInteger)expectedLength];
                    NSString *rawString = [NSString stringWithUTF8String:[trimmed bytes]];
                    //Trim leading and trailing whitespace or newline characters.
                    rawString = [rawString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    //If we have multiple lines in our response we should only pay attention to the first one.
                    rawString = [[rawString componentsSeparatedByString:@"\n"] objectAtIndex:0];
                    NSArray *components = [rawString componentsSeparatedByString:@","];
                    if ([components count] == 2) {
                        //Check the reported version number against the current version number and check that our URL is vaugely sane.
                        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[components objectAtIndex:0]]];
                        if ([NSURLConnection canHandleRequest:request]) {
                            if ([[components objectAtIndex:1] caseInsensitiveCompare:[[self->updateAddresses objectForKey:[scoreDirectories objectAtIndex:self->headersDownloaded]] objectAtIndex:1]] == NSOrderedDescending) {
                                [self->availableUpdates addObject:[NSArray arrayWithObjects:[[scoreDirectories objectAtIndex:self->headersDownloaded] lastPathComponent], [components objectAtIndex:0], [components objectAtIndex:1], [[self->updateAddresses objectForKey:[scoreDirectories objectAtIndex:self->headersDownloaded]] objectAtIndex:1], nil]];
                            }
                        }
                    }
                }
            }
            self->headersDownloaded++;
            //Need to do UI updates on the main thread, otherwise we'll see huge delays.
            dispatch_async(dispatch_get_main_queue(), ^{
                self->updateProgress.progress = (CGFloat)self->headersDownloaded / [scoreDirectories count];
            });
            if (self->headersDownloaded < [scoreDirectories count]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self->statusLabel.text = [NSString stringWithFormat:@"Checking %@", [[scoreDirectories objectAtIndex:self->headersDownloaded] lastPathComponent]];
                });
                [[dataTasks objectAtIndex:self->headersDownloaded] resume];
            } else {
                self->checkComplete = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self->windowTitle.title = @"Select Scores to Update";
                    if ([self->availableUpdates count] == 0) {
                        self->statusLabel.text = @"No updates found";
                    } else if ([self->availableUpdates count] == 1) {
                        self->statusLabel.text = @"1 update found";
                    } else {
                        self->statusLabel.text = [NSString stringWithFormat:@"%i updates found", (int)[self->availableUpdates count]];
                    }
                    [self->availableUpdatesTable reloadData];
                });
            }
        };
        
        for (int i = 0; i < [scoreDirectories count]; i++) {
            NSURLSessionDataTask *task = [headerSession dataTaskWithURL:[NSURL URLWithString:[[updateAddresses objectForKey:[scoreDirectories objectAtIndex:i]] objectAtIndex:0]] completionHandler:completionBlock];
            [dataTasks addObject:task];
        }
        
        statusLabel.text = [NSString stringWithFormat:@"Checking %@", [[scoreDirectories objectAtIndex:0] lastPathComponent]];
        [[dataTasks objectAtIndex:0] resume];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)update
{
    cancelButton.title = @"Cancel";
    updateButton.enabled = NO;
    
    //Create our download session
    if (downloadSession == nil) {
        NSURLSessionConfiguration *downloadSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        downloadSessionConfig.requestCachePolicy = NSURLRequestReloadIgnoringCacheData;
        downloadSession = [NSURLSession sessionWithConfiguration:downloadSessionConfig delegate:self delegateQueue:nil];
    }
    
    for (int i = 0; i < [availableUpdatesTable.indexPathsForSelectedRows count]; i++) {
        [selectedUpdates addObject:[availableUpdates objectAtIndex:[availableUpdatesTable.indexPathsForSelectedRows objectAtIndex:i].row]];
    }
    currentDownload = 0;
    failCount = 0;
    statusLabel.text = [NSString stringWithFormat:@"Downloading %@", [[selectedUpdates objectAtIndex:0] objectAtIndex:0]];
    
    //Create our initial download task
    NSURLSessionDownloadTask *currentTask = [downloadSession downloadTaskWithURL:[NSURL URLWithString:[[selectedUpdates objectAtIndex:0] objectAtIndex:1]]];
    [currentTask resume];
}

- (IBAction)cancel
{
    [downloadSession invalidateAndCancel];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    if (checkComplete) {
        return [availableUpdates count];
    } else {
        return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell;
    
    cell = [tableView dequeueReusableCellWithIdentifier:@"UpdateCell"];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"UpdateCell"];
    }
    
    NSString *versionLabel = [NSString stringWithFormat:@"%@ -> %@", [[availableUpdates objectAtIndex:indexPath.row] objectAtIndex:3], [[availableUpdates objectAtIndex:indexPath.row] objectAtIndex:2]];
    cell.textLabel.text = [[[availableUpdates objectAtIndex:indexPath.row] objectAtIndex:0] lastPathComponent];
    cell.detailTextLabel.text = versionLabel;
    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryCheckmark;
    if ([[tableView indexPathsForSelectedRows] count] > 0) {
        updateButton.enabled = YES;
    }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryNone;
    if ([[tableView indexPathsForSelectedRows] count] == 0) {
        updateButton.enabled = NO;
    }
}

#pragma mark - NSURLSessionDownload delegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    if (session != downloadSession) {
        //We shouldn't be here.
        return;
    }
    
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)downloadTask.response;
    if (response.statusCode != 200) {
        failCount++;
    } else if (updateDirectory != nil && [location isFileURL]) {
        //Move our finished download to the updates directory.
        [fileManager moveItemAtPath:location.path toPath:[[updateDirectory stringByAppendingPathComponent:[[selectedUpdates objectAtIndex:currentDownload] objectAtIndex:0]] stringByAppendingPathExtension:@"dsz"] error:nil];
    }
    
    currentDownload++;
    if (currentDownload < [selectedUpdates count]) {
        //Cue up the next download after updating the user interface.
        dispatch_async(dispatch_get_main_queue(), ^{
            self->updateProgress.progress = (CGFloat)self->currentDownload / [self->selectedUpdates count];;
            self->statusLabel.text = [NSString stringWithFormat:@"Downloading %@", [[self->selectedUpdates objectAtIndex:self->currentDownload] objectAtIndex:0]];
        });
        
        NSURLSessionDownloadTask *currentTask = [downloadSession downloadTaskWithURL:[NSURL URLWithString:[[selectedUpdates objectAtIndex:currentDownload] objectAtIndex:1]]];
        [currentTask resume];
    } else {
        //We are done here.
        for (int i = 0; i < [selectedUpdates count]; i++) {
            [availableUpdates removeObjectIdenticalTo:[selectedUpdates objectAtIndex:i]];
        }
        
        if (failCount > 0) {
            UIAlertController *updateErrorAlert = [UIAlertController alertControllerWithTitle:@"Update Error" message:@"Some files did not download successfully." preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self->statusLabel.text = @"";
                    self->cancelButton.title = @"Close";
                    [self->availableUpdatesTable reloadData];
                });
            }];
            [updateErrorAlert addAction:okAction];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->updateProgress.progress = 1;
                [self presentViewController:updateErrorAlert animated:YES completion:nil];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->updateProgress.progress = 1;
                self->statusLabel.text = @"Finished Downloading";
                self->cancelButton.title = @"Close";
                [self->availableUpdatesTable reloadData];
            });
        }
        
        [updateDelegate downloadedUpdatesToDirectory:updateDirectory];
    }
    
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    if (session != downloadSession) {
        return;
    }
    
    CGFloat progress = (CGFloat)totalBytesWritten / (totalBytesExpectedToWrite * [selectedUpdates count]);
    progress += (CGFloat)currentDownload / [selectedUpdates count];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->updateProgress.progress = progress;
    });
}

@end

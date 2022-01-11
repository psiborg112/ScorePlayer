//
//  DownloadViewController.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 4/12/18.
//

#import "DownloadViewController.h"
#import "OpusParser.h"

@interface DownloadViewController ()

- (void)setupQRCapture;
- (void)restoreUI;
- (void)tap;

@end

@implementation DownloadViewController {
    NSURLSession *downloadSession;
    
    AVCaptureSession *captureSession;
    AVCaptureVideoPreviewLayer *videoPreviewLayer;
    __block BOOL isCapturing;
    
    NSFileManager *fileManager;
    NSString *downloadDirectory;
    NSString *destination;
    __block BOOL isDownloading;
}

@synthesize cancelButton, downloadButton, downloadProgress, statusLabel, scoreURLLabel, scoreURLField, captureView, downloadDelegate;

- (void)viewDidLoad {
    [super viewDidLoad];
    downloadButton.enabled = NO;
    isDownloading = NO;
    NSURLSessionConfiguration *downloadSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    downloadSessionConfig.requestCachePolicy = NSURLRequestReloadIgnoringCacheData;
    downloadSession = [NSURLSession sessionWithConfiguration:downloadSessionConfig delegate:self delegateQueue:nil];
    fileManager = [NSFileManager defaultManager];
    
    //Get our downloads directory. (Use the same directory as we do for updates.)
    fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if ([paths count] > 0) {
        NSString *directory = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"Updates"];
        if ([fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) {
            downloadDirectory = directory;
        }
    }
    
    // Do any additional setup after loading the view.
    // Add a tap gesture recognizer, which we can use to restart video capture.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)];
    [captureView addGestureRecognizer:tap];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if ([downloadDelegate respondsToSelector:@selector(finishedUpdating)]) {
        [downloadDelegate finishedUpdating];
    }
    downloadDelegate = nil;
}

- (IBAction)download {
    statusLabel.text = @"Downloading";
    [captureSession stopRunning];
    isCapturing = NO;
    downloadButton.enabled = NO;
    scoreURLField.enabled = NO;
    scoreURLField.textColor = [UIColor lightGrayColor];
    scoreURLLabel.textColor = [UIColor lightGrayColor];
    cancelButton.title = @"Cancel";
    isDownloading = YES;
    NSURL *downloadURL =  [NSURL URLWithString:scoreURLField.text];
    NSURLSessionDownloadTask *download = [downloadSession downloadTaskWithURL:downloadURL];
    destination = [downloadURL lastPathComponent];
    if (![destination.pathExtension isEqualToString:@"dsz"]) {
        destination = [destination stringByAppendingString:@".dsz"];
    }
    [download resume];
}

- (IBAction)cancel {
    [downloadSession invalidateAndCancel];
    [captureSession stopRunning];
    isCapturing = NO;
    isDownloading = NO;
    captureSession = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)setupQRCapture
{
    //Set up our capture session.
    NSError *error;
    AVCaptureDevice *captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
    if (input == nil) {
        return;
    }
    captureSession = [[AVCaptureSession alloc] init];
    [captureSession addInput:input];
    
    //Capture metadata, scanning for QR codes.
    AVCaptureMetadataOutput *captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
    [captureSession addOutput:captureMetadataOutput];
    
    dispatch_queue_t metadataQueue;
    metadataQueue = dispatch_queue_create("metadataQueue", NULL);
    [captureMetadataOutput setMetadataObjectsDelegate:self queue:metadataQueue];
    [captureMetadataOutput setMetadataObjectTypes:[NSArray arrayWithObject:AVMetadataObjectTypeQRCode]];
    
    //Set up our video preview window.
    videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
    [videoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [videoPreviewLayer setFrame:captureView.bounds];
    [captureView.layer addSublayer:videoPreviewLayer];
    
    NSInteger borderWidth = 90;
    CALayer *border = [CALayer layer];
    border.borderColor = [UIColor blackColor].CGColor;
    border.borderWidth = borderWidth;
    border.frame = captureView.bounds;
    border.opacity = 0.6;
    [captureView.layer addSublayer:border];
    
    CALayer *focusLayer = [CALayer layer];
    focusLayer.borderColor = [UIColor redColor].CGColor;
    focusLayer.borderWidth = 3;
    focusLayer.frame = CGRectMake(borderWidth, borderWidth, captureView.frame.size.width - (2 * borderWidth), captureView.frame.size.height - (2 * borderWidth));
    [captureView.layer addSublayer:focusLayer];
    [captureSession startRunning];
    captureMetadataOutput.rectOfInterest = [videoPreviewLayer metadataOutputRectOfInterestForRect:focusLayer.frame];
    isCapturing = YES;
}

- (void)restoreUI
{
    cancelButton.title = @"Close";
    scoreURLField.enabled = YES;
    scoreURLField.textColor = [UIColor blackColor];
    scoreURLLabel.textColor = [UIColor blackColor];
}

- (void)tap
{
    if (!isCapturing && !isDownloading) {
        if (!captureSession) {
            [self setupQRCapture];
        }
        if (captureSession) {
            [captureSession startRunning];
            downloadButton.enabled = NO;
            scoreURLField.text = @"";
            statusLabel.text = @"Looking for QR code";
            downloadProgress.progress = 0;
        }
    }
}

#pragma mark - Metadata capture delegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    AVMetadataMachineReadableCodeObject *metadataObj = [metadataObjects objectAtIndex:0];
    if ([[metadataObj type] isEqualToString:AVMetadataObjectTypeQRCode]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->scoreURLField.text = [metadataObj stringValue];
            if ([OpusParser isValidURL:[metadataObj stringValue]]) {
                self->downloadButton.enabled = YES;
            }
            self->statusLabel.text = @"Code found";
            [self->captureSession stopRunning];
            self->isCapturing = NO;
        });
    }
}

#pragma mark - UITextField delegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if ([OpusParser isValidURL:textField.text]) {
        downloadButton.enabled = YES;
    } else {
        downloadButton.enabled = NO;
    }
    if (downloadProgress.progress > 0) {
        downloadProgress.progress = 0;
        statusLabel.text = @"";
    }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    return YES;
}

#pragma mark - NSURLSessionDownload delegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    BOOL success = YES;
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)downloadTask.response;
    if (response.statusCode != 200) {
        success = NO;
        UIAlertController *downloadErrorAlert = [UIAlertController alertControllerWithTitle:@"Download Failed" message:@"There was a problem downloading the score file. (Is it still available on the server?)" preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->isDownloading = NO;
                self->statusLabel.text = @"";
                [self restoreUI];
            });
        }];
        [downloadErrorAlert addAction:okAction];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->downloadProgress.progress = 1;
            [self presentViewController:downloadErrorAlert animated:YES completion:nil];
        });
    }
    
    //Move our finished download to the updates directory.
    if (downloadDirectory != nil && [location isFileURL] && success) {
        [fileManager moveItemAtPath:location.path toPath:[downloadDirectory stringByAppendingPathComponent:destination] error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->downloadProgress.progress = 1;
            self->statusLabel.text = @"Finished Downloading";
            [self restoreUI];
            self->isDownloading = NO;
        });
        [downloadDelegate downloadedUpdatesToDirectory:downloadDirectory];
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    CGFloat progress = (CGFloat)totalBytesWritten / totalBytesExpectedToWrite;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->downloadProgress.progress = progress;
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (error) {
        UIAlertController *downloadErrorAlert = [UIAlertController alertControllerWithTitle:@"Download Failed" message:@"Unable to download the score file. (Is the server reachable?)" preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->isDownloading = NO;
                self->statusLabel.text = @"";
                [self restoreUI];
            });
        }];
        [downloadErrorAlert addAction:okAction];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->downloadProgress.progress = 1;
            [self presentViewController:downloadErrorAlert animated:YES completion:nil];
        });
    }
}

@end

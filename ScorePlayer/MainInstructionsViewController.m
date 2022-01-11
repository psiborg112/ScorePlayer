//
//  MainInstructionsViewController.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 15/05/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import "MainInstructionsViewController.h"

@interface MainInstructionsViewController ()

- (void)checkForNavigation;

@end

@implementation MainInstructionsViewController {
    BOOL navigationEnabled;
    NSTimer *checkForNavigation;
}

@synthesize instructionsViewer, backButton, forwardButton, bottomBar;

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        //Assume that our instructions are a single html page until told otherwise.
        navigationEnabled = NO;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    backButton.enabled = NO;
    forwardButton.enabled = NO;
    WKUserContentController *contentController = nil;
    
    //Load our dark.css if we're in dark mode.
    if (@available(iOS 12.0, *)) {
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            NSString *cssFile = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"dark.css"];
            NSString *css = [NSString stringWithContentsOfFile:cssFile encoding:NSUTF8StringEncoding error:nil];
            css = [css stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            NSString *js = [NSString stringWithFormat:@"var style = document.createElement('style'); style.innerHTML = '%@'; document.head.appendChild(style);", css];
               
            WKUserScript *userScript = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
            contentController = [[WKUserContentController alloc] init];
               [contentController addUserScript:userScript];
        }
    }
    
    //Manually add our instructions view due to an issue with WKWebView and the
    //interface builder pre iOS 11.0.
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    if (contentController != nil) {
        config.userContentController = contentController;
    }
    instructionsViewer = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 768, 768) configuration:config];
    if (@available(iOS 13.0, *)) {
        instructionsViewer.backgroundColor = [UIColor systemBackgroundColor];
    }
    //instructionsViewer.hidden = YES;
    [self.view addSubview:instructionsViewer];
    instructionsViewer.navigationDelegate = self;
    
    NSURL *instructionsURL = [NSURL fileURLWithPath:[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"index.html"]];
    [instructionsViewer loadRequest:[NSURLRequest requestWithURL:instructionsURL]];
    
    if (!navigationEnabled) {
        backButton.title = nil;
        backButton.style = UIBarButtonItemStylePlain;
        forwardButton.title = nil;
        forwardButton.style = UIBarButtonItemStylePlain;
    } else {
        [checkForNavigation invalidate];
        checkForNavigation = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(checkForNavigation) userInfo:nil repeats:YES];
    }
    
    //Add our constraints
    instructionsViewer.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *topConstraint = [NSLayoutConstraint constraintWithItem:instructionsViewer attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1 constant:0];
    NSLayoutConstraint *bottomConstraint = [NSLayoutConstraint constraintWithItem:instructionsViewer attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:bottomBar attribute:NSLayoutAttributeTop multiplier:1 constant:0];
    NSLayoutConstraint *leadingConstraint = [NSLayoutConstraint constraintWithItem:instructionsViewer attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1 constant:0];
    NSLayoutConstraint *trailingConstraint = [NSLayoutConstraint constraintWithItem:instructionsViewer attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTrailing multiplier:1 constant:0];
    [self.view addConstraints:[NSArray arrayWithObjects:topConstraint, bottomConstraint, leadingConstraint, trailingConstraint, nil]];
}

- (IBAction)back
{
    if (navigationEnabled) {
        [instructionsViewer goBack];
    }
}

- (IBAction)forward
{
    if (navigationEnabled) {
        [instructionsViewer goForward];
    }
}

- (IBAction)close
{
    NSLog(@"%i", (int)self.view.frame.size.width);
    [checkForNavigation invalidate];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)setNavigationEnabled:(BOOL)enabled
{
    if (navigationEnabled != enabled)
    {
        navigationEnabled = enabled;
        [checkForNavigation invalidate];
        if (navigationEnabled) {
            backButton.title = @"Back";
            backButton.style = UIBarButtonItemStylePlain;
            forwardButton.title = @"Forward";
            forwardButton.style = UIBarButtonItemStylePlain;
            checkForNavigation = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(checkForNavigation) userInfo:nil repeats:YES];
        } else {
            backButton.title = nil;
            backButton.style = UIBarButtonItemStylePlain;
            forwardButton.title = nil;
            forwardButton.style = UIBarButtonItemStylePlain;
        }
    }
}

- (BOOL)navigationEnabled
{
    return navigationEnabled;
}

- (void)checkForNavigation
{
    if (navigationEnabled) {
        backButton.enabled = instructionsViewer.canGoBack;
        forwardButton.enabled = instructionsViewer.canGoForward;
    }
}

#pragma mark - WKNavigation delegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    //If we're not loading a local html file, load in safari.
    if (navigationAction.request.URL.host != nil) {
        [[UIApplication sharedApplication] openURL:navigationAction.request.URL];
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

/*- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    if (webView.isHidden) {
        webView.hidden = NO;
    }
}*/

#pragma mark - UIWebView delegate

//This is now handled by a timer because links to page elements don't trigger a load event.
/*- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    if (navigationEnabled) {
        backButton.enabled = webView.canGoBack;
        forwardButton.enabled = webView.canGoForward;
    }
}*/

/*- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    //If we're not loading a local html file, load in safari.
    if (request.URL.host != nil) {
        [[UIApplication sharedApplication] openURL:request.URL];
        return NO;
    }
    return YES;
}*/

@end

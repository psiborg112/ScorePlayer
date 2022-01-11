//
//  AppDelegate.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "AppDelegate.h"
#import "Renderer.h"
#import "OSCMessage.h"
#import "PlayerViewController.h"
#import "MainInstructionsViewController.h"

@implementation AppDelegate {
    NSDictionary *destinations;
    NSInteger sentGoodbyes;
    NSInteger goodbyeCount;
    
    GCDAsyncUdpSocket *udpSocket;
}

@synthesize window = _window;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.

    return YES;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    
    //Shut down the player so that we don't interfere with network operations
    UINavigationController *navigationController = (UINavigationController *)self.window.rootViewController;
    for (int i = 0; i < [navigationController.viewControllers count]; i++) {
        if ([[navigationController.viewControllers objectAtIndex:i] isKindOfClass:[PlayerViewController class]]) {
            [[navigationController.viewControllers objectAtIndex:i] playerShutdown];
        }
    }
    
    //Move back to the score chooser window and clear our renderer image cache
    if (![navigationController.visibleViewController isKindOfClass:[MainInstructionsViewController class]]) {
        [navigationController popToRootViewControllerAnimated:NO];
        [navigationController dismissViewControllerAnimated:NO completion:nil];
    }
    [Renderer clearCache];
    
    //Save any user preferences
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults synchronize];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    [Renderer clearCache];
}

- (BOOL)application:(UIApplication *)application openURL:(nonnull NSURL *)url options:(nonnull NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if ([paths count] > 0) {
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *fileName = [url path];
        [fileManager moveItemAtPath:fileName toPath:[documentsDirectory stringByAppendingPathComponent:[fileName lastPathComponent]] error:nil];
    }
    return YES;
}

- (void)manageUdpShutdown:(GCDAsyncUdpSocket *)socket goodbyeMessage:(OSCMessage *)message destinations:(NSMutableDictionary *)dest
{
    //We shouldn't be able to get here so soon that we'll still be shutting down a previous
    //socket, but check and close it just in case.
    if (udpSocket != nil) {
        udpSocket.delegate = nil;
        [udpSocket close];
    }
    
    udpSocket = socket;
    udpSocket.delegate = self;
    
    //Copy our dictionary
    destinations = [NSDictionary dictionaryWithDictionary:dest];
    goodbyeCount = 0;
    sentGoodbyes = 0;
    //Get an initial count
    for (NSString* address in destinations) {
        goodbyeCount += [[destinations objectForKey:address] count];
    }
    
    //Send our messages
    for (NSString* address in destinations) {
        for (int i = 0; i < [[destinations objectForKey:address] count]; i++) {
            int port = [[[destinations objectForKey:address] objectAtIndex:i] intValue];
            [socket sendData:[message messageAsDataWithHeader:NO] toHost:address port:port withTimeout:3 tag:0];
        }
    }
}

#pragma mark - GCDAsyncUdpSocket delegate

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
    sentGoodbyes++;
    if (sentGoodbyes == goodbyeCount) {
        udpSocket.delegate = nil;
        [udpSocket close];
        udpSocket = nil;
    }
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error
{
    //We tried to send our goodbye message but it didn't work. Since we're just keeping track
    //of the number of messages sent, use the same code as a successful send.
    [self udpSocket:sock didSendDataWithTag:tag];
}

@end

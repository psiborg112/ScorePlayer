//
//  OptionsViewController.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 30/03/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Renderer.h"

@interface OptionsViewController : UIViewController {
    NSString *className;
    __weak id<RendererOptions> rendererOptionsDelegate;
}

@property (nonatomic, strong) IBOutlet UIScrollView *optionsScrollView;

@property (nonatomic, strong) NSString *className;
@property (nonatomic, weak) id<RendererOptions> rendererOptionsDelegate;

- (IBAction)cancel;
- (IBAction)ok;

@end

//
//  TalkingBoardOptions.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 30/03/13.
//  Copyright (c) 2013 Decibel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Renderer.h"

@interface TalkingBoardOptions : UIView <RendererOptionsView>

@property (nonatomic, strong) IBOutlet UISlider *planchetteSlider;
@property (nonatomic, strong) IBOutlet UILabel *planchetteLabel;

- (IBAction)adjustPlanchettes;

@end

//
//  ScoresViewController.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/06/12.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "ScoresViewController.h"
#import "Score.h"
#import "Renderer.h"
#import "SSZipArchive.h"
#import "PlayerViewController.h"
#import "UpdateViewController.h"
#import "DownloadViewController.h"

@interface ScoresViewController ()

- (BOOL)importScores;
- (BOOL)importScoresFromDirectory:(NSString *)directory;
- (void)loadScores;
- (NSMutableArray *)getDirectoryList;
- (NSArray *)sortScores;
- (NSArray *)sortDirectories;
- (void)refreshScores;
- (void)handleCorruptScores;
- (void)processNextCorruptScore;
- (void)showTable;
- (void)resetKnocks;
- (void)disableControls:(BOOL)disabled;

@end

@implementation ScoresViewController {
    Score *selectedScore;
    NSMutableArray *scores;
    NSArray *scoresSorted;
    NSMutableArray *scoresFiltered;
    BOOL isFiltered;
    
    NSMutableArray *parsers;
    int finishedParsers;
    NSCondition *parserCondition;
    NSFileManager *fileManager;
    NSString *scoresDirectory;
    NSString *bundleAnnotationsDirectory;
    NSMutableArray *directories;
    NSArray *directoriesSorted;
    NSMutableArray *directoriesFiltered;
    NSMutableArray *newDirectories;
    BOOL scoresLoaded;
    __block BOOL refreshInProgress;
    NSCondition *refreshCondition;
    BOOL firstLoad;
    NSTimer *scoresRefresh;
    NSTimer *showTable;
    BOOL firstAppearance;
    
    NSString *identifier;
    
    BOOL handlingCorruptScores;
    NSMutableArray *corruptScores;
    __block int currentCorruptScore;
    
    NSMutableDictionary *updateAddresses;
    BOOL updateDialogDisplayed;
    
    Mode viewMode;
    __block NSInteger knocks;
    NSTimer *knocksTimer;
    CALayer *dimmer;
    __block BOOL awaitingRestoreConfirmation;
    __block BOOL dumpInProgress;
    BOOL projectionMode;
    
    //Debug
    BOOL showDocumentsLocation;
    int generateTicket;
    BOOL poseForIntroScreenshot;
}

@synthesize scoresTableView, changeModeButton, aboutButton, scoreSearch, bottomBar, instructionsButton, projectionButton, updateButton, dumpButton, dumpIndicator;

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    refreshCondition = [NSCondition new];
    parserCondition = [NSCondition new];
    
    //Start in the score chooser mode
    viewMode = kChooseScore;
    
    //Initialize data source for table first
    scores = [[NSMutableArray alloc] init];
    scoresFiltered = [[NSMutableArray alloc] init];
    isFiltered = NO;
    updateAddresses = [[NSMutableDictionary alloc] init];
    
    //Import any new scores and load the score list
    fileManager = [NSFileManager defaultManager];
    scoresDirectory = [self getScoresDirectory];
    bundleAnnotationsDirectory = [[scoresDirectory stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Annotations"];
    
    directories = [[NSMutableArray alloc] init];
    directoriesFiltered = [[NSMutableArray alloc] init];
    newDirectories = [self getDirectoryList];
    corruptScores = [[NSMutableArray alloc] init];
    handlingCorruptScores = NO;
    
    scoresLoaded = NO;
    refreshInProgress = NO;
    awaitingRestoreConfirmation = NO;
    firstLoad = YES;
    updateDialogDisplayed = NO;
    
    [self importScores];
    [self loadScores];
    firstLoad = NO;
    
    showDocumentsLocation = YES;
    knocks = 0;
    projectionMode = NO;
    identifier = nil;
    poseForIntroScreenshot = NO;
    
    //Set up our dimmer layer
    dimmer = [CALayer layer];
    dimmer.backgroundColor = [UIColor blackColor].CGColor;
    dimmer.opacity = 0.4;
    dimmer.frame = CGRectMake(0, 0, 1024, 1024);
    
    //Check if our blank thumbnail exists, and if not, create it.
    if (![fileManager fileExistsAtPath:[scoresDirectory stringByAppendingPathComponent:@".blank.png"]]) {
        CGFloat screenScale = [[UIScreen mainScreen] scale];
        UIGraphicsBeginImageContext(CGSizeMake(88 * screenScale, 66 * screenScale));
        UIImage *blankThumbnail = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [UIImagePNGRepresentation(blankThumbnail) writeToFile:[scoresDirectory stringByAppendingPathComponent:@".blank.png"] atomically:YES];
    }
    
    //This Should be disabled.
    generateTicket = 0;
    for (int i = 0; i < generateTicket; i++) {
        NSMutableArray *pool = [[NSMutableArray alloc] init];
        for (int j = 1; j <= 45; j++) {
            [pool addObject:[NSNumber numberWithInt:j]];
        }
        NSMutableArray *numbers = [[NSMutableArray alloc] init];
        for (int j = 0; j < 6; j++) {
            int index = arc4random_uniform((int)[pool count]);
            [numbers addObject:[pool objectAtIndex:index]];
            [pool removeObjectAtIndex:index];
        }
        [numbers sortUsingSelector:@selector(compare:)];
        NSLog(@"%i %i %i %i %i %i", [[numbers objectAtIndex:0] intValue], [[numbers objectAtIndex:1] intValue], [[numbers objectAtIndex:2] intValue], [[numbers objectAtIndex:3] intValue], [[numbers objectAtIndex:4] intValue], [[numbers objectAtIndex:5] intValue]);
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    //Check to see that we're in the right mode
    if (viewMode == kChooseScore) {
        [scoresTableView reloadData];
    } else {
        //We don't need to run the refreshScores method here, since changeMode takes care of that.
        [self changeMode];
    }
    
    scoresRefresh = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refreshScores) userInfo:nil repeats:YES];
    
    //Clear the table selection and hide the table while we wait for the network.
    [scoresTableView deselectRowAtIndexPath:[scoresTableView indexPathForSelectedRow] animated:NO];
    scoresTableView.hidden = YES;
    self.navigationItem.title = @"Decibel Score Player";
    aboutButton.enabled = NO;
    changeModeButton.enabled = NO;
    bottomBar.hidden = YES;
    scoreSearch.hidden = YES;
    
    
    if (isFiltered) {
        scoreSearch.text = @"";
        isFiltered = NO;
        [scoresTableView reloadData];
    }
    
    if (!poseForIntroScreenshot) {
        showTable = [NSTimer scheduledTimerWithTimeInterval:1.2 target:self selector:@selector(showTable) userInfo:nil repeats:NO];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [scoresRefresh invalidate];
    [showTable invalidate];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"toPlayer"]) {
        //Set the current score of the player and the service name to be used for network broadcast.
        PlayerViewController *player = (PlayerViewController *)segue.destinationViewController;
        player.initialScore = selectedScore;
        player.availableScores = scoresSorted;
        player.serviceName = @"decibel";
        player.identifier = identifier;
        player.projectionMode= projectionMode;
        //Finally, reset our identifier.
        identifier = nil;
    } else {
        //Common to all other segues
        if (@available(iOS 13.0, *)) {
            [segue.destinationViewController setModalInPresentation:YES];
        }
        if (viewMode == kManageImports) {
            dumpButton.title = @"";
        }
    }
    
    if ([segue.identifier isEqualToString:@"toUpdate"]) {
        ((UpdateViewController *)segue.destinationViewController).updateAddresses = updateAddresses;
        ((UpdateViewController *)segue.destinationViewController).updateDelegate = self;
    }
    
    if ([segue.identifier isEqualToString:@"toDownload"]) {
        ((DownloadViewController *)segue.destinationViewController).downloadDelegate = self;
    }
    
    //Common to all segues
    knocks = 0;
    [knocksTimer invalidate];
}

- (IBAction)changeMode
{
    if (viewMode == kChooseScore) {
        viewMode = kManageImports;
        scoresTableView.rowHeight = 44;
        [scoresTableView reloadData];
        [scoresTableView setEditing:YES animated:YES];
        self.navigationItem.title = @"Manage Imported Scores";
        self.navigationItem.rightBarButtonItem.title = @"Choose Score";
        scoreSearch.placeholder = @"Find Installed dsz";
        dumpButton.title = @"";
        knocks = 0;
        [knocksTimer invalidate];
        
        projectionButton.title = @"Download Score";
        
        //Check if we should enable our update button.
        if ([updateAddresses count] > 0) {
            updateButton.enabled = YES;
            updateButton.title = @"Check for Updates";
        }
    } else {
        viewMode = kChooseScore;
        scoresTableView.rowHeight = 66;
        [scoresTableView setEditing:NO animated:NO];
        [scoresTableView reloadData];
        self.navigationItem.title = @"Choose Score";
        self.navigationItem.rightBarButtonItem.title = @"Manage Files";
        scoreSearch.placeholder = @"Find Score";
        
        if (projectionMode) {
            projectionButton.title = @"Disable Projection Mode";
        } else {
            projectionButton.title = @"Enable Projection Mode";
        }
        
        updateButton.enabled = NO;
        updateButton.title = @"";
        
        dumpButton.title = @"";
        knocks = 0;
        [knocksTimer invalidate];
    }
}

- (IBAction)showInstructions
{
    [self performSegueWithIdentifier:@"toMainInstructions" sender:self];
}

- (IBAction)toggleProjectionMode
{
    if (viewMode == kChooseScore) {
        if (projectionMode) {
            projectionMode = NO;
            projectionButton.title = @"Enable Projection Mode";
        } else {
            UIAlertController *projectionWarning = [UIAlertController alertControllerWithTitle:@"Enable Projection Mode" message:@"Enabling projection mode will hide most of the player interface. You will only be able to control the score from another networked device.\n\nDo you want to continue?" preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *yesAction = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                self->projectionMode = YES;
                self->projectionButton.title = @"Disable Projection Mode";
            }];
            UIAlertAction *noAction = [UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleDefault handler:nil];
            [projectionWarning addAction:yesAction];
            [projectionWarning addAction:noAction];
            [self presentViewController:projectionWarning animated:YES completion:nil];
        }
    } else {
        updateDialogDisplayed = YES;
        [self performSegueWithIdentifier:@"toDownload" sender:self];
    }
}

- (IBAction)update
{
    updateDialogDisplayed = YES;
    [self performSegueWithIdentifier:@"toUpdate" sender:self];
}

- (IBAction)dump
{
    if (viewMode == kChooseScore) {
        return;
    }
    
    if (knocks < 2) {
        if (knocks == 0) {
            [knocksTimer invalidate];
            knocksTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(resetKnocks) userInfo:nil repeats:NO];
        }
        knocks++;
        return;
    }
    
    if ([dumpButton.title isEqualToString:@"Dump"]) {
        UIAlertController *dumpScores = [UIAlertController alertControllerWithTitle:@"Dump Scores to Archive" message:@"Do you want to export the entire collection of installed scores to an archive?" preferredStyle:UIAlertControllerStyleAlert];
            
        UIAlertAction *noAction = [UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            self->dumpButton.title = @"";
            self->knocks = 0;
        }];
        
        UIAlertAction *yesAction = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self->dumpInProgress = YES;
            [self->dumpIndicator startAnimating];
            [self.view.layer insertSublayer:self->dimmer below:self->dumpIndicator.layer];
            self->dumpButton.title = @"";
            self->knocks = 0;
            [self disableControls:YES];
            
            //Don't block the main queue while we create our zip file.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                
                //Dump all our scores to a zip file.
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                if ([paths count] == 0 || self->scoresDirectory == nil) {
                    //Either we can't find the documents directory or our scores directory. Abort!
                    return;
                }
                
                NSString *zipFileName = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"ScoreDump.zip"];
            
                //Check if the zip file already exists and remove if necessary.
                if ([self->fileManager fileExistsAtPath:zipFileName]) {
                    [self->fileManager removeItemAtPath:zipFileName error:nil];
                }
                
                [SSZipArchive createZipFileAtPath:zipFileName withContentsOfDirectory:self->scoresDirectory];
            
                //Store the creation date.
                NSDictionary *zipAttrs = [self->fileManager attributesOfItemAtPath:zipFileName error:nil];
                if (zipAttrs != nil) {
                    NSDate *modificationDate = (NSDate *)[zipAttrs objectForKey:NSFileModificationDate];
                    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
                    [defaults setObject:modificationDate forKey:@"ScoreDumpModificationDate"];
                }
                
                self->dumpInProgress = NO;
                //Perform our final UI updates on the main queue
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->dimmer removeFromSuperlayer];
                    [self->dumpIndicator stopAnimating];
                    [self disableControls:NO];
                });
            });
        }];
            
        [dumpScores addAction:noAction];
        [dumpScores addAction:yesAction];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:dumpScores animated:YES completion:nil];
        });
    } else {
        [knocksTimer invalidate];
        dumpButton.title = @"Dump";
    }
}

- (BOOL)importScores
{
    //Get our documents directory, and check that the score directory has been set.
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if ([paths count] == 0 || scoresDirectory == nil) {
        //Either we can't find the documents directory or our scores directory. Abort!
        return NO;
    }
    
    NSString *documentsDirectory = [paths objectAtIndex:0];
    if (showDocumentsLocation) {
        NSLog(@"%@", documentsDirectory);
        showDocumentsLocation = NO;
    }
    
    //Before importing any scores, check for the special case of the existence of a ScoreDump.zip file.
    //(But only if this is not on first load.)
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *zipFileName = [documentsDirectory stringByAppendingPathComponent:@"ScoreDump.zip"];
    
    if (!firstLoad && [fileManager fileExistsAtPath:zipFileName]) {
        //Check if the modification date is newer than the saved one
        NSDate *zipModificationDate;
        NSDictionary *zipAttrs = [fileManager attributesOfItemAtPath:zipFileName error:nil];
        if (zipAttrs != nil) {
            zipModificationDate = (NSDate *)[zipAttrs objectForKey:NSFileModificationDate];
        }
        if (zipModificationDate != nil) {
            NSDate *savedDate = [defaults objectForKey:@"ScoreDumpModificationDate"];
            if (savedDate == nil || [zipModificationDate compare:savedDate] == NSOrderedDescending) {
                UIAlertController *restoreScores = [UIAlertController alertControllerWithTitle:@"Restore Scores from Archive" message:@"Do you want to restore the score collection from the found archive? WARNING: This will overwrite all existing scores." preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *yesAction = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                    [self->dumpIndicator startAnimating];
                    [self.view.layer insertSublayer:self->dimmer below:self->dumpIndicator.layer];
                    if (self->projectionButton.enabled) {
                        self->projectionButton.title = @"";
                        self->projectionButton.enabled = NO;
                    }
                    
                    [self disableControls:YES];
                    
                    //Don't block the main queue with the zip operation.
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        for (int i = 0; i < [self->directories count]; i++) {
                            [self->fileManager removeItemAtPath:[self->directories objectAtIndex:i] error:nil];
                        }
                        
                        for (int i = 0; i < [self->scores count];) {
                            if ([((Score *)[self->scores objectAtIndex:i]).scorePath hasPrefix:self->scoresDirectory]) {
                                [self->scores removeObjectAtIndex:i];
                            } else {
                                i++;
                            }
                        }
                        [self->directories removeAllObjects];
                        [self->updateAddresses removeAllObjects];
                        [Renderer clearCache];
                        
                        //Now unzip our file.
                        [SSZipArchive unzipFileAtPath:zipFileName toDestination:self->scoresDirectory];
                        self->newDirectories = [self getDirectoryList];
                        
                        //Remove the dump file.
                        [self->fileManager removeItemAtPath:zipFileName error:nil];
                        
                        //Set the refreshInProgress variable so that we know the list is being refreshed.
                        //(Use this to block the timer function instead of the awaitingRestoreConfirmation flag in case we decide
                        //to check for this flag in the importScores or LoadScores function in the future.)
                        [self->refreshCondition lock];
                        self->refreshInProgress = YES;
                        self->awaitingRestoreConfirmation = NO;
                        
                        [self importScores];
                        [self loadScores];
                        self->refreshInProgress = NO;
                        [self->refreshCondition broadcast];
                        [self->refreshCondition unlock];
                        
                        //Perform final UI updates in the main queue.
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self->dimmer removeFromSuperlayer];
                            [self->dumpIndicator stopAnimating];
                            [self disableControls:NO];
                        });
                    });
                }];
                UIAlertAction *noAction = [UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    //We only need to remove the dump file here.
                    [self->fileManager removeItemAtPath:zipFileName error:nil];
                }];
                [restoreScores addAction:yesAction];
                [restoreScores addAction:noAction];
                [self presentViewController:restoreScores animated:YES completion:nil];
                
                //For now return with a NO so that the loadscores function is not called.
                awaitingRestoreConfirmation = YES;
                return NO;
            }
        }
    } else if ([defaults objectForKey:@"ScoreDumpModificationDate"] != nil && ![fileManager fileExistsAtPath:[documentsDirectory stringByAppendingPathComponent:@"ScoreDump.zip"]]) {
        //If a previous dump file has been removed, remove the saved modification date.
        [defaults removeObjectForKey:@"ScoreDumpModificationDate"];
    }
    
    //Then import our scores.
    return [self importScoresFromDirectory:documentsDirectory];
}

- (BOOL)importScoresFromDirectory:(NSString *)directory
{
    //First check that our scores directory is set and that the supplied directory exits.
    BOOL isDirectory = NO;
    [fileManager fileExistsAtPath:directory isDirectory:&isDirectory];
    
    if (scoresDirectory == nil || !directory) {
        return NO;
    }
    
    //Get a list of .dsz (decibel score zip) files in the selected directory
    NSArray *directoryContents = [fileManager contentsOfDirectoryAtPath:directory error:nil];
    if (directoryContents == nil) {
        //No files found or an error has occurred. Return.
        return NO;
    }
    //Filter out files of any other extension
    NSPredicate *filter = [NSPredicate predicateWithFormat:@"self ENDSWITH '.dsz'"];
    NSArray *zippedScores = [directoryContents filteredArrayUsingPredicate:filter];
    
    if ([zippedScores count] == 0) {
        //No score files to import
        return NO;
    }
    
    //Unzip scores to our scores directory
    for (int i = 0; i < [zippedScores count]; i++) {
        NSString *fileName = [directory stringByAppendingPathComponent:[zippedScores objectAtIndex:i]];
        NSString *destination = [scoresDirectory stringByAppendingPathComponent:[[zippedScores objectAtIndex:i] stringByDeletingPathExtension]];
        
        //If the directory already exists then we'll replace it with the new score.
        //Move the directory to a temporary location until our replacement score successfully unzips.
        BOOL backupMade = NO;
        if ([fileManager fileExistsAtPath:destination]) {
            NSError *error;
            [fileManager moveItemAtPath:destination toPath:[destination stringByAppendingString:@".bak"] error:&error];
            if (error != nil) {
                //No backup could be made. Delete the directory instead.
                [fileManager removeItemAtPath:destination error:nil];
            } else {
                backupMade = YES;
            }
        }
        
        //Try to unzip our archive.
        if ([SSZipArchive unzipFileAtPath:fileName toDestination:destination]) {
            //If we successfully unzipped the score then we can remove the original file.
            [fileManager removeItemAtPath:fileName error:nil];
            
            //Remove our backup directory.
            if (backupMade) {
                [fileManager removeItemAtPath:[destination stringByAppendingString:@".bak"] error:nil];
            }
            
            //Remove the directory from our list so that we don't end up with a duplicate when
            //processing the new scores.
            [directories removeObject:destination];
            [updateAddresses removeObjectForKey:destination];
            
            //And remove any associated scores from the list.
            for (int i = 0; i < [scores count]; i++) {
                if ([((Score *)[scores objectAtIndex:i]).scorePath isEqualToString:destination]) {
                    [scores removeObjectAtIndex:i];
                    i--;
                }
            }
            
            //We also need to clear the image cache so that we don't have any references to old images
            [Renderer removeDirectoryFromCache:destination];
            
            //Add the destination directory to the list of new directories for processing.
            if ([newDirectories indexOfObject:destination] == NSNotFound) {
                [newDirectories addObject:destination];
            }
        } else {
            //Something went wrong while unzipping. If we're refreshing the list then the most likely
            //problem is that we tried to update while files were still being copied to the device.
            //If it wasn't during a refresh then the file is corrupt and we should remove it.
            if (!refreshInProgress) {
                [fileManager removeItemAtPath:fileName error:nil];
                [fileManager removeItemAtPath:destination error:nil];
            }
            
            //Restore our backup.
            if (backupMade) {
                NSError *error;
                [fileManager moveItemAtPath:[destination stringByAppendingString:@".bak"] toPath:destination error:&error];
                if (error != nil) {
                    //If we can't restore our backup, don't leave it lying around.
                    [fileManager removeItemAtPath:[destination stringByAppendingString:@".bak"] error:nil];
                }
            }
        }
    }
    return YES;
}

- (void)loadScores
{
    //Change flags as needed. The loaded flag is set false to show that a load operation is in progress.
    scoresLoaded = NO;
    
    for (int i = 0; i < [newDirectories count]; i++) {
        if (![fileManager fileExistsAtPath:[[newDirectories objectAtIndex:i] stringByAppendingPathComponent:@"opus.xml"]]) {
            //If no score definition exists in the subdirectory then this isn't a valid score and
            //shouldn't be in the scores directory. Remove it from our processing list and delete it.
            [fileManager removeItemAtPath:[newDirectories objectAtIndex:i] error:nil];
            [newDirectories removeObjectAtIndex:i];
        }
    }
    
    //If this is our first load, start with the bundled scores.
    parsers = [[NSMutableArray alloc] init];
    if (firstLoad) {
        NSData *xmlScore = [[NSData alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Bundled" ofType:@"xml"]];
        OpusParser *parser = [[OpusParser alloc] initWithData:xmlScore scorePath:[[NSBundle mainBundle] bundlePath] timeOut:5 asScoreComponent:NO];
        parser.thumbnailPath = scoresDirectory;
        parser.annotationsPath = bundleAnnotationsDirectory;
        parser.delegate = self;
        [parsers addObject:parser];
    }
    
    //Set up the remaining parsers.
    for (int i = 0; i < [newDirectories count]; i++) {
        NSData *xmlScore = [[NSData alloc] initWithContentsOfFile:[[newDirectories objectAtIndex:i] stringByAppendingPathComponent:@"opus.xml"]];
        OpusParser *parser = [[OpusParser alloc] initWithData:xmlScore scorePath:[newDirectories objectAtIndex:i] timeOut:5 asScoreComponent:NO];
        parser.delegate = self;
        [parsers addObject:parser];
    }
    
    //Then start.
    [parserCondition lock];
    finishedParsers = 0;
    [parserCondition unlock];
    for (int i = 0; i < [parsers count]; i++) {
        [[parsers objectAtIndex:i] startParse];
    }
    
    //Wait for all of our parsers to finish or time out, then clean up.
    [parserCondition lock];
    while (finishedParsers < [parsers count]) {
        [parserCondition wait];
    }
    [parsers removeAllObjects];
    [parserCondition unlock];
    
    //We're done loading the scores. Now sort them alphabetically by composer and name.
    scoresSorted = [self sortScores];
    
    //Update the master directory list by appending the new directories we just processed
    [directories addObjectsFromArray:newDirectories];
    [newDirectories removeAllObjects];
    directoriesSorted = [self sortDirectories];
    
    //The remaining code contains all sorts of user interface updates, so make sure we're on the main queue.
    
    dispatch_async(dispatch_get_main_queue(), ^{
        //Reload our table view
        self->scoresLoaded = YES;
        [self->scoresTableView reloadData];
    
        //Check if we need to enable the update button.
        if (self->viewMode == kManageImports && !self->projectionButton.enabled && [self->updateAddresses count] > 0) {
            self->projectionButton.enabled = YES;
            self->projectionButton.title = @"Check for Updates";
        }
    
        if ([self->corruptScores count] > 0) {
            [self handleCorruptScores];
        }
    });
}

- (NSString *)getScoresDirectory
{
    //Return the directory of our imported scores or create it if it doesn't exist yet. If it can't
    //be created, then return nil. (Scores are stored in a subdirectory "Library/Application Support".)
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if ([paths count] == 0) {
        return nil;
    }
    //We only need the first path returned by the above function
    NSString *directory = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"Scores"];
    if ([fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) {
        return directory;
    } else {
        return nil;
    }
}

- (NSMutableArray *)getDirectoryList
{
    //Get list of directories to process
    NSMutableArray *directoryList = [[NSMutableArray alloc] init];
    
    //We do this by getting a list of all files and then checking whether they're subdirectories
    if (scoresDirectory != nil) {
        NSArray *directoryContents = [fileManager contentsOfDirectoryAtPath:scoresDirectory error:nil];
        for (int i = 0; i < [directoryContents count]; i++) {
            BOOL isDirectory = NO;
            NSString *currentFile = [scoresDirectory stringByAppendingPathComponent:[directoryContents objectAtIndex:i]];
            [fileManager fileExistsAtPath:currentFile isDirectory:&isDirectory];
            if (isDirectory) {
                [directoryList addObject:currentFile];
            }
        }
    }
    return directoryList;
}

- (NSArray *)sortScores
{
    NSSortDescriptor *composerDescriptor = [[NSSortDescriptor alloc] initWithKey:@"composerSurnames" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    NSSortDescriptor *nameDescriptor = [[NSSortDescriptor alloc] initWithKey:@"scoreName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    
    NSArray *sortDescriptors = [NSArray arrayWithObjects:composerDescriptor, nameDescriptor, nil];
    return [scores sortedArrayUsingDescriptors:sortDescriptors];
}

- (NSArray *)sortDirectories
{
    return [directories sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)refreshScores
{
    if (!scoresLoaded || refreshInProgress || handlingCorruptScores || awaitingRestoreConfirmation || updateDialogDisplayed || dumpInProgress) {
        //If we're already refreshing the list or we're in the process of prompting the user about 
        //corrupt scores then our work here is done.
        return;
    }
    //Don't run the refresh on the main queue to avoid blocking the UI.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self->refreshCondition lock];
        self->refreshInProgress = YES;
        if ([self importScores]) {
            [self loadScores];
        }
        self->refreshInProgress = NO;
        [self->refreshCondition broadcast];
        [self->refreshCondition unlock];
    });
}

- (void)handleCorruptScores
{
    //This should not be called if there are no corrupt scores
    if ([corruptScores count] == 0) {
        return;
    }
    handlingCorruptScores = YES;
    currentCorruptScore = -1;
    
    [self processNextCorruptScore];
}

- (void)processNextCorruptScore
{
    currentCorruptScore++;
    if (currentCorruptScore == [corruptScores count]) {
        [corruptScores removeAllObjects];
        handlingCorruptScores = NO;
        directoriesSorted = [self sortDirectories];
        return;
    }
    
    UIAlertController *removeScore = [UIAlertController alertControllerWithTitle:@"Corrupt Score" message:[NSString stringWithFormat:@"The score file %@.dsz is corrupt. Do you wish to delete it from your collection?", [[corruptScores objectAtIndex:currentCorruptScore] lastPathComponent]] preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *yesAction = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self->fileManager removeItemAtPath:[self->corruptScores objectAtIndex:self->currentCorruptScore] error:nil];
        [self->directories removeObject:[self->corruptScores objectAtIndex:self->currentCorruptScore]];
        [self processNextCorruptScore];
    }];
    UIAlertAction *noAction = [UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self processNextCorruptScore];
    }];
    [removeScore addAction:yesAction];
    [removeScore addAction:noAction];
    [self presentViewController:removeScore animated:YES completion:nil];
}

- (void)showTable
{
    self.navigationItem.title = @"Choose Score";
    scoresTableView.hidden = NO;
    aboutButton.enabled = YES;
    changeModeButton.enabled = YES;
    bottomBar.hidden = NO;
    scoreSearch.hidden = NO;
}

- (void)resetKnocks
{
    knocks = 0;
}

- (void)disableControls:(BOOL)disabled
{
    aboutButton.enabled = !disabled;
    changeModeButton.enabled = !disabled;
    instructionsButton.enabled = !disabled;
    dumpButton.enabled = !disabled;
    if (![projectionButton.title isEqualToString:@""]) {
        projectionButton.enabled = !disabled;
    }
    scoresTableView.userInteractionEnabled = !disabled;
    scoreSearch.userInteractionEnabled = !disabled;
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
    if (viewMode == kChooseScore) {
        if (!scoresLoaded) {
            return 0;
        } else {
            if (isFiltered) {
                return [scoresFiltered count];
            } else {
                return [scoresSorted count];
            }
        }
    } else {
        if (isFiltered) {
            return [directoriesFiltered count];
        } else {
            return [directoriesSorted count];
        }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (viewMode == kChooseScore) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ScoreCell"];
    
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ScoreCell"];
        }
	
        NSArray *dataSource;
        if (isFiltered) {
            dataSource = scoresFiltered;
        } else {
            dataSource = scoresSorted;
        }
        cell.textLabel.text = ((Score *)[dataSource objectAtIndex:indexPath.row]).scoreName;
        cell.detailTextLabel.text = ((Score *)[dataSource objectAtIndex:indexPath.row]).composerFullText;
        NSString *fileName = [NSString stringWithFormat:@".%@.%@.thumbnail.png", ((Score *)[dataSource objectAtIndex:indexPath.row]).composerFullText, ((Score *)[dataSource objectAtIndex:indexPath.row]).scoreName];
        fileName = [fileName stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
        fileName = [fileName stringByReplacingOccurrencesOfString:@":" withString:@"."];
        if ([((Score *)[dataSource objectAtIndex:indexPath.row]).scorePath isEqualToString:[[NSBundle mainBundle] bundlePath]]) {
            fileName = [scoresDirectory stringByAppendingPathComponent:fileName];
        } else {
            fileName = [((Score *)[dataSource objectAtIndex:indexPath.row]).scorePath stringByAppendingPathComponent:fileName];
        }
        if ([fileManager fileExistsAtPath:fileName]) {
            cell.imageView.image = [UIImage imageWithContentsOfFile:fileName];
        } else {
            cell.imageView.image = [UIImage imageWithContentsOfFile:[scoresDirectory stringByAppendingPathComponent:@".blank.png"]];
        }
        return cell;
    } else {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ImportsCell"];
        
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ImportsCell"];
        }
        
        if (isFiltered) {
            cell.textLabel.text = [[directoriesFiltered objectAtIndex:indexPath.row] lastPathComponent];
        } else {
            cell.textLabel.text = [[directoriesSorted objectAtIndex:indexPath.row] lastPathComponent];
        }
        return cell;
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView.editing == YES) {
        return UITableViewCellEditingStyleDelete;
    } else {
        return UITableViewCellEditingStyleNone;
    }
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (viewMode == kChooseScore) {
        return;
    }
    
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        //Make sure we check if the list has been filtered.
        NSInteger directoryIndex;
        if (isFiltered) {
            directoryIndex = [directories indexOfObjectIdenticalTo:[directoriesFiltered objectAtIndex:indexPath.row]];
            [directoriesFiltered removeObjectAtIndex:indexPath.row];
        } else {
            directoryIndex = [directories indexOfObjectIdenticalTo:[directoriesSorted objectAtIndex:indexPath.row]];
        }
        
        //First we need to delete the directory associated with the row
        [fileManager removeItemAtPath:[directories objectAtIndex:directoryIndex] error:nil];
        
        //Then remove any scores associated with that directory
        for (int i = 0; i < [scores count]; i++) {
            if ([((Score *)[scores objectAtIndex:i]).scorePath isEqualToString:[directories objectAtIndex:directoryIndex]]) {
                [scores removeObjectAtIndex:i];
                i--;
            }
        }
        scoresSorted = [self sortScores];
        
        //Do the same for our filtered scores if necessary.
        if (isFiltered) {
            for (int i = 0; i < [scoresFiltered count]; i++) {
                if ([((Score *)[scoresFiltered objectAtIndex:i]).scorePath isEqualToString:[directories objectAtIndex:directoryIndex]]) {
                    [scoresFiltered removeObjectAtIndex:i];
                    i--;
                }
            }
        }
        
        //Clear any images from the cache that were located in that directory
        [Renderer removeDirectoryFromCache:[directories objectAtIndex:directoryIndex]];
        [updateAddresses removeObjectForKey:[directories objectAtIndex:directoryIndex]];
        
        if ([updateAddresses count] == 0 && projectionButton.enabled) {
            projectionButton.title = @"";
            projectionButton.enabled = NO;
        }
        
        //Then remove the reference from the directories array and the table
        [directories removeObjectAtIndex:directoryIndex];
        directoriesSorted = [self sortDirectories];
        [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        
    } //else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    //}   
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (viewMode == kManageImports) {
        //If we're managing the imported scores, show which scores are contained within the directory.
        NSInteger directoryIndex;
        if (isFiltered) {
            directoryIndex = [directories indexOfObjectIdenticalTo:[directoriesFiltered objectAtIndex:indexPath.row]];
        } else {
            directoryIndex = [directories indexOfObjectIdenticalTo:[directoriesSorted objectAtIndex:indexPath.row]];
        }
        
        NSMutableString *scoreList = [[NSMutableString alloc] init];
        int scoresInDirectory = 0;
        for (int i = 0; i < [scoresSorted count]; i++) {
            if ([((Score *)[scoresSorted objectAtIndex:i]).scorePath isEqualToString:[directories objectAtIndex:directoryIndex]]) {
                [scoreList appendFormat:@"\n%@ - %@", ((Score *)[scoresSorted objectAtIndex:i]).composerFullText, ((Score *)[scoresSorted objectAtIndex:i]).scoreName];
                scoresInDirectory++;
            }
        }
        
        NSMutableString *alertMessage;
        if (scoresInDirectory > 1) {
            alertMessage = [NSMutableString stringWithFormat:@"Score file contains the following works:\n%@", scoreList];
        } else {
            alertMessage = [NSMutableString stringWithFormat:@"Score file contains the following work:\n%@", scoreList];
        }
        if ([updateAddresses objectForKey:[directories objectAtIndex:directoryIndex]] != nil) {
            [alertMessage appendFormat:@"\n\nVersion: %@", [[updateAddresses objectForKey:[directories objectAtIndex:directoryIndex]] objectAtIndex:1]];
        }
        
        UIAlertController *scoreContents = [UIAlertController alertControllerWithTitle:@"Contents" message:alertMessage preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [scoreContents addAction:okAction];
        [self presentViewController:scoreContents animated:YES completion:^{
            [self->scoresTableView deselectRowAtIndexPath:[self->scoresTableView indexPathForSelectedRow] animated:YES];
        }];
    } else {
        //Stop any more score refresh events from firing.
        [scoresRefresh invalidate];
    
        if (isFiltered) {
            selectedScore = [scoresFiltered objectAtIndex:indexPath.row];
        } else {
            selectedScore = [scoresSorted objectAtIndex:indexPath.row];
        }
        [scoreSearch resignFirstResponder];
    
        if (selectedScore.askForIdentifier) {
            UIAlertController *identifierInputBox = [UIAlertController alertControllerWithTitle:@"Enter Identifier" message:@"Enter a unique identifier for this iPad." preferredStyle:UIAlertControllerStyleAlert];
            [identifierInputBox addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.delegate = self;
                textField.keyboardType = UIKeyboardTypeDefault;
                textField.placeholder = [[UIDevice currentDevice] name];
            }];
            
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                if ([[identifierInputBox.textFields objectAtIndex:0].text length] != 0) {
                    self->identifier = [identifierInputBox.textFields objectAtIndex:0].text;
                }
                //Wait for any current refresh operation to complete.
                [self->refreshCondition lock];
                while (self->refreshInProgress) {
                    [self->refreshCondition wait];
                }
                [self->refreshCondition unlock];
                
                [self performSegueWithIdentifier:@"toPlayer" sender:self];
            }];
            
            [identifierInputBox addAction:okAction];
            [self presentViewController:identifierInputBox animated:YES completion:nil];
        } else {
            [refreshCondition lock];
            while (refreshInProgress) {
                [refreshCondition wait];
            }
            [refreshCondition unlock];
            
            [self performSegueWithIdentifier:@"toPlayer" sender:self];
        }
    }
}

#pragma mark - OpusParser delegate

- (void)parserFinished:(id)parser withScores:(NSMutableArray *)newScores;
{
    if (((OpusParser *)parser).updateURL != nil) {
        NSString *updateURL = ((OpusParser *)parser).updateURL;
        NSString *version = ((OpusParser *)parser).opusVersion;
        [updateAddresses setObject:[NSArray arrayWithObjects:updateURL, version, nil] forKey:((OpusParser *)parser).scorePath];
    }
    
    ((OpusParser *)parser).delegate = nil;
    [scores addObjectsFromArray:newScores];
    [parserCondition lock];
    finishedParsers++;
    [parserCondition signal];
    [parserCondition unlock];
}

- (void)parserError:(id)parser
{
    ((OpusParser *)parser).delegate = nil;
    if (![((OpusParser *)parser).scorePath isEqualToString:[[NSBundle mainBundle] bundlePath]]) {
        [corruptScores addObject:((OpusParser *)parser).scorePath];
    }
    [parserCondition lock];
    finishedParsers++;
    [parserCondition signal];
    [parserCondition unlock];
}

#pragma mark - UpdateDelegate

- (void)downloadedUpdatesToDirectory:(NSString *)downloadDirectory
{
    if (downloadDirectory != nil) {
        if ([self importScoresFromDirectory:downloadDirectory]) {
            [self loadScores];
        }
    }
}

- (void)finishedUpdating
{
    updateDialogDisplayed = NO;
}

#pragma mark - UITextField delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    return YES;
}

#pragma mark - UISearchBar delegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    if (searchText.length == 0){
        isFiltered = NO;
    } else {
        isFiltered = YES;
        //Filter both our scores and directories so that we can change between view modes easily.
        [scoresFiltered removeAllObjects];
        
        for (int i = 0; i < [scoresSorted count]; i++) {
            NSRange nameRange = [((Score *)[scoresSorted objectAtIndex:i]).scoreName rangeOfString:searchText options:NSCaseInsensitiveSearch];
            NSRange composerRange = [((Score *)[scoresSorted objectAtIndex:i]).composerFullText rangeOfString:searchText options:NSCaseInsensitiveSearch];
            if (nameRange.location != NSNotFound || composerRange.location != NSNotFound) {
                [scoresFiltered addObject:[scoresSorted objectAtIndex:i]];
            }
        }
        [directoriesFiltered removeAllObjects];
        
        for (int i = 0; i < [directories count]; i++) {
            NSRange pathRange = [[[directories objectAtIndex:i] lastPathComponent] rangeOfString:searchText options:NSCaseInsensitiveSearch];
            if (pathRange.location != NSNotFound) {
                [directoriesFiltered addObject:[directories objectAtIndex:i]];
            }
        }
    }
    
    [scoresTableView reloadData];
}

@end

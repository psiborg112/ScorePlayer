//
//  Network2ViewController.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 9/11/2014.
//  Copyright (c) 2014 Decibel. All rights reserved.
//

#import "Network2ViewController.h"

const NSInteger RECOMMEND_UPDATE_MAJOR = 2;
const NSInteger RECOMMEND_UPDATE_MINOR = 1;

@interface Network2ViewController ()

- (void)changeMode:(Mode)newViewMode;
- (void)filterScores:(NSString *)searchText;

@end

@implementation Network2ViewController {
    NSNetServiceBrowser *netServiceBrowser;
    NSString *service;
    NSMutableArray *servers;
    NSMutableArray *filteredScores;
    UIColor *defaultVersionColour;
    
    Mode viewMode;
    BOOL isFiltered;
    BOOL layoutView;
}

@synthesize networkTableView, windowTitle, disconnectButton, manualConnectionButton, scoreChangeButton, cancelButton, scoreSearch, bottomBar, tableLeadingConstraint, serviceName, serverNamePrefix, localServerName, lastAddress, connected, allowScoreChange, networkConnectionDelegate;

- (void)viewDidLoad {
    [super viewDidLoad];
    viewMode = kChooseServer;
    // Do any additional setup after loading the view.
    netServiceBrowser = [[NSNetServiceBrowser alloc] init];
    netServiceBrowser.delegate = self;
    
    service = [NSString stringWithFormat:@"_%@._tcp.", serviceName];
    servers = [[NSMutableArray alloc] init];
    
    scoreChangeButton.enabled = NO;
    scoreChangeButton.title = @"";
    
    filteredScores = [[NSMutableArray alloc] init];
    isFiltered = NO;
    layoutView = NO;
    
    defaultVersionColour = nil;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [netServiceBrowser searchForServicesOfType:service inDomain:@""];
    
    if (connected) {
        [self changeMode:kViewDevices];
    } else {
        [self changeMode:kChooseServer];
    }
    layoutView = YES;
}

- (IBAction)disconnect
{
    [networkConnectionDelegate disconnect];
    [self changeMode:kChooseServer];
    [networkTableView reloadData];
}

- (IBAction)manuallyConnect
{
    UIAlertController *manualInputBox = [UIAlertController alertControllerWithTitle:@"Enter Address" message:@"Enter a server address to connect to." preferredStyle:UIAlertControllerStyleAlert];
    
    [manualInputBox addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"address:port";
        if (self->lastAddress != nil) {
            textField.text = self->lastAddress;
        }
        textField.delegate = self;
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self->netServiceBrowser stop];
        NSInteger port = 0x0dBA;
        NSString *address;
        //If we have more than one colon we're dealing with an IPv6 address.
        NSArray *separated = [[manualInputBox.textFields objectAtIndex:0].text componentsSeparatedByString:@":"];
        if ([separated count] > 2) {
            if ([[separated objectAtIndex:0] hasPrefix:@"["]) {
                NSString *adjusted = [[manualInputBox.textFields objectAtIndex:0].text substringFromIndex:1];
                separated = [adjusted componentsSeparatedByString:@"]:"];
                if ([separated count] > 1) {
                    address = [separated objectAtIndex:0];
                    port = [[separated objectAtIndex:1] integerValue];
                } else {
                    //This shouldn't be a valid option.
                    address = adjusted;
                }
            } else {
                address = [manualInputBox.textFields objectAtIndex:0].text;
            }
        } else if ([separated count] > 1) {
            //IPv4 address from this point on.
            address = [separated objectAtIndex:0];
            port = [[separated objectAtIndex:1] integerValue];
        } else {
            address = [manualInputBox.textFields objectAtIndex:0].text;
        }
        //Use a three second timeout when connecting manually so that the interface doesn't
        //become unresponsive due to a failing DNS lookup.
        [self->networkConnectionDelegate saveLastManualAddress:[manualInputBox.textFields objectAtIndex:0].text];
        [self->networkConnectionDelegate connectToServer:address onPort:port withTimeout:3];
        self->networkConnectionDelegate = nil;
        [self performSegueWithIdentifier:@"returnToPlayer" sender:self];
        //[self dismissViewControllerAnimated:YES completion:nil];
        //NSLog(@"Address: %@, Port: %i", address, (int)port);
    }];
    
    [manualInputBox addAction:cancelAction];
    [manualInputBox addAction:okAction];
    
    [self presentViewController:manualInputBox animated:YES completion:nil];
}

- (IBAction)viewScoreList
{
    if (viewMode == kViewDevices) {
        [self changeMode:kChooseScore];
    } else if (viewMode == kChooseScore) {
        [self changeMode:kViewDevices];
    }
}

- (IBAction)cancel
{
    [netServiceBrowser stop];
    networkConnectionDelegate = nil;
    [self performSegueWithIdentifier:@"returnToPlayer" sender:self];
    //[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)changeMode:(Mode)newViewMode
{
    if (viewMode == newViewMode) {
        return;
    }
    
    if (newViewMode == kChooseServer) {
        windowTitle.title = @"Connect to Device";
        cancelButton.title = @"Cancel";
        disconnectButton.enabled = NO;
        manualConnectionButton.enabled = YES;
        scoreChangeButton.title = @"";
        scoreChangeButton.enabled = NO;
        scoreSearch.hidden = YES;
        tableLeadingConstraint.active = YES;
        if (layoutView) {
            [self.view layoutIfNeeded];
        }
        //networkTableView.frame = CGRectMake(scoreSearch.frame.origin.x, scoreSearch.frame.origin.y, networkTableView.frame.size.width, bottomBar.frame.origin.y - scoreSearch.frame.origin.y);
    } else if (newViewMode == kViewDevices) {
        windowTitle.title = @"Connected Devices";
        cancelButton.title = @"Close";
        disconnectButton.enabled = YES;
        manualConnectionButton.enabled = NO;
        if (allowScoreChange && availableScores != nil) {
            scoreChangeButton.enabled = YES;
            scoreChangeButton.title = @"Change Score";
        }
        scoreSearch.hidden = YES;
        tableLeadingConstraint.active = YES;
        if (layoutView) {
            [self.view layoutIfNeeded];
        }
        //networkTableView.frame = CGRectMake(scoreSearch.frame.origin.x, scoreSearch.frame.origin.y, networkTableView.frame.size.width, bottomBar.frame.origin.y - scoreSearch.frame.origin.y);
    } else {
        if (viewMode != kViewDevices) {
            //We shouldn't be able to change to here from the choose server view.
            return;
        }
        windowTitle.title = @"Choose a New Score";
        cancelButton.title = @"Cancel";
        scoreChangeButton.title = @"View Connected Devices";
        isFiltered = NO;
        scoreSearch.text = @"";
        scoreSearch.hidden = NO;
        tableLeadingConstraint.active = NO;
        [self.view layoutIfNeeded];
        //networkTableView.frame = CGRectMake(scoreSearch.frame.origin.x, scoreSearch.frame.origin.y + scoreSearch.frame.size.height, networkTableView.frame.size.width, bottomBar.frame.origin.y - scoreSearch.frame.origin.y - scoreSearch.frame.size.height);
    }
    viewMode = newViewMode;
    [networkTableView reloadData];
}

- (void)filterScores:(NSString *)searchText
{
    [filteredScores removeAllObjects];
    for (int i = 0; i < [availableScores count]; i++) {
        NSRange nameRange = [[[availableScores objectAtIndex:i] objectAtIndex:0] rangeOfString:searchText options:NSCaseInsensitiveSearch];
        NSRange composerRange = [[[availableScores objectAtIndex:i] objectAtIndex:1] rangeOfString:searchText options:NSCaseInsensitiveSearch];
        if (nameRange.location != NSNotFound || composerRange.location != NSNotFound) {
            [filteredScores addObject:[availableScores objectAtIndex:i]];
        }
    }
}

#pragma mark NetworkStatus delegate

- (void)setNetworkDevices:(NSArray *)devices
{
    //First, sort our devices keeping the server at the top. (If we have more than just one client.)
    if ([devices count] > 2) {
        NSMutableArray *clients = [devices mutableCopy];
        [clients removeObjectAtIndex:0];
        //Compare using the first object in the multidemensional array.
        [clients sortUsingComparator:^(id a, id b){
            return [[a objectAtIndex:0] localizedCaseInsensitiveCompare:[b objectAtIndex:0]];
        }];
        [clients insertObject:[devices objectAtIndex:0] atIndex:0];
        networkDevices = clients;
    } else {
        networkDevices = devices;
    }
    
    //If our network connection delegate is not set, it probably means we're still in the middle
    //of our segue. Don't update the table otherwise it will cause our view to load prematurely.
    if (networkConnectionDelegate == nil) {
        return;
    }
    
    if (viewMode == kChooseServer) {
        if ([devices count] > 1) {
            //someone has joined us. Show the network status.
            [self changeMode:kViewDevices];
        }
    } else {
        if ([devices count] > 1) {
            if (viewMode == kViewDevices) {
                [networkTableView reloadData];
            }
        } else {
            //We're the last device left on the network. Allow the user to choose a server to connect to.
            [self changeMode:kChooseServer];
        }
    }
}

- (NSArray *)networkDevices
{
    return networkDevices;
}

- (void)setAvailableScores:(NSArray *)scores
{
    availableScores = scores;
    
    if (networkConnectionDelegate == nil) {
        return;
    }
    
    if (viewMode == kViewDevices && allowScoreChange && availableScores != nil) {
        scoreChangeButton.enabled = YES;
        scoreChangeButton.title = @"Change Score";
    } else if (availableScores == nil) {
        if (viewMode == kChooseScore) {
            [self changeMode:kViewDevices];
        }
        scoreChangeButton.enabled = NO;
        scoreChangeButton.title = @"";
    }
    
    if (viewMode == kChooseScore) {
        if (isFiltered) {
            [self filterScores:scoreSearch.text];
        }
        [networkTableView reloadData];
    }
}

- (NSArray *)availableScores
{
    return availableScores;
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
    if (viewMode == kChooseServer) {
        return [servers count];
    } else if (viewMode == kViewDevices) {
        return [networkDevices count];
    } else {
        if (isFiltered) {
            return [filteredScores count];
        } else {
            return [availableScores count];
        }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell;
    if (viewMode == kChooseServer) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"ServerCell"];
        
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ServerCell"];
        }
        
        NSString *remove = [NSString stringWithFormat:@"%@.", serverNamePrefix];
        cell.textLabel.text = [((NSNetService *)[servers objectAtIndex:indexPath.row]).name substringFromIndex:[remove length]];
    } else if (viewMode == kViewDevices) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"DeviceCell"];
    
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DeviceCell"];
        }
    
        cell.textLabel.text = [[networkDevices objectAtIndex:indexPath.row] objectAtIndex:0];
        
        NSArray *versionComponents = [[[networkDevices objectAtIndex:indexPath.row] objectAtIndex:1] componentsSeparatedByString:@"."];
        if ([versionComponents count] > 2 && [[versionComponents objectAtIndex:0] integerValue] <= RECOMMEND_UPDATE_MAJOR && [[versionComponents objectAtIndex:1] integerValue] < RECOMMEND_UPDATE_MINOR) {
            if (defaultVersionColour == nil) {
                defaultVersionColour = cell.detailTextLabel.textColor;
            }
            cell.detailTextLabel.textColor = [UIColor redColor];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Version %@ - Update Strongly Recommended", [[networkDevices objectAtIndex:indexPath.row] objectAtIndex:1]];
        } else {
            if (defaultVersionColour != nil) {
                cell.detailTextLabel.textColor = defaultVersionColour;
            }
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Version %@", [[networkDevices objectAtIndex:indexPath.row] objectAtIndex:1]];
        }
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"DeviceCell"];
        
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DeviceCell"];
        }
        
        if (defaultVersionColour != nil) {
            cell.detailTextLabel.textColor = defaultVersionColour;
        }
        if (isFiltered) {
            cell.textLabel.text = [[filteredScores objectAtIndex:indexPath.row] objectAtIndex:0];
            cell.detailTextLabel.text = [[filteredScores objectAtIndex:indexPath.row] objectAtIndex:1];
        } else {
            cell.textLabel.text = [[availableScores objectAtIndex:indexPath.row] objectAtIndex:0];
            cell.detailTextLabel.text = [[availableScores objectAtIndex:indexPath.row] objectAtIndex:1];
        }
    }
    return cell;
}

#pragma mark - Table view delegate

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (viewMode == kViewDevices) {
        return nil;
    } else {
        return indexPath;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (viewMode == kChooseServer) {
        NSNetService *server = [servers objectAtIndex:indexPath.row];
        server.delegate = self;
        [server resolveWithTimeout:5];
    } else if (viewMode == kChooseScore) {
        [self dismissViewControllerAnimated:YES completion:nil];
        if (isFiltered) {
            [networkConnectionDelegate requestScoreLoad:[filteredScores objectAtIndex:indexPath.row]];
        } else {
            [networkConnectionDelegate requestScoreLoad:[availableScores objectAtIndex:indexPath.row]];
        }
        networkConnectionDelegate = nil;
    }
}

#pragma mark - NSNetServiceBrowser delegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreComing
{
    assert(netService != nil);
    
    //Check to see if the server is already on our list then add it
    //(This shouldn't be possible, but check just in case)
    if(![servers containsObject:netService] && [netService.name hasPrefix:[NSString stringWithFormat:@"%@.", serverNamePrefix]] && ![netService.name isEqualToString:localServerName]) {
        NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
        [servers sortUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        [servers addObject:netService];
    }
    
    if (!moreComing && (viewMode == kChooseServer)) {
        //Update our table view
        NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
        [servers sortUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        [networkTableView reloadData];
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)netService moreComing:(BOOL)moreComing
{
    assert(netService != nil);
    
    //Remove the server from our list
    if ([servers containsObject:netService]) {
        [servers removeObject:netService];
    }
    
    if (!moreComing && (viewMode == kChooseServer)) {
        //Update our table view
        [networkTableView reloadData];
    }
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
    [servers removeAllObjects];
}

#pragma mark - NSNetService delegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    [netServiceBrowser stop];
    netServiceBrowser.delegate = nil;
    [networkConnectionDelegate connectToServer:sender.hostName onPort:sender.port withTimeout:-1];
    networkConnectionDelegate = nil;
    [self performSegueWithIdentifier:@"returnToPlayer" sender:self];
    //[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITextField delegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    //Check that this is a valid hostname character.
    NSMutableCharacterSet *validCharacters = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [validCharacters addCharactersInString:@"[].-:"];
    for (int i = 0; i < [string length]; i++) {
        unichar currentCharacter = [string characterAtIndex:i];
        if (![validCharacters characterIsMember:currentCharacter]) {
            return NO;
        }
    }
    
    NSString *newString = [textField.text stringByReplacingCharactersInRange:range withString:string];
    
    //Only allow a single opening bracket at the very start of our string, and only allow
    //a single closing bracket if we have an opening bracket.
    if (![newString hasPrefix:@"["] && [newString rangeOfString:@"]"].location != NSNotFound) {
        return NO;
    }
    if ([newString rangeOfString:@"["].location != NSNotFound && [newString rangeOfString:@"["].location > 0) {
        return NO;
    }
    NSArray *separated = [newString componentsSeparatedByString:@"["];
    if ([separated count] > 2) {
        return NO;
    }
    separated = [newString componentsSeparatedByString:@"]"];
    if ([separated count] > 2) {
        return NO;
    }
    //Check that we only have one double colon. (And no triple colons.)
    separated = [newString componentsSeparatedByString:@"::"];
    if ([separated count] > 2 || [newString rangeOfString:@":::"].location != NSNotFound) {
        return NO;
    }

    return YES;
}

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
        [self filterScores:searchText];
    }
    
    [networkTableView reloadData];
}


@end

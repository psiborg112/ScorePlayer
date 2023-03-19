//
//  Canvas.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 1/11/16.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import "Canvas.h"
#import "Score.h"
#import "OSCMessage.h"

@interface Canvas ()

- (void)changePart:(NSInteger)relativeChange;
- (NSMutableArray *)findChildren:(NSString *)layer;
- (void)clearCanvas;
- (NSMutableDictionary *)getPropertyTypes;
- (NSMutableDictionary *)getCapabilities;
- (void)sendErrorMessage:(NSString *)error;
- (NSMutableArray *)getFontList;

@end

@implementation Canvas {
    Score *score;
    CALayer *canvas;
    int backgroundColour[4];
    
    NSMutableDictionary *objects;
    NSMutableDictionary *flushRequired;
    NSMutableArray *zOrder;
    NSMutableDictionary *propertyTypes;
    NSMutableDictionary *capabilities;
    NSMutableArray *fontList;
    NSLock *objectsLock;
    
    //NSString *tmpDir;
    //int currentBlobNumber;
    
    NSInteger parts;
    NSInteger currentPart;
    BOOL hasScore;
    
    NSString *scriptFile;
    BOOL clearOnReset;
    
    NSXMLParser *xmlParser;
    NSMutableString *currentString;
    BOOL isData;
    BOOL prefsLoaded;
    NSCondition *prefsCondition;
    
    BOOL hasLayers;
    //BOOL hasBlobs;
    
    __weak id<RendererUI> UIDelegate;
    __weak id<RendererMessaging> messagingDelegate;
}

+ (void)colourString:(NSString *)colourString toArray:(int *)colourArray
{
    NSArray *colour = [colourString componentsSeparatedByString:@","];
    if ([colour count] == 3 || [colour count] == 4) {
        for (int i = 0; i < 3; i++) {
            colourArray[i] = [[colour objectAtIndex:i] intValue] & 255;
        }
        if ([colour count] == 4) {
            colourArray[3] = [[colour objectAtIndex:3] intValue] & 255;
        } else {
            colourArray[3] = 255;
        }
    }
}

- (void)changePart:(NSInteger)relativeChange
{
    NSInteger newPart = currentPart + relativeChange;
    if (newPart > parts) {
        if (hasScore) {
            newPart = 0;
        } else {
            newPart = 1;
        }
    } else if (newPart <= 0 && !hasScore) {
        newPart = parts;
    } else if (newPart < 0 && hasScore) {
        newPart = parts;
    }
    
    currentPart = newPart;
    [objectsLock lock];
    for (NSString *key in objects) {
        NSInteger partNumber = ((id<CanvasObject>)[objects objectForKey:key]).partNumber;
        if (currentPart == 0 || partNumber == currentPart || partNumber == 0) {
            ((id<CanvasObject>)[objects objectForKey:key]).hidden = NO;
        } else {
            ((id<CanvasObject>)[objects objectForKey:key]).hidden = YES;
        }
    }
    [objectsLock unlock];
}

- (NSMutableArray *)findChildren:(NSString *)layer
{
    //Do not lock the objectsLock here due to recursion! Do it from the calling function.
    NSMutableArray *result = [[NSMutableArray alloc] init];
    for (NSString *key in objects) {
        if ([((id<CanvasObject>)[objects objectForKey:key]).parentLayer isEqualToString:layer]) {
            [result addObject:key];
            [result addObjectsFromArray:[self findChildren:key]];
        }
    }
    return result;
}

- (void)clearCanvas
{
    [objectsLock lock];
    [objects removeAllObjects];
    [flushRequired removeAllObjects];
    [zOrder removeAllObjects];
    [objectsLock unlock];
    canvas.sublayers = nil;
}

- (NSMutableDictionary *)getPropertyTypes
{
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    [result setObject:@"s" forKey:@"imageFile"];
    [result setObject:@"i" forKey:@"scrollerWidth"];
    [result setObject:@"i" forKey:@"scrollerPosition"];
    [result setObject:@"f" forKey:@"scrollerSpeed"];
    [result setObject:@"s" forKey:@"text"];
    [result setObject:@"s" forKey:@"font"];
    [result setObject:@"f" forKey:@"fontSize"];
    [result setObject:@"s" forKey:@"glyphType"];
    [result setObject:@"f" forKey:@"glyphSize"];
    [result setObject:@"i" forKey:@"lineWidth"];
    [result setObject:@"s" forKey:@"clefCollection"];
    [result setObject:@"s" forKey:@"noteCollection"];
    [result setObject:@"i" forKey:@"width"];
    [result setObject:@"s" forKey:@"points"];
    return result;
}

- (NSMutableDictionary *)getCapabilities
{
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    
    //Establish some common capabilities and then set capabilities for individual object types.
    NSArray *all = [NSArray arrayWithObject:@"setColour"];
    NSArray *nonLine = [NSArray arrayWithObjects:@"addLayer", @"addScroller", @"addText", @"addGlyph", @"addStave", @"addLine", nil];
    NSArray *nonCanvas = [NSArray arrayWithObjects:@"remove", @"setOpacity", @"fade", nil];
    NSArray *nonLineOrCanvas = [NSArray arrayWithObjects:@"setPosition", @"move", nil];
    
    NSMutableArray *canvas = [[NSMutableArray alloc] initWithObjects:@"clear", nil];
    [canvas addObjectsFromArray:all];
    [canvas addObjectsFromArray:nonLine];
    NSMutableArray *line = [[NSMutableArray alloc] initWithObjects:@"setWidth", @"setStartPoint", @"setEndPoint", nil];
    [line addObjectsFromArray:all];
    [line addObjectsFromArray:nonCanvas];
    
    NSMutableArray *base = [[NSMutableArray alloc] init];
    [base addObjectsFromArray:all];
    [base addObjectsFromArray:nonLine];
    [base addObjectsFromArray:nonCanvas];
    [base addObjectsFromArray:nonLineOrCanvas];
    
    NSMutableArray *layer = [[NSMutableArray alloc] initWithObjects:@"loadImage", @"clearImage", @"setSize", nil];
    [layer addObjectsFromArray:base];
    
    NSMutableArray *scroller = [[NSMutableArray alloc] initWithObjects:@"setScrollerWidth", @"setScrollerPosition", @"setScrollerSpeed", @"start", @"stop", nil];
    [scroller addObjectsFromArray:layer];
    
    NSMutableArray *text = [[NSMutableArray alloc] initWithObjects:@"setText", @"setFont", @"setFontSize", nil];
    [text addObjectsFromArray:base];
    
    NSMutableArray *glyph = [[NSMutableArray alloc] initWithObjects:@"setGlyph", @"setGlyphSize", nil];
    [glyph addObjectsFromArray:base];
    
    NSMutableArray *stave = [[NSMutableArray alloc] initWithObjects:@"setSize", @"setLineWidth", @"setClef", @"removeClef", @"addNotehead", @"addNote", @"removeNote", @"clear", nil];
    [stave addObjectsFromArray:base];
    
    [result setObject:canvas forKey:@"canvas"];
    [result setObject:line forKey:@"CanvasLine"];
    [result setObject:layer forKey:@"CanvasLayer"];
    [result setObject:scroller forKey:@"CanvasScroller"];
    [result setObject:text forKey:@"CanvasText"];
    [result setObject:glyph forKey:@"CanvasGlyph"];
    [result setObject:stave forKey:@"CanvasStave"];
    return result;
}

- (void)sendErrorMessage:(NSString *)error
{
    //Only send this if we are the master to avoid duplicate messages.
    if (!isMaster) {
        return;
    }
    OSCMessage *errorMessage = [[OSCMessage alloc] init];
    [errorMessage appendAddressComponent:@"External"];
    [errorMessage appendAddressComponent:@"Error"];
    [errorMessage addStringArgument:error];
    [messagingDelegate sendData:errorMessage];
}

- (NSMutableArray *)getFontList
{
    NSMutableArray *fonts = [[NSMutableArray alloc] init];
    NSArray *families = [UIFont familyNames];
    for (int i = 0; i < [families count]; i++) {
        [fonts addObjectsFromArray:[UIFont fontNamesForFamilyName:[families objectAtIndex:i]]];
    }
    return fonts;
}

#pragma mark - Renderer delegate

- (void)setIsMaster:(BOOL)master
{
    isMaster = master;
    
    if (!isMaster) {
        hasLayers = NO;
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"LayersRequest"];
        [messagingDelegate sendData:message];
    }
}

- (BOOL)isMaster
{
    return isMaster;
}

+ (RendererFeatures)getRendererRequirements
{
    return kUsesScaledCanvas;
}

- (id)initRendererWithScore:(Score *)scoreData canvas:(CALayer *)playerCanvas UIDelegate:(__weak id<RendererUI>)UIDel messagingDelegate:(__weak id<RendererMessaging>)messagingDel
{
    self = [super init];
    
    score = scoreData;
    canvas = playerCanvas;
    UIDelegate = UIDel;
    messagingDelegate = messagingDel;
    
    objects = [[NSMutableDictionary alloc] init];
    flushRequired = [[NSMutableDictionary alloc] init];
    zOrder = [[NSMutableArray alloc] init];
    objectsLock = [[NSLock alloc] init];
    
    propertyTypes = [self getPropertyTypes];
    capabilities = [self getCapabilities];
    fontList = [self getFontList];
    
    //If our duration isn't positive set the player to display a static score interface.
    if (UIDelegate.clockDuration <= 0) {
        [UIDelegate setStaticScoreUI];
    } else {
        //Otherwise, for the moment disable clock changes or the slider display.
        UIDelegate.clockVisible = NO;
        UIDelegate.allowClockChange = NO;
    }
    
    //tmpDir = NSTemporaryDirectory();
    //currentBlobNumber = 0;
    
    currentPart = 1;
    hasLayers = YES;
    //hasBlobs = YES;
    parts = 1;
    hasScore = NO;
    clearOnReset = YES;
    prefsCondition = [NSCondition new];
    
    for (int i = 0; i < 4; i++) {
        backgroundColour[i] = 0;
    }
    
    //Check if we have a preferences file and load preferences if needed.
    if (score.prefsFile != nil) {
        NSString *prefsFile = [score.scorePath stringByAppendingPathComponent:score.prefsFile];
        NSData *prefsData = [[NSData alloc] initWithContentsOfFile:prefsFile];
        xmlParser = [[NSXMLParser alloc] initWithData:prefsData];
        
        isData = NO;
        prefsLoaded = NO;
        xmlParser.delegate = self;
        [xmlParser parse];
    } else {
        prefsLoaded = YES;
    }
    
    return self;
}

- (void)reset
{
    [prefsCondition lock];
    while (!prefsLoaded) {
        [prefsCondition wait];
    }
    [prefsCondition unlock];
    
    //Clear all the layers if needed.
    if (clearOnReset) {
        [self clearCanvas];
    }
}

- (void)receiveMessage:(OSCMessage *)message
{
    if ([message.address count] < 1) {
        return;
    }
    
    if (isMaster && [[message.address objectAtIndex:0] isEqualToString:@"LayersRequest"]) {
        OSCMessage *message = [[OSCMessage alloc] init];
        [message appendAddressComponent:@"LayersData"];
        [message addIntegerArgument:[zOrder count]];
        [message addStringArgument:[NSString stringWithFormat:@"%i,%i,%i,%i", backgroundColour[0], backgroundColour[1], backgroundColour[2], backgroundColour[3]]];
        
        [objectsLock lock];
        for (int i = 0; i < [zOrder count]; i++) {
            id<CanvasObject> currentObject = (id<CanvasObject>)[objects objectForKey:[zOrder objectAtIndex:i]];
            NSString *objectType = NSStringFromClass([currentObject class]);
            //Add common arguments.
            //Name, object type, parent layer, part number, position x, position y, width, height, opacity.
            [message addStringArgument:[zOrder objectAtIndex:i]];
            [message addStringArgument:objectType];
            [message addStringArgument:currentObject.parentLayer];
            [message addIntegerArgument:currentObject.partNumber];
            int x = currentObject.position.x;
            int y = currentObject.position.y;
            int width = currentObject.size.width;
            int height = currentObject.size.height;
            [message addIntegerArgument:x];
            [message addIntegerArgument:y];
            [message addIntegerArgument:width];
            [message addIntegerArgument:height];
            [message addStringArgument:currentObject.colour];
            [message addFloatArgument:currentObject.opacity];
            
            //Add an argument that shows our sent layer properties. This will allow flexibility in the future.
            //(If no additional properties exist, this should remain set to "none")
            [message addStringArgument:@"none"];
            
            NSMutableString *tags = [[NSMutableString alloc] init];
            NSMutableString *properties = [[NSMutableString alloc] init];
            if ([objectType isEqualToString:@"CanvasLayer"] || [objectType isEqualToString:@"CanvasScroller"]) {
                if (currentObject.imageFile != nil) {
                    [tags appendString:@"s"];
                    [properties appendString:@",imageFile"];
                    [message addStringArgument:[currentObject.imageFile lastPathComponent]];
                }
            }
            
            if ([objectType isEqualToString:@"CanvasScroller"]) {
                [tags appendString:@"iifi"];
                [properties appendString:@",scrollerWidth,scrollerPosition,scrollerSpeed,isRunning"];
                [message addIntegerArgument:currentObject.scrollerWidth];
                [message addIntegerArgument:currentObject.scrollerPosition];
                [message addFloatArgument:currentObject.scrollerSpeed];
                if (currentObject.isRunning) {
                    [message addIntegerArgument:1];
                } else {
                    [message addIntegerArgument:0];
                }
            } else if ([objectType isEqualToString:@"CanvasText"]) {
                if (currentObject.text != nil) {
                    [tags appendString:@"s"];
                    [properties appendString:@",text"];
                    [message addStringArgument:currentObject.text];
                }
                if (currentObject.font != nil) {
                    [tags appendString:@"s"];
                    [properties appendString:@",font"];
                    [message addStringArgument:currentObject.font];
                }
                [tags appendString:@"f"];
                [properties appendString:@",fontSize"];
                [message addFloatArgument:currentObject.fontSize];
            } else if ([objectType isEqualToString:@"CanvasGlyph"]) {
                if (currentObject.glyphType != nil) {
                    [tags appendString:@"s"];
                    [properties appendString:@",glyphType"];
                    [message addStringArgument:currentObject.glyphType];
                }
                [tags appendString:@"f"];
                [properties appendString:@",fontSize"];
                [message addFloatArgument:currentObject.fontSize];
            } else if ([objectType isEqualToString:@"CanvasStave"]) {
                [tags appendString:@"iss"];
                [properties appendString:@",lineWidth,clefCollection,noteCollection"];
                [message addIntegerArgument:currentObject.lineWidth];
                [message addStringArgument:currentObject.clefCollection];
                [message addStringArgument:currentObject.noteCollection];
            } else if ([objectType isEqualToString:@"CanvasLine"]) {
                [tags appendString:@"is"];
                [properties appendString:@",width,points"];
                [message addIntegerArgument:currentObject.width];
                [message addStringArgument:currentObject.points];
            }
            
            if (tags.length > 0) {
                //If we have properties, replace the necessary argument.
                [message replaceArgumentAtIndex:([message.arguments count] - 1 - tags.length) withString:[NSString stringWithFormat:@"%@%@", tags, properties]];
            }
        }
        
        [objectsLock unlock];
        [messagingDelegate sendData:message];
        
        //Also send out any blobs. (This is done separately so that the loading of the current score state
        //is not unnecessarily delayed.)
        /*if (currentBlobNumber > 0) {
            OSCMessage *blobs = [[OSCMessage alloc] init];
            [blobs appendAddressComponent:@"BlobData"];
            for (int i = 0; i < currentBlobNumber; i++) {
                [blobs addBlobArgument:[NSData dataWithContentsOfFile:[tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%i", i]]]];
            }
            [messagingDelegate sendData:blobs];
        }*/
    } else if (!hasLayers && [[message.address objectAtIndex:0] isEqualToString:@"LayersData"]) {
        //First clear any existing layers.
        [self clearCanvas];
        
        //Check that we a count of the number of layers we're expecting and the background canvas colour.
        if (![message.typeTag hasPrefix:@",is"]) {
            return;
        }
        
        int currentTagPosition = CANVAS_GLOBAL_COUNT + 1;
        //int layerCount = [[message.arguments objectAtIndex:0] intValue];
        //currentBlobNumber = [[message.arguments objectAtIndex:1] intValue];
        
        /*if (currentBlobNumber > 0) {
            hasBlobs = NO;
        }*/
        
        //And check that our data is of the right format.
        NSString *basicLayerTags = @"sssiiiiisfs";
        while (currentTagPosition < message.typeTag.length) {
            //First check that the basic tags match what we're expecting.
            if ((message.typeTag.length - basicLayerTags.length >= currentTagPosition) && ([[message.typeTag substringWithRange:NSMakeRange(currentTagPosition, basicLayerTags.length)] isEqualToString:basicLayerTags])) {
                //Then check the additional tags.
                currentTagPosition += basicLayerTags.length;
                NSArray *additionalProperties = [[message.arguments objectAtIndex:(currentTagPosition - 2)] componentsSeparatedByString:@","];
                if (![[additionalProperties objectAtIndex:0] isEqualToString:@"none"]) {
                    if ((message.typeTag.length - [[additionalProperties objectAtIndex:0] length] >= currentTagPosition) && ([[message.typeTag substringWithRange:NSMakeRange(currentTagPosition, [[additionalProperties objectAtIndex:0] length])] isEqualToString:[additionalProperties objectAtIndex:0]])) {
                        currentTagPosition += [[additionalProperties objectAtIndex:0] length];
                    } else {
                        //If the lengths differ, then discard the message.
                        return;
                    }
                }
            } else {
                return;
            }
        }
        
        //Set the background colour.
        [Canvas colourString:[message.arguments objectAtIndex:1] toArray:backgroundColour];
        canvas.backgroundColor = [UIColor colorWithRed:(backgroundColour[0] / 255.0) green:(backgroundColour[1] / 255.0) blue:(backgroundColour[2] / 255.0) alpha:(backgroundColour[3] / 255.0)].CGColor;
        
        //Set up our layers.
        [objectsLock lock];
        int argumentOffset = CANVAS_GLOBAL_COUNT;
        while (argumentOffset < [message.arguments count]) {
            int partNumber = [[message.arguments objectAtIndex:argumentOffset + CANVAS_PART_OFFSET] intValue];
            NSArray *additionalProperties = [[message.arguments objectAtIndex:argumentOffset + CANVAS_PROPERTIES_OFFSET] componentsSeparatedByString:@","];
            Class objectClass = NSClassFromString([message.arguments objectAtIndex:argumentOffset + CANVAS_TYPE_OFFSET]);
            if (objectClass != nil && [objectClass conformsToProtocol:@protocol(CanvasObject)])  {
                id<CanvasObject> object = [[objectClass alloc] initWithScorePath:score.scorePath];
                object.position = CGPointMake([[message.arguments objectAtIndex:argumentOffset + CANVAS_X_OFFSET] intValue], [[message.arguments objectAtIndex:argumentOffset + CANVAS_Y_OFFSET] intValue]);
                object.size = CGSizeMake([[message.arguments objectAtIndex:argumentOffset + CANVAS_WIDTH_OFFSET] intValue], [[message.arguments objectAtIndex:argumentOffset + CANVAS_HEIGHT_OFFSET] intValue]);
                object.partNumber = partNumber;
                object.colour = [message.arguments objectAtIndex:argumentOffset + CANVAS_COLOUR_OFFSET];
                object.opacity = [[message.arguments objectAtIndex:argumentOffset + CANVAS_OPACITY_OFFSET] floatValue];
                
                //Check that our parent layer exists. (And check the special case of the object being the canvas.)
                if ([[message.arguments objectAtIndex:argumentOffset + CANVAS_PARENT_OFFSET] isEqualToString:@"canvas"] || ([objects objectForKey:[message.arguments objectAtIndex:argumentOffset + CANVAS_PARENT_OFFSET]] != nil)) {
                    if ([[message.arguments objectAtIndex:argumentOffset + CANVAS_PARENT_OFFSET] isEqualToString:@"canvas"]) {
                        [canvas addSublayer:object.containerLayer];
                    } else {
                        [((id<CanvasObject>)[objects objectForKey:[message.arguments objectAtIndex:argumentOffset + CANVAS_PARENT_OFFSET]]).objectLayer addSublayer:object.containerLayer];
                    }
                    object.parentLayer = [message.arguments objectAtIndex:argumentOffset + CANVAS_PARENT_OFFSET];
                    [objects setObject:object forKey:[message.arguments objectAtIndex:argumentOffset]];
                    [zOrder addObject:[message.arguments objectAtIndex:argumentOffset + CANVAS_NAME_OFFSET]];
                    
                    //Now deal with specific layer type specific options.
                    if ([additionalProperties count] == [[additionalProperties objectAtIndex:0] length] + 1) {
                        BOOL startObject = NO;
                        for (int i = 1; i < [additionalProperties count]; i++) {
                            //We need to create a special case for the isRunning property. This should be used to start or stop
                            //an object's built in animations.
                            if ([[additionalProperties objectAtIndex:i] isEqualToString:@"isRunning"]) {
                                if ([[[additionalProperties objectAtIndex:0] substringWithRange:NSMakeRange(i - 1, 1)] isEqualToString:@"i"] && [[message.arguments objectAtIndex:argumentOffset + CANVAS_PROPERTIES_OFFSET + i] intValue] != 0) {
                                    startObject = YES;
                                }
                            } else {
                                NSString *setterString = [NSString stringWithFormat:@"set%@%@:", [[[additionalProperties objectAtIndex:i] substringToIndex:1] capitalizedString], [[additionalProperties objectAtIndex:i] substringFromIndex:1]];
                                //Check that our layer actually responds to the property being set, and that we have
                                //the correct argument type.
                                if ([object respondsToSelector:NSSelectorFromString(setterString)] && [[propertyTypes objectForKey:[additionalProperties objectAtIndex:i]] isEqualToString:[[additionalProperties objectAtIndex:0] substringWithRange:NSMakeRange(i - 1, 1)]]) {
                                    [(id)object setValue:[message.arguments objectAtIndex:argumentOffset + CANVAS_PROPERTIES_OFFSET + i] forKey:[additionalProperties objectAtIndex:i]];
                                }
                            }
                        }
                        if (startObject && [object respondsToSelector:@selector(start)]) {
                            [object start];
                        }
                    }
                }
                if (![[additionalProperties objectAtIndex:0] isEqualToString:@"none"]) {
                    argumentOffset += [[additionalProperties objectAtIndex:0] length];
                }
                argumentOffset += basicLayerTags.length;
            }
        }
        
        [objectsLock unlock];
        [self changePart:0];
    /*} else if (!hasBlobs && [[message.address objectAtIndex:0] isEqualToString:@"BlobData"]) {
        NSString *typeTag = [message.typeTag substringFromIndex:1];
        NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"b"] invertedSet];
        if ([typeTag rangeOfCharacterFromSet:invalidTags].location != NSNotFound) {
            return;
        }
        
        for (int i = 0; i < [message.arguments count]; i++) {
            [[message.arguments objectAtIndex:i] writeToFile:[tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%i", i]] atomically:YES];
        }
        
        //Load blobs into any existing layers that reference them.
        NSArray *keys = [imageFiles allKeys];
        for (int i = 0; i < [keys count]; i++) {
            if ([[imageFiles objectForKey:[keys objectAtIndex:i]] hasPrefix:tmpDir]) {
                [self loadImageFile:[imageFiles objectForKey:[keys objectAtIndex:i]] forLayer:[keys objectAtIndex:i] autoSizing:NO];
            }
        }*/
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"Command"] && [message.address count] > 2) {
        //We have a command to execute on one of our objects.
        
        //First get our object type.
        NSString *objectType;
        if ([[message.address objectAtIndex:1] isEqualToString:@"canvas"]) {
            objectType = @"canvas";
        } else if ([objects objectForKey:[message.address objectAtIndex:1]] != nil) {
            objectType = NSStringFromClass([[objects objectForKey:[message.address objectAtIndex:1]] class]);
        } else {
            [self sendErrorMessage:@"The specified object does not exist."];
            return;
        }
        
        //Then check if the command applies to our given object.
        if ([[capabilities objectForKey:objectType] indexOfObject:[message.address objectAtIndex:2]] == NSNotFound) {
            [self sendErrorMessage:@"The given command is not valid for this object."];
        }

        if (([[message.address objectAtIndex:2] isEqualToString:@"addLayer"] || [[message.address objectAtIndex:2] isEqualToString:@"addScroller"] || [[message.address objectAtIndex:2] isEqualToString:@"addText"] || [[message.address objectAtIndex:2] isEqualToString:@"addGlyph"] || [[message.address objectAtIndex:2] isEqualToString:@"addStave"] || [[message.address objectAtIndex:2] isEqualToString:@"addLine"]) && [message.typeTag hasPrefix:@",si"]) {
            //We have an object to add. Check that we have at least a name and part number so that we can run the common object creation code.
            CALayer *parentLayer;
            NSInteger parentPartNumber;
            if ([[message.address objectAtIndex:1] isEqualToString:@"canvas"]) {
                parentLayer = canvas;
                parentPartNumber = 0;
            } else {
                parentLayer = ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).objectLayer;
                parentPartNumber = ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).partNumber;
            }
            
            if ([objects objectForKey:[message.arguments objectAtIndex:0]] != nil || [[message.arguments objectAtIndex:0] isEqualToString:@"canvas"]) {
                //If an object already exists with the same name we shouldn't recreate it.
                //We definitely shouldn't create an object called canvas!
                if ([[message.arguments objectAtIndex:0] isEqualToString:@"canvas"]) {
                    [self sendErrorMessage:@"The name 'canvas' is reserved."];
                } else {
                    [self sendErrorMessage:@"An object of that name already exists."];
                }
                return;
            }
            
            //Check if our part number is valid to begin with.
            NSInteger partNumber = [[message.arguments objectAtIndex:1] integerValue];
            if (partNumber > parts || partNumber < 0) {
                [self sendErrorMessage:@"The specified part number does not exist"];
                return;
            }
            //Also, if our parent layer belongs to a specific part, force our sublayer to belong there too.
            if (parentPartNumber != 0) {
                partNumber = parentPartNumber;
            }
            
            //Object specific logic.
            id<CanvasObject> object;
            if ([[message.address objectAtIndex:2] isEqualToString:@"addLayer"]) {
                //Add a new image layer. Arguments: name, part number, x, y, width, height.
                //(If the part number is 0 then the layer appears in all parts.)
                if (![message.typeTag isEqualToString:@",siiiii"]) {
                    [self sendErrorMessage:@"Expected Arguments: name(s) part(i) x(i) y(i) width(i) height(i)"];
                    return;
                }
                object = [[NSClassFromString(@"CanvasLayer") alloc] initWithScorePath:score.scorePath];
                object.position = CGPointMake([[message.arguments objectAtIndex:2] intValue], [[message.arguments objectAtIndex:3] intValue]);
                object.size = CGSizeMake([[message.arguments objectAtIndex:4] intValue], [[message.arguments objectAtIndex:5] intValue]);
                
            } else if ([[message.address objectAtIndex:2] isEqualToString:@"addScroller"]) {
                //Add a new scroller layer. Arguments: name, part number, x, y, width, height, scrollerWidth, scrollerSpeed.
                if (![message.typeTag isEqualToString:@",siiiiiif"]) {
                    [self sendErrorMessage:@"Expected Arguments: name(s) part(i) x(i) y(i) width(i) height(i) scrollerWidth(i) scrollerSpeed(f)"];
                    return;
                }
                
                object = [[NSClassFromString(@"CanvasScroller") alloc] initWithScorePath:score.scorePath];
                object.position = CGPointMake([[message.arguments objectAtIndex:2] intValue], [[message.arguments objectAtIndex:3] intValue]);
                object.size = CGSizeMake([[message.arguments objectAtIndex:4] intValue], [[message.arguments objectAtIndex:5] intValue]);
                object.scrollerWidth = [[message.arguments objectAtIndex:6] intValue];
                object.scrollerSpeed = [[message.arguments objectAtIndex:7] floatValue];
                
            } else if ([[message.address objectAtIndex:2] isEqualToString:@"addText"] || [[message.address objectAtIndex:2] isEqualToString:@"addGlyph"]) {
                //Add a new text or glyph layer. Argumets: name, part number, x, y, width, height.
                NSString *type = [[message.address objectAtIndex:2] substringFromIndex:3];
                if (!([message.typeTag isEqualToString:@",siii"] || [message.typeTag isEqualToString:@",siiif"])) {
                    if ([type isEqualToString:@"Text"]) {
                        [self sendErrorMessage:@"Expected Arguments: name(s) part(i) x(i) y(i) (fontSize(f))"];
                    } else {
                        [self sendErrorMessage:@"Expected Arguments: name(s) part(i) x(i) y(i) (glyphSize(f))"];
                    }
                    return;
                }
                
                object = [[NSClassFromString([NSString stringWithFormat:@"Canvas%@", type]) alloc] initWithScorePath:score.scorePath];
                object.position = CGPointMake([[message.arguments objectAtIndex:2] intValue], [[message.arguments objectAtIndex:3] intValue]);
                if ([message.typeTag isEqualToString:@",siiif"]) {
                    object.fontSize = [[message.arguments objectAtIndex:4] floatValue];
                }
            
            } else if ([[message.address objectAtIndex:2] isEqualToString:@"addStave"]) {
                if (![message.typeTag isEqualToString:@",siiiiii"]) {
                    [self sendErrorMessage:@"Expected Arguments: name(s) part(i) x(i) y(i) width(i) height(i) lineWidth(i)"];
                }
                
                object = [[NSClassFromString(@"CanvasStave") alloc] initWithScorePath:score.scorePath];
                object.position = CGPointMake([[message.arguments objectAtIndex:2] intValue], [[message.arguments objectAtIndex:3] intValue]);
                object.size = CGSizeMake([[message.arguments objectAtIndex:4] intValue], [[message.arguments objectAtIndex:5] intValue]);
                object.lineWidth = [[message.arguments objectAtIndex:6] intValue];
            } else if ([[message.address objectAtIndex:2] isEqualToString:@"addLine"]) {
                if (![message.typeTag isEqualToString:@",siiiiii"]) {
                    [self sendErrorMessage:@"Expected Arguments: name(s) part(i) x1(i) y1(i) x2(i) y2(i) lineWidth(i)"];
                }
                object = [[NSClassFromString(@"CanvasLine") alloc] initWithScorePath:score.scorePath];
                object.width = [[message.arguments objectAtIndex:6] intValue];
                object.startPoint = CGPointMake([[message.arguments objectAtIndex:2] intValue], [[message.arguments objectAtIndex:3] intValue]);
                object.endPoint = CGPointMake([[message.arguments objectAtIndex:4] intValue], [[message.arguments objectAtIndex:5] intValue]);
            }
            
            //Finally add our object to the necessary collections, its parent layer, and make sure it appears in the right part.
            if (object != nil) {
                [objectsLock lock];
                object.partNumber = partNumber;
                object.parentLayer = [message.address objectAtIndex:1];
                [objects setObject:object forKey:[message.arguments objectAtIndex:0]];
                [zOrder addObject:[message.arguments objectAtIndex:0]];
                
                if (!(currentPart == 0 || partNumber == 0 || partNumber == currentPart)) {
                    object.hidden = YES;
                }
                
                //None of the layers being added are initialized with content already in them.
                //Disable any animations so that they don't interfere with already running ones.
                [flushRequired setObject:[NSNumber numberWithBool:YES] forKey:[message.arguments objectAtIndex:0]];
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                [parentLayer addSublayer:object.containerLayer];
                [CATransaction commit];
                [objectsLock unlock];
            }
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"remove"]) {
            //Removes our layer. First check if the referenced layer exists.
            if ([objects objectForKey:[message.address objectAtIndex:1]] != nil) {
                [objectsLock lock];
                //If it responds to the stop command then we should run that first.
                if ([[objects objectForKey:[message.address objectAtIndex:1]] respondsToSelector:@selector(stop)]) {
                    [(id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]] stop];
                }
                
                //Then remove it from the canvas and all references to it.
                [((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).containerLayer removeFromSuperlayer];
                [objects removeObjectForKey:[message.address objectAtIndex:1]];
                [zOrder removeObject:[message.address objectAtIndex:1]];
                [objectsLock unlock];
            } else {
                [self sendErrorMessage:@"The specified object does not exist."];
                return;
            }
        
            //Then remove any children.
            [objectsLock lock];
            NSMutableArray *children = [self findChildren:[message.address objectAtIndex:1]];
            for (int i = 0; i < [children count]; i++) {
                [objects removeObjectForKey:[children objectAtIndex:i]];
                [zOrder removeObject:[children objectAtIndex:i]];
            }
            [objectsLock unlock];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setColour"]) {
            //Sets the colour of the given layer.
            if (!([message.typeTag isEqualToString:@",iiii"] || [message.typeTag isEqualToString:@",iii"])) {
                [self sendErrorMessage:@"Expected Arguments: r(i) b(i) g(i) (a(i))"];
                return;
            }
            NSMutableString *colourString = [NSMutableString stringWithFormat:@"%i", [[message.arguments objectAtIndex:0] intValue]];
            for (int i = 1; i < [message.arguments count]; i++) {
                [colourString appendFormat:@",%i", [[message.arguments objectAtIndex:i] intValue]];
            }
            if ([[message.address objectAtIndex:1] isEqualToString:@"canvas"]) {
                [Canvas colourString:[NSString stringWithString:colourString] toArray:backgroundColour];
                UIColor *colour = [UIColor colorWithRed:(backgroundColour[0] / 255.0) green:(backgroundColour[1] / 255.0) blue:(backgroundColour[2] / 255.0) alpha:(backgroundColour[3] / 255.0)];
                canvas.backgroundColor = colour.CGColor;
                [UIDelegate setMarginColour:colour];
            } else if ([objects objectForKey:[message.address objectAtIndex:1]] != nil) {
                ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).colour = [NSString stringWithString:colourString];
            } else {
                [self sendErrorMessage:@"The specified object does not exist."];
                return;
            }
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"clear"]) {
            if ([objectType isEqualToString:@"canvas"]) {
                [self clearCanvas];
            } else {
                [[objects objectForKey:[message.address objectAtIndex:1]] clear];
            }
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setPosition"]) {
            if (![message.typeTag isEqualToString:@",ii"]) {
                [self sendErrorMessage:@"Expected Arguments: x(i) y(i)"];
                return;
            }
            //Sets the position of the given layer.
            [flushRequired setObject:[NSNumber numberWithBool:YES] forKey:[message.address objectAtIndex:1]];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).position = CGPointMake([[message.arguments objectAtIndex:0] intValue], [[message.arguments objectAtIndex:1] intValue]);
            [CATransaction commit];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setOpacity"]) {
            //Sets the opacity of the given layer.
            if (![message.typeTag isEqualToString:@",f"]) {
                [self sendErrorMessage:@"Expected Arguments: opacity(f)"];
                return;
            }
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).opacity = [[message.arguments objectAtIndex:0] floatValue];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"move"]) {
            //Moves the given layer to a new position over a specified amount of time.
            if (![message.typeTag isEqualToString:@",iif"]) {
                [self sendErrorMessage:@"Expected Arguments: x(i) y(i) duration(f)"];
                return;
            }
            if ([[flushRequired objectForKey:[message.address objectAtIndex:1]] boolValue] == YES) {
                [CATransaction flush];
                [flushRequired setObject:[NSNumber numberWithBool:NO] forKey:[message.address objectAtIndex:1]];
            }
            [CATransaction begin];
            [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
            [CATransaction setAnimationDuration:[[message.arguments objectAtIndex:2] floatValue]];
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).position = CGPointMake([[message.arguments objectAtIndex:0] intValue], [[message.arguments objectAtIndex:1] intValue]);
            [CATransaction commit];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"fade"]) {
            if (![message.typeTag isEqualToString:@",ff"]) {
                [self sendErrorMessage:@"Expected Arguments: opacity(f) duration(f)"];
                return;
            }
            if ([[flushRequired objectForKey:[message.address objectAtIndex:1]] boolValue] == YES) {
                [CATransaction flush];
                [flushRequired setObject:[NSNumber numberWithBool:NO] forKey:[message.address objectAtIndex:1]];
            }
            [CATransaction begin];
            [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
            [CATransaction setAnimationDuration:[[message.arguments objectAtIndex:1] floatValue]];
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).opacity = [[message.arguments objectAtIndex:0] floatValue];
            [CATransaction commit];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"loadImage"]) {
            //Loads an image into the given layer, with the option to automatically adjust the size.
            //If the size is adjusted then animations are disabled.
            if (!([message.typeTag isEqualToString:@",si"] || [message.typeTag isEqualToString:@",s"])) {
                [self sendErrorMessage:@"Expected Arguments: imageFile(s) (autosize(i))"];
                return;
            }
        
            NSString *imageFile = [message.arguments objectAtIndex:0];
            BOOL autosize = NO;
            if ([message.typeTag isEqualToString:@",si"] && [[message.arguments objectAtIndex:1] intValue] != 0) {
                autosize = YES;
            }
            [[objects objectForKey:[message.address objectAtIndex:1]] loadImage:imageFile autoSizing:autosize];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"clearImage"]) {
            //Clear the displayed image.
            [[objects objectForKey:[message.address objectAtIndex:1]] clearImage];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setSize"]) {
            if (![message.typeTag isEqualToString:@",ii"]) {
                [self sendErrorMessage:@"Expected Arguments: width(i) height(i)"];
                return;
            }
            //Sets the size of the given layer.
            [flushRequired setObject:[NSNumber numberWithBool:YES] forKey:[message.address objectAtIndex:1]];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).size = CGSizeMake([[message.arguments objectAtIndex:0] intValue], [[message.arguments objectAtIndex:1] intValue]);
            [CATransaction commit];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setScrollerWidth"]) {
            if (![message.typeTag isEqualToString:@",i"]) {
                [self sendErrorMessage:@"Expected Arguments: scrollerWidth(i)"];
                return;
            }
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).scrollerWidth = [[message.arguments objectAtIndex:0] integerValue];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setScrollerPosition"]) {
            if (![message.typeTag isEqualToString:@",i"]) {
                [self sendErrorMessage:@"Expected Arguments: scrollerPosition(i)"];
                return;
            }
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).scrollerPosition = [[message.arguments objectAtIndex:0] integerValue];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setScrollerSpeed"]) {
            if (![message.typeTag isEqualToString:@",f"]) {
                [self sendErrorMessage:@"Expected Arguments: scrollerSpeed(f)"];
                return;
            }
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).scrollerSpeed = [[message.arguments objectAtIndex:0] floatValue];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"start"]) {
            [(id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]] start];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"stop"]) {
            [(id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]] stop];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setText"]) {
            if (![message.typeTag isEqualToString:@",s"]) {
                [self sendErrorMessage:@"Expected Arguments: text(s)"];
                return;
            }
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).text = [message.arguments objectAtIndex:0];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setFont"]) {
            if (![message.typeTag isEqualToString:@",s"]) {
                [self sendErrorMessage:@"Expected Arguments: fontName(s)"];
                return;
            }
            if ([fontList indexOfObject:[message.arguments objectAtIndex:0]] == NSNotFound) {
                [self sendErrorMessage:@"Font not found."];
                return;
            }
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).font = [message.arguments objectAtIndex:0];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setFontSize"]) {
            if (![message.typeTag isEqualToString:@",f"]) {
                [self sendErrorMessage:@"Expected Arguments: fontSize(f)"];
                return;
            }
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).fontSize = [[message.arguments objectAtIndex:0] floatValue];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setGlyph"]) {
            if (![message.typeTag isEqualToString:@",s"]) {
                [self sendErrorMessage:@"Expected Arguments: glyphType(s)"];
                return;
            }
            BOOL result = [[objects objectForKey:[message.address objectAtIndex:1]] setGlyph:[message.arguments objectAtIndex:0]];
            if (!result) {
                [self sendErrorMessage:@"Unknown glyph type"];
            }
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setGlyphSize"]) {
            if (![message.typeTag isEqualToString:@",f"]) {
                [self sendErrorMessage:@"Expected Arguments: glyphSize(f)"];
                return;
            }
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).fontSize = [[message.arguments objectAtIndex:0] floatValue];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setLineWidth"]) {
            if (![message.typeTag isEqualToString:@",i"]) {
                [self sendErrorMessage:@"Expected Arguments: lineWidth(i)"];
                return;
            }
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).lineWidth = [[message.arguments objectAtIndex:0] intValue];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setClef"]) {
            if (![message.typeTag isEqualToString:@",si"]) {
                [self sendErrorMessage:@"Expected Arguments: clef(s) position(i)"];
                return;
            }
            NSString *result = [[objects objectForKey:[message.address objectAtIndex:1]] setClef:[message.arguments objectAtIndex:0] atPosition:[[message.arguments objectAtIndex:1] intValue]];
            if (result != nil) {
                [self sendErrorMessage:result];
            }
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"removeClef"]) {
            if (![message.typeTag isEqualToString:@",i"]) {
                [self sendErrorMessage:@"Expected Arguments: position(i)"];
                return;
            }
            NSString *result = [[objects objectForKey:[message.address objectAtIndex:1]] removeClefAtPosition:[[message.arguments objectAtIndex:0] intValue]];
            if (result != nil) {
                [self sendErrorMessage:result];
            }
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"addNote"]) {
            if (![message.typeTag isEqualToString:@",sii"]) {
                [self sendErrorMessage:@"Expected Arguments: pitch(s) position(i) duration(i)"];
                return;
            }
            NSString *result = [[objects objectForKey:[message.address objectAtIndex:1]] addNote:[message.arguments objectAtIndex:0] atPosition:[[message.arguments objectAtIndex:1] intValue] ofDuration:[[message.arguments objectAtIndex:2] intValue]];
            if (result != nil) {
                [self sendErrorMessage:result];
            }
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"addNotehead"]) {
            if (!([message.typeTag isEqualToString:@",sii"] || [message.typeTag isEqualToString:@",si"])) {
                [self sendErrorMessage:@"Expected Arguments: pitch(s) position(i) (filled(i))"];
                return;
            }
            BOOL filled = YES;
            if ([message.typeTag isEqualToString:@",sii"]) {
                filled = [[message.arguments objectAtIndex:2] boolValue];
            }
            NSString *result = [[objects objectForKey:[message.address objectAtIndex:1]] addNotehead:[message.arguments objectAtIndex:0] atPosition:[[message.arguments objectAtIndex:1] intValue] filled:filled];
            if (result != nil) {
                [self sendErrorMessage:result];
            }
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"removeNote"]) {
            if (![message.typeTag isEqualToString:@",si"]) {
                [self sendErrorMessage:@"Expected Arguments: pitch(s) position(i)"];
                return;
            }
            NSString *result = [[objects objectForKey:[message.address objectAtIndex:1]] removeNote:[message.arguments objectAtIndex:0] atPosition:[[message.arguments objectAtIndex:1] intValue]];
            if (result != nil) {
                [self sendErrorMessage:result];
            }
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setWidth"]) {
            if (![message.typeTag isEqualToString:@",i"]) {
                [self sendErrorMessage:@"Expected Arguments: width(i)"];
                return;
            }
            ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).width = [[message.arguments objectAtIndex:1] intValue];
        } else if ([[message.address objectAtIndex:2] isEqualToString:@"setStartPoint"] || [[message.address objectAtIndex:2] isEqualToString:@"setEndPoint"]) {
            if (![message.typeTag isEqualToString:@",ii"]) {
                [self sendErrorMessage:@"Expected Arguments: x(i) y(i)"];
            }
            CGPoint point = CGPointMake([[message.arguments objectAtIndex:0] intValue], [[message.arguments objectAtIndex:1] intValue]);
            if ([[message.address objectAtIndex:2] isEqualToString:@"setStartPoint"]) {
                ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).startPoint = point;
            } else {
                ((id<CanvasObject>)[objects objectForKey:[message.address objectAtIndex:1]]).endPoint = point;
            }
        }
    } /*else if ([[message.address objectAtIndex:0] isEqualToString:@"LoadNewBlob"]) {
        if (![message.typeTag isEqualToString:@",sbi"]) {
            return;
        }
        
        NSString *imageFile = [tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%i", currentBlobNumber]];
        [[message.arguments objectAtIndex:1] writeToFile:imageFile atomically:YES];
        
        BOOL autosize = NO;
        if ([[message.arguments objectAtIndex:2] intValue] > 0) {
            autosize = YES;
        }
        
        [self loadImageFile:imageFile forLayer:[message.arguments objectAtIndex:0] autoSizing:autosize];
        
        if (isMaster) {
            //Let our external know what the stored blob number is for later reuse.
            OSCMessage *message = [[OSCMessage alloc] init];
            [message appendAddressComponent:@"External"];
            [message appendAddressComponent:@"BlobNumber"];
            [message addIntegerArgument:currentBlobNumber];
            [messagingDelegate sendData:message];
        }
        
        currentBlobNumber++;
    } else if ([[message.address objectAtIndex:0] isEqualToString:@"LoadBlob"]) {
        if (![message.typeTag isEqualToString:@",sii"]) {
            return;
        }
        
        if ([[message.arguments objectAtIndex:1] intValue] < 0 || [[message.arguments objectAtIndex:1] intValue] >= currentBlobNumber) {
            return;
        }
        
        NSString *imageFile = [tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%i", [[message.arguments objectAtIndex:1] intValue]]];
        BOOL autosize = NO;
        if ([[message.arguments objectAtIndex:2] intValue] > 0) {
            autosize = YES;
        }
        
        [self loadImageFile:imageFile forLayer:[message.arguments objectAtIndex:0] autoSizing:autosize];
    }*/
}

- (void)swipeUp
{
    if (parts > 1) {
        [self changePart:1];
        [UIDelegate partChangedToPart:currentPart];
    }
}

- (void)swipeDown
{
    if (parts > 1) {
        [self changePart:-1];
        [UIDelegate partChangedToPart:currentPart];
    }
}

#pragma mark - NSXMLparser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if ([elementName isEqualToString:@"parts"] || [elementName isEqualToString:@"scriptfile"] || [elementName isEqualToString:@"clearonreset"] || [elementName isEqualToString:@"createscore"]) {
        isData = YES;
        currentString = nil;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (isData) {
        if (currentString == nil) {
            currentString = [[NSMutableString alloc] initWithString:string];
        } else {
            [currentString appendString:string];
        }
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if ([elementName isEqualToString:@"parts"]) {
        if ([currentString integerValue] > 0) {
            parts = [currentString integerValue];
        }
    } else if ([elementName isEqualToString:@"scriptfile"]) {
        //TODO: Add code to check for the presence and validity of a script file.
    } else if ([elementName isEqualToString:@"clearonreset"]) {
        if (currentString != nil && [currentString caseInsensitiveCompare:@"no"] == NSOrderedSame) {
            clearOnReset = NO;
        }
    } else if ([elementName isEqualToString:@"createscore"]) {
        if (currentString != nil && [currentString caseInsensitiveCompare:@"yes"] == NSOrderedSame) {
            hasScore = YES;
            currentPart = 0;
        }
    }
    isData = NO;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    if (scriptFile != nil) {
        clearOnReset = NO;
    }
    
    [prefsCondition lock];
    prefsLoaded = YES;
    [prefsCondition signal];
    [prefsCondition unlock];
    
    parser.delegate = nil;
    xmlParser = nil;
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    //If the preferences file is bad, just use the default options for the moment.
    //TODO: Actually deal with bad preferences properly.
    parser.delegate = nil;
    xmlParser = nil;
    
    [prefsCondition lock];
    prefsLoaded = YES;
    [prefsCondition signal];
    [prefsCondition unlock];
}

@end

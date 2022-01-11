//
//  OSCMessage.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 17/11/2014.
//  Copyright (c) 2012 Decibel. All rights reserved.
//

#import "OSCMessage.h"

@interface OSCMessage ()

- (void)padData:(NSMutableData *)data forString:(BOOL)isString;
- (NSString *)extractFirstStringFrom:(const char *)data index:(NSUInteger *)index length:(NSUInteger)length;

//These functions ensure that we have the right endian format for OSC data types.
+ (SInt32)OSCIntValue:(SInt32)intValue;
+ (SInt32)OSCFloatValue:(Float32)floatValue;
+ (SInt32)intFromOSC:(SInt32)oscInt;
+ (Float32)floatFromOSC:(SInt32)oscFloat;
+ (double)timestampFromOSC:(SInt64)oscTimestamp isNow:(BOOL *)isNow;

@end

@implementation OSCMessage {
    //Used to cache our resulting data so that we only regenerate it if necessary.
    NSMutableData *addressData;
    NSMutableData *argumentData;
}

@synthesize timestamp;

+ (NSDate *)ntpReferenceDate
{
    NSDateComponents *refComponents = [[NSDateComponents alloc] init];
    [refComponents setYear:1900];
    [refComponents setMonth:1];
    [refComponents setDay:1];
    [refComponents setHour:0];
    [refComponents setMinute:0];
    [refComponents setSecond:0];
    [refComponents setNanosecond:0];
    return [[NSCalendar currentCalendar] dateFromComponents:refComponents];
}

+ (NSArray *)processBundle:(NSData *)bundleData
{
    NSMutableArray *messages = [[NSMutableArray alloc] init];
    int currentLocation = 8;
    
    //For the moment we're not implementing support for time tags. Bundles get processed immediately.
    //Check that we've actually been given a bundle.
    if (![[NSString stringWithUTF8String:[bundleData bytes]] isEqualToString:@"#bundle"]) {
        return nil;
    }
    
    //The start of timestamp support.
    SInt64 buffer;
    [bundleData getBytes:&buffer range:NSMakeRange(currentLocation, sizeof(SInt64))];
    currentLocation += sizeof(SInt64);
    BOOL isNow = NO;
    double timestamp = [OSCMessage timestampFromOSC:buffer isNow:&isNow];
    // NSLog(@"Timestamp: %e", timestamp);
    
    while (currentLocation < [bundleData length]) {
        SInt32 buffer;
        [bundleData getBytes:&buffer range:NSMakeRange(currentLocation, sizeof(SInt32))];
        currentLocation += sizeof(SInt32);
        int messageSize = [OSCMessage intFromOSC:buffer];
        messageSize += (4 - (messageSize % 4)) % 4;
        if (messageSize + currentLocation <= [bundleData length]) {
            NSData *messageData = [bundleData subdataWithRange:NSMakeRange(currentLocation, messageSize)];
            if ([[NSString stringWithUTF8String:[messageData bytes]] isEqualToString:@"#bundle"]) {
                //Our bundle contains a bundle.
                NSArray *subMessages = [OSCMessage processBundle:messageData];
                if (subMessages != nil) {
                    [messages addObjectsFromArray:subMessages];
                }
            } else {
                //Process as a standard message.
                OSCMessage *currentMessage = [[OSCMessage alloc] initWithData:messageData];
                
                //If we received a valid message then add it to our array.
                if (currentMessage != nil) {
                    [messages addObject:currentMessage];
                    if (!isNow) {
                        currentMessage.timestamp = timestamp;
                    }
                }
            }
        }
        currentLocation += messageSize;
    }
    
    if ([messages count] > 0) {
        return messages;
    } else {
        return nil;
    }
}

- (id)init
{
    self = [super init];
    address = [[NSMutableArray alloc] init];
    typeTag = [[NSMutableString alloc] initWithString:@","];
    arguments = [[NSMutableArray alloc] init];
    timestamp = 0;
    return self;
}

- (id)initWithData:(NSData *)oscData
{
    self = [super init];
    NSUInteger index = 0;
    NSUInteger length = [oscData length];
    const char *rawData = (const char *)[oscData bytes];
    
    //Get our address and check if it starts with "/"
    //(May perform additional validation later.)
    NSString *newAddress = [self extractFirstStringFrom:rawData index:&index length:length];
    if ([newAddress characterAtIndex:0] != '/') {
        return nil;
    }
    [self setAddressWithString:newAddress];
    
    //Get our tag type and check that it is valid.
    typeTag = [[NSMutableString alloc] initWithString:[self extractFirstStringFrom:rawData index:&index length: length]];
    if ([typeTag characterAtIndex:0] != ',') {
        return nil;
    }
    NSString *argTags = [typeTag substringFromIndex:1];
    NSCharacterSet *invalidTags = [[NSCharacterSet characterSetWithCharactersInString:@"ifsb"] invertedSet];
    if ([argTags rangeOfCharacterFromSet:invalidTags].location != NSNotFound) {
        return nil;
    }
    
    //Now use our tag type to populate our data array. We'll need to check that we have enough
    //data for each tag.
    
    arguments = [[NSMutableArray alloc] init];
    int intSize = sizeof(SInt32);
    for (int i = 1; i < [typeTag length]; i++) {
        char type = [typeTag characterAtIndex:i];
        if (type == 'i') {
            if ([oscData length] >= index + intSize) {
                SInt32 buffer;
                memcpy(&buffer, rawData + index, intSize);
                [arguments addObject:[NSNumber numberWithInt:[OSCMessage intFromOSC:(SInt32)buffer]]];
                index += intSize;
            } else {
                //Our OSC message isn't properly formatted.
                return nil;
            }
        } else if (type == 'f') {
            if ([oscData length] >= index + intSize) {
                SInt32 buffer;
                memcpy(&buffer, rawData + index, intSize);
                [arguments addObject:[NSNumber numberWithFloat:[OSCMessage floatFromOSC:(SInt32)buffer]]];
                index += intSize;
            } else {
                return nil;
            }
        } else if (type == 's') {
            NSString *arg = [self extractFirstStringFrom:rawData index:&index length:length];
            if (arg == nil) {
                return nil;
            } else {
                [arguments addObject:arg];
            }
        } else if (type == 'b') {
            //Minimum size of a blob is the size of the header plus 4 bytes.
            if ([oscData length] >= index + intSize + 4) {
                SInt32 header;
                memcpy(&header, rawData + index, intSize);
                int blobLength = [OSCMessage intFromOSC:header];
                //Skip past our header before getting our data.
                index += 4;
                int padLength = (4 - (blobLength % 4)) % 4;
                if (length - index < blobLength + padLength) {
                    //We don't have enough data.
                    return nil;
                }
                [arguments addObject:[NSData dataWithBytes:(rawData + index) length:blobLength]];
                index += blobLength + padLength;
            } else {
                return nil;
            }
        }
    }
    
    //All successful.
    return self;
}

- (NSArray *)address
{
    return [NSArray arrayWithArray:address];
}

- (NSString *)typeTag
{
    return [NSString stringWithString:typeTag];
}

- (NSArray *)arguments
{
    return [NSArray arrayWithArray:arguments];
}

- (BOOL)appendAddressComponent:(NSString *)string
{
    //Make sure this is only one component.
    if ([string rangeOfString:@"/"].location != NSNotFound) {
        return NO;
    }
    [address addObject:string];
    addressData = nil;
    return YES;
}

- (BOOL)prependAddressComponent:(NSString *)string
{
    //Make sure this is only one component.
    if ([string rangeOfString:@"/"].location != NSNotFound) {
        return NO;
    }
    [address insertObject:string atIndex:0];
    addressData = nil;
    return YES;
}

- (BOOL)setAddressWithString:(NSString *)string
{
    string = [string stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSArray *newAddress = [string componentsSeparatedByString:@"/"];
    //Check that none of our address components are empty.
    for (int i = 0; i < [newAddress count]; i++) {
        if ([[newAddress objectAtIndex:i] isEqualToString:@""]) {
            return NO;
        }
    }
    address = [newAddress mutableCopy];
    addressData = nil;
    return YES;
}

- (BOOL)stripFirstAddressComponent {
    //Only remove the first address component if we have additional components.
    if ([address count] > 1) {
        [address removeObjectAtIndex:0];
        addressData = nil;
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)copyAddressFromMessage:(OSCMessage *)message
{
    if ([message.address count] < 1) {
        return NO;
    } else {
        address = [[NSMutableArray alloc] initWithArray:message.address];
        addressData = nil;
        return YES;
    }
}

- (void)addIntegerArgument:(NSInteger)intArg
{
    [typeTag appendString:@"i"];
    [arguments addObject:[NSNumber numberWithInt:(int)intArg]];
    argumentData = nil;
}

- (void)addFloatArgument:(CGFloat)floatArg
{
    [typeTag appendString:@"f"];
    [arguments addObject:[NSNumber numberWithFloat:floatArg]];
    argumentData = nil;
}

- (void)addStringArgument:(NSString *)stringArg
{
    [typeTag appendString:@"s"];
    [arguments addObject:stringArg];
    argumentData = nil;
}

- (void)addBlobArgument:(NSData *)blobArg
{
    [typeTag appendString:@"b"];
    [arguments addObject:blobArg];
    argumentData = nil;
}

- (void)replaceArgumentAtIndex:(NSUInteger)index withInteger:(NSInteger)intArg
{
    [typeTag replaceCharactersInRange:NSMakeRange(index + 1, 1) withString:@"i"];
    [arguments replaceObjectAtIndex:index withObject:[NSNumber numberWithInt:(int)intArg]];
    argumentData = nil;
}

- (void)replaceArgumentAtIndex:(NSUInteger)index withFloat:(CGFloat)floatArg
{
    [typeTag replaceCharactersInRange:NSMakeRange(index + 1, 1) withString:@"f"];
    [arguments replaceObjectAtIndex:index withObject:[NSNumber numberWithFloat:floatArg]];
    argumentData = nil;
}

- (void)replaceArgumentAtIndex:(NSUInteger)index withString:(NSString *)stringArg
{
    [typeTag replaceCharactersInRange:NSMakeRange(index + 1, 1) withString:@"s"];
    [arguments replaceObjectAtIndex:index withObject:stringArg];
    argumentData = nil;
}

- (void)replaceArgumentAtIndex:(NSUInteger)index withBlob:(NSData *)blobArg
{
    [typeTag replaceCharactersInRange:NSMakeRange(index + 1, 1) withString:@"b"];
    [arguments replaceObjectAtIndex:index withObject:blobArg];
    argumentData = nil;
}

- (void)appendArgumentsFromMessage:(OSCMessage *)message
{
    if ([message.arguments count] == 0) {
        return;
    }
    
    [typeTag appendString:[message.typeTag substringFromIndex:1]];
    [arguments addObjectsFromArray:message.arguments];
    argumentData = nil;
}

- (void)removeArgumentAtIndex:(NSUInteger)index
{
    [arguments removeObjectAtIndex:index];
    [typeTag replaceCharactersInRange:NSMakeRange(index + 1, 1) withString:@""];
    argumentData = nil;
}

- (void)removeAllArguments
{
    [arguments removeAllObjects];
    typeTag = [[NSMutableString alloc] initWithString:@","];
    argumentData = nil;
}

- (NSData *)messageAsDataWithHeader:(BOOL)includeHeader
{
    NSMutableData *message;
    if (includeHeader) {
        message = [[NSMutableData alloc] initWithLength:4];
    } else {
        message = [[NSMutableData alloc] init];
    }
    
    //Make sure we have some address information. Then add it.
    if ([address count] == 0) {
        return nil;
    }
    
    if (addressData == nil) {
        addressData = [[NSMutableData alloc] init];
        for (int i = 0; i < [address count]; i++) {
            [addressData appendData:[[NSString stringWithFormat:@"/%@", [address objectAtIndex:i]] dataUsingEncoding:NSUTF8StringEncoding]];
        }
        [self padData:addressData forString:YES];
    }
    [message appendData:addressData];
    
    //Add the type tag.
    [message appendData:[typeTag dataUsingEncoding:NSUTF8StringEncoding]];
    [self padData:message forString:YES];
    
    //Then add our arguments.
    if (argumentData == nil) {
        argumentData = [[NSMutableData alloc] init];
        for (int i = 0; i < [arguments count]; i++) {
            char type = [typeTag characterAtIndex:i + 1];
            if (type == 'i') {
                SInt32 arg = [OSCMessage OSCIntValue:[[arguments objectAtIndex:i] intValue]];
                [argumentData appendBytes:&arg length:sizeof(SInt32)];
            } else if (type == 'f') {
                SInt32 arg = [OSCMessage OSCFloatValue:[[arguments objectAtIndex:i] floatValue]];
                [argumentData appendBytes:&arg length:sizeof(SInt32)];
            } else if (type == 's') {
                [argumentData appendData:[[arguments objectAtIndex:i] dataUsingEncoding:NSUTF8StringEncoding]];
                [self padData:argumentData forString:YES];
            } else if (type == 'b') {
                SInt32 length = [OSCMessage OSCIntValue:(SInt32)[[arguments objectAtIndex:i] length]];
                [argumentData appendBytes:&length length:sizeof(SInt32)];
                [argumentData appendData:[arguments objectAtIndex:i]];
                [self padData:argumentData forString:NO];
            } else {
                //This shouldn't be possible. (Unrecognized tag type.) Return nil.
                argumentData = nil;
                return nil;
            }
        }
    }
    [message appendData:argumentData];
    
    if (includeHeader) {
        //Remove the length of our header when calculating the length to store in the header.
        SInt32 length = [OSCMessage OSCIntValue:(SInt32)([message length] - 4)];
        [message replaceBytesInRange:NSMakeRange(0, 4) withBytes:&length];
    }
    
    return message;
}

- (void)padData:(NSMutableData *)data forString:(BOOL)isString;
{
    int padLength = 4 - ([data length] % 4);
    if (!isString) {
        padLength = padLength % 4;
    }
    [data increaseLengthBy:padLength];
}

- (NSString *)extractFirstStringFrom:(const char *)data index:(NSUInteger *)index length:(NSUInteger)length;
{
    //Get the first null terminated string.
    NSUInteger i = 0;
    BOOL foundNull = NO;
    while (!foundNull && i < length - *index) {
        if (data[*index + i] == 0) {
            foundNull = YES;
        } else {
            i++;
        }
    }
    
    //If we didn't find a null character then our data wasn't formatted correctly.
    if (*index + i == length) {
        *index = length;
        return nil;
    }
    
    NSString *firstString = [NSString stringWithUTF8String:(data + *index)];
    
    //Increase our index by the length of the string and the null padding.
    int padLength = 4 - ([firstString lengthOfBytesUsingEncoding:NSUTF8StringEncoding] % 4);
    *index += [firstString lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + padLength;
    return firstString;
}

+ (SInt32)OSCIntValue:(SInt32)intValue
{
    return OSSwapHostToBigInt32(intValue);
}

+ (SInt32)OSCFloatValue:(Float32)floatValue
{
    SInt32 floatAsInt = *((SInt32 *)(&floatValue));
    return OSSwapHostToBigInt32(floatAsInt);
}

+ (SInt32)intFromOSC:(SInt32)oscInt
{
    return OSSwapBigToHostConstInt32(oscInt);
}

+ (Float32)floatFromOSC:(SInt32)oscFloat
{
    SInt32 floatAsInt = OSSwapBigToHostInt32(oscFloat);
    return *((Float32 *)&floatAsInt);
}

+ (double)timestampFromOSC:(SInt64)oscTimestamp isNow:(BOOL *)isNow
{
    SInt64 fixedPointAsInt = OSSwapBigToHostInt64(oscTimestamp);
    if (fixedPointAsInt == 1) {
        *isNow = YES;
    }
    double timestamp = (double)fixedPointAsInt / 4294967296; //pow(2, 32);
    return timestamp;
}

@end

//
//  OSCMessage.h
//  ScorePlayer
//
//  Created by Aaron Wyatt on 17/11/2014.
//
//

#import <Foundation/Foundation.h>

@interface OSCMessage : NSObject {
    NSMutableArray *address;
    NSMutableString *typeTag;
    NSMutableArray *arguments;
    double timestamp;
}

@property (nonatomic, readonly) NSArray *address;
@property (nonatomic, readonly) NSString *typeTag;
@property (nonatomic, readonly) NSArray *arguments;
@property (nonatomic) double timestamp;

+ (NSDate *)ntpReferenceDate;
+ (NSArray *)processBundle:(NSData *)bundleData;

- (id)initWithData:(NSData *)oscData;

- (BOOL)appendAddressComponent:(NSString *)string;
- (BOOL)prependAddressComponent:(NSString *)string;
- (BOOL)setAddressWithString:(NSString *)string;
- (BOOL)stripFirstAddressComponent;
- (BOOL)copyAddressFromMessage:(OSCMessage *)message;

- (void)addIntegerArgument:(NSInteger)intArg;
- (void)addFloatArgument:(CGFloat)floatArg;
- (void)addStringArgument:(NSString *)stringArg;
- (void)addBlobArgument:(NSData *)blobArg;

- (void)replaceArgumentAtIndex:(NSUInteger)index withInteger:(NSInteger)intArg;
- (void)replaceArgumentAtIndex:(NSUInteger)index withFloat:(CGFloat)floatArg;
- (void)replaceArgumentAtIndex:(NSUInteger)index withString:(NSString *)stringArg;
- (void)replaceArgumentAtIndex:(NSUInteger)index withBlob:(NSData *)blobArg;

- (void)appendArgumentsFromMessage:(OSCMessage *)message;

- (void)removeArgumentAtIndex:(NSUInteger)index;
- (void)removeAllArguments;

- (NSData *)messageAsDataWithHeader:(BOOL)includeHeader;

@end

//
//  ObjCRetriableOperation.h
//  ObjCRetriableOperation
//
//  Created by ouyanghua on 2019/12/31.
//  Copyright © 2019 ouyanghua. All rights reserved.
//

#import <Foundation/Foundation.h>

//! Project version number for ObjCRetriableOperation.
FOUNDATION_EXPORT double ObjCRetriableOperationVersionNumber;

//! Project version string for ObjCRetriableOperation.
FOUNDATION_EXPORT const unsigned char ObjCRetriableOperationVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <ObjCRetriableOperation/PublicHeader.h>

NS_ASSUME_NONNULL_BEGIN


FOUNDATION_EXPORT NSTimeInterval OBJC_RETRIABLE_NEVER;

@interface ObjCRetriableOperation : NSOperation

+ (instancetype)operationWithCompletion:(void(^ _Nullable)(id _Nullable response,NSError * _Nullable latestError))completion
                             retryAfter:(NSTimeInterval(^ _Nullable)(NSInteger currentRetryTime,NSError * _Nullable latestError))retryAfter
                                  start:(void(^_Nonnull)(void(^ _Nonnull callback)(id _Nullable response,NSError * _Nullable error)))start
                                 cancel:(NSError *(^_Nonnull)(void))cancel;

- (instancetype)initWithCompletion:(void(^ _Nullable)(id _Nullable response,NSError * _Nullable latestError))completion
                        retryAfter:(NSTimeInterval(^ _Nullable)(NSInteger currentRetryTime,NSError * _Nullable latestError))retryAfter
                             start:(void(^_Nonnull)(void(^ _Nonnull callback)(id _Nullable response,NSError * _Nullable error)))start
                            cancel:(NSError *(^_Nonnull)(void))cancel NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
/**
 pause operation.
 */
- (void)pause;

/**
 resume operation;
 */
- (void)resume;

/**
 enable log or not.

 @param enabled enabled
 */
+ (void)setLogEnabled:(BOOL)enabled;

@end
NS_ASSUME_NONNULL_END

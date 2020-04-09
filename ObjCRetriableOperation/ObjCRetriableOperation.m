//
//  ObjCRetriableOperation.m
//  ObjCRetriableOperation
//
//  Created by ouyanghua on 2019/12/31.
//  Copyright © 2019 ouyanghua. All rights reserved.
//

#import "ObjCRetriableOperation.h"

NSTimeInterval OBJC_RETRIABLE_NEVER = DBL_MAX;

#if TARGET_OS_IOS || TARGET_OS_TV
#define RETRIABLE_UIKIT 1
#endif

#if RETRIABLE_UIKIT
#import <UIKit/UIKit.h>
#endif

static BOOL logEnabled = NO;

static inline void retriable_log(NSString *log){
    if (logEnabled) printf("\n%s\n",[log UTF8String]);
}

#define RetryLog(...) retriable_log([NSString stringWithFormat:__VA_ARGS__])

@interface ObjCRetriableOperation ()

@property (nonatomic,assign) BOOL                       _isExecuting;
@property (nonatomic,assign) BOOL                       _isFinished;

@property (nonatomic,strong) void(^mCompletionBlock) (id response,NSError *latestError);
@property (nonatomic,strong) NSTimeInterval (^mRetryAfterBlock) (NSInteger currentRetryTime,NSError *latestError);
@property (nonatomic,strong) void(^mStartBlock)(void(^callback) (id response,NSError *error));
@property (nonatomic,strong) void(^mCancelBlock) (void);

@property (nonatomic,assign) NSInteger                  currentRetryTime;
@property (nonatomic,strong) NSError                    *latestError;
@property (nonatomic,strong) id                         response;
@property (nonatomic,retain) dispatch_source_t          timer;
@property (nonatomic,strong) NSRecursiveLock            *lock;
#if RETRIABLE_UIKIT
@property (nonatomic,assign) UIBackgroundTaskIdentifier backgroundTaskId;
#endif
@property (nonatomic,assign) BOOL                       isPaused;

@end

@implementation ObjCRetriableOperation

+ (void)setLogEnabled:(BOOL)enabled{
    logEnabled=enabled;
}

- (void)dealloc{
#if RETRIABLE_UIKIT
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#endif
    [self cancel];
    RetryLog(@"%@ will dealloc",self);
}

+ (instancetype)operationWithCompletion:(void(^ _Nullable)(id _Nullable response,NSError * _Nullable latestError))completion
                             retryAfter:(NSTimeInterval(^ _Nullable)(NSInteger currentRetryTime,NSError * _Nullable latestError))retryAfter
                                  start:(void(^_Nonnull)(void(^ _Nonnull callback)(id _Nullable response,NSError * _Nullable error)))start
                                 cancel:(void(^_Nonnull)(void))cancel{
    return [[self alloc]initWithCompletion:completion retryAfter:retryAfter start:start cancel:cancel];
}

- (instancetype)initWithCompletion:(void(^)(id response,NSError *latestError))completion
                        retryAfter:(NSTimeInterval(^)(NSInteger currentRetryTime,NSError *latestError))retryAfter
                             start:(void(^)(void(^callback)(id response,NSError *error)))start
                            cancel:(void(^)(void))cancel{
    self=[super init];
    if (!self) return nil;
    self.lock=[[NSRecursiveLock alloc]init];
    self.mCompletionBlock =completion;
    self.mRetryAfterBlock = retryAfter;
    self.mStartBlock = start;
    self.mCancelBlock = cancel;
#if RETRIABLE_UIKIT
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
#endif
    return self;
}

- (void)start{
    [self.lock lock];
    [self startTask];
    [self.lock unlock];
}

- (void)cancel{
    [self.lock lock];
    if (self.isCancelled||self.isFinished) {
        [self.lock unlock];
        return;
    }
    [super cancel];
    [self cancelTask];
    [self complete];
    [self.lock unlock];
}

- (void)pause{
    self.isPaused=YES;
}

- (void)resume{
    self.isPaused=NO;
}

- (void)startTask{
    if (self.isCancelled||self.isFinished) return;
    [self beginBackgroundTask];
    if (self.isPaused) return;
    if (self.currentRetryTime==0) RetryLog(@"%@ did start",self);
    else RetryLog(@"%@ retrying: %ld",self,(long)self.currentRetryTime);
    self._isExecuting=YES;
    __weak typeof(self) weakSelf=self;
    self.mStartBlock(^(id response, NSError *error) {
        __strong typeof(weakSelf) self=weakSelf;
        [self.lock lock];
        if (self.isCancelled||self.isFinished){
            [self.lock unlock];
            return;
        }
        self.response=response;
        self.latestError=error;
        if (!error||!self.mRetryAfterBlock) {
            [self complete];
            [self.lock unlock];
            return;
        }
        NSTimeInterval interval=self.mRetryAfterBlock(++self.currentRetryTime,self.latestError);
        if (interval==OBJC_RETRIABLE_NEVER) {
            [self complete];
            [self.lock unlock];
            return;
        }
        if (self.isPaused){
            [self.lock unlock];
            return;
        }
        if (self.timer) {
            NSAssert(0, @"there is a issue about multiple callback");
            dispatch_source_cancel(self.timer);
            self.timer=nil;
        }
        RetryLog(@"%@ will retry after: %.2f\nlatest error: %@",self,interval,self.latestError);
        if (interval == 0){
            [self.lock lock];
            [self startTask];
            [self.lock unlock];
            return;
        }
        self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(self.timer, dispatch_walltime(DISPATCH_TIME_NOW, interval*NSEC_PER_SEC), INT32_MAX * NSEC_PER_SEC, 0 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(self.timer, ^{
            __strong typeof(weakSelf) self=weakSelf;
            [self.lock lock];
            dispatch_source_cancel(self.timer);
            self.timer=nil;
            [self startTask];
            [self.lock unlock];
        });
        dispatch_resume(self.timer);
        [self.lock unlock];
    });
}

- (void)cancelTask{
    self.mCancelBlock();
    if (!self.timer) return;
    dispatch_source_cancel(self.timer);
    self.timer=nil;
}

- (void)complete{
    self._isExecuting=NO;
    self._isFinished=YES;
    if (self.mCompletionBlock) self.mCompletionBlock(self.response, self.latestError);
    RetryLog(@"%@ did complete\nresponse: %@\nerror: %@",self,self.response,self.latestError);
    self.response = nil;
    self.latestError = nil;
    [self endBackgroundTask];
}

#pragma mark --
#pragma mark -- background task

#if RETRIABLE_UIKIT
- (void)applicationWillEnterForeground{
    [self.lock lock];
    if (self.isExecuting&&self.backgroundTaskId==UIBackgroundTaskInvalid) [self startTask];
    [self.lock unlock];
}
#endif

- (void)beginBackgroundTask{
#if RETRIABLE_UIKIT
    if (self.backgroundTaskId!=UIBackgroundTaskInvalid) return;
    __weak typeof(self) weakSelf=self;
    self.backgroundTaskId=[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        __strong typeof(weakSelf) self=weakSelf;
        [self.lock lock];
        if (self.executing&&!self.isPaused) [self cancelTask];
        self.backgroundTaskId=UIBackgroundTaskInvalid;
        RetryLog(@"%@ background task did expired",self);
        [self.lock unlock];
    }];
    RetryLog(@"%@ background task did begin",self);
#endif
}

- (void)endBackgroundTask{
#if RETRIABLE_UIKIT
    if (self.backgroundTaskId==UIBackgroundTaskInvalid) return;
    [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskId];
    self.backgroundTaskId=UIBackgroundTaskInvalid;
    RetryLog(@"%@ background task did end",self);
#endif
}

- (void)setIsPaused:(BOOL)isPaused{
    [self.lock lock];
    if (_isPaused==isPaused) {
        [self.lock unlock];
        return;
    }
    _isPaused=isPaused;
#if RETRIABLE_UIKIT
    if (!self.executing||self.backgroundTaskId==UIBackgroundTaskInvalid){
#else
        if (!self.executing){
#endif
            [self.lock unlock];
            return;
        }
        if (isPaused) [self cancelTask];
        else [self startTask];
        [self.lock unlock];
    }
    
    - (void)set_isExecuting:(BOOL)_isExecuting{
        [self willChangeValueForKey:@"isExecuting"];
        __isExecuting=_isExecuting;
        [self didChangeValueForKey:@"isExecuting"];
    }
    
    - (void)set_isFinished:(BOOL)_isFinished{
        [self willChangeValueForKey:@"isFinished"];
        __isFinished=_isFinished;
        [self didChangeValueForKey:@"isFinished"];
    }
    
    - (BOOL)isExecuting{
        return __isExecuting;
    }
    
    - (BOOL)isFinished{
        return __isFinished;
    }
    
    - (BOOL)isAsynchronous{
        return YES;
    }
    
    @end

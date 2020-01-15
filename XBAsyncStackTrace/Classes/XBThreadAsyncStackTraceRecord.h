//
//  XBThreadAsyncStackTraceRecord.h
//  AsyncStackTrace
//
//  Created by xiaobochen on 2019/2/21.
//  Copyright © 2019年 xiaobochen. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef struct AsyncStackTrace {
    void *_Nonnull* _Nonnull backTrace;
    size_t size;
} AsyncStackTrace;

@interface XBThreadAsyncStackTraceRecord : NSObject
@property (nonatomic, assign) pthread_t pthread;
@property (nonatomic, assign, readonly) AsyncStackTrace asyncStackTrace;


//initialize before call other func;
+ (BOOL)initializeAsyncStackTraceRecord;
+ (nullable instancetype)currentAsyncStackTraceRecord;
+ (void)asyncStackTraceRecordDidCreate:(XBThreadAsyncStackTraceRecord *)asyncStackTraceRecord;
+ (void)asynTraceRecordWillDestroy:(XBThreadAsyncStackTraceRecord *)asyncStackTraceRecord;
+ (XBThreadAsyncStackTraceRecord *)asyncTraceForPthread:(pthread_t)pthread;
- (instancetype)initWithPthread:(pthread_t)pthread NS_DESIGNATED_INITIALIZER;
//now backTrace will not nest, async's func will not run another asyn's func;
- (void)recordBackTrace:(AsyncStackTrace)asyncStackTrace;
- (void)popBackTrace;
- (void *_Nonnull* _Nonnull)backTrace;
- (size_t)backTraceSize;
- (NSString *)symbolicatedBackTrace;
@end

NS_ASSUME_NONNULL_END

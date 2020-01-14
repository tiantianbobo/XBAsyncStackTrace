//
//  XBThreadAsyncStackTraceRecord.m
//  AsyncStackTrace
//
//  Created by xiaobochen on 2019/2/21.
//  Copyright © 2019年 xiaobochen. All rights reserved.
//

#import "XBThreadAsyncStackTraceRecord.h"
#import <pthread.h>
#import <os/lock.h>
#import <execinfo.h>



//参考_CFGetTSDCreateIfNeeded
#define XB_TSD_BAD_PTR ((void *)0x1000)
typedef pthread_key_t tls_key_t;
static inline tls_key_t tls_create(void (* _Nullable dtor)(void*)) {
    tls_key_t k;
    int result = pthread_key_create(&k, dtor);
    if(__builtin_expect(result,0)) {
        NSLog(@"pthread_key_create failed!:%d",result);
        k = 0;
    }
    return k;
}
static inline void *tls_get(tls_key_t k) {
    return pthread_getspecific(k);
}
static inline void tls_set(tls_key_t k, const void * _Nullable value) {
    pthread_setspecific(k, value);
}
static tls_key_t XBThreadAsyncStackTraceTlsKey;
static NSMutableDictionary<NSValue *, XBThreadAsyncStackTraceRecord *> *recordDic;
static BOOL initialized = NO;
static void destroyThreadStackTraceRecord(void *value) {
    if (value == XB_TSD_BAD_PTR) {
        return;
    }
    XBThreadAsyncStackTraceRecord *record = CFBridgingRelease(value);
    [XBThreadAsyncStackTraceRecord asynTraceRecordWillDestroy:record];
    tls_set(XBThreadAsyncStackTraceTlsKey, XB_TSD_BAD_PTR);
    record = nil;
}
#define CHECKINITIALIZED()     NSAssert(initialized, @"should initializeAsyncStackTraceRecord first")

@interface XBThreadAsyncStackTraceRecord()
@property (nonatomic, assign) AsyncStackTrace asyncStackTrace;
@end

@implementation XBThreadAsyncStackTraceRecord
+ (BOOL)initializeAsyncStackTraceRecord {
    XBThreadAsyncStackTraceTlsKey = tls_create(&destroyThreadStackTraceRecord);
    if (XBThreadAsyncStackTraceTlsKey == 0) {
        return NO;
    }
    recordDic = [[NSMutableDictionary alloc] initWithCapacity:100];
    initialized = YES;
    return YES;
}
+ (nullable instancetype)currentAsyncStackTraceRecord {
    CHECKINITIALIZED();
    XBThreadAsyncStackTraceRecord *asyncStackTraceRecord = (__bridge XBThreadAsyncStackTraceRecord *)(tls_get(XBThreadAsyncStackTraceTlsKey));
    if (asyncStackTraceRecord == XB_TSD_BAD_PTR) {
//wont't call currentAsyncStackTraceRecord while tsd cleanup.
        assert(false);
        return nil;
    }
    if (!asyncStackTraceRecord) {
        asyncStackTraceRecord = [XBThreadAsyncStackTraceRecord new];
        tls_set(XBThreadAsyncStackTraceTlsKey, CFBridgingRetain(asyncStackTraceRecord));
        [self asyncStackTraceRecordDidCreate:asyncStackTraceRecord];
    }
    return asyncStackTraceRecord;
}

+ (void)asyncStackTraceRecordDidCreate:(XBThreadAsyncStackTraceRecord *)asyncStackTraceRecord {
    CHECKINITIALIZED();
    @synchronized (self) {
        recordDic[[NSValue valueWithPointer:asyncStackTraceRecord.pthread]] = asyncStackTraceRecord;
    }
}
+ (void)asynTraceRecordWillDestroy:(XBThreadAsyncStackTraceRecord *)asyncStackTraceRecord {
    CHECKINITIALIZED();
    @synchronized (self) {
        [recordDic removeObjectForKey:[NSValue valueWithPointer:asyncStackTraceRecord.pthread]];
    }
}
+ (XBThreadAsyncStackTraceRecord *)asyncTraceForPthread:(pthread_t)pthread {
    CHECKINITIALIZED();
    XBThreadAsyncStackTraceRecord *asyncStackTraceRecord;
    @synchronized (self) {
        asyncStackTraceRecord = recordDic[[NSValue valueWithPointer:pthread]];
    }
    return asyncStackTraceRecord;
}
- (instancetype)initWithPthread:(pthread_t)pthread {
    if (self = [super init]) {
        self.pthread = pthread;
    }
    return self;
}
- (instancetype)init {
    if (self = [self initWithPthread:pthread_self()]) {
        
    }
    return self;
}
- (void)recordBackTrace:(AsyncStackTrace)asyncStackTrace {
    self.asyncStackTrace = asyncStackTrace;
}
- (void)popBackTrace {
    [self clearCurBackTrace];
}
- (void)clearCurBackTrace {
    free(self.asyncStackTrace.backTrace);
    AsyncStackTrace zeroStruct;
    zeroStruct.backTrace = NULL;
    zeroStruct.size = 0;
    self.asyncStackTrace = zeroStruct;
}
- (NSString *)symbolicatedBackTrace {
    NSMutableString *info = [NSMutableString new];
    char **strings;
    strings = backtrace_symbols(self.asyncStackTrace.backTrace, (int)self.asyncStackTrace.size);
    for (int i = 0; i < self.asyncStackTrace.size; i++) {
        [info appendFormat:@"%s\n",strings[i]];
    }
    return [info copy];
}
- (void)dealloc {
    [self clearCurBackTrace];
}
@end

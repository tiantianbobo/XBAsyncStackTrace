//
//  AsyncStackTrace.m
//  AsyncStackTrace
//
//  Created by xiaobochen on 2019/2/21.
//  Copyright © 2019年 xiaobochen. All rights reserved.
//

#import "XBAsyncStackTraceManager.h"
#import "hookfunc.h"
#import <execinfo.h>
#import "XBThreadAsyncStackTraceRecord.h"
#import "XBTimeCostRecord.h"
#include <objc/runtime.h>

#pragma mark - TIME_COST_RECORD

#define ENABLE_TIME_COST_RECORD 0
#if ENABLE_TIME_COST_RECORD
static XBTimeCostRecord *timeCostRecord;
#define XBTIME_TICK()  CFAbsoluteTime xb_time_start = CFAbsoluteTimeGetCurrent();
#define XBTIME_TOCK()  [timeCostRecord addTimeCost:(CFAbsoluteTimeGetCurrent() - xb_time_start)]
#else
#define XBTIME_TICK()
#define XBTIME_TOCK()
#endif

#pragma mark - asyncStrackTrace helper func

__attribute__((always_inline)) AsyncStackTrace getCurAsyncStackTrace(void) {
    int maxBacktraceLimit = [XBAsyncStackTraceManager sharedInstance].maxBacktraceLimit;
    AsyncStackTrace asyncStackTrace;
    void **backTracePtr = (void **)malloc(sizeof(void*) * maxBacktraceLimit);
    size_t size = backtrace(backTracePtr, maxBacktraceLimit);
    asyncStackTrace.backTrace = backTracePtr;
    asyncStackTrace.size = size;
    return asyncStackTrace;
}

__attribute__((always_inline)) NSValue *getCurAsyncStackTraceNSValue(void) {
    AsyncStackTrace asyncStackTrace = getCurAsyncStackTrace();
    NSValue *traceValue = [NSValue value:&asyncStackTrace withObjCType:@encode(AsyncStackTrace)];
    return traceValue;
}

AsyncStackTrace asyncStrckTraceFromNSValue(NSValue *value) {
    AsyncStackTrace asyncStackTrace;
    [value getValue:&asyncStackTrace];
    return asyncStackTrace;
}

#pragma mark - hook dispatch helper func

static __attribute__((always_inline)) dispatch_block_t blockRecordAsyncTrace(dispatch_block_t block) {
    XBTIME_TICK();
    AsyncStackTrace asyncStackTrace = getCurAsyncStackTrace();
    NSCAssert(block != NULL, @"block is nil");
    if (block == nil) {
        __asm__(""); __builtin_trap();
    }
    __block dispatch_block_t oriBlock = block;
    dispatch_block_t newBlock = ^(){
        XBThreadAsyncStackTraceRecord *curRecord = [XBThreadAsyncStackTraceRecord currentAsyncStackTraceRecord];
        [curRecord recordBackTrace:asyncStackTrace];
        oriBlock();
        oriBlock = nil;
       //force block dispose oriBlock, so if any crash happens inside __destroy_helper_block we can still get async stack trace.
        [curRecord popBackTrace];
     };
    XBTIME_TOCK();
    return newBlock;
}

typedef struct AsyncRecord {
    void *_Nullable context;
    dispatch_function_t oriFunc;
    AsyncStackTrace asyncStackTrace;
} AsyncRecord;
static __attribute__((always_inline)) void* newContextRecordAsyncTrace(void *_Nullable context, dispatch_function_t work) {
    XBTIME_TICK();
    AsyncRecord *record = (AsyncRecord *)calloc(sizeof(AsyncRecord),1);
//    if (record == NULL) {
//        return NULL;
//    }
    record->context = context;
    record->oriFunc = work;
    AsyncStackTrace asyncStackTrace = getCurAsyncStackTrace();
    record->asyncStackTrace = asyncStackTrace;
    XBTIME_TOCK();
    return record;
}
static void replaceFuncRecordAsyncTrace(void *_Nullable context) {
    AsyncRecord *record = (AsyncRecord *)context;
    XBThreadAsyncStackTraceRecord *curRecord = [XBThreadAsyncStackTraceRecord currentAsyncStackTraceRecord];
    [curRecord recordBackTrace:record->asyncStackTrace];
    dispatch_function_t oriFunc = record->oriFunc;
    NSCAssert(oriFunc, @"oriFunc is nil");
    if (oriFunc != NULL) {
        oriFunc(record->context);
    }
    [curRecord popBackTrace];
    free(record);
}
#define NEW_CONTEXT_WORK_RECORD(context,work) newContextRecordAsyncTrace(context, work),replaceFuncRecordAsyncTrace

#pragma mark - hook dispatch

HOOK_FUNC(void, dispatch_async, dispatch_queue_t queue, dispatch_block_t block)
    orig_dispatch_async(queue,blockRecordAsyncTrace(block));
}

HOOK_FUNC(void, dispatch_async_f, dispatch_queue_t queue, void *_Nullable context, dispatch_function_t work)
    orig_dispatch_async_f(queue,NEW_CONTEXT_WORK_RECORD(context,work));

}
HOOK_FUNC(void, dispatch_after, dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block)
    orig_dispatch_after(when,queue,blockRecordAsyncTrace(block));
}
HOOK_FUNC(void, dispatch_after_f, dispatch_time_t when, dispatch_queue_t queue, void *_Nullable context, dispatch_function_t work)
    orig_dispatch_after_f(when,queue,NEW_CONTEXT_WORK_RECORD(context,work));
}
HOOK_FUNC(void, dispatch_barrier_async, dispatch_queue_t queue, dispatch_block_t block)
    orig_dispatch_barrier_async(queue,blockRecordAsyncTrace(block));
}
HOOK_FUNC(void, dispatch_barrier_async_f, dispatch_queue_t queue, void *_Nullable context, dispatch_function_t work)
    orig_dispatch_barrier_async_f(queue,NEW_CONTEXT_WORK_RECORD(context,work));
}

#pragma mark - hook NSObject helper func

#define XB_HOOKMETHOD(class, aSelector)\
xb_hookMethod(class, @selector(aSelector),  @selector(xb_##aSelector))

void xb_hookMethod(Class class, SEL oriSel, SEL hookSel) {
    Method systemMethod = class_getInstanceMethod(class, oriSel);
    Method zwMethod = class_getInstanceMethod(class, hookSel);
    assert(systemMethod != NULL);
    assert(zwMethod != NULL);
    method_exchangeImplementations(systemMethod, zwMethod);
}

@interface XBAsyncRecordParam : NSObject
@property (nonatomic, strong) id arg;
@property (nonatomic, assign) SEL aSelector;
@property (nonatomic, assign) AsyncStackTrace asyncStackTrace;
@end
@implementation XBAsyncRecordParam
- (instancetype)initWithSelector:(SEL)aSelector ar:(id)arg {
    if (self = [super init]) {
        self.aSelector = aSelector;
        self.arg = arg;
    }
    return self;
}

@end

#pragma mark - hook NSObject

@interface NSObject (XB_Hook_NSThreadPerformAdditions)

@end


@implementation NSObject  (XB_Hook_NSThreadPerformAdditions)

- (void)xb_performSelector:(SEL)aSelector onThread:(NSThread *)thr withObject:(nullable id)arg waitUntilDone:(BOOL)wait modes:(nullable NSArray<NSString *> *)array {
    if (!wait) {
        XBAsyncRecordParam *param = [[XBAsyncRecordParam alloc] initWithSelector:aSelector ar:arg];
        param.asyncStackTrace = getCurAsyncStackTrace();
        [self xb_performSelector:@selector(xb_performWithAsyncTrace:) onThread:thr withObject:param waitUntilDone:wait modes:array];
    } else {
        [self xb_performSelector:aSelector onThread:thr withObject:arg waitUntilDone:wait modes:array];
    }
}

- (void)xb_performWithAsyncTrace:(XBAsyncRecordParam *)param {
    XBThreadAsyncStackTraceRecord *curRecord = [XBThreadAsyncStackTraceRecord currentAsyncStackTraceRecord];
    [curRecord recordBackTrace:param.asyncStackTrace];
#    pragma clang diagnostic push
#     pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    (void)[self performSelector:param.aSelector withObject:param.arg];
#       pragma clang diagnostic pop
    [curRecord popBackTrace];
}

@end

#pragma mark - hook NSThread
const void *XBNSThreadAsyncStackTraceKey;

@interface NSThread (XB_Hook_NSThread)

@end


@implementation NSThread  (XB_Hook_NSThread)

- (instancetype)xb_init {
    NSThread *newSelf = [self xb_init];
    NSValue *traceValue = getCurAsyncStackTraceNSValue();
    objc_setAssociatedObject(newSelf, &XBNSThreadAsyncStackTraceKey, traceValue, OBJC_ASSOCIATION_RETAIN);
    return newSelf;
}

- (instancetype)xb_initWithTarget:(id)target selector:(SEL)selector object:(nullable id)argument {
    NSThread *newSelf = [self xb_initWithTarget:target selector:selector object:argument];
    NSValue *traceValue = getCurAsyncStackTraceNSValue();
    objc_setAssociatedObject(newSelf, &XBNSThreadAsyncStackTraceKey, traceValue, OBJC_ASSOCIATION_RETAIN);
    return newSelf;
}

- (instancetype)xb_initWithBlock:(void (^)(void))block {
    NSThread *newSelf = [self xb_initWithBlock:block];
    NSValue *traceValue = getCurAsyncStackTraceNSValue();
    objc_setAssociatedObject(newSelf, &XBNSThreadAsyncStackTraceKey, traceValue, OBJC_ASSOCIATION_RETAIN);
    return newSelf;
}

- (void)xb_main {
    NSValue *traceValue = objc_getAssociatedObject(self, &XBNSThreadAsyncStackTraceKey);
    XBThreadAsyncStackTraceRecord *curRecord = [XBThreadAsyncStackTraceRecord currentAsyncStackTraceRecord];
    if (traceValue != nil) {
        AsyncStackTrace asyncStackTrace = asyncStrckTraceFromNSValue(traceValue);
        [curRecord recordBackTrace:asyncStackTrace];
    }
    [self xb_main];
    if (traceValue != nil) {
        [curRecord popBackTrace];
        objc_setAssociatedObject(self, &XBNSThreadAsyncStackTraceKey, nil, OBJC_ASSOCIATION_RETAIN);
    }
}

@end

@interface XBAsyncStackTraceManager()
@property (nonatomic, assign) BOOL xbInitialized;

@end


@implementation XBAsyncStackTraceManager
+ (instancetype)sharedInstance {
    static XBAsyncStackTraceManager *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [self new];
    });
    return s_instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _maxBacktraceLimit = 32;
    }
    return self;
}

- (BOOL)beginHook {
    @synchronized (self) {
        if (self.xbInitialized) {
            return YES;
        }
        BOOL result = [XBThreadAsyncStackTraceRecord initializeAsyncStackTraceRecord];
        if(!__builtin_expect(result,1)) {
            return NO;
        }
    #if ENABLE_TIME_COST_RECORD
        timeCostRecord = [XBTimeCostRecord new];
    #endif
        BEGIN_HOOK(dispatch_async);
        BEGIN_HOOK(dispatch_async_f);
        BEGIN_HOOK(dispatch_after);
        BEGIN_HOOK(dispatch_after_f);
        BEGIN_HOOK(dispatch_barrier_async);
        BEGIN_HOOK(dispatch_barrier_async_f);
        {
            XB_HOOKMETHOD([NSObject class], performSelector:onThread:withObject:waitUntilDone:modes:);
        }
        {
            XB_HOOKMETHOD([NSThread class], main);
            XB_HOOKMETHOD([NSThread class], init);
            XB_HOOKMETHOD([NSThread class], initWithBlock:);
            XB_HOOKMETHOD([NSThread class], initWithTarget:selector:object:);
        }
        self.xbInitialized = YES;
    }
    return YES;
}
- (XBThreadAsyncStackTraceRecord *)asyncTraceForPthread:(pthread_t)pthread {
    return [XBThreadAsyncStackTraceRecord asyncTraceForPthread:pthread];
}
- (NSString *)getTimeCostDesc {
#if ENABLE_TIME_COST_RECORD
    return [timeCostRecord timeCostDesc];
#else
    return @"ENABLE_TIME_COST_RECORD not enabled";
#endif
}
@end

//
//  XBAsyncStackTraceTests.m
//  XBAsyncStackTraceTests
//
//  Created by xiaobochen on 2020/1/13.
//  Copyright © 2020 xiaobochen. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "XBAsyncStackTrace.h"
#include <pthread.h>
#include <execinfo.h>
#include <dlfcn.h>

@interface XBAsyncStackTraceTests : XCTestCase
@property (nonatomic, strong) XBAsyncStackTraceManager *asyncManager;
@property (nonatomic, assign) int maxBacktraceLimit;
@property (nonatomic, strong) NSMutableArray<XCTestExpectation *> *xbExpectationArray;
@end

@implementation XBAsyncStackTraceTests
- (XCTestExpectation *)xbExpectationWithDescription:(NSString *)description {
    XCTestExpectation *expectation = [self expectationWithDescription:description];
    [self.xbExpectationArray addObject:expectation];
    return expectation;
}

- (void)waitForXbExpectation {
    [self waitForExpectations:self.xbExpectationArray timeout:5];
    [self.xbExpectationArray removeAllObjects];
}

- (void)printSymbolicatedBackTrace:(XBThreadAsyncStackTraceRecord *)asyncRecord backTracePtr:(void **)backTracePtr backTraceSize:(size_t)backTraceSize {
    NSString *asyncStackRecordStr = [NSString stringWithFormat:@"asyncStackTrceRecord:\n%@",[asyncRecord symbolicatedBackTrace]];
    NSLog(@"\n%@", asyncStackRecordStr);
    char **strings = backtrace_symbols(backTracePtr, (int)backTraceSize);
    NSMutableString *backTracePtrStr = [NSMutableString stringWithString:@"backTracePtr:\n"];
    for(int j = 0; j < backTraceSize; j++)
        [backTracePtrStr appendFormat:@"%s\n", strings[j]];
    NSLog(@"\n%@", backTracePtrStr);
    
}

- (void)setUp {
    self.asyncManager = [XBAsyncStackTraceManager sharedInstance];
    BOOL initialized = [self.asyncManager beginHook];
    self.maxBacktraceLimit = self.asyncManager.maxBacktraceLimit;
    self.xbExpectationArray = [NSMutableArray new];
    XCTAssert(initialized, @"XBAsyncStackTraceManager hook failed");
}

- (void)tearDown {

}

- (void)_checkAsyncStackTraceIsCorrect:(XBThreadAsyncStackTraceRecord *)asyncStackTrceRecord backTracePtr:(void **)backTracePtr backTraceSize:(size_t)backTraceSize ignoreTopStackIndex:(int)ignoreTopStackIndex {
    AsyncStackTrace asyncStackTrace = asyncStackTrceRecord.asyncStackTrace;
    int maxBacktraceLimit = self.asyncManager.maxBacktraceLimit;
    XCTAssert(backTraceSize <= maxBacktraceLimit);
    XCTAssert(asyncStackTrace.size <= maxBacktraceLimit);
    if (backTraceSize == maxBacktraceLimit ) {
        XCTAssert(asyncStackTrace.size == maxBacktraceLimit, @"back trace size beyond limit, async stack trace :%zd should be maxBacktraceLimit:%d, ", asyncStackTrace.size, maxBacktraceLimit);
    } else {
        XCTAssert((asyncStackTrace.size+1) == maxBacktraceLimit, @"async stack trace :%zd should be maxBacktraceLimit:%d -1 ", asyncStackTrace.size, maxBacktraceLimit);
    }
//asyncStackTrceRecord:
//0   XBAsyncStackTraceTests              0x000000010760f4c1 wrap_dispatch_async + 273
//1   XBAsyncStackTraceTests              0x000000010760e09a -[XBAsyncStackTraceTests testAsyncStackTrace] + 282
//2   CoreFoundation                      0x00007fff23b9f95c __invoking___ + 140
//3   CoreFoundation                      0x00007fff23b9cd8f -[NSInvocation invoke] + 287
//4   XCTest                              0x0000000105193121 __24-[XCTestCase invokeTest]_block_invoke.208 + 78
//backTracePtr:
//0   XBAsyncStackTraceTests              0x000000010760e001 -[XBAsyncStackTraceTests testAsyncStackTrace] + 129
//1   CoreFoundation                      0x00007fff23b9f95c __invoking___ + 140
//2   CoreFoundation                      0x00007fff23b9cd8f -[NSInvocation invoke] + 287
//3   XCTest                              0x0000000105193121 __24-[XCTestCase invokeTest]_block_invoke.208 + 78
    for (size_t i = ignoreTopStackIndex+1; i < asyncStackTrace.size; i++) {
        if (asyncStackTrace.backTrace[i] != backTracePtr[i-ignoreTopStackIndex]) {
            XCTAssert(NO);
        }
    }
//
    Dl_info asyncDlInfo;
    XCTAssert(asyncStackTrace.size > ignoreTopStackIndex);
    dladdr(asyncStackTrace.backTrace[ignoreTopStackIndex], &asyncDlInfo);
    Dl_info backTraceDlInfo;
    XCTAssert(backTraceSize > 1);
    dladdr(backTracePtr[0], &backTraceDlInfo);
    XCTAssert(asyncDlInfo.dli_saddr == backTraceDlInfo.dli_saddr);
    return ;
}

#define GET_CUR_BACK_TRACE \
void **backTracePtr = (void **)malloc(sizeof(void*) * self.maxBacktraceLimit);\
size_t backTraceSize = backtrace(backTracePtr, self.maxBacktraceLimit);

#define CHCK_ASYNC_STACK_TRACE \
XBThreadAsyncStackTraceRecord *curAsyncStackTraceRecor = [self.asyncManager asyncTraceForPthread:pthread_self()];\
XCTAssert(curAsyncStackTraceRecor.pthread == pthread_self());\
[self _checkAsyncStackTraceIsCorrect:curAsyncStackTraceRecor backTracePtr:backTracePtr backTraceSize:backTraceSize ignoreTopStackIndex:1];

#define DECLARE_EXPECTATION(description)\
XCTestExpectation *description##_expectation = [self xbExpectationWithDescription:@#description];
- (void)testDispatchBlockAsyncBarrierAsyncAfterCanGetAsyncStackTrace {
    GET_CUR_BACK_TRACE;
    dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
    DECLARE_EXPECTATION(dispatch_async);
    dispatch_async(queue, ^{
        CHCK_ASYNC_STACK_TRACE;
        [dispatch_async_expectation fulfill];
    });
    DECLARE_EXPECTATION(dispatch_barrier_async);
    dispatch_barrier_async(queue, ^{
        CHCK_ASYNC_STACK_TRACE;
        [dispatch_barrier_async_expectation fulfill];
    });
    DECLARE_EXPECTATION(dispatch_after);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), queue, ^{
        CHCK_ASYNC_STACK_TRACE;
        [dispatch_after_expectation fulfill];
    });
    [self waitForXbExpectation];
}

#define RECORD_KEY @"RECORD_KEY"
#define TESTS_KEY @"TESTS_KEY"
#define EXPECTATION_KEY @"EXPECTATION_KEY"

#define GET_CUR_BACK_TRACE_WITH_ASYNC_STRACK_RECORD \
GET_CUR_BACK_TRACE;\
XBThreadAsyncStackTraceRecord *asyncStackTraceRecord = [[XBThreadAsyncStackTraceRecord alloc] initWithPthread:pthread_self()];\
AsyncStackTrace asyncStackTrace;\
asyncStackTrace.backTrace = backTracePtr;\
asyncStackTrace.size = backTraceSize;\
[asyncStackTraceRecord recordBackTrace:asyncStackTrace];
void async_func_callback(void *context);
- (void)testDispatchFuncAsyncBarrierAsyncAfterCanGetAsyncStackTrace {
    GET_CUR_BACK_TRACE_WITH_ASYNC_STRACK_RECORD;
    dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
    
    NSDictionary *contextDict = @{RECORD_KEY:asyncStackTraceRecord, TESTS_KEY:self};
#define DICT_WITH_EXPECTATION(description) \
NSMutableDictionary *description##_dict = [NSMutableDictionary dictionaryWithDictionary:contextDict];\
description##_dict[EXPECTATION_KEY] = [self xbExpectationWithDescription:@#description];
    
    DICT_WITH_EXPECTATION(dispatch_async_f);
    dispatch_async_f(queue, (void *)CFBridgingRetain(dispatch_async_f_dict), async_func_callback);
    DICT_WITH_EXPECTATION(dispatch_barrier_async_f);
    dispatch_barrier_async_f(queue, (void *)CFBridgingRetain(dispatch_barrier_async_f_dict), async_func_callback);
    DICT_WITH_EXPECTATION(dispatch_after_f);
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), queue, (void *)CFBridgingRetain(dispatch_after_f_dict), async_func_callback);
    [self waitForXbExpectation];
}

- (void)_selectorThatCheckCanGetAsyncStrackTrace:(NSDictionary *)contextDict {
    XBThreadAsyncStackTraceRecord *asyncRecord = contextDict[RECORD_KEY];
    AsyncStackTrace asyncStackTrace = asyncRecord.asyncStackTrace;
    XBThreadAsyncStackTraceRecord *curAsyncStackTraceRecor = [self.asyncManager asyncTraceForPthread:pthread_self()];
//asyncStackTrceRecord:
//0   XBAsyncStackTraceTests              0x0000000111d7e82a -[NSObject(XB_Hook_NSThreadPerformAdditions) xb_performSelector:onThread:withObject:waitUntilDone:modes:] + 378
//1   Foundation                          0x00007fff25683c24 -[NSObject(NSThreadPerformAdditions) performSelector:onThread:withObject:waitUntilDone:] + 110
//2   XBAsyncStackTraceTests              0x0000000111d7e0bf -[XBAsyncStackTraceTests testPerformSelectorCanGetAsyncStackTrace] + 559
//
//backTracePtr:
//0   XBAsyncStackTraceTests              0x0000000111d7df11 -[XBAsyncStackTraceTests testPerformSelectorCanGetAsyncStackTrace] + 129
//1   CoreFoundation                      0x00007fff23b9f95c __invoking___ + 140
    [self _checkAsyncStackTraceIsCorrect:curAsyncStackTraceRecor backTracePtr:asyncStackTrace.backTrace backTraceSize:asyncStackTrace.size ignoreTopStackIndex:2];
    XCTestExpectation *expectation = contextDict[EXPECTATION_KEY];
    [expectation fulfill];
}

- (void)testPerformSelectorCanGetAsyncStackTrace {
    GET_CUR_BACK_TRACE_WITH_ASYNC_STRACK_RECORD;
    NSDictionary *contextDict = @{RECORD_KEY:asyncStackTraceRecord};
    DICT_WITH_EXPECTATION(testPerformSelectorCanGetAsyncStackTrace);
    [self performSelector:@selector(_selectorThatCheckCanGetAsyncStrackTrace:) onThread:[NSThread mainThread] withObject:testPerformSelectorCanGetAsyncStackTrace_dict waitUntilDone:NO];
    [self waitForXbExpectation];
}


- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        int max_concurrent = 1000;
        dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
        for (int i = 0; i < max_concurrent; i++) {
            dispatch_async(queue, ^{
               //
            });
        }
    }];
}

@end

void async_func_callback(void *context) {
    NSDictionary *contextDict = CFBridgingRelease(context);
    XBAsyncStackTraceTests *tests = contextDict[TESTS_KEY];
    XBThreadAsyncStackTraceRecord *record = contextDict[RECORD_KEY];
    AsyncStackTrace asyncStackTrace = record.asyncStackTrace;
    XCTestExpectation *expectation = contextDict[EXPECTATION_KEY];
    assert(expectation != nil);
    XBThreadAsyncStackTraceRecord *curAsyncStackTraceRecor = [tests.asyncManager asyncTraceForPthread:pthread_self()];
    [tests _checkAsyncStackTraceIsCorrect:curAsyncStackTraceRecor backTracePtr:asyncStackTrace.backTrace backTraceSize:asyncStackTrace.size ignoreTopStackIndex:1];
    [expectation fulfill];
}

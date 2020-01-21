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

#define RECORD_KEY @"RECORD_KEY"
#define TESTS_KEY @"TESTS_KEY"
#define EXPECTATION_KEY @"EXPECTATION_KEY"

__attribute__((always_inline)) XBThreadAsyncStackTraceRecord *getCurAsyncStackTraceRecord(void) {
    int maxBacktraceLimit = [XBAsyncStackTraceManager sharedInstance].maxBacktraceLimit;
    AsyncStackTrace asyncStackTrace;
    void **backTracePtr = (void **)malloc(sizeof(void*) * maxBacktraceLimit);
    size_t size = backtrace(backTracePtr, maxBacktraceLimit);
    asyncStackTrace.backTrace = backTracePtr;
    asyncStackTrace.size = size;
    XBThreadAsyncStackTraceRecord *asyncStackTraceRecord = [[XBThreadAsyncStackTraceRecord alloc] initWithPthread:pthread_self()];
    [asyncStackTraceRecord recordBackTrace:asyncStackTrace];
    return asyncStackTraceRecord;
}

void async_func_callback(void *context);

@interface XBAsyncStackTraceTests : XCTestCase
@property (nonatomic, strong) XBAsyncStackTraceManager *asyncManager;
@property (nonatomic, assign) int maxBacktraceLimit;
@property (nonatomic, strong) NSMutableArray<XCTestExpectation *> *xbExpectationArray;
@end

@implementation XBAsyncStackTraceTests

- (void)setUp {
    self.asyncManager = [XBAsyncStackTraceManager sharedInstance];
    BOOL initialized = [self.asyncManager beginHook];
    self.maxBacktraceLimit = self.asyncManager.maxBacktraceLimit;
    self.xbExpectationArray = [NSMutableArray new];
    XCTAssert(initialized, @"XBAsyncStackTraceManager hook failed");
}

- (void)tearDown {

}

- (XCTestExpectation *)xbExpectationWithDescription:(NSString *)description {
    XCTestExpectation *expectation = [self expectationWithDescription:description];
    [self.xbExpectationArray addObject:expectation];
    return expectation;
}

- (void)waitForXbExpectation {
    [self waitForExpectations:self.xbExpectationArray timeout:5];
    [self.xbExpectationArray removeAllObjects];
}

- (NSDictionary *)contextDictWithActualRecord:(XBThreadAsyncStackTraceRecord *)record expectationDesc:(NSString *)expectationDesc {
    XCTestExpectation *expectation = [self xbExpectationWithDescription:expectationDesc];
    return @{RECORD_KEY:record, TESTS_KEY:self, EXPECTATION_KEY:expectation};
}

- (int)getAdditionalFrame:(XBThreadAsyncStackTraceRecord *)actualStack asyncRecord:(XBThreadAsyncStackTraceRecord *)asyncRecord {
    for (int i = 0; i < asyncRecord.backTraceSize; i++) {
        BOOL isEqualFromCurFrame = YES;
        for (int j = 1; j+i < asyncRecord.backTraceSize ; j++) {
            if(actualStack.backTrace[j] != asyncRecord.backTrace[j+i]) {
                isEqualFromCurFrame = NO;
                break;
            }
        }
        if (isEqualFromCurFrame) {
            return i;
        }
    }
    return -1;
}

//for dispatch func
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
- (void)_checkAsyncStackTraceSizeCorrect:(XBThreadAsyncStackTraceRecord *)actualStack asyncRecord:(XBThreadAsyncStackTraceRecord *)asyncRecord additionalFrame:(int)additionalFrame {
    int maxBacktraceLimit = self.asyncManager.maxBacktraceLimit;
    XCTAssert(actualStack.backTraceSize <= maxBacktraceLimit);
    XCTAssert(asyncRecord.backTraceSize <= maxBacktraceLimit);
    if (actualStack.backTraceSize + additionalFrame <= maxBacktraceLimit) {
        XCTAssert((actualStack.backTraceSize + additionalFrame) == asyncRecord.backTraceSize, @"asyncRecord.backTraceSize :%zd should be actualStack.backTraceSize:%zd + %d", asyncRecord.backTraceSize, actualStack.backTraceSize, additionalFrame);
    } else {
        XCTAssert(asyncRecord.backTraceSize == maxBacktraceLimit, @"actualStack.backTraceSize:%zd + %d beyond limit, asyncRecord.backTraceSize :%zd should be maxBacktraceLimit:%d, ", actualStack.backTraceSize, additionalFrame, asyncRecord.backTraceSize, maxBacktraceLimit);
    }
}

- (void)_checkAsyncStackTraceTopFrameCorrect:(XBThreadAsyncStackTraceRecord *)actualRecord asyncRecord:(XBThreadAsyncStackTraceRecord *)asyncRecord additionalFrame:(int)additionalFrame {
    Dl_info asyncRecordTopDlInfo;
    XCTAssert(asyncRecord.backTraceSize > additionalFrame);
    dladdr(asyncRecord.backTrace[additionalFrame], &asyncRecordTopDlInfo);
    Dl_info actualTopDlInfo;
    XCTAssert(actualRecord.backTraceSize > 1);
    dladdr(actualRecord.backTrace[0], &actualTopDlInfo);
    XCTAssert(asyncRecordTopDlInfo.dli_saddr == actualTopDlInfo.dli_saddr, @"asyncRecordTopDlInfo top Frame[%d]:%p,%s is not equal to actualTopDlInfo[0],%p,%s", additionalFrame, asyncRecordTopDlInfo.dli_saddr, asyncRecordTopDlInfo.dli_sname, actualTopDlInfo.dli_saddr, actualTopDlInfo.dli_sname);
}

- (void)_checkAsyncStackTraceBottomFrameCorrect:(XBThreadAsyncStackTraceRecord *)actualRecord asyncRecord:(XBThreadAsyncStackTraceRecord *)asyncRecord additionalFrame:(int)additionalFrame {
    [self _checkAsyncStackTraceTopFrameCorrect:actualRecord asyncRecord:asyncRecord additionalFrame:additionalFrame];
    for (size_t i = additionalFrame + 1; i < asyncRecord.backTraceSize; i++) {
        XCTAssert(asyncRecord.backTrace[i] == actualRecord.backTrace[i-additionalFrame], "asyncRecord backTrace[%zu]:%p is not equal to actualRecord backTrace[%zu]:%p",
                      i, asyncRecord.backTrace[i], i-additionalFrame, actualRecord.backTrace[i-additionalFrame]);
    }
}

- (void)_checkAsyncStackTraceIsCorrect:(XBThreadAsyncStackTraceRecord *)actualRecord
                       additionalFrame:(int)additionalFrame {
    XBThreadAsyncStackTraceRecord *asyncRecord = [self.asyncManager asyncTraceForPthread:pthread_self()];
    XCTAssert(asyncRecord.pthread == pthread_self());
    [self _checkAsyncStackTraceSizeCorrect:actualRecord asyncRecord:asyncRecord additionalFrame:additionalFrame];
    [self _checkAsyncStackTraceBottomFrameCorrect:actualRecord asyncRecord:asyncRecord additionalFrame:additionalFrame];
    return ;
}

- (void)_checkAsyncStackTraceIsCorrect:(XBThreadAsyncStackTraceRecord *)actualRecord {
    XBThreadAsyncStackTraceRecord *asyncRecord = [self.asyncManager asyncTraceForPthread:pthread_self()];
    int additionalFrame = [self getAdditionalFrame:actualRecord asyncRecord:asyncRecord];
    const int MaxAdditionalFrame = 10;
    XCTAssert(additionalFrame >= 0 && additionalFrame < MaxAdditionalFrame);
    [self _checkAsyncStackTraceIsCorrect:actualRecord additionalFrame:additionalFrame];
    return ;
}

- (void)checkAsyncStackTraceWithContextDict:(NSDictionary *)contextDict {
    XBThreadAsyncStackTraceRecord *actualRecord = contextDict[RECORD_KEY];
    [self _checkAsyncStackTraceIsCorrect:actualRecord];
    XCTestExpectation *expectation = contextDict[EXPECTATION_KEY];
    XCTAssert(expectation != NULL);
    [expectation fulfill];
}

- (void)testDispatchBlockAsyncBarrierAfterCanGetAsyncStackTrace {
    XBThreadAsyncStackTraceRecord *actualRecord = getCurAsyncStackTraceRecord();
    dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
    NSDictionary *dispatch_async_dict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"dispatch_async"];
    dispatch_async(queue, ^{
        [self checkAsyncStackTraceWithContextDict:dispatch_async_dict];
    });
    
    NSDictionary *dispatch_barrier_async_dict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"dispatch_barrier_async"];
    dispatch_barrier_async(queue, ^{
        [self checkAsyncStackTraceWithContextDict:dispatch_barrier_async_dict];
    });
    
    NSDictionary *dispatch_after_dict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"dispatch_after"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), queue, ^{
        [self checkAsyncStackTraceWithContextDict:dispatch_after_dict];
    });
    [self waitForXbExpectation];
}

- (void)testDispatchFuncAsyncBarrierAfterCanGetAsyncStackTrace {
    XBThreadAsyncStackTraceRecord *actualRecord = getCurAsyncStackTraceRecord();
    dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
    
    NSDictionary *dispatch_async_f_dict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"dispatch_async_f"];
    dispatch_async_f(queue, (void *)CFBridgingRetain(dispatch_async_f_dict), async_func_callback);
    
    NSDictionary *dispatch_barrier_async_f_dict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"dispatch_barrier_async_f"];
    dispatch_barrier_async_f(queue, (void *)CFBridgingRetain(dispatch_barrier_async_f_dict), async_func_callback);
    
    NSDictionary *dispatch_after_f_dict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"dispatch_after_f"];
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), queue, (void *)CFBridgingRetain(dispatch_after_f_dict), async_func_callback);
    [self waitForXbExpectation];
}

//asyncStackTrceRecord:
//0   XBAsyncStackTraceTests              0x0000000111d7e82a -[NSObject(XB_Hook_NSThreadPerformAdditions) xb_performSelector:onThread:withObject:waitUntilDone:modes:] + 378
//1   Foundation                          0x00007fff25683c24 -[NSObject(NSThreadPerformAdditions) performSelector:onThread:withObject:waitUntilDone:] + 110
//2   XBAsyncStackTraceTests              0x0000000111d7e0bf -[XBAsyncStackTraceTests testPerformSelectorCanGetAsyncStackTrace] + 559
//
//backTracePtr:
//0   XBAsyncStackTraceTests              0x0000000111d7df11 -[XBAsyncStackTraceTests testPerformSelectorCanGetAsyncStackTrace] + 129
//1   CoreFoundation                      0x00007fff23b9f95c __invoking___ + 140
- (void)_selectorThatCheckCanGetAsyncStrackTrace:(NSDictionary *)contextDict {
    [self checkAsyncStackTraceWithContextDict:contextDict];
}

- (void)testPerformSelectorCanGetAsyncStackTrace {
    XBThreadAsyncStackTraceRecord *actualRecord = getCurAsyncStackTraceRecord();
    SEL aSelector = @selector(_selectorThatCheckCanGetAsyncStrackTrace:);
    
    NSDictionary *performSelectorDict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"performSelector"];
    [self performSelector:aSelector onThread:[NSThread mainThread] withObject:performSelectorDict waitUntilDone:NO modes:@[NSDefaultRunLoopMode]];

    NSDictionary *performSelectorOnMainThreadDict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"performSelectorOnMainThread"];
    [self performSelectorOnMainThread:aSelector withObject:performSelectorOnMainThreadDict waitUntilDone:NO modes:@[NSDefaultRunLoopMode]];

    //NSThread init
    NSDictionary *performSelectorInBackgroundDict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"performSeleperformSelectorInBackgroundDictctor"];
    [self performSelectorInBackground:aSelector withObject:performSelectorInBackgroundDict ];
    
    [self waitForXbExpectation];
}

- (void)testNSOperationQueueCanGetAsyncStackTrace  {
    XBThreadAsyncStackTraceRecord *actualRecord = getCurAsyncStackTraceRecord();
    NSOperationQueue *operationQueue = [[NSOperationQueue alloc] init];

    NSDictionary *addOperationWithBlockDict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"addOperationWithBlock"];
    [operationQueue addOperationWithBlock:^{
        [self checkAsyncStackTraceWithContextDict:addOperationWithBlockDict];
    }];
#if defined(__IPHONE_13_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_13_0
    NSDictionary *addOperationWithBaiierBlockDict = [self contextDictWithActualRecord:actualRecord expectationDesc:@"addOperationWithBaiierBlock"];
        //  NSBarrierOperation, call dispatch_async
        [operationQueue addBarrierBlock:^{
            [self checkAsyncStackTraceWithContextDict:addOperationWithBaiierBlockDict];
        }];
    }
#endif
    
    NSDictionary *addOperationWithInvokeOperation = [self contextDictWithActualRecord:actualRecord expectationDesc:@"addOperationWithInvokeOperation"];
    NSInvocationOperation *invokeOperation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(checkAsyncStackTraceWithContextDict:) object:addOperationWithInvokeOperation];
    [operationQueue addOperation:invokeOperation];
    
    NSDictionary *addOperationWithBlockOperation = [self contextDictWithActualRecord:actualRecord expectationDesc:@"addOperationWithBlockOperation"];
    NSBlockOperation *blockOperation = [NSBlockOperation blockOperationWithBlock:^{
        [self checkAsyncStackTraceWithContextDict:addOperationWithBlockOperation];
    }];
    [operationQueue addOperation:blockOperation];

//{
//    NSDictionary *addOperations1 = [self contextDictWithActualRecord:actualRecord expectationDesc:@"addOperations1"];
//    NSOperation *operation1 = [NSBlockOperation blockOperationWithBlock:^{
//        [self checkAsyncStackTraceWithContextDict:addOperations1];
//    }];
//    NSDictionary *addOperations2 = [self contextDictWithActualRecord:actualRecord expectationDesc:@"addOperations2"];
//    NSOperation *operation2 = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(checkAsyncStackTraceWithContextDict:) object:addOperations2];
//
//    NSArray *operations = @[operation1, operation2];
//
//    [operationQueue addOperations:operations waitUntilFinished:NO];
//}
    [self waitForXbExpectation];
}

- (void)testNSThreadCanGetAsyncStackTrace {
    XBThreadAsyncStackTraceRecord *actualRecord = getCurAsyncStackTraceRecord();

//    detachNewThreadWithBlock use pthread with __NSThread__block_start__, now does not support.
    
//    NSDictionary *detachThreadWithBlock = [self contextDictWithActualRecord:actualRecord expectationDesc:@"detachThreadWithBlock"];
//    [NSThread detachNewThreadWithBlock:^{
//        [self checkAsyncStackTraceWithContextDict:detachThreadWithBlock];
//    }];

    NSDictionary *detachNewThreadSelector = [self contextDictWithActualRecord:actualRecord expectationDesc:@"detachNewThreadSelector"];
    [NSThread detachNewThreadSelector:@selector(checkAsyncStackTraceWithContextDict:) toTarget:self withObject:detachNewThreadSelector];
    
    NSDictionary *threadInitWithBlockDic = [self contextDictWithActualRecord:actualRecord expectationDesc:@"threadInitWithBlock"];
    NSThread *threadInitWithBlock = [[NSThread alloc] initWithBlock:^{
        [self checkAsyncStackTraceWithContextDict:threadInitWithBlockDic];
    }];
    [threadInitWithBlock start];
    
    NSDictionary *threadInitWithSelectorDic = [self contextDictWithActualRecord:actualRecord expectationDesc:@"threadInitWithSelectorDic"];
    NSThread *threadInitWithSelector= [[NSThread alloc] initWithTarget:self selector:@selector(checkAsyncStackTraceWithContextDict:) object:threadInitWithSelectorDic];
    [threadInitWithSelector start];
    
    [self waitForXbExpectation];
}

- (void)testStackLengthNotBeyondMaxBackTraceLimit {
    //make xctests coverage 100;
    int MaxBacktraceLimit = 128;
    [[XBAsyncStackTraceManager sharedInstance] setMaxBacktraceLimit:MaxBacktraceLimit];
    self.maxBacktraceLimit = self.asyncManager.maxBacktraceLimit;
    XCTAssert(self.maxBacktraceLimit == MaxBacktraceLimit);
    
    [self testPerformSelectorCanGetAsyncStackTrace];
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
    [tests checkAsyncStackTraceWithContextDict:contextDict];
}

//
//  AsyncStackTrace.h
//  AsyncStackTrace
//
//  Created by xiaobochen on 2019/2/21.
//  Copyright © 2019年 xiaobochen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XBThreadAsyncStackTraceRecord.h"
@interface XBAsyncStackTraceManager : NSObject
//default 32
@property (nonatomic, assign) int maxBacktraceLimit;
+ (instancetype)sharedInstance;
- (NSString *)getTimeCostDesc;
- (BOOL)beginHook;
- (XBThreadAsyncStackTraceRecord *)asyncTraceForPthread:(pthread_t)pthread;

@end

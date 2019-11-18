//
//  MRCFile.m
//  XBAsyncStackTraceExample
//
//  Created by xiaobochen on 2019/11/18.
//  Copyright © 2019 xiaobochen. All rights reserved.
//

#import "MRCTest.h"
#import "objc/runtime.h"
@implementation MRCTest
+ (void)runAsyncCrashOnRelease {
    MRCTest *mrcTest = [MRCTest new] ;
    NSObject *object = [NSObject new];//block capture two object, make destory helper block named __destroy_helper_block_e8_32o40o
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [object description];
        [mrcTest description];//object comes first, so it will dealloc last, which make [mrcTest dealloc] will not become tail call and __destroy_helper_block_e8_32o40o will appear on stack
    });
    [mrcTest release];
}

- (void)dealloc {
    [super dealloc];
    id object = (__bridge id)(void*)1;
    [object class];
}
@end

//
//  ViewController.m
//  AsyncStackTraceExample
//
//  Created by xiaobochen on 2019/2/21.
//  Copyright © 2019年 xiaobochen. All rights reserved.
//

#import "ViewController.h"
#include <sys/types.h>
#include <sys/sysctl.h>
#include <mach/task.h>
#include <mach/mach_init.h>
#include <mach/mach_port.h>
#import <XBASyncStackTrace/XBAsyncStackTrace-umbrella.h>
#import <pthread.h>
#import "MRCTest.h"
void sig_handler(int sig, siginfo_t *info, void *context)
{
#ifdef arm64
    ucontext_t *ucontext = (ucontext_t *)context;
    NSLog(@"signal caught 0: %d, pc 0x%llx\n", sig, ucontext->uc_mcontext->__ss.__pc);
    ucontext->uc_mcontext->__ss.__pc = ucontext->uc_mcontext->__ss.__lr;
#endif
    XBThreadAsyncStackTraceRecord *record = [[XBAsyncStackTraceManager
                                        sharedInstance] asyncTraceForPthread:pthread_self()];
    void **backTrace = record.asyncStackTrace.backTrace;
    size_t size = record.asyncStackTrace.size;
    NSLog(@"asyncStack:%zd %p\n%@", size, backTrace, [record symbolicatedBackTrace]);
    exit(1);

}
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    //breakpoint on this line and type following command to tell lldb to not stop on SIGSEGV, so that we can debug our sig_handler.
    //pro hand -p true -s false SIGSEGV
    int ret = task_set_exception_ports(
                                       mach_task_self(),
                                       EXC_MASK_CRASH|EXC_MASK_BAD_ACCESS,
                                       MACH_PORT_NULL,//m_exception_port,
                                       EXCEPTION_DEFAULT,
                                       0);
    NSLog(@"set_exception_ports:%d",ret);
    struct sigaction sa;
    memset(&sa, 0, sizeof(struct sigaction));
    sa.sa_flags = SA_SIGINFO;
    sa.sa_sigaction = sig_handler;

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGKILL, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    [[XBAsyncStackTraceManager sharedInstance] setMaxBackTraceLimit:32];
    [[XBAsyncStackTraceManager sharedInstance] beginHook];

//    [self testTimeCost];
//    [self testNSOperationQueueCrash];
//    [self testPerformSelectCrash];
//    [self testDispatchAsyncCrash];
    [MRCTest runAsyncCrashOnRelease];
//    [self testUIAnimationBlockCrash];
}
- (void)testTimeCost {
    for (int  i = 0 ; i < 100; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSLog(@"running %d test", i );
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"timeCost:\n%@", [[XBAsyncStackTraceManager sharedInstance] getTimeCostDesc]);
    });
}



- (void)callCrashFunc {
    //        void *a = calloc(1, sizeof(void *));
    //        ((void(*)())a)();
    id object = (__bridge id)(void*)1;
    [object class];
//    NSLog(@"remove this line will cause tail call optimization");
}
- (void)testDispatchAsyncCrash {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self callCrashFunc];
    });
}
- (void)testUIAnimationBlockCrash {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [UIView animateWithDuration:2 animations:^{
        dispatch_group_leave(group);
        self.view.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    } completion:^(BOOL finished) {
        XBThreadAsyncStackTraceRecord *record = [[XBAsyncStackTraceManager
                                             sharedInstance] asyncTraceForPthread:pthread_self()];
        NSLog(@"asyncStack:%@",[record symbolicatedBackTrace]);
        dispatch_group_leave(group);
    }];
}
- (void)testNSOperationQueueCrash {
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self callCrashFunc];
    }];
}
- (void)testPerformSelectCrash {
    [self performSelectorOnMainThread:@selector(callCrashFunc) withObject:nil waitUntilDone:NO];
}
- (void)testCFRunLoopAddSouce {
    
}
@end

(see this for english version .[this](#XBAsyncStackTrace_en))  
# XBAsyncStackTrace
iOS 异步堆栈回朔框架
##使用方法
使用如下代码开启异步堆栈监控，目前只支持dispatch的异步api和performSelector:onThread:withObject:waitUntilDone:modes:。

```
[[XBAsyncStackTraceManager sharedInstance] setMaxBackTraceLimit:32];//set the max back trace frame limit, default is 32.
[[XBAsyncStackTraceManager sharedInstance] beginHook];
```
在你的crash回调函数里使用如下代码获取线程的异步堆栈。

```
XBThreadAsyncTraceRecord *record = [[XBAsyncStackTraceManager sharedInstance] asyncTraceForPthread:pthread_for_crash_thread];
void **backTrace = record.asyncStackTrace.backTrace;
size_t size = record.asyncStackTrace.size;
```
## 为什么需要异步堆栈
```
- (void)callCrashFunc {
    id object = (__bridge id)(void*)1;
    [object class];
//    NSLog(@"remove this line will cause tail call optimization");
}
- (void)testDispatchAsyncCrash {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self callCrashFunc];
    });
}
```
猜下这个代码crash时候抓到的堆栈是什么。
注意:开启-O1的编译优化选项编译上面的代码(debug 默认是 -O0)

```
* thread #3, queue = 'com.apple.root.default-qos', stop reason = signal SIGSEGV
  * frame #0: 0x000000010186fd85 libobjc.A.dylib`objc_msgSend + 5
    frame #1: 0x0000000104166595 libdispatch.dylib`_dispatch_call_block_and_release + 12
    frame #2: 0x0000000104167602 libdispatch.dylib`_dispatch_client_callout + 8
    frame #3: 0x000000010416a064 libdispatch.dylib`_dispatch_queue_override_invoke + 1028
    frame #4: 0x000000010417800a libdispatch.dylib`_dispatch_root_queue_drain + 351
    frame #5: 0x00000001041789af libdispatch.dylib`_dispatch_worker_thread2 + 130
    frame #6: 0x0000000104553169 libsystem_pthread.dylib`_pthread_wqthread + 1387
    frame #7: 0x0000000104552be9 libsystem_pthread.dylib`start_wqthread + 13
```
是不是很惊奇？堆栈上全是系统函数。
实际上，由于block的最后一行是调用另外一个方法，在开启了编译优化选项的情况下，编译器会使用尾调用优化来优化这里的代码。所以最后一行 `[object class]`的汇编代码实际上会是个jump的指令而不是call指令（jump指令是直接执行指定地址的代码，call代码会把当前的执行地址压栈，对于arm来说就是b和bl这两个指令，对于x86则是j和call这两个指令）。所以实际crash地址（block的最后一行`[object class]`）是不会被存到堆栈上的，所以也就意味着这个时候去回朔堆栈是找不到当前实际crash地址的任何信息的。但是XBAsyncStackTrace会记录异步堆栈，就像Xcode在开启了堆栈记录选项（在(Product -> Scheme -> Edit Scheme）的时候会显示当前执行block是在哪里被提交给dispatch一样。下面是XBAsyncStackTrace对于上述代码记录下来的异步堆栈。

```
0   XBAsyncStackTraceExample            0x000000010c89d75c blockRecordAsyncTrace + 76
1   XBAsyncStackTraceExample            0x000000010c89d302 wrap_dispatch_async + 98
2   XBAsyncStackTraceExample            0x000000010c89c02c -[ViewController testDispatchAsyncCrash] + 92
3   XBAsyncStackTraceExample            0x000000010c89be3d -[ViewController viewDidLoad] + 269
4   UIKitCore                           0x0000000110ae44e1 -[UIViewController loadViewIfRequired] + 1186
5   UIKitCore                           0x0000000110ae4940 -[UIViewController view] + 27
```
## 原理
XBAsyncStackTrace hook了dispatch里的 async/after/barrier，包括block和func版本。在hook方法里，我们首先记录了当前的调用堆栈，然后再调用原来的dispatch系列方法，但是这里传的block参数是另外新创建的一个block,该block的代码会捕捉开头记录的调用堆栈，并且设置为当前执行线程的异步堆栈，然后再调用原来的block,执行结束后，再清除掉记录的当前线程的异步堆栈。
如果是“_f”的版本，我们会创建个新的参数记录原来的func参数，context参数，当前的调用堆栈，然后传给dispatch另外的一个函数的地址，该函数接受我们刚刚创建的新参数，获取参数中的func参数，context参数，和调用堆栈，设置当前线程的异步堆栈为获取的调用堆栈，然后使用context参数调用原来的func，最后清除当前的异步堆栈，流程和block版本一样。
在你的crash回调函数里，获取crash线程的异步堆栈，如果存在，该堆栈就是crash处的异步堆栈。
对于performSelector:onThread:withObject:waitUntilDone:modes:, 也是一样的处理。
另外对于block版本，有另外的一个优化以捕捉block在dispatch中释放导致的无堆栈crash。
考虑如下的代码。

```
+ (void)runAsyncCrashOnRelease {
    MRCTest *mrcTest = [MRCTest new] ;
    NSObject *object = [NSObject new];//block capture two object, make destory helper block named __destroy_helper_block_e8_32o40o
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [object description];
        [mrcTest description];//object comes first, so it will dealloc last, which make [mrcTest dealloc] will not become tail call and __destroy_helper_block_e8_32o40o will appear on stack
    });
    NSObject *danglingPointer = [[NSObject new] autorelease];
    objc_setAssociatedObject(mrcTest, @"danglingPointer", danglingPointer, OBJC_ASSOCIATION_RETAIN);
    [danglingPointer release];//danglingPointer was over releasd, but only crash when block release mrcTest.
    [mrcTest release];
}
```
block捕捉了mrcTest这个对象，这个对象被过度释放了，但是在block执行完毕后dispatch释放该对象的时候才会crash,可以看到crash堆栈如下。并且crash堆栈上的__destroy_helper_block_e8_32o40o，无法对应到到具体的block的，因为凡是捕捉两个对象的mrc下编写的block的dispose_helper都是这个命名。使用该地址去查找源码找到的只会是第一个捕捉两个对象的mrc下编写的block的源码。

```
* thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 6.1
    frame #0: 0x00000001000edc34 XBAsyncStackTraceExample`sig_handler(sig=<unavailable>, info=<unavailable>, context=<unavailable>) at ViewController.m:30:5 [opt]
    frame #1: 0x000000021ef619ec libsystem_platform.dylib`_sigtramp + 56
    frame #2: 0x000000021e540754 libobjc.A.dylib`_object_remove_assocations + 468
    frame #3: 0x000000021e540754 libobjc.A.dylib`_object_remove_assocations + 468
    frame #4: 0x000000021e53a6d4 libobjc.A.dylib`objc_destructInstance + 96
    frame #5: 0x000000021e53a720 libobjc.A.dylib`object_dispose + 16
  * frame #6: 0x00000001000ee454 XBAsyncStackTraceExample`__destroy_helper_block_e8_32o40o((null)=0x0000000283289890) at MRCTest.m:15:112 [opt]
    frame #7: 0x000000021edeca44 libsystem_blocks.dylib`_Block_release + 152
    frame #8: 0x00000001000f04b0 XBAsyncStackTraceExample`__blockRecordAsyncTrace_block_invoke(.block_descriptor=0x0000000282999c40) at XBAsyncStackTraceManager.m:49:18
    frame #9: 0x0000000100500c74 libdispatch.dylib`_dispatch_client_callout + 16
    frame #10: 0x0000000100503ffc libdispatch.dylib`_dispatch_continuation_pop + 524
    frame #11: 0x0000000100516610 libdispatch.dylib`_dispatch_source_invoke + 1444
    frame #12: 0x000000010050e56c libdispatch.dylib`_dispatch_main_queue_callback_4CF + 960
    frame #13: 0x000000021f2e2c1c CoreFoundation`__CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__ + 12
    frame #14: 0x000000021f2ddb54 CoreFoundation`__CFRunLoopRun + 1924
    frame #15: 0x000000021f2dd0b0 CoreFoundation`CFRunLoopRunSpecific + 436
    frame #16: 0x00000002214dd79c GraphicsServices`GSEventRunModal + 104
    frame #17: 0x000000024bb13978 UIKitCore`UIApplicationMain + 212
    frame #18: 0x00000001000ee6e0 XBAsyncStackTraceExample`main(argc=<unavailable>, argv=<unavailable>) at main.m:14:16 [opt]
    frame #19: 0x000000021eda28e0 libdyld.dylib`start + 4
```
XBAsyncStackTrace也是能捕捉这种情况的。

```
2020-01-14 16:27:19.399811+0800 XBAsyncStackTraceExample[2513:1563452] asyncStack:32 0x2800c8200
0   XBAsyncStackTraceExample            0x00000001000ef8ac wrap_dispatch_after + 220
1   XBAsyncStackTraceExample            0x00000001000ee374 +[MRCTest runAsyncCrashOnRelease] + 148
2   XBAsyncStackTraceExample            0x00000001000edd7c -[ViewController viewDidLoad] + 320
```
原理是我们在替换传给dispatch的block时候，在执行完毕原来的block的时候，强制释放该block,这样就把原有的block的释放时机提早到我们的异步堆栈捕获时机中，由于提交给dispatch的block，dispatch只会执行一次，所以逻辑上是没有问题的。代码如下：

```
    __block dispatch_block_t oriBlock = block;
    dispatch_block_t newBlock = ^(){
        XBThreadAsyncStackTraceRecord *curRecord = [XBThreadAsyncStackTraceRecord currentAsyncStackTraceRecord];
        [curRecord recordBackTrace:asyncStackTrace];
        oriBlock();
        oriBlock = nil;
       //force block dispose oriBlock, so if any crash happens inside __destroy_helper_block we can still get async stack trace.
        [curRecord popBackTrace];
     };
```
## 安装
pod 'XBAsyncStackTrace'  
XBAsyncStackTrace可以直接通过Pod安装，将上面代码添加到Podfile就可以了。
注意：XBAsyncStackTrace依赖fishhook来hook相关方法。如果你通过Pod安装XBAsyncStackTrace，Pod也会安装fishhook，如果你是直接编译源码链接，也要链接fishhook,目前工程里是直接链接了fishhook。

## XBAsyncStackTraceExample
XBAsyncStackTraceExample是一个演示如何使用XBAsyncStackTrace的例子。打开XBAsyncStackTraceExample.xcworkspace，并且在crash代码前打个断点，在lldb中输入如下指令，"pro hand -p true -s false SIGSEGV"，该指令告诉lldb忽略SIGSEGV信号，这样XBAsyncStackTraceExample的crash handler就可以捕捉到crash，你就可以调试你的crash捕捉逻辑了。可以看到在sig_handler获取并打印当前crash线程的异步堆栈。
##XBAsyncStackTraceTests
XBAsyncStackTraceTests测试了dispatch的六种情况和performSelector:onThread:withObject:waitUntilDone:情况下捕捉到的异步堆栈的正确性。代码在调用异步方法前获取当前的堆栈，在异步调用的代码里获取当前的异步堆栈，对比两个堆栈是否一致。由于我们是在hook的方法中去获取异步堆栈，所以和实际代码获取的堆栈比较的话，第一层堆栈是多余的，第二层堆栈的方法是一致的，但是偏移是有所差别的。对于performSelector:onThread:withObject:waitUntilDone:modes则是忽略前面两层堆栈。

------

# <a name="XBAsyncStackTrace_en">XBAsyncStackTrace</a>
# XBAsyncStackTrace
iOS async stack trace record
## Usage
Add the following code to begin recording async stack trace.(For now only support dispatch and performSelector:onThread:withObject:waitUntilDone:modes:)

```
[[XBAsyncStackTraceManager sharedInstance] setMaxBackTraceLimit:32];//set the max back trace frame limit, default is 32.
[[XBAsyncStackTraceManager sharedInstance] beginHook];
```
Get async stack trace in your crash handler.

```
XBThreadAsyncTraceRecord *record = [[XBAsyncStackTraceManager sharedInstance] asyncTraceForPthread:pthread_for_crash_thread];
void **backTrace = record.asyncStackTrace.backTrace;
size_t size = record.asyncStackTrace.size;
```
## Why need async stack trace
```
- (void)callCrashFunc {
    id object = (__bridge id)(void*)1;
    [object class];
//    NSLog(@"remove this line will cause tail call optimization");
}
- (void)testDispatchAsyncCrash {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self callCrashFunc];
    });
}
```
Note:compile it with -O1(debug default -O0)
Guess what stack trace will be when this code crash? 

```
* thread #3, queue = 'com.apple.root.default-qos', stop reason = signal SIGSEGV
  * frame #0: 0x000000010186fd85 libobjc.A.dylib`objc_msgSend + 5
    frame #1: 0x0000000104166595 libdispatch.dylib`_dispatch_call_block_and_release + 12
    frame #2: 0x0000000104167602 libdispatch.dylib`_dispatch_client_callout + 8
    frame #3: 0x000000010416a064 libdispatch.dylib`_dispatch_queue_override_invoke + 1028
    frame #4: 0x000000010417800a libdispatch.dylib`_dispatch_root_queue_drain + 351
    frame #5: 0x00000001041789af libdispatch.dylib`_dispatch_worker_thread2 + 130
    frame #6: 0x0000000104553169 libsystem_pthread.dylib`_pthread_wqthread + 1387
    frame #7: 0x0000000104552be9 libsystem_pthread.dylib`start_wqthread + 13
```
Surprising!  
Actually, since last line of the block inside callCrashFunc is calling another func, if compiler optimization was set, there will be a tail call optimization. So the assemble code for `[object class]` will be an jump opcode not an call opcode(for arm, it will be b versus bl, for x86, it will be j versus call).So the actual crash address will not be pushed into the stack, which means the stack trace will not contain any info about the real crash address.  
But the XBAsyncStackTrace will record the async stack trace, as the Xcode do if Queue Debugging:enable backtrace recording(Product -> Scheme -> Edit Scheme) was selected(Debug Navigator will show you the stack frame where the current running func was enqueued to the dispatch). The following shows async stack trace XBAsyncStackTrace record for the example crash.

```
0   XBAsyncStackTraceExample            0x000000010c89d75c blockRecordAsyncTrace + 76
1   XBAsyncStackTraceExample            0x000000010c89d302 wrap_dispatch_async + 98
2   XBAsyncStackTraceExample            0x000000010c89c02c -[ViewController testDispatchAsyncCrash] + 92
3   XBAsyncStackTraceExample            0x000000010c89be3d -[ViewController viewDidLoad] + 269
4   UIKitCore                           0x0000000110ae44e1 -[UIViewController loadViewIfRequired] + 1186
5   UIKitCore                           0x0000000110ae4940 -[UIViewController view] + 27
```
## How it works
We hook dispatch async/after/barrier func, both block version and func version.At the beginning of replace func, we record the call stack trace, and call original dispatch func with another block parameter, which will set the current thread's async stack trace as the stack trace recorded before, and invoke original block, clear the current thread's async stack trace at the end of block.  
If this is "_f" version, we alloc a new parameter record the func and context passed to dispatch func and current call stack trace, and pass another func to dispatch, which will accept the new parameter, set current thread's async stack trace as recorded stack trace, call original func and clear current thread's async stack trace at the end as block version.
And in your crash handler, get the thread's async stack trace.If there is one, this must be the crash func's async stack trace.  
For performSelector:onThread:withObject:waitUntilDone:modes:, it does the same thing.
## install
pod 'XBAsyncStackTrace'  
note:XBAsyncStackTrace relies on the fishhook to hook func.If you install from Pod, Pod will install fishhook too.If you link XBAsyncStackTrace library built from source, you need link fishhook too.
## Example
In XBAsyncStackTraceExample, you should run pod install first then open the workspace.And you should make a breakpoint in the project ,and print "pro hand -p true -s false SIGSEGV" in lldb, which tells lldb to not stop on SIGSEGV, so that the crash handler will catch crash while you are debugging.


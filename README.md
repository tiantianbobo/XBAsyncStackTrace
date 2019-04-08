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


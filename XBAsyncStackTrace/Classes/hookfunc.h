//
//  hookfunc.h
//  AsyncStackTrace
//
//  Created by xiaobochen on 2019/2/21.
//  Copyright © 2019年 xiaobochen. All rights reserved.
//

#ifndef hookfunc_h
#define hookfunc_h
#define USE_FISH_HOOK 1

#if USE_FISH_HOOK
#import "fishhook.h"
#define WRAP(x) wrap_##x
#define ORIFUNC(func) orig_##func
#define HOOK_FUNC(ret_type, func, ...) \
ret_type func(__VA_ARGS__); \
static ret_type WRAP(func)(__VA_ARGS__); \
static ret_type (*ORIFUNC(func))(__VA_ARGS__); \
ret_type WRAP(func)(__VA_ARGS__) {


#define BEGIN_HOOK(func) \
rebind_symbols((struct rebinding[1]){{#func, WRAP(func), (void *)&ORIFUNC(func)}}, 1);
#else

#endif
#endif /* hookfunc_h */

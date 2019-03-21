//
//  AppDelegate.h
//  XBAsyncStackTraceExample
//
//  Created by xiaobochen on 2019/3/20.
//  Copyright © 2019年 xiaobochen. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (readonly, strong) NSPersistentContainer *persistentContainer;

- (void)saveContext;


@end


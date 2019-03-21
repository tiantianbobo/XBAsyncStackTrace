//
//  XBTimeCostRecord.h
//  ASyncStackTrace
//
//  Created by xiaobochen on 2019/3/6.
//  Copyright © 2019年 xiaobochen. All rights reserved.
//

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN
typedef struct XBTimeCostStruct {
    double totalTimeCost;
    size_t totalCnt;
} XBTimeCostStruct;
@interface XBTimeCostRecord : NSObject
- (void)addTimeCost:(double)timeCost;
- (XBTimeCostStruct)getTimeCostRecord;
- (NSString *)timeCostDesc;
@end

NS_ASSUME_NONNULL_END

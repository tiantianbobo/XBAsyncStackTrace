//
//  XBTimeCostRecord.m
//  ASyncStackTrace
//
//  Created by xiaobochen on 2019/3/6.
//  Copyright © 2019年 xiaobochen. All rights reserved.
//

#import "XBTimeCostRecord.h"
#include <atomic>

@interface XBTimeCostRecord() {
    std::atomic<XBTimeCostStruct> _timeCost;

}
@end
@implementation XBTimeCostRecord
- (void)addTimeCost:(double)timeCost {
    XBTimeCostStruct current = _timeCost.load();
    XBTimeCostStruct newValue = current;
    do {
        newValue = {newValue.totalTimeCost + timeCost, newValue.totalCnt + 1};
    } while (!_timeCost.compare_exchange_weak(current, newValue));

}
- (XBTimeCostStruct)getTimeCostRecord {
    XBTimeCostStruct costRecord = _timeCost.load();
    return costRecord;
}
- (NSString *)timeCostDesc {
    XBTimeCostStruct costRecord = [self getTimeCostRecord];
    return [NSString stringWithFormat:@"%zd times, total:%f, average:%f",costRecord.totalCnt,costRecord.totalTimeCost,costRecord.totalTimeCost /costRecord.totalCnt];
}
@end

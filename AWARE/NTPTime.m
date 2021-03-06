//
//  NTPTime.m
//  AWARE
//
//  Created by Yuuki Nishiyama on 12/14/15.
//  Copyright © 2015 Yuuki NISHIYAMA. All rights reserved.
//

#import "NTPTime.h"
#import "ios-ntp.h"

@implementation NTPTime  {
//    NSTimer * uploadTimer;
    NSTimer * sensingTimer;
//    NetAssociation * netAssociation;
 }

- (instancetype)initWithSensorName:(NSString *)sensorName withAwareStudy:(AWAREStudy *)study{
    self = [super initWithSensorName:sensorName withAwareStudy:study];
    if (self) {
    }
    return self;
}

- (void) createTable{
    NSLog(@"[%@] Create Table", [self getSensorName]);
    NSString *query = [[NSString alloc] init];
    query = @"_id integer primary key autoincrement,"
    "timestamp real default 0,"
    "device_id text default '',"
    "drift real default 0," //clocks drift from ntp time
    "ntp_time real default 0," //actual ntp timestamp in milliseconds
    "UNIQUE (timestamp,device_id)";
    [super createTable:query];
}


- (BOOL)startSensor:(double)upInterval withSettings:(NSArray *)settings{
    NSLog(@"[%@] Start Device Usage Sensor", [self getSensorName]);
    sensingTimer = [NSTimer scheduledTimerWithTimeInterval:60*10
                                                    target:self
                                                  selector:@selector(getNTPTime)
                                                  userInfo:nil
                                                   repeats:YES];
    
    return YES;
}



- (BOOL)stopSensor{
    [sensingTimer invalidate];
    return YES;
}


///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////

- (void) getNTPTime {
    NetworkClock * nc = [NetworkClock sharedNetworkClock];
    NSDate * nt = nc.networkTime;
    double offset = nc.networkOffset * 1000;
    NSNumber * unixtime = [AWAREUtils getUnixTimestamp:[NSDate new]];
    NSNumber * ntpUnixtime = [AWAREUtils getUnixTimestamp:nt];
    NSMutableDictionary *dic = [[NSMutableDictionary alloc] init];
    [dic setObject:unixtime forKey:@"timestamp"];
    [dic setObject:[self getDeviceId] forKey:@"device_id"];
    [dic setObject:[NSNumber numberWithDouble:offset] forKey:@"drift"]; // real
    [dic setObject:ntpUnixtime forKey:@"ntp_time"]; // real
    [self setLatestValue:[NSString stringWithFormat:@"[%f] %@",offset, nt ]];
    [self saveData:dic];
}


@end

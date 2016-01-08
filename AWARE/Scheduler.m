//
//  Scheduler.m
//  AWARE
//
//  Created by Yuuki Nishiyama on 12/17/15.
//  Copyright © 2015 Yuuki NISHIYAMA. All rights reserved.
//

#import "Scheduler.h"
#import "AWARESchedule.h"
#import "ESMStorageHelper.h"
#import "SingleESMObject.h"

@implementation Scheduler {
    NSMutableArray * scheduleManager; // This variable manages NSTimers.
    NSString * KEY_SCHEDULE;
    NSString * KEY_TIMER;
}

- (instancetype)initWithSensorName:(NSString *)sensorName {
    self = [super initWithSensorName:@"scheduler"];
    if (self) {
//                [super setSensorName:sensorName];
        scheduleManager = [[NSMutableArray alloc] init];
        KEY_SCHEDULE = @"key_schedule";
        KEY_TIMER = @"key_timer";
    }
    return self;
}

- (BOOL)startSensor:(double)upInterval withSettings:(NSArray *)settings{
    
    ESMStorageHelper *helper = [[ESMStorageHelper alloc] init];
    [helper removeEsmTexts];
    
    // Make schdules
    //    [schedules addObject:[self getScheduleForTest]];
    AWARESchedule * drinkOne = [self getDringSchedule];
    AWARESchedule * drinkTwo = [self getDringSchedule];
    AWARESchedule * emotionOne = [self getEmotionSchedule];
    AWARESchedule * emotionTwo = [self getEmotionSchedule];
    AWARESchedule * emotionThree = [self getEmotionSchedule];
    AWARESchedule * emotionFour = [self getEmotionSchedule];
    
    // Set Notification Time using -getTargetTimeAsNSDate:hour:minute:second method.
    NSDate * now = [NSDate new];
    drinkOne.schedule = [self getTargetTimeAsNSDate:now hour:9];
    drinkTwo.schedule = [self getTargetTimeAsNSDate:now hour:1];
    emotionOne.schedule = [self getTargetTimeAsNSDate:now hour:9];
    emotionTwo.schedule = [self getTargetTimeAsNSDate:now hour:13];
    emotionThree.schedule = [self getTargetTimeAsNSDate:now hour:17];
    emotionFour.schedule = [self getTargetTimeAsNSDate:now hour:21];
    [emotionFour setScheduleType:SCHEDULE_INTERVAL_TEST];
    
//    drinkTwo.schedule =[self getTargetTimeAsNSDate:now hour:13 minute:5 second:0];
//    emotionFour.schedule = [NSDate new];//[self getTargetTimeAsNSDate:now hour:13 minute:5 second:0];
//    [emotionFour setScheduleType:SCHEDULE_INTERVAL_TEST];
    
    // Add maked schedules to schedules
    // Set a New ESMSchedule to a SchduleManager
    NSMutableArray *schedules = [[NSMutableArray alloc] init]
    ;
    [schedules addObject:drinkOne];
    [schedules addObject:drinkTwo];
    [schedules addObject:emotionOne];
    [schedules addObject:emotionTwo];
    [schedules addObject:emotionThree];
    [schedules addObject:emotionFour];
    
    for (AWARESchedule * s in schedules) {
        NSTimer * notificationTimer = [[NSTimer alloc] initWithFireDate:s.schedule
                                                               interval:[s.interval doubleValue]
                                                                 target:self
                                                               selector:@selector(scheduleAction:)
                                                               userInfo:s.scheduleId
                                                                repeats:YES];
        //https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/Timers/Articles/usingTimers.html
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        [runLoop addTimer:notificationTimer forMode:NSDefaultRunLoopMode];
        
        NSMutableDictionary * dic = [[NSMutableDictionary alloc] init];
        [dic setObject:s forKey:KEY_SCHEDULE];
        [dic setObject:notificationTimer forKey:KEY_TIMER];
        [scheduleManager addObject:dic];
//        [self scheduleAction:s.scheduleId];
    }
    return NO;
}

- (NSDate *) getTargetTimeAsNSDate:(NSDate *) nsDate
                              hour:(int) hour {
    return [self getTargetTimeAsNSDate:nsDate hour:hour minute:0 second:0];
}

- (NSDate *) getTargetTimeAsNSDate:(NSDate *) nsDate
                              hour:(int) hour
                            minute:(int) minute
                            second:(int) second {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *dateComps = [calendar components:NSYearCalendarUnit |
                                   NSMonthCalendarUnit  |
                                   NSDayCalendarUnit    |
                                   NSHourCalendarUnit   |
                                   NSMinuteCalendarUnit |
                                   NSSecondCalendarUnit fromDate:nsDate];
    [dateComps setDay:dateComps.day];
    [dateComps setHour:hour];
    [dateComps setMinute:minute];
    [dateComps setSecond:second];
    NSDate * targetNSDate = [calendar dateFromComponents:dateComps];
    // If the maked target day is newer than now, Aware remakes the target day as same time tomorrow.
    if ([targetNSDate timeIntervalSince1970] < [nsDate timeIntervalSince1970]) {
        [dateComps setDay:dateComps.day + 1];
        NSDate * tomorrowNSDate = [calendar dateFromComponents:dateComps];
        return tomorrowNSDate;
    }else{
        return targetNSDate;
    }
}


- (void) scheduleAction: (NSTimer *) sender {
    // Get a schedule ID
    NSString* scheduleId = [sender userInfo];
    // Search the target sechedule by the schedule ID
    for (NSDictionary * dic in scheduleManager) {
        AWARESchedule *schedule = [dic objectForKey:KEY_SCHEDULE];
        NSLog(@"%@ - %@", schedule.scheduleId, scheduleId);
        
        if ([schedule.scheduleId isEqualToString:scheduleId]) {
            NSString* esmStr = schedule.esmStr;
            // Add esm text to local storage
            ESMStorageHelper * helper = [[ESMStorageHelper alloc] init];
            [helper addEsmText:esmStr];
            [self sendLocalNotificationWithSchedule:schedule soundFlag:YES];
            break;
        }
    }
}

- (BOOL)stopSensor {
    for (NSDictionary * dic in scheduleManager) {
//        AWARESchedule *schedule = [dic objectForKey:KEY_SCHEDULE];
        NSTimer* timer = [dic objectForKey:KEY_TIMER];
        [timer invalidate];
    }
    scheduleManager = [[NSMutableArray alloc] init];
    ESMStorageHelper * helper = [[ESMStorageHelper alloc] init];
    [helper removeEsmTexts];
    return YES;
}

- (void) sendLocalNotificationWithSchedule : (AWARESchedule *) schedule
                                 soundFlag : (BOOL) soundFlag{
    if (schedule == nil) {
        return;
    }
    
    UILocalNotification *localNotification = [UILocalNotification new];
    CGFloat currentVersion = [[[UIDevice currentDevice] systemVersion] floatValue];
    NSLog(@"OS:%f", currentVersion);
    if (currentVersion >= 9.0){
        localNotification.alertTitle = schedule.title;
        localNotification.alertBody = schedule.body;
    } else {
        localNotification.alertBody = schedule.body;
    }
    localNotification.fireDate = [NSDate new];
    localNotification.timeZone = [NSTimeZone localTimeZone];
    localNotification.category = schedule.scheduleId;
    if(soundFlag) {
        localNotification.soundName = UILocalNotificationDefaultSoundName;
    }
    localNotification.hasAction = YES;
    [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
}


- (AWARESchedule *) getDringSchedule{
    SingleESMObject *esmObject = [[SingleESMObject alloc] init];
    NSString * deviceId = @"";
    double timestamp = 0;
    NSString * submit = @"Next";
    NSString * trigger = @"AWARE Tester";
    
    // Scale
    NSMutableDictionary *startDatePicker = [esmObject getEsmDictionaryAsDatePickerWithDeviceId:deviceId
                                                                                     timestamp:timestamp
                                                                                         title:@""
                                                                                  instructions:@"Did you drink any alcohol yesterday? If so, approximately what time did you START drinking?"
                                                                                        submit:submit
                                                                           expirationThreshold:@60
                                                                                       trigger:trigger];
    
    NSMutableDictionary *stopDatePicker = [esmObject getEsmDictionaryAsDatePickerWithDeviceId:deviceId
                                                                                    timestamp:timestamp
                                                                                        title:@""
                                                                                 instructions:@"Approximately what time did you STOP drinking?"
                                                                                       submit:submit
                                                                          expirationThreshold:@60
                                                                                      trigger:trigger];
    
    NSMutableDictionary *drinks = [esmObject getEsmDictionaryAsScaleWithDeviceId:deviceId
                                                                       timestamp:timestamp
                                                                           title:@""
                                                                    instructions:@"How many drinks did you have over this time period?"
                                                                          submit:submit
                                                             expirationThreshold:@60
                                                                         trigger:trigger
                                                                             min:@0
                                                                             max:@10
                                                                      scaleStart:@0
                                                                        minLabel:@"0"
                                                                        maxLabel:@"10"
                                                                       scaleStep:@1];
    
    // radio
    NSMutableDictionary *dicRadio = [esmObject getEsmDictionaryAsRadioWithDeviceId:deviceId
                                                                         timestamp:timestamp
                                                                             title:@""
                                                                      instructions:@"Mark any of the reasons you drink alcohol"
                                                                            submit:submit
                                                               expirationThreshold:@60
                                                                           trigger:trigger
                                                                            radios:[NSArray arrayWithObjects:@"Because it makes social events more fun", @"To forget about my problems", @"Because like the feeling", @"So I won't feel left out", @"None", @"Other", nil]];
    
    NSArray* arrayForJson = [[NSArray alloc] initWithObjects:startDatePicker, stopDatePicker, drinks, dicRadio, nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:arrayForJson options:0 error:nil];
    NSString* jsonStr =  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    AWARESchedule * schedule = [[AWARESchedule alloc] initWithScheduleId:@"drink"];
    [schedule setScheduleAsNormalWithDate:[NSDate new]
                             intervalType:SCHEDULE_INTERVAL_DAY
                                      esm:jsonStr
                                    title:@"BlancedCampus Question"
                                     body:@"Tap to answer."
                               identifier:@"---"];
    return schedule;
}



- (AWARESchedule *) getEmotionSchedule{
    //    // Likert scale
    NSString * title = @"During the past hour, I would describe myself as..."
    "(Scale: 1=Disagree strongly; 2=Disagree slightly; 3=Neither agree nor disagree; 4=Agree slightly; 5=Agree strongly)";
    NSString *title2 = @"During the past hour, I have been..."
    "(Scale: 1=Not at all; 2=Slightly; 3=Somewhat; 4=Very; 5=Extremely)";
    NSString * deviceId = @"";
    NSString * submit = @"Next";
    double timestamp = 0;
    NSNumber * exprationThreshold = [NSNumber numberWithInt:60];
    NSString * trigger = @"trigger";
    NSNumber *likertMax = @5;
    NSString *likertMaxLabel = @"3";
    NSString *likertMinLabel = @"";
    NSNumber *likertStep = @0;
    SingleESMObject *esmObject = [[SingleESMObject alloc] init];
    

    NSDictionary * quietLikert = [esmObject getEsmDictionaryAsLikertScaleWithDeviceId:deviceId
                                                                      timestamp:timestamp
                                                                          title:title
                                                                   instructions:@"Quiet, reserved"
                                                                         submit:submit
                                                            expirationThreshold:exprationThreshold
                                                                        trigger:trigger
                                                                      likertMax:likertMax
                                                                 likertMaxLabel:likertMaxLabel
                                                                 likertMinLabel:likertMinLabel
                                                                     likertStep:likertStep];
    

    NSDictionary * compassionateLikert = [esmObject getEsmDictionaryAsLikertScaleWithDeviceId:deviceId
                                                                            timestamp:timestamp
                                                                                title:@""
                                                                         instructions:@"Compassionate, has a soft heart"
                                                                               submit:submit
                                                                  expirationThreshold:exprationThreshold
                                                                              trigger:trigger
                                                                            likertMax:likertMax
                                                                       likertMaxLabel:likertMaxLabel
                                                                       likertMinLabel:likertMinLabel
                                                                           likertStep:likertStep];

    NSDictionary * disorganizedLikert = [esmObject getEsmDictionaryAsLikertScaleWithDeviceId:deviceId
                                                                               timestamp:timestamp
                                                                                   title:@""
                                                                            instructions:@"Disorganized, indifferent"
                                                                                  submit:submit
                                                                     expirationThreshold:exprationThreshold
                                                                                 trigger:trigger
                                                                               likertMax:likertMax
                                                                          likertMaxLabel:likertMaxLabel
                                                                          likertMinLabel:likertMinLabel
                                                                              likertStep:likertStep];
    

    NSDictionary * emotionallyLikert = [esmObject getEsmDictionaryAsLikertScaleWithDeviceId:deviceId
                                                                              timestamp:timestamp
                                                                                  title:@""
                                                                           instructions:@"Emotionally stable, not easily upset"
                                                                                 submit:submit
                                                                    expirationThreshold:exprationThreshold
                                                                                trigger:trigger
                                                                              likertMax:likertMax
                                                                         likertMaxLabel:likertMaxLabel
                                                                         likertMinLabel:likertMinLabel
                                                                             likertStep:likertStep];

    
    NSDictionary * interestLikert = [esmObject getEsmDictionaryAsLikertScaleWithDeviceId:deviceId
                                                                            timestamp:timestamp
                                                                                title:@""
                                                                         instructions:@"Having little interest in abstract ideas"
                                                                               submit:submit
                                                                  expirationThreshold:exprationThreshold
                                                                              trigger:trigger
                                                                            likertMax:likertMax
                                                                       likertMaxLabel:likertMaxLabel
                                                                       likertMinLabel:likertMinLabel
                                                                           likertStep:likertStep];
    
    

    NSDictionary * stressedLikert = [esmObject getEsmDictionaryAsLikertScaleWithDeviceId:deviceId
                                                                          timestamp:timestamp
                                                                              title:title2
                                                                       instructions:@"Stressed, overwhelmed"
                                                                             submit:submit
                                                                expirationThreshold:exprationThreshold
                                                                            trigger:trigger
                                                                          likertMax:likertMax
                                                                     likertMaxLabel:likertMaxLabel
                                                                     likertMinLabel:likertMinLabel
                                                                         likertStep:likertStep];
    

    NSDictionary * productiveLikert = [esmObject getEsmDictionaryAsLikertScaleWithDeviceId:deviceId
                                                                           timestamp:timestamp
                                                                               title:@""
                                                                        instructions:@"Productive, curious, focused, attentive"
                                                                              submit:submit
                                                                 expirationThreshold:exprationThreshold
                                                                             trigger:trigger
                                                                           likertMax:likertMax
                                                                      likertMaxLabel:likertMaxLabel
                                                                      likertMinLabel:likertMinLabel
                                                                          likertStep:likertStep];
    

    NSDictionary * boredLikert = [esmObject getEsmDictionaryAsLikertScaleWithDeviceId:deviceId
                                                                            timestamp:timestamp
                                                                                title:@""
                                                                         instructions:@"Bored"
                                                                               submit:submit
                                                                  expirationThreshold:exprationThreshold
                                                                              trigger:trigger
                                                                            likertMax:likertMax
                                                                       likertMaxLabel:likertMaxLabel
                                                                       likertMinLabel:likertMinLabel
                                                                           likertStep:likertStep];
                 
    
    NSDictionary * havingRadio = [esmObject getEsmDictionaryAsRadioWithDeviceId:deviceId
                                                                       timestamp:timestamp
                                                                           title:@"Arousal and Positive/Negative Affect"
                                                                    instructions:@"During the past hour, I have been having..."
                                                                          submit:submit
                                                             expirationThreshold:exprationThreshold
                                                                         trigger:trigger
                                                                          radios: [[NSArray alloc] initWithObjects:@"Low energy", @"Somewhat low energy", @"Neutral", @"Somewhat high energy", @"High Energy", nil]];
    
    NSDictionary * feeringRadio = [esmObject getEsmDictionaryAsRadioWithDeviceId:deviceId
                                                                       timestamp:timestamp
                                                                           title:@""
                                                                    instructions:@"During the past hour, I have been feeling..."
                                                                          submit:submit
                                                             expirationThreshold:exprationThreshold
                                                                         trigger:trigger
                                                                          radios: [[NSArray alloc] initWithObjects:@"Negative", @"Somewhat negative", @"Neutral", @"Somewhat positive", @"Positive", nil]];
    
    NSArray* arrayForJson = [[NSArray alloc] initWithObjects:quietLikert, compassionateLikert, disorganizedLikert,emotionallyLikert, interestLikert, stressedLikert, productiveLikert, boredLikert, havingRadio, feeringRadio, nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:arrayForJson options:0 error:nil];
    NSString* jsonStr =  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    AWARESchedule * schedule = [[AWARESchedule alloc] initWithScheduleId:@"emotion"];
    
    [schedule setScheduleAsNormalWithDate:[NSDate new]
                             intervalType:SCHEDULE_INTERVAL_DAY
                                      esm:jsonStr
                                    title:@"BlancedCampus Question"
                                     body:@"Tap to answer."
                               identifier:@"---"];
    return schedule;
}


- (AWARESchedule *)getScheduleForTest {
    NSString * deviceId = @"";
    NSString * submit = @"Next";
    double timestamp = 0;
    NSNumber * exprationThreshold = [NSNumber numberWithInt:60];
    NSString * trigger = @"trigger";
    SingleESMObject *esmObject = [[SingleESMObject alloc] init];
    
    NSMutableDictionary *dicFreeText = [esmObject getEsmDictionaryAsFreeTextWithDeviceId:deviceId
                                                                              timestamp:timestamp
                                                                                  title:@"ESM Freetext"
                                                                           instructions:@"The user can answer an open ended question." submit:submit
                                                                    expirationThreshold:exprationThreshold
                                                                                trigger:trigger];
    
    //    NSMutableDictionary *dicRadio = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *dicRadio = [esmObject getEsmDictionaryAsRadioWithDeviceId:deviceId
                                                                         timestamp:timestamp
                                                                             title:@"ESM Radio"
                                                                      instructions:@"The user can only choose one option."
                                                                            submit:submit
                                                               expirationThreshold:exprationThreshold
                                                                           trigger:trigger
                                                                            radios:[NSArray arrayWithObjects:@"Aston Martin", @"Lotus", @"Jaguar", nil]];
    
    //    NSMutableDictionary *dicCheckBox = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *dicCheckBox = [esmObject getEsmDictionaryAsCheckBoxWithDeviceId:deviceId
                                                                               timestamp:timestamp
                                                                                   title:@"ESM Checkbox"
                                                                            instructions:@"The user can choose multiple options."
                                                                                  submit:submit
                                                                     expirationThreshold:exprationThreshold
                                                                                 trigger:trigger
                                                                              checkBoxes:[NSArray arrayWithObjects:@"One", @"Two", @"Three", nil]];
    
    //    NSMutableDictionary *dicLikert = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *dicLikert = [esmObject getEsmDictionaryAsLikertScaleWithDeviceId:deviceId
                                                                                timestamp:timestamp
                                                                                    title:@"ESM Likert"
                                                                             instructions:@"User rating 1 to 5 or 7 at 1 step increments."
                                                                                   submit:submit
                                                                      expirationThreshold:exprationThreshold
                                                                                  trigger:trigger
                                                                                likertMax:@5
                                                                           likertMaxLabel:@"3"
                                                                           likertMinLabel:@""
                                                                               likertStep:@1];
    
    //    NSMutableDictionary *dicQuick = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *dicQuick = [esmObject getEsmDictionaryAsQuickAnswerWithDeviceId:deviceId
                                                                               timestamp:timestamp
                                                                                   title:@"ESM Quick Answer"
                                                                            instructions:@"One touch answer."
                                                                                  submit:submit
                                                                     expirationThreshold:exprationThreshold
                                                                                 trigger:trigger
                                                                            quickAnswers:[NSArray arrayWithObjects:@"Yes", @"No", @"Maybe", nil]];
    
    //    NSMutableDictionary *dicScale = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *dicScale = [esmObject getEsmDictionaryAsScaleWithDeviceId:deviceId
                                                                         timestamp:timestamp
                                                                             title:@"ESM Scale"
                                                                      instructions:@"Between 0 and 10 with 2 increments."
                                                                            submit:submit
                                                               expirationThreshold:exprationThreshold
                                                                           trigger:trigger
                                                                               min:@0
                                                                               max:@10
                                                                        scaleStart:@5
                                                                          minLabel:@"0"
                                                                          maxLabel:@"10"
                                                                         scaleStep:@1];
    
    //    NSMutableDictionary *datePicker = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *dicDatePicker = [esmObject getEsmDictionaryAsDatePickerWithDeviceId:deviceId
                                                                                   timestamp:timestamp
                                                                                       title:@"ESM Date Picker"
                                                                                instructions:@"The user selects date and time."
                                                                                      submit:submit
                                                                         expirationThreshold:exprationThreshold
                                                                                     trigger:trigger];
    
    
    NSArray* arrayForJson = [[NSArray alloc] initWithObjects:dicFreeText, dicRadio, dicCheckBox,dicLikert, dicQuick, dicScale, dicDatePicker, nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:arrayForJson options:0 error:nil];
    NSString* jsonStr =  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    AWARESchedule * schedule = [[AWARESchedule alloc] initWithScheduleId:@"SOME SPECIAL ID"];
    [schedule setScheduleAsNormalWithDate:[NSDate new]
                             intervalType:SCHEDULE_INTERVAL_TEST
                                      esm:jsonStr
                                    title:@"You have a ESM!"
                                     body:@"Please answer a ESM. Thank you."
                               identifier:@"---"];
    return schedule;
}



@end
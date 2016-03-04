
//
//  ESMStorageHelper.m
//  AWARE
//
//  Created by Yuuki Nishiyama on 12/24/15.
//  Copyright © 2015 Yuuki NISHIYAMA. All rights reserved.
//
//  This class helps to access a temporal esm storage on a NSUserDefault.
//

#import "ESMStorageHelper.h"
#import "MultiESMObject.h"
#import "AWAREUtils.h"
#import "AWAREEsmUtils.h"
#import "ESM.h"
#import "AWAREKeys.h"
#import "SingleESMObject.h"
#import "MultiESMObject.h"
#import "Debug.h"

@implementation ESMStorageHelper

/**
 * 
 */
- (void) addEsmText:(NSString *)esmText
             withId:(NSString *)scheduleId
            timeout:(NSNumber *)timeout{
    NSMutableArray * newEsms = [[NSMutableArray alloc] init];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray* esms  = [[NSArray alloc] initWithArray:[defaults objectForKey:@"storedEsms"]];
    if (esms == nil) {
        esms = [[NSMutableArray alloc] init];
    }
    for (NSDictionary * existingEsm in esms) {
        NSString *existingScheduleId = [existingEsm objectForKey:@"scheduleId"];
        if ([existingScheduleId isEqualToString:scheduleId]) {
            NSString* esmStr = [existingEsm objectForKey:@"esmText"];
            [self storeEsmAsTimeout:esmStr];
        }else{
            [newEsms addObject:existingEsm];
        }
    }
    
    NSMutableDictionary * dic = [[NSMutableDictionary alloc] init];
    [dic setObject:esmText forKey:@"esmText"];
    [dic setObject:scheduleId forKey:@"scheduleId"];
    [dic setObject:timeout forKey:@"timeout"];
    [newEsms addObject:dic];
    
    [defaults setObject:(NSArray *)newEsms forKey:@"storedEsms"];
}


/**
 *
 */
- (void) removeEsmTexts {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"storedEsms"];
    
    Debug * debugSensor = [[Debug alloc] initWithAwareStudy:nil];
    [debugSensor saveDebugEventWithText:@"[esms] Remove all ESMs from a temp-storage." type:DebugTypeInfo label:@""];
}


/**
 *
 */
- (void) removeEsmWithText:(NSString *)esmText {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* storedEsms  = [[NSMutableArray alloc] initWithArray:[defaults objectForKey:@"storedEsms"]];
    NSMutableArray* newEsms = [[NSMutableArray alloc] init];
    if (storedEsms != nil) {
        for (NSDictionary * esm in storedEsms) {
            NSString * storedEsmText = [esm objectForKey:@"esmText"];
            if (![storedEsmText isEqualToString:esmText]) {
                [newEsms addObject:esm];
            }
        }
        [defaults setObject:newEsms forKey:@"storedEsms"];
    }
    
    Debug * debugSensor = [[Debug alloc] initWithAwareStudy:nil];
    [debugSensor saveDebugEventWithText:@"[esms] Remove an ESM from a temp-storage." type:DebugTypeInfo label:@""];
}


/**
 *
 */
- (NSArray *) getEsmTexts {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray * array =[defaults objectForKey:@"storedEsms"];
    NSMutableArray * esms = [[NSMutableArray alloc] init];
    if (array != nil) {
        for (NSDictionary * dic in array) {
            NSString * esmText = [dic objectForKey:@"esmText"];
//            NSString * scheduleId = [dic objectForKey:@"scheduleId"];
//            NSNumber * timeout = [dic objectForKey:@"timeout"];
            [esms addObject:esmText];
        }
        return esms;
    }else{
        return nil;
    }
}



/**
 *
 */
- (void) storeEsmAsTimeout:(NSString*) esmStr {
    NSLog(@"Store a dismissed esm object");
    
    /// If the local esm storage stored some esms,(1)AWARE iOS save the answer as cancel(dismiss).
    /// In addition, (2)UI view moves to a next stored esm.
    
    /// Answers object
    NSMutableArray *answers = [[NSMutableArray alloc] init];
    
    // Create
    ESM *esm = [[ESM alloc] initWithSensorName:SENSOR_ESMS withAwareStudy:nil];
    NSNumber * answeredTime = [AWAREUtils getUnixTimestamp:[NSDate new]];
    NSString *deviceId = [esm getDeviceId];
    
    MultiESMObject * multiEsmObject = [[MultiESMObject alloc] initWithEsmText:esmStr];
    
    for (SingleESMObject * singleEsm in multiEsmObject.esms) {
        NSMutableDictionary *dic = [AWAREEsmUtils getEsmFormatDictionary:(NSMutableDictionary *)singleEsm.esmObject
                                                            withTimesmap:answeredTime
                                                                 devieId:deviceId];
        NSNumber *unixtime = [self getUnixtimeInEsm:esmStr];
        if (unixtime == nil) {
            unixtime = answeredTime;
        }
        NSLog(@"[Answer] %@ - %@", unixtime, answeredTime);
        [dic setObject:unixtime forKey:@"timestamp"];
        [dic setObject:deviceId forKey:@"device_id"];
        // set answerd timestamp with KEY_ESM_USER_ANSWER_TIMESTAMP
        [dic setObject:answeredTime forKey:KEY_ESM_USER_ANSWER_TIMESTAMP];
        // Set "expired" status to KEY_ESM_STATUS. //TODO: Check!
        [dic setObject:@3 forKey:KEY_ESM_STATUS];
        // Add the esm to answer object.
        [answers addObject:dic];
    }
    
    // Save the answers to the local storage.
    [esm saveDataWithArray:answers];

    Debug * debugSensor = [[Debug alloc] initWithAwareStudy:nil];
    [debugSensor saveDebugEventWithText:@"[esms] Save an ESM to main-storage as a timeout ESM" type:DebugTypeInfo label:@""];
    
    // Sync with AWARE database immediately
    // [esm performSelector:@selector(syncAwareDB) withObject:0 afterDelay:5];
}



/**
 *
 */
- (NSNumber *) getUnixtimeInEsm:(NSString* )jsonStr {
    /**
     * [{"esm":[{"":""},{"":""},{"":""}]}]
     * - esms -> array
     * - esm -> dictionary
     * - elements -> array
     * - element -> dictionary
     */
    NSNumber * timestamp = nil;
    NSError *writeError = nil;
    NSArray *esms = [NSJSONSerialization JSONObjectWithData:[jsonStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&writeError];
    if (writeError != nil) {
        NSLog(@"ERROR: %@", writeError.debugDescription);
        return timestamp;
    }
    for (NSDictionary * esm in esms) {
        NSDictionary * elements = [esm objectForKey:@"esm"];
        timestamp = (NSNumber *)[elements objectForKey:@"timestamp"];
    }
    return timestamp;
}

@end

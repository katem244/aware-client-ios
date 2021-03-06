//
//  LocalCoreDataStorageHelper.m
//  AWARE
//
//  Created by Yuuki Nishiyama on 2/18/16.
//  Copyright © 2016 Yuuki NISHIYAMA. All rights reserved.
//

#import "LocalCoreDataStorageHelper.h"
#import "AWAREKeys.h"

@implementation LocalCoreDataStorageHelper{
    // A key for a sensor upload marker
    NSString * KEY_SENSOR_UPLOAD_MARK;
    // A key for a losted length
    NSString * KEY_SENSOR_UPLOAD_LOSTED_TEXT_LENGTH;
    
    // A file size
    uint64_t fileSize;
    // A sensor name
    NSString * sensorName;
    
    // An array list for a buffer
    NSMutableArray * bufferArray;
    // A buffer size for an array list
    int bufferSize;
    
    // A Debug sensor
    Debug * debugSensor;
    
    // A state of file lock
    bool isLock;
    
    // Losted text length
    int lostedTextLength;
    
    NSInteger latestTextLength;
}


- (instancetype)initWithStorageName:(NSString *)name{
    if (self = [super init]) {
        // default lock state is false
        isLock = NO;
        // set sensor name
        sensorName = name;
        // make an original upload marker for each sensor
        KEY_SENSOR_UPLOAD_MARK = [NSString stringWithFormat:@"key_sensor_upload_mark_%@", sensorName];
        // make an original losted text length marker for each sensor
        KEY_SENSOR_UPLOAD_LOSTED_TEXT_LENGTH = [NSString stringWithFormat:@"key_sensor_upload_losted_text_length_%@", sensorName];
        // init buffer array
        bufferArray = [[NSMutableArray alloc] init];
        // init size of buffer
        bufferSize = 0;
        // last text length
        latestTextLength = 0;
        // create new local storage with sensor name
        [self createNewFile:sensorName];
    }
    return self;
}


///////////////////////////////////////////////////
///////////////////////////////////////////////////


/**
 * Save data to the local storage with NSArray
 * @param   NSArray A sensor data(NSDictionary) as NSArray
 * @return A resulat of data storing
 */
- (bool) saveDataWithArray:(NSArray*) array {
    if (array == nil) {
        return false;
    }
    bool result = false;
    for (NSDictionary *dic in array) {
        result = [self saveData:dic];
    }
    return result;
}


/**
 * Save data with NSDictionary
 * @param NSDictionary  A sensor data as a NSDictionary
 * @return A result of data storing
 */
- (bool) saveData:(NSDictionary *) data {
    return [self saveData:data toLocalFile:[self getSensorName]];
}



/**
 * Save data with a NSDictionary and a sensor(storage) name
 * @param NSDictionary  A sensor data as a NSDictionary
 * @param NSString      A sensor name
 * @return A result of data storing
 */
- (bool) saveData:(NSDictionary *)data toLocalFile:(NSString *)fileName{
    
    if (isLock) {
        //        NSLog(@"[%@] This sensor is Locked now!", [self getSensorName]);
        return NO;
    }
    
    [bufferArray addObject:data];
    
    if ( bufferArray.count >  bufferSize) {
        
        NSError*error=nil;
        NSData*d=[NSJSONSerialization dataWithJSONObject:bufferArray options:2 error:&error];
        NSMutableString* jsonstr = nil;
        if (!error) {
            jsonstr = [[NSMutableString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        } else {
            NSString * errorStr = [NSString stringWithFormat:@"[%@] %@", [self getSensorName], [error localizedDescription]];
            // [AWAREUtils sendLocalNotificationForMessage:errorStr soundFlag:YES];
            [self saveDebugEventWithText:errorStr type:DebugTypeError label:@""];
            return NO;
        }
        // remove head and tail object ([]) TODO check
        NSRange deleteRangeHead = NSMakeRange(0, 1);
        [jsonstr deleteCharactersInRange:deleteRangeHead];
        NSRange deleteRangeTail = NSMakeRange(jsonstr.length-1, 1);
        [jsonstr deleteCharactersInRange:deleteRangeTail];
        // append "," to the tail of object
        [jsonstr appendFormat:@","];
        
        // save the data to local storage
        [self appendLine:jsonstr];
        
        // init buffer array
        [bufferArray removeAllObjects];
    }
    return YES;
}


/**
 * Append a line to a local storage
 * @param NSString A JSON format (like) sensor data
 * @return A result of data storing
 */
- (BOOL) appendLine:(NSString *) line {
    if (!line) {
        NSLog(@"[%@] Line is null", [self getSensorName] );
        return NO;
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:[self getFilePath]];
    if (fh == nil) { // no
        NSString * fileName = [self getSensorName];
        NSString* debugMassage = [NSString stringWithFormat:@"[%@] ERROR: AWARE can not handle the file.", fileName];
        [self saveDebugEventWithText:debugMassage type:DebugTypeError label:fileName];
        return NO;
    }else{
        [fh seekToEndOfFile];
        NSData * tempdataLine = [line dataUsingEncoding:NSUTF8StringEncoding];
        [fh writeData:tempdataLine];
        
        NSString * oneLine = [[NSString alloc] initWithString:[NSString stringWithFormat:@"%@", line]];
        NSData *data = [oneLine dataUsingEncoding:NSUTF8StringEncoding];
        [fh writeData:data];
        [fh synchronizeFile];
        [fh closeFile];
        return YES;
    }
    return YES;
}



//////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////

/**
 * Get sensor data for post
 * @return sensor data for post as a text
 *
 * NOTE:
 * This method returns unformated(JSON) text.
 * For example,
 *   tamp":0,"device_id":"xxxx-xxxx-xx","value":"1234"},
 *   {"timestamp":1,"device_id":"xxxx-xxxx-xx","value":"1234"},
 *   {"timestamp":"2","device_i
 *
 * For getting formated(JSON) text, you should use -fixJsonFormat:clipedText method with the unformated text
 * The method covert a formated JSON text from the unformated text.
 * For example,
 *   {"timestamp":1,"device_id":"xxxx-xxxx-xx","value":"1234"}
 */
- (NSMutableString *) getSensorDataForPost {
    
    NSInteger maxLength = [self getMaxDateLength];
    NSInteger seek = [self getMarker] * maxLength;
    NSString * path = [self getFilePath];
    NSMutableString *data = nil;
    
    // Handle the file
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fileHandle) {
        NSString * message = [NSString stringWithFormat:@"[%@] AWARE can not handle the file.", [self getSensorName]];
        // NSLog(@"%@", message);
        [self saveDebugEventWithText:message type:DebugTypeError label:@""];
        return Nil;
    }
    
    NSLog(@"[%@] Seek point => %ld", [ self getSensorName], seek);
    
    // Set seek point with losted text
    if (seek > [self getLostedTextLength]) {
        NSInteger seekPointWithLostedText = seek-[self getLostedTextLength];
        if (seekPointWithLostedText < 0) {
            seekPointWithLostedText = seek;
        }
        [fileHandle seekToFileOffset:seekPointWithLostedText];
    }else{
        [fileHandle seekToFileOffset:seek];
    }
    
    // Clip text with max length
    NSData *clipedData = [fileHandle readDataOfLength:maxLength];
    [fileHandle closeFile];
    
    // Make NSString from NSData object
    data = [[NSMutableString alloc] initWithData:clipedData encoding:NSUTF8StringEncoding];
    
    latestTextLength = data.length;
    
    return data;
}


/**
 * Convert an unformated JSON text to a formated JSON text.
 * @param   NSString    An unformated JSON text
 * @return  NSString    A formated JSON text
 *
 * For example,
 * [Before: Unformated JSON Text]
 *   tamp":0,"device_id":"xxxx-xxxx-xx","value":"1234"},
 *   {"timestamp":1,"device_id":"xxxx-xxxx-xx","value":"1234"},
 *   {"timestamp":"2","device_i
 *
 * [After: Formated JSON Text]
 *   {"timestamp":1,"device_id":"xxxx-xxxx-xx","value":"1234"}
 *
 * NOTE: The lotest text length is stored after success to data upload by -setLostedTextLength:length.
 */
- (NSMutableString *) fixJsonFormat:(NSMutableString *) clipedText {
    // head
    if ([clipedText hasPrefix:@"{"]) {
    }else{
        NSRange rangeOfExtraText = [clipedText rangeOfString:@"{"];
        if (rangeOfExtraText.location == NSNotFound) {
            // NSLog(@"[HEAD] There is no extra text");
        }else{
            // NSLog(@"[HEAD] There is some extra text!");
            NSRange deleteRange = NSMakeRange(0, rangeOfExtraText.location);
            [clipedText deleteCharactersInRange:deleteRange];
        }
    }
    
    // tail
    if ([clipedText hasSuffix:@"}"]){
    }else{
        NSRange rangeOfExtraText = [clipedText rangeOfString:@"}" options:NSBackwardsSearch];
        if (rangeOfExtraText.location == NSNotFound) {
            // NSLog(@"[TAIL] There is no extra text");
            lostedTextLength = 0;
        }else{
            // NSLog(@"[TAIL] There is some extra text!");
            NSRange deleteRange = NSMakeRange(rangeOfExtraText.location+1, clipedText.length-rangeOfExtraText.location-1);
            [clipedText deleteCharactersInRange:deleteRange];
            lostedTextLength = (int)deleteRange.length;
        }
    }
    [clipedText insertString:@"[" atIndex:0];
    [clipedText appendString:@"]"];
    // NSLog(@"%@", clipedText);
    return clipedText;
}



//////////////////////////////////////
//////////////////////////////////////

- (uint64_t) getFileSize{
    return [self getFileSizeWithName:sensorName];
}

- (uint64_t) getFileSizeWithName:(NSString*) name {
    NSString * path = [self getFilePathWithName:name];
    return [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
}

- (NSInteger) getMaxDateLength {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSInteger length = [userDefaults integerForKey:KEY_MAX_DATA_SIZE];
    return length;
}

///////////////////////////////////////
///////////////////////////////////////

/**
 * Set a next progress maker to local default storage
 */
- (void) setNextMark {
    NSLog(@"[%@] Line lenght is %llu", [self getSensorName], [self getFileSize]);
    if(latestTextLength < [self getMaxDateLength]){
        [self setMarker:0];
        [self setLostedTextLength:0];
    }else{
        [self setMarker:[self getMarker]+1];
        [self setLostedTextLength:lostedTextLength];
    }
}

/**
 * Reset a progress maker with zero(0)
 */
- (void) restMark {
    [self setMarker:0];
}


/**
 * Get a current progress marker for data upload from local default storage.
 * @return int A current progress maker for data upload
 */
- (int) getMarker {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSNumber * number = [NSNumber numberWithInteger:[userDefaults integerForKey:KEY_SENSOR_UPLOAD_MARK]];
    return number.intValue;
}


/**
 * Set a current progress marker for data upload to local default storage.
 * @param   int   A progress marker for data upload
 */
- (void) setMarker:(int) intMarker {
    if (intMarker <= 0) {
        intMarker = 0;
    }
    NSNumber * number = [NSNumber numberWithInt:intMarker];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:number.integerValue forKey:KEY_SENSOR_UPLOAD_MARK];
}



////////////////////////////////////////////////
////////////////////////////////////////////////

- (int) getLostedTextLength{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSNumber * number = [NSNumber numberWithInteger:[userDefaults integerForKey:KEY_SENSOR_UPLOAD_LOSTED_TEXT_LENGTH]];
    return number.intValue;
}

- (void) setLostedTextLength:(int)lostedTextLength {
    NSNumber * number = [NSNumber numberWithInt:lostedTextLength];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:number.integerValue forKey:KEY_SENSOR_UPLOAD_LOSTED_TEXT_LENGTH];
}



//////////////////////////////////////////////
///////////////////////////////////////////////

/**
 * Get a file path of a text file based storage on iOS device
 * [NOTE]
 * This method return a path with a sensor name which is from -getSensorName method.
 * If you want to use special name, you should use -getFilePathWithName:name method.
 * @return NSString     A file path of a text file based storage
 */
- (NSString *) getFilePath {
    return [self getFilePathWithName:[self getSensorName]];
}


/**
 * Get a file path of a text file based storage on iOS device
 * @param   NSString    A name for a text file based storage
 * @return  NSString    A file path of a text file based storage
 */
- (NSString *) getFilePathWithName:(NSString *) name {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString * path = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.dat",name]];
    return path;
}

///////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////


/**
 * Create a new text file as a local storage.
 * @param   NSString  A file name of local storage
 * @return  A result of data storing
 */
-(BOOL)createNewFile:(NSString*) fileName {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString * path = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.dat",fileName]];
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:path]) { // yes
        BOOL result = [manager createFileAtPath:path
                                       contents:[NSData data]
                                     attributes:nil];
        if (!result) {
            NSLog(@"[%@] Failed to create the file.", fileName);
            return NO;
        }else{
            NSLog(@"[%@] Create the file.", fileName);
            return YES;
        }
    }
    return NO;
}


///////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////
/**
 * Clear data from a local storage with a file name
 * @param   NSStr   ing    A file name for a local storage
 * @return  A result of data clearing
 */
- (bool) clearFile:(NSString *) fileName {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString * path = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.dat",fileName]];
    if ([manager fileExistsAtPath:path]) { // yes
        bool result = [@"" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
        if (result) {
            NSLog(@"[%@] Correct to clear sensor data.", fileName);
            return YES;
        }else{
            NSLog(@"[%@] Error to clear sensor data.", fileName);
            return NO;
        }
    }else{
        NSLog(@"[%@] The file is not exist.", fileName);
        [self createNewFile:fileName];
        return NO;
    }
    return NO;
}




////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////

/// Utils

- (bool)saveDebugEventWithText:(NSString *)eventText
                          type:(NSInteger)type
                         label:(NSString *)label{
    if (debugSensor != nil) {
        [debugSensor saveDebugEventWithText:eventText type:type label:label];
        return  YES;
    }
    return NO;
}

- (void) trackDebugEventsWithDebugSensor:(Debug*)debug{
    debugSensor = debug;
}


- (NSString *) getSensorName {
    if (sensorName == nil) {
        return @"";
    }
    return sensorName;
}



- (void) dbLock { isLock = YES; }


- (void) dbUnlock { isLock = NO; }


- (void)setBufferSize:(int)size{
    if (size >= 0 ) {
        bufferSize = size;
    }else{
        bufferSize = 0;
    }
}


/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////
/**
 * ===========
 * For CoreData
 * ===========
 */
#pragma mark - Core Data stack

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;

- (NSURL *)applicationDocumentsDirectory {
    // The directory the application uses to store the Core Data store file. This code uses a directory named "jp.ac.keio.sfc.ht.tetujin.AWARE" in the application's documents directory.
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (NSManagedObjectModel *)managedObjectModel {
    // The managed object model for the application. It is a fatal error for the application not to be able to find and load its model.
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
//    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"[sensor]" withExtension:@"momd"];
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:[self getSensorName] withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    // The persistent store coordinator for the application. This implementation creates and returns a coordinator, having added the store for the application to it.
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }

    // Create the coordinator and store
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
//    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"[sensor].sqlite"];
    NSString *storageName = [NSString stringWithFormat:@"%@.sqlite", [self getSensorName]];
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:storageName];
    NSError *error = nil;
    NSString *failureReason = @"There was an error creating or loading the application's saved data.";
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        // Report any error we got.
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[NSLocalizedDescriptionKey] = @"Failed to initialize the application's saved data";
        dict[NSLocalizedFailureReasonErrorKey] = failureReason;
        dict[NSUnderlyingErrorKey] = error;
        error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN" code:9999 userInfo:dict];
        // Replace this with code to handle the error appropriately.
        // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }

    return _persistentStoreCoordinator;
}


- (NSManagedObjectContext *)managedObjectContext {
    // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.)
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }

    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (!coordinator) {
        return nil;
    }
    _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    return _managedObjectContext;
}

#pragma mark - Core Data Saving support

- (void)saveContext {
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        NSError *error = nil;
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
            // Replace this implementation with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }
}


@end


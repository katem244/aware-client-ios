//
//  bluetooth.m
//  AWARE
//
//  Created by Yuuki Nishiyama on 11/24/15.
//  Copyright © 2015 Yuuki NISHIYAMA. All rights reserved.
//
//  NOTE: This sensor can scan BLE devices' UUID. Those UUIDs not unique.
//

#import "Bluetooth.h"

@implementation Bluetooth {
    MDBluetoothManager * mdBluetoothManager;
    NSTimer * scanTimer;
    int scanDuration;
    int defaultScanInterval;
    NSDate * sessionTime;
    
    NSString * KEY_BLUETOOTH_TIMESTAMP;
    NSString * KEY_BLUETOOTH_DEVICE_ID;
    NSString * KEY_BLUETOOTH_ADDRESS;
    NSString * KEY_BLUETOOTH_NAME;
    NSString * KEY_BLUETOOTH_RSSI;
    NSString * KEY_BLUETOOTH_LABLE;
}

- (instancetype)initWithSensorName:(NSString *)sensorName withAwareStudy:(AWAREStudy *)study{
    self = [super initWithSensorName:sensorName withAwareStudy:study];
    if (self) {
        mdBluetoothManager = [MDBluetoothManager sharedInstance];
        scanDuration = 30; // 30 second
        defaultScanInterval = 60*5; // 5 min
        sessionTime = [NSDate new];
        
        KEY_BLUETOOTH_TIMESTAMP = @"timestamp";
        KEY_BLUETOOTH_DEVICE_ID = @"device_id";
        KEY_BLUETOOTH_ADDRESS = @"bt_address";
        KEY_BLUETOOTH_NAME = @"bt_name";
        KEY_BLUETOOTH_RSSI = @"bt_rssi";
        KEY_BLUETOOTH_LABLE = @"label";
    }
    return self;
}

- (void) createTable{
    // Send a table create query (for both BLE and classic Bluetooth)
    NSLog(@"[%@] Create Table", [self getSensorName]);
    
    NSMutableString * query = [[NSMutableString alloc] init];
    [query appendString:@"_id integer primary key autoincrement,"];
    [query appendFormat:@"%@ real default 0,", KEY_BLUETOOTH_TIMESTAMP];
    [query appendFormat:@"%@ text default '',", KEY_BLUETOOTH_DEVICE_ID];
    [query appendFormat:@"%@ text default '',", KEY_BLUETOOTH_ADDRESS];
    [query appendFormat:@"%@ text default '',", KEY_BLUETOOTH_NAME];
    [query appendFormat:@"%@ real default 0,", KEY_BLUETOOTH_RSSI];
    [query appendFormat:@"%@ text default '',", KEY_BLUETOOTH_LABLE];
    [query appendFormat:@"UNIQUE (timestamp,device_id)"];
    
    [super createTable:query];
}


- (BOOL)startSensor:(double)upInterval withSettings:(NSArray *)settings{

    double interval = [self getSensorSetting:settings withKey:@"frequency_bluetooth"];
    if (interval <= 0) {
        interval = defaultScanInterval;
    }
    
    scanTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                 target:self
                                               selector:@selector(startToScanBluetooth:)
                                               userInfo:nil
                                                repeats:YES];
    [scanTimer fire];
    
    // Init a CBCentralManager for sensing BLE devices
    NSLog(@"[%@] Start BLE Sensor", [self getSensorName]);
//    _myCentralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
//    [_myCentralManager performSelector:@selector(stopScan) withObject:nil afterDelay:scanDuration];
    
    // Set notification events for scanning classic bluetooth devices
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bluetoothDeviceDiscoveredNotification:) name:@"BluetoothDeviceDiscoveredNotification" object:nil];

    
    return YES;
}

- (BOOL) stopSensor {
    // Stop a scan ble devices by CBCentralManager
    [_myCentralManager stopScan];
    _myCentralManager = nil;
    
    // Stop the scan timer for the classic bluetooth
    [scanTimer invalidate];
    scanTimer = nil;
    // Stop scanning classic bluetooth
    [mdBluetoothManager endScan];
    // remove notification observer from notification center
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"BluetoothDeviceDiscoveredNotification" object:nil];
    
    return YES;
}

- (BOOL)syncAwareDBInForeground{
    return [super syncAwareDBInForeground];
}

////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////


- (void) saveBluetoothDeviceWithAddress:(NSString *) address
                                   name:(NSString *) name
                                   rssi:(NSNumber *) rssi{
    if (name == nil) name = @"";
    if (address == nil ) address = @"";
    if (rssi == nil) rssi = @-1;
    
    NSNumber * unixtime = [AWAREUtils getUnixTimestamp:[NSDate new]];
    NSMutableDictionary *dic = [[NSMutableDictionary alloc] init];
    [dic setObject:unixtime forKey:@"timestamp"];
    [dic setObject:[self getDeviceId] forKey:@"device_id"];
    [dic setObject:address forKey:@"bt_address"]; //varchar
    [dic setObject:name forKey:@"bt_name"]; //text
    [dic setObject:rssi  forKey:@"bt_rssi"]; //int
    [dic setObject:[[AWAREUtils getUnixTimestamp:sessionTime] stringValue] forKey:@"label"]; //text
    [self setLatestValue:[NSString stringWithFormat:@"%@(%@), %@", name, address,rssi]];
    [self saveData:dic toLocalFile:SENSOR_BLUETOOTH];
    
    if ([self isDebug]) {
        [AWAREUtils sendLocalNotificationForMessage:[NSString stringWithFormat:@"Find a new Blueooth device! %@ (%@)", name, address] soundFlag:NO];
    }
}



/////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////
// For Classic Bluetooth


/**
 * @param   sender  A NSTimer sender
 * @discussion  Start to scan the claasic blueooth devices with private APIs. Also, the method is called by NSTimer class which is initialized at the startSensor method in Bluetooth sensor.
 */
-(void)startToScanBluetooth:(id)sender{
    // Set up for a classic bluetooth
    if (![mdBluetoothManager bluetoothIsPowered]) {
        [mdBluetoothManager turnBluetoothOn];
    }
    
    _peripherals = [[NSMutableArray alloc] init];
    sessionTime = [NSDate new];
    
    // start scanning classic bluetooth devices.
    if (![mdBluetoothManager isScanning]) {
        NSString *scanStartMessage = [NSString stringWithFormat:@"Start scanning Bluetooth devices during %d second!", scanDuration];
        NSLog(@"...Start scanning Bluetooth devices.");
        if ([self isDebug]){
           [AWAREUtils sendLocalNotificationForMessage:scanStartMessage soundFlag:NO];
        }
        // start to scan Bluetooth devices
        [mdBluetoothManager startScan];
        // stop to scan Bluetooth devies after "scanDuration" second.
        [self performSelector:@selector(stopToScanBluetooth) withObject:0 afterDelay:scanDuration];
        NSLog(@"...After %d second, the Blueooth scan will be end.", scanDuration);
    }
    
    
    // start scanning ble devices.
    _myCentralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    [_myCentralManager performSelector:@selector(stopScan) withObject:nil afterDelay:scanDuration];
}


- (void) stopToScanBluetooth {
    if ([self isDebug]){
        [AWAREUtils sendLocalNotificationForMessage:@"Stop scanning Bluetooth devices!" soundFlag:NO];
    }
    
    [mdBluetoothManager endScan];
}

- (void)receivedBluetoothNotification:(MDBluetoothNotification)bluetoothNotification{
    switch (bluetoothNotification) {
        case MDBluetoothPowerChangedNotification:
            NSLog(@"changed");
            break;
        case MDBluetoothDeviceUpdatedNotification:
            NSLog(@"update");
            break;
        case MDBluetoothDeviceRemovedNotification:
            NSLog(@"remove");
            break;
        case MDBluetoothDeviceDiscoveredNotification:
            NSLog(@"discoverd");
            break;
        default:
            break;
    }
}

- (void)bluetoothDeviceDiscoveredNotification:(NSNotification *)notification{
    NSLog(@"%@", notification.description);
    
    // save a bluetooth device information
    BluetoothDevice * bluetoothDevice = notification.object;
    NSString* address = bluetoothDevice.address;
    NSString* name = bluetoothDevice.name;
    if (address == nil) address = @"";
    if (name == nil) name = @"";
    
    [self saveBluetoothDeviceWithAddress:address name:name rssi:@-1];
}

////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
// For BLE

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
//    NSLog(@"centralManagerDidUpdateState");
    if([central state] == CBCentralManagerStatePoweredOff){
        NSLog(@"CoreBluetooth BLE hardware is powered off");
    }else if([central state] == CBCentralManagerStatePoweredOn){
        NSLog(@"CoreBluetooth BLE hardware is powered on");
        NSArray *services = @[
                            [CBUUID UUIDWithString:BATTERY_SERVICE],
                            [CBUUID UUIDWithString:BODY_COMPOSITION_SERIVCE],
                            [CBUUID UUIDWithString:CURRENT_TIME_SERVICE],
                            [CBUUID UUIDWithString:DEVICE_INFORMATION],
                            [CBUUID UUIDWithString:ENVIRONMENTAL_SENSING],
                            [CBUUID UUIDWithString:GENERIC_ACCESS],
                            [CBUUID UUIDWithString:GENERIC_ATTRIBUTE],
                            [CBUUID UUIDWithString:MEASUREMENT],
                            [CBUUID UUIDWithString:BODY_LOCATION],
                            [CBUUID UUIDWithString:MANUFACTURER_NAME],
                            [CBUUID UUIDWithString:HEART_RATE_UUID],
                            [CBUUID UUIDWithString:HTTP_PROXY_UUID],
                            [CBUUID UUIDWithString:HUMAN_INTERFACE_DEVICE],
                            [CBUUID UUIDWithString:INDOOR_POSITIONING],
                            [CBUUID UUIDWithString:LOCATION_NAVIGATION ],
                            [CBUUID UUIDWithString:PHONE_ALERT_STATUS],
                            [CBUUID UUIDWithString:REFERENCE_TIME],
                            [CBUUID UUIDWithString:SCAN_PARAMETERS],
                            [CBUUID UUIDWithString:TRANSPORT_DISCOVERY],
                            [CBUUID UUIDWithString:USER_DATA],
                            [CBUUID UUIDWithString:@"AA80"]
                              ];
        [central scanForPeripheralsWithServices:services options:nil];
    }else if([central state] == CBCentralManagerStateUnauthorized){
        NSLog(@"CoreBluetooth BLE hardware is unauthorized");
    }else if([central state] == CBCentralManagerStateUnknown){
        NSLog(@"CoreBluetooth BLE hardware is unknown");
    }else if([central state] == CBCentralManagerStateUnsupported){
        NSLog(@"CoreBluetooth BLE hardware is unsupported on this platform");
    }
}




- (void) centralManager:(CBCentralManager *)central
  didDiscoverPeripheral:(CBPeripheral *)peripheral
      advertisementData:(NSDictionary *)advertisementData
                   RSSI:(NSNumber *)RSSI {
    NSLog(@"Discovered %@", peripheral.name);
    NSLog(@"UUID %@", peripheral.identifier);
    NSLog(@"%@", peripheral);
    NSString *name = peripheral.name;
    NSString *uuid = peripheral.identifier.UUIDString;
    
    [self saveBluetoothDeviceWithAddress:uuid name:name rssi:RSSI];
    
    [_peripherals addObject:peripheral];
    [_myCentralManager connectPeripheral:peripheral options:nil];
    
}


- (void) centralManager:(CBCentralManager *) central
   didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Peripheral connected");
    peripheral.delegate = self;
    [peripheral readRSSI];
    [peripheral discoverServices:nil];
}


- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    for (CBService *service in peripheral.services) {
//        NSLog(@"Discoverd serive %@", service.UUID);
        if ([service.UUID isEqual:[CBUUID UUIDWithString:@"180A"]]) {
            [peripheral discoverCharacteristics:nil forService:service];
        }
    }
}


- (void) peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    for (CBCharacteristic *characteristic in service.characteristics ) {
//        NSLog(@"Discovered characteristic: %@(%@)",characteristic.UUID,characteristic.UUID.UUIDString);
//        Manufacturer Name String(2A29)
//        Model Number String(2A24)
//        Serial Number String(2A25)
//        Hardware Revision String(2A27)
//        Firmware Revision String(2A26)
//        Software Revision String(2A28)
//        System ID(2A23)
       if([characteristic.UUID isEqual:[CBUUID UUIDWithString:@"2A25"]]) {
//            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
            [peripheral readValueForCharacteristic:characteristic];
        }
    }
}



- (CBCharacteristic *) getCharateristicWithUUID:(NSString *)uuid from:(CBService *) cbService
{
    for (CBCharacteristic *characteristic in cbService.characteristics) {
        if([characteristic.UUID isEqual:[CBUUID UUIDWithString:uuid]]){
            return characteristic;
        }
    }
    return nil;
}


- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
             error:(NSError *)error
{
    NSString * serialNumber = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
//    NSLog(@"%@", peripheral);
    NSString *name = [NSString stringWithFormat:@"%@ (%@)", peripheral.name, serialNumber];
    NSString *uuid = peripheral.identifier.UUIDString;
    NSNumber *rssi = peripheral.RSSI;
    NSLog(@"%@", name);
    [self saveBluetoothDeviceWithAddress:uuid name:name rssi:rssi];
    
}


- (void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error{

}



@end

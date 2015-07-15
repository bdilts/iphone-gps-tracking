//
//  AICLocationTracker.m
//  Gathr
//
//  Created by David Lui on 6/28/14.
//  Copyright (c) 2014 Softaic. All rights reserved.
//

#import "AICLocationTracker.h"

#define LATITUDE @"latitude"
#define LONGITUDE @"longitude"
#define ACCURACY @"theAccuracy"

@implementation AICLocationTracker

+ (CLLocationManager *)sharedLocationManager
{
	static CLLocationManager *_locationManager;
	
	@synchronized(self) {
		if (_locationManager == nil) {
            
			_locationManager = [[CLLocationManager alloc] init];
            [_locationManager setPausesLocationUpdatesAutomatically:YES];
            [_locationManager setDesiredAccuracy:kCLLocationAccuracyNearestTenMeters];
		}
	}
    
	return _locationManager;
}


- (id)init
{
    NSLog(@"AICLocationTracker init:");
    
	if (self == [super init]) {
        _mode = NO; // normal tracking
    }
    
	return self;
}

- (id)initWithBackgroundTrackingEnabled:(BOOL)backgroundTrackingEnabled
{
    NSLog(@"AICLocationTracker initWithBackgroundTrackingEnabled: %d", backgroundTrackingEnabled);
    
    self = [self init];
    if (self && backgroundTrackingEnabled) {
        //Get the share model and also initialize myLocationArray
        self.shareModel = [LocationShareModel sharedModel];
        self.shareModel.myLocationArray = [[NSArray alloc]init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

- (void)startLocationTracking
{
    NSLog(@"AICLocationTracker startLocationTracking:");
    
    if ([CLLocationManager locationServicesEnabled] == NO) {
        NSLog(@"locationServicesEnabled false");
		UIAlertView *servicesDisabledAlert = [[UIAlertView alloc] initWithTitle:@"Location Services Disabled" message:@"You currently have all location services for this device disabled" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[servicesDisabledAlert show];
        
	} else {
        CLAuthorizationStatus authorizationStatus= [CLLocationManager authorizationStatus];
        
        if (authorizationStatus == kCLAuthorizationStatusDenied || authorizationStatus == kCLAuthorizationStatusRestricted) {
            NSLog(@"authorizationStatus failed");
        } else {
            NSLog(@"authorizationStatus authorized");
            [self setLocationManager];
        }
	}
}

- (void)stopLocationTracking
{
    NSLog(@"AICLocationTracker stopLocationTracking:");
    
    if (self.shareModel.timer) {
        [self.shareModel.timer invalidate];
        self.shareModel.timer = nil;
    }
    CLLocationManager *locationManager = [AICLocationTracker sharedLocationManager];
    if ( !_mode ) [locationManager stopUpdatingLocation]; // normal location tracking
    else [locationManager stopMonitoringSignificantLocationChanges]; // significant location tracking
}

- (void)applicationEnterBackground
{
    NSLog(@"AICLocationTracker applicationEnterBackground:");
    
    [self setLocationManager];
    //Use the BackgroundTaskManager to manage all the background Task
    self.shareModel.bgTask = [BackgroundTaskManager sharedBackgroundTaskManager];
    [self.shareModel.bgTask beginNewBackgroundTask];
}

- (void)restartLocationUpdates
{
    NSLog(@"AICLocationTracker restartLocationUpdates:");
    
    if (self.shareModel.timer) {
        [self.shareModel.timer invalidate];
        self.shareModel.timer = nil;
    }
    
    [self setLocationManager];
}

- (void)setLocationManager
{
    CLLocationManager *locationManager = [AICLocationTracker sharedLocationManager];
    [locationManager setDelegate:self];
    //[locationManager setDesiredAccuracy:kCLLocationAccuracyBestForNavigation];
    [locationManager setDesiredAccuracy:kCLLocationAccuracyNearestTenMeters];
    [locationManager setDistanceFilter:kCLDistanceFilterNone];
    
    if ( !_mode ) [locationManager startUpdatingLocation]; // normal location tracking
    else [locationManager startMonitoringSignificantLocationChanges]; // significant location tracking
}

//==================================================
// CLLocationManager Delegate Methods
//==================================================
#pragma mark- CLLocationManager Delegate Methods
//==================================================
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    NSLog(@"AICLocationTracker didUpdateLocations: %d", (int)locations.count);
    
    [self clearOldLocations];
    
    for (int i=0; i<locations.count; i++){
        CLLocation * newLocation = [locations objectAtIndex:i];
        CLLocationCoordinate2D theLocation = newLocation.coordinate;
        CLLocationAccuracy theAccuracy = newLocation.horizontalAccuracy;
        
        NSTimeInterval locationAge = -[newLocation.timestamp timeIntervalSinceNow];
        
        if (locationAge > 30.0) continue;
        
        // Select only valid location and also location with good accuracy
        if (newLocation != nil  &&  theAccuracy > 0  &&  theAccuracy < 2000  &&  (!(theLocation.latitude==0.0 && theLocation.longitude==0.0))) {
            _myLastLocation = theLocation;
            _myLastLocationAccuracy= theAccuracy;
            
            NSMutableDictionary * dict = [[NSMutableDictionary alloc]init];
            [dict setObject:[NSNumber numberWithFloat:theLocation.latitude] forKey:LATITUDE];
            [dict setObject:[NSNumber numberWithFloat:theLocation.longitude] forKey:LONGITUDE];
            [dict setObject:[NSNumber numberWithFloat:theAccuracy] forKey:ACCURACY];
            
            // Add the vallid location with good accuracy into an array
            // Every 1 minute, I will select the best location based on accuracy and send to server
            self.shareModel.myLocationArray = [self.shareModel.myLocationArray arrayByAddingObject:dict];
        }
    }

    id<AICLocationTrackerDelegate> strongDelegate = self.delegate;
    if ([strongDelegate respondsToSelector:@selector(AICLocationTracker:didUpdateLocations:)]) {
        [strongDelegate AICLocationTracker:self didUpdateLocations:@[]];
    }

    // If the timer still valid, return it (Will not run the code below)
    if (self.shareModel.timer) return;
    
    self.shareModel.bgTask = [BackgroundTaskManager sharedBackgroundTaskManager];
    [self.shareModel.bgTask beginNewBackgroundTask];
    
    // Restart the locationMaanger after 1 minute
    self.shareModel.timer = [NSTimer scheduledTimerWithTimeInterval:60 target:self
                                                           selector:@selector(restartLocationUpdates)
                                                           userInfo:nil
                                                            repeats:NO];
    [self stopLocationDelayByXSeconds];
    /*
    // Will only stop the locationManager after 10 seconds, so that we can get some accurate locations
    // The location manager will only operate for 10 seconds to save battery
    NSTimer * delayXSeconds;
    delayXSeconds = [NSTimer scheduledTimerWithTimeInterval:10 target:self
                                                    selector:@selector(stopLocationDelayByXSeconds)
                                                    userInfo:nil
                                                     repeats:NO]; */
}

- (void)locationManager: (CLLocationManager *)manager didFailWithError: (NSError *)error
{
    switch ([error code]) {
        case kCLErrorNetwork: // general, network-related error
        {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Network Error" message:@"Please check your network connection." delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil, nil];
            [alert show];
        }
            break;
        case kCLErrorDenied:{
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Enable Location Service" message:@"You have to enable the Location Service to use this App. To enable, please go to Settings->Privacy->Location Services" delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil, nil];
            [alert show];
        }
            break;
        default:
            break;
    }
}

// Stop the locationManager
- (void)stopLocationDelayByXSeconds
{
    NSLog(@"AICLocationTracker stopLocationDelayByXSeconds:");
    CLLocationManager *locationManager = [AICLocationTracker sharedLocationManager];
    if ( !_mode ) [locationManager stopUpdatingLocation]; // normal location tracking
    else [locationManager stopMonitoringSignificantLocationChanges]; // significant location tracking

    // First time, set normal location tracking to get current location in every case
    // Second time, set significant location tracking
    if ( !_mode ) _mode = YES;
    //NSLog(@"locationManager stop Updating after 10 seconds");
}

// Get the best location
- (CLLocationCoordinate2D)getBestLocation
{
    NSLog(@"AICLocationTracker getBestLocation : %d", (int)self.shareModel.myLocationArray.count);
    
    // Find the best location from the array based on accuracy
    NSDictionary *myBestLocation = [[NSDictionary alloc]init];
    
    for (int i=0; i<self.shareModel.myLocationArray.count; i++) {
        NSDictionary *currentLocation = [self.shareModel.myLocationArray objectAtIndex:i];
        
        if (i == 0) myBestLocation = currentLocation;
        else {
            if ([[currentLocation objectForKey:ACCURACY] floatValue] <= [[myBestLocation objectForKey:ACCURACY] floatValue]) {
                myBestLocation = currentLocation;
            }
        }
    }
    
    // If the array is 0, get the last location
    // Sometimes due to network issue or unknown reason, you could not get the location during that period, the best you can do is sending the last known location to the server
    if (self.shareModel.myLocationArray.count == 0) {
        NSLog(@"Unable to get location, use the last known location");
        self.myLocation = self.myLastLocation;
        self.myLocationAccuracy = self.myLastLocationAccuracy;
        
    } else {
        CLLocationCoordinate2D theBestLocation;
        theBestLocation.latitude = [[myBestLocation objectForKey:LATITUDE] floatValue];
        theBestLocation.longitude = [[myBestLocation objectForKey:LONGITUDE] floatValue];
        self.myLocation = theBestLocation;
        self.myLocationAccuracy = [[myBestLocation objectForKey:ACCURACY] floatValue];
    }
    
    NSLog(@"Best Location: Latitude(%f) Longitude(%f) Accuracy(%f)", self.myLocation.latitude, self.myLocation.longitude, self.myLocationAccuracy);
    
    return self.myLocation;
}

- (void)clearOldLocations
{
    NSLog(@"AICLocationTracker clearOldLocations:");
    self.shareModel.myLocationArray = nil;
    self.shareModel.myLocationArray = [[NSArray alloc] init];
}
@end

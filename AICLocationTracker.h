//
//  AICLocationTracker.h
//  Gathr
//
//  Created by David Lui on 6/28/14.
//  Copyright (c) 2014 Softaic. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

#import "LocationShareModel.h"

@protocol AICLocationTrackerDelegate;

@interface AICLocationTracker : NSObject<CLLocationManagerDelegate>

@property (nonatomic, weak) id<AICLocationTrackerDelegate> delegate;

@property (nonatomic, assign) BOOL mode;

@property (nonatomic) CLLocationCoordinate2D myLastLocation;
@property (nonatomic) CLLocationAccuracy myLastLocationAccuracy;

@property (nonatomic) CLLocationCoordinate2D myLocation;
@property (nonatomic) CLLocationAccuracy myLocationAccuracy;

@property (strong, nonatomic) LocationShareModel *shareModel;

+ (CLLocationManager *)sharedLocationManager;

- (id)initWithBackgroundTrackingEnabled:(BOOL)backgroundTrackingEnabled;
- (void)startLocationTracking;
- (void)stopLocationTracking;
- (CLLocationCoordinate2D)getBestLocation;
- (void)clearOldLocations;

@end


@protocol AICLocationTrackerDelegate <NSObject>
- (void)AICLocationTracker:(AICLocationTracker *)locationTracker didUpdateLocations:(NSArray *)locations;
@end
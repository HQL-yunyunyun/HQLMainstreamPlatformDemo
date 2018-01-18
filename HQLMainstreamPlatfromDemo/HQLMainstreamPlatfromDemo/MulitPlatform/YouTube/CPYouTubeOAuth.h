//
//  GCGoogleAuthFetcherManager.h
//  GoCreate3.0
//
//  Created by 何启亮 on 2017/9/18.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GTMAppAuth/GTMAppAuth.h>

static NSString *const YouTubeAuthorizationDidChangeNotification = @"cp.YouTubeAuthorizationDidChangeNotification";
static NSString *const YouTubeAuthorizationDidChangeNotificationAuthorizationKey = @"cp.YouTubeAuthorizationDidChangeNotificationAuthorizationKey";

/*
@protocol GCGoogleAuthFetchManagerObserver <NSObject>

@optional

- (void)authorizationDidRemove;

@end
 //*/

@interface CPYouTubeOAuth : NSObject

- (instancetype)initWithAuthorization:(GTMAppAuthFetcherAuthorization *)authorization;

@property (atomic, strong, readonly) GTMAppAuthFetcherAuthorization *authorization;

/* auth method */
- (void)doYouTubeAuthWithPresentController:(UIViewController *)controller thenHandler:(void(^)(GTMAppAuthFetcherAuthorization *authorization, NSError *error))handler;


- (void)cleanAppAuth;

// fetch user info
- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void(^)(NSDictionary *userInfo, NSError *error))handler;


/*
 + (instancetype)shareManager;
 
 @property (assign, nonatomic) BOOL isAuthorization;
 
 // observer mthod
 - (void)addAuthObserver:(id <GCGoogleAuthFetchManagerObserver>)observer;
 - (void)removeAuthObserver:(id <GCGoogleAuthFetchManagerObserver>)observer;
 
 - (void)clearAppAuthWithIsNotification:(BOOL)isNotification;
 
 //*/

@end

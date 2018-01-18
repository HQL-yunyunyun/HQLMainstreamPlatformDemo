//
//  GCGoogleAuthFetcherManager.m
//  GoCreate3.0
//
//  Created by 何启亮 on 2017/9/18.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import "CPYouTubeOAuth.h"

#import <GTLRYouTube.h>

#import "AppDelegate.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import <GTMSessionFetcher/GTMSessionFetcherService.h>

//#import "CustomUserDefault.h"
//#import "GCFileManager.h"

/*! @brief The OIDC issuer from which the configuration will be discovered.
 */
static NSString *const kIssuer = @"https://accounts.google.com";

/*! @brief The OAuth client ID.
 @discussion For Google, register your client at
 https://console.developers.google.com/apis/credentials?project=_
 The client should be registered with the "iOS" type.
 */
static NSString *const kClientID = @"117770256090-eesgrjqput2cs5dp9hlscch2u6j6ab80.apps.googleusercontent.com";

/*! @brief The OAuth redirect URI for the client @c kClientID.
 @discussion With Google, the scheme of the redirect URI is the reverse DNS notation of the
 client ID. This scheme must be registered as a scheme in the project's Info
 property list ("CFBundleURLTypes" plist key). Any path component will work, we use
 'oauthredirect' here to help disambiguate from any other use of this scheme.
 */
static NSString *const kRedirectURI = @"com.googleusercontent.apps.117770256090-eesgrjqput2cs5dp9hlscch2u6j6ab80:/oauthredirect";

@interface CPYouTubeOAuth () <OIDAuthStateErrorDelegate, OIDAuthStateChangeDelegate>

//@property (strong, nonatomic) NSMutableArray <id <GCGoogleAuthFetchManagerObserver>>*observerArray;

@end

@implementation CPYouTubeOAuth {
    GTMAppAuthFetcherAuthorization * _authorization;
    
    OIDAuthState *_authState;
}

#pragma mark - initialization
/*
+ (instancetype)shareManager {
    static GCGoogleAuthFetcherManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (manager == nil) {
            manager = [[GCGoogleAuthFetcherManager alloc]init];
        }
    });
    return manager;
}

- (instancetype)init {
    if (self = [super init]) {
        // 获取钥匙串中的key
        [self loadState];
        self.observerArray = [NSMutableArray array];
        
    }
    return self;
}//*/

- (instancetype)initWithAuthorization:(GTMAppAuthFetcherAuthorization *)authorization {
    if (self = [super init]) {
        _authorization = authorization;
    }
    return self;
}

#pragma mark - auth method

- (void)doYouTubeAuthWithPresentController:(UIViewController *)controller thenHandler:(void (^)(GTMAppAuthFetcherAuthorization *, NSError *))handler {
    if ([_authorization canAuthorize]) {
        //self.isAuthorization = YES;
        handler ? handler(_authorization, nil) : nil;
        return;
    }
    
    NSURL *issuer = [NSURL URLWithString:kIssuer];
    NSURL *redirectURI = [NSURL URLWithString:kRedirectURI];
    
    [OIDAuthorizationService discoverServiceConfigurationForIssuer:issuer completion:^(OIDServiceConfiguration * _Nullable configuration, NSError * _Nullable error) {
        if (!configuration) {
            [self logMessage:@"Error retrieving discovery document: %@", [error localizedDescription]];
            // remove app auth
            //[self clearAppAuthWithIsNotification:YES];
            
            [self cleanAppAuth];
            
            handler ? handler(nil, error) : nil;
            
            return;
        }
        
        [self logMessage:@"Got configuration: %@", configuration];
        
        // bulids authentication request
        OIDAuthorizationRequest *request = [[OIDAuthorizationRequest alloc] initWithConfiguration:configuration clientId:kClientID scopes:@[kGTLRAuthScopeYouTube, kGTLRAuthScopeYouTubeForceSsl,kGTLRAuthScopeYouTubeReadonly, OIDScopeEmail, OIDScopeOpenID, OIDScopeProfile] redirectURL:redirectURI responseType:OIDResponseTypeCode additionalParameters:nil];
        
        // init authorization request
        [self logMessage:@"Initiating authorization request with scope: %@", request.scope];
        
        AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
        appDelegate.currentAuthorizationFlow = [OIDAuthState authStateByPresentingAuthorizationRequest:request presentingViewController:controller callback:^(OIDAuthState * _Nullable authState, NSError * _Nullable error) {
            
            _authState = authState;
            _authState.errorDelegate = self;
            _authState.stateChangeDelegate = self;
            
            GTMAppAuthFetcherAuthorization *authorization = nil;
            if (authState) { // 创建成功
                [self logMessage:@"Got authorization tokens. Access token: %@", authState.lastTokenResponse.accessToken];
                
                authorization = [[GTMAppAuthFetcherAuthorization alloc] initWithAuthState:authState];
                [self setGtmAuthorization:authorization];
                
            } else { // 创建失败
                //[self clearAppAuthWithIsNotification:YES];
                
                [self cleanAppAuth];
                
                [self logMessage:@"Authorization error: %@", [error localizedDescription]];
            }
            
            handler ? handler(authorization, error) : nil;
            
        }];
    }];
}

- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void (^)(NSDictionary *, NSError *))handler {
    // 检查权限
    if (!_authorization || ![_authorization canAuthorize]) {
        [self doYouTubeAuthWithPresentController:controller thenHandler:^(GTMAppAuthFetcherAuthorization *authorization, NSError *error) {
            [self fetchUserInfoWithPresentController:controller completeHandler:handler];
        }];
        return;
    }
    
    // Creates a GTMSessionFetcherService with the authorization.
    // Normally you would save this service object and re-use it for all REST API calls.
    GTMSessionFetcherService *fetcherService = [[GTMSessionFetcherService alloc] init];
    fetcherService.authorizer = _authorization;
    
    // Creates a fetcher for the API call.
    NSURL *userinfoEndpoint = [NSURL URLWithString:@"https://www.googleapis.com/oauth2/v3/userinfo"];
    GTMSessionFetcher *fetcher = [fetcherService fetcherWithURL:userinfoEndpoint];
    [fetcher beginFetchWithCompletionHandler:^(NSData *data, NSError *error) {
        // Checks for an error.
        if (error) {
            // OIDOAuthTokenErrorDomain indicates an issue with the authorization.
            if ([error.domain isEqual:OIDOAuthTokenErrorDomain]) {
                //[self setGtmAuthorization:nil];
                //[self clearAppAuthWithIsNotification:YES];
                
                [self cleanAppAuth];
                
                [self logMessage:@"Authorization error during token refresh, clearing state. %@", error];
                // Other errors are assumed transient.
            } else {
                [self logMessage:@"Transient error during token refresh. %@", error];
            }
            
            handler ? handler(nil, error) : nil;
            return;
        }
        
        // Parses the JSON response.
        NSError *jsonError = nil;
        id jsonDictionaryOrArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        // JSON error.
        if (jsonError) {
            [self logMessage:@"JSON decoding error %@", jsonError];
            handler ? handler(nil, jsonError) : nil;
            return;
        }
        
        // Success response!
        [self logMessage:@"Success: %@", jsonDictionaryOrArray];
        NSDictionary *userInfo = jsonDictionaryOrArray;
        
        /*
        [[CustomUserDefault standardUserDefaults] setObject:jsonDictionaryOrArray[@"name"] forKey:YouTubeAccountNickName];
        [[CustomUserDefault standardUserDefaults] setObject:jsonDictionaryOrArray[@"picture"] forKey:YouTubeAccountIconURL];
        
        [[CustomUserDefault standardUserDefaults] setObject:jsonDictionaryOrArray[@"email"] forKey:GCYouTubeUserAccount];
        [[CustomUserDefault standardUserDefaults] synchronize];
        
        //[[GCFileManager sharedGCFileManager] createUserDirectoryWithBid:jsonDictionaryOrArray[@"email"]]; // 创建目录
        [[GCFileManager sharedGCFileManager] createYouTubeAccountDirectoryWithAccount:jsonDictionaryOrArray[@"email"]];
         //*/
        
        handler ? handler(userInfo, error) : nil;
    }];
}

#pragma mark -

- (void)cleanAppAuth {
    if (!_authorization) {
        return;
    }
    
    [self setGtmAuthorization:nil];
}

/*
- (void)loadState {
    GTMAppAuthFetcherAuthorization * authorization = [GTMAppAuthFetcherAuthorization authorizationFromKeychainForName:kGTMAppAuthKeychainItemName];
    if ([authorization canAuthorize]) {
        [self setGtmAuthorization:authorization];
    } else {
        [self clearAppAuthWithIsNotification:YES];
    }
}

- (void)clearAppAuthWithIsNotification:(BOOL)isNotification {
    if (!_authorization) {
        return;
    }
    
    [self setGtmAuthorization:nil];
    
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:YouTubeAccountIconURL];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:YouTubeAccountNickName];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:GCYouTubeUserAccount];
    [[CustomUserDefault standardUserDefaults] synchronize];
    
    if (isNotification) {
        // 发出通知
        for (id<GCGoogleAuthFetchManagerObserver> observer in self.observerArray) {
            if ([observer respondsToSelector:@selector(authorizationDidRemove)]) {
                [observer authorizationDidRemove];
            }
        }
        
    }
}
//*/

- (void)setGtmAuthorization:(GTMAppAuthFetcherAuthorization *)authorization {
    if ([_authorization isEqual:authorization] || (!_authorization && !authorization)) {
        return;
    }
    _authorization = authorization;
    //self.isAuthorization = (authorization ? YES : NO);
    [self stateChanged];
}

- (void)stateChanged {
    [self saveState];
}
//*/
/*! @brief Saves the @c GTMAppAuthFetcherAuthorization to @c NSUSerDefaults.
 */
///*
- (void)saveState {
    
    // 发送通知
    NSDictionary *dict = nil;
    if (_authorization) {
        dict = @{YouTubeAuthorizationDidChangeNotificationAuthorizationKey : _authorization};
    }
    NSNotification *noti = [NSNotification notificationWithName:YouTubeAuthorizationDidChangeNotification object:nil userInfo:dict];
    [[NSNotificationCenter defaultCenter] postNotification:noti];
    
    /*
     if (_authorization.canAuthorize) {
         [GTMAppAuthFetcherAuthorization saveAuthorization:_authorization toKeychainForName:kGTMAppAuthKeychainItemName];
     } else {
         [GTMAppAuthFetcherAuthorization removeAuthorizationFromKeychainForName:kGTMAppAuthKeychainItemName];
     }//*/
}

/*
#pragma mark - observer method

- (void)addAuthObserver:(id<GCGoogleAuthFetchManagerObserver>)observer {
    for (id a in self.observerArray) {
        if ([a isEqual:observer]) {
            return;
        }
    }
    
    [self.observerArray addObject:observer];
}

- (void)removeAuthObserver:(id<GCGoogleAuthFetchManagerObserver>)observer {
    if ([self.observerArray containsObject:observer]) {
        [self.observerArray removeObject:observer];
    }
}
 //*/

#pragma mark -

/*! @brief Logs a message to stdout and the textfield.
 @param format The format string and arguments.
 */
///*
- (void)logMessage:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) {
    // gets message as string
    va_list argp;
    va_start(argp, format);
    NSString *log = [[NSString alloc] initWithFormat:format arguments:argp];
    va_end(argp);
    
    // appends to output log
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"hh:mm:ss";
    NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
    
    PLog(@"%@",[NSString stringWithFormat:@"%@: %@",
                dateString,
                log]);
}

#pragma mark - auth state delegate
///*
- (void)didChangeState:(OIDAuthState *)state {
    if (state.isAuthorized) {
        [self setGtmAuthorization:[[GTMAppAuthFetcherAuthorization alloc] initWithAuthState:state]];
    } else {
//        [self clearAppAuthWithIsNotification:YES];
        [self cleanAppAuth];
    }
}//*/

- (void)authState:(OIDAuthState *)state didEncounterAuthorizationError:(NSError *)error {
    [self logMessage:@"Received authorization error: %@", error];
//    [self clearAppAuthWithIsNotification:YES];
    [self cleanAppAuth];
}

#pragma mark - getter

- (GTMAppAuthFetcherAuthorization *)authorization {
    return _authorization;
}
//*/
@end

//
//  CPPlatformAuthManager.m
//  GoCreate3.0
//
//  Created by 何启亮 on 2017/11/13.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import "CPPlatformAuthManager.h"

#import "CPYouTubeOAuth.h"
#import "HQLTwitchOAuth.h"
#import "CPFacebookOAuth.h"

#import "CPYoutubeBrocastRoomModel.h"

//#import "CustomUserDefault.h"
//#import "GCFileManager.h"

/* Keychain item name for saving the user's authentication information.*/
NSString *const kGTMAppAuthKeychainItemName = @"com.GoCreate.GoCreate:YouTube.AppAuth";

// twitch keychain
NSString *const kTWITCHAppAuthKeychainItemName = @"hql.twitch.example:Twitch.AppAuth";

@interface CPPlatformAuthManager () <HQLTwitchOAuthDelegate, CPFacebookOAuthDelegate>

@property (strong, nonatomic) CPYouTubeOAuth *youtubeOAuth;
@property (strong, nonatomic) HQLTwitchOAuth *twitchOAuth;
@property (strong, nonatomic) CPFacebookOAuth *facebookOAuth;
@property (strong, nonatomic) CPTwitterOAuth *twitterOAuth;

@property (assign, nonatomic) CPPlatformAuthType currentBroadcastPlatform;
@property (assign, nonatomic) BOOL isBeginReceiveLiveMessages;
@property (assign, nonatomic) BOOL isBeginFetchLiveStatus;

@end

@implementation CPPlatformAuthManager {
    BOOL isLiveMessage_sign;
    BOOL isLiveStatus_sign;
}

+(CPPlatformAuthManager *)shareManager {
    
    static CPPlatformAuthManager *m = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (m == nil) {
            m = [[CPPlatformAuthManager alloc] init];
        }
    });
    return m;
}

- (instancetype)init {
    if (self = [super init]) {
        
        self.currentBroadcastPlatform = CPPlatformAuthType_UNKNOW;
        self.isBeginReceiveLiveMessages = NO;
        self.isBeginFetchLiveStatus = NO;
        
        isLiveStatus_sign = NO;
        isLiveMessage_sign = NO;
        
        // 添加通知
        [self addNotification];
        [self loadState];
        [self preparePlatform];
    }
    return self;
}

- (void)dealloc {
    [self removeNotification];
    PLog(@"dealloc ---> %@", NSStringFromClass([self class]));
}

#pragma mark - prepare

- (void)loadState {
    [self setYoutubeAuth:[GTMAppAuthFetcherAuthorization authorizationFromKeychainForName:kGTMAppAuthKeychainItemName]];
    [self setTwitchAuth:[TwitchAppFetcherAuthorization authorizationFromKeychainForName:kTWITCHAppAuthKeychainItemName]];
    [self setFacebookAuth:[FBSDKAccessToken currentAccessToken]];
    [self setTwitterAuth:[[TWTRTwitter sharedInstance].sessionStore session]];
}

- (void)preparePlatform {
    if (!self.youtubeOAuth) {
        self.youtubeOAuth = [[CPYouTubeOAuth alloc] initWithAuthorization:self.youtubeAuthorization];
    }
    if (!self.twitchOAuth) {
        self.twitchOAuth = [[HQLTwitchOAuth alloc] initWithAuthorization:self.twitchAuthorization];
        self.twitchOAuth.delegate = self;
    }
    if (!self.facebookOAuth) {
        self.facebookOAuth = [[CPFacebookOAuth alloc] initWithAuthorization:self.facebookAuthorization];
    }
    if (!self.twitterOAuth) {
        self.twitterOAuth = [[CPTwitterOAuth alloc] initWithAuthorization:self.twitterAuthorization];
    }
}

#pragma mark - tool

- (BOOL)platformIsAuthWithPlatformType:(CPPlatformAuthType)type {
    switch (type) {
        case CPPlatformAuthType_YouTube: {
            return self.youtubeAuthorization ? YES : NO;
        }
        case CPPlatformAuthType_Twitch: {
            return self.twitchAuthorization ? YES : NO;
        }
        case CPPlatformAuthType_Facebook: {
            return self.facebookAuthorization ? YES : NO;
        }
        case CPPlatformAuthType_Twitter: {
            return self.twitterAuthorization ? YES : NO;
        }
        default: {
            return NO;
        }
    }
}

#pragma mark - fetch auth

- (void)doAppAuthPlatformType:(CPPlatformAuthType)type presentController:(UIViewController *)controller otherParam:(NSDictionary *)otherParam thenHandler:(void (^)(CPPlatformAuthManager *, NSError *))handler {
    __weak typeof(self) _self = self;
    
    switch (type) {
        case CPPlatformAuthType_YouTube: {
            [self.youtubeOAuth doYouTubeAuthWithPresentController:controller thenHandler:^(GTMAppAuthFetcherAuthorization *authorization, NSError *error) {
                [_self setYoutubeAuth:authorization];
                handler ? handler(_self, error) : nil;
            }];
            break;
        }
        case CPPlatformAuthType_Twitch: {
            [self.twitchOAuth doTwitchAuthWithPresentController:controller thenHandler:^(TwitchAppFetcherAuthorization *authorization, NSError *error) {
                [_self setTwitchAuth:authorization];
                handler ? handler(_self, error) : nil;
            }];
            break;
        }
        case CPPlatformAuthType_Facebook: {
            
            NSArray *needPermissions = otherParam[@"permissions"];
            if (needPermissions.count <= 0) {
                needPermissions = [CPFacebookOAuth commonPermissions];
            }
            [self.facebookOAuth doFacebookAuthWithPresentController:controller permissionsArray:needPermissions thenHandler:^(FBSDKAccessToken *token, NSArray<NSString *> *grantedPermissions, NSArray<NSString *> *declinedPermissions, NSError *error) {
                
                if (declinedPermissions.count > 0) {
                    if (!error) {
                        error = [NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"Facebook权限被拒绝"}];
                    }
                }
                
                [_self setFacebookAuth:token];
                handler ? handler(_self, error) : nil;
            }];
            break;
        }
            
        case CPPlatformAuthType_Twitter: {
            [self.twitterOAuth doTwitterAuthWithPresentController:controller thenHandler:^(TWTRSession *authorization, NSError *error) {
                [_self setTwitterAuth:authorization];
                handler ? handler(_self, error) : nil;
            }];
            break;
        }
            
        default:
            break;
    }
}

- (void)fetchUserInfoWithPlatformType:(CPPlatformAuthType)type presentController:(UIViewController *)controller completeHandler:(void (^)(NSDictionary *, NSError *))handler {
    
    __weak typeof(self) _self = self;
    
    switch (type) {
        case CPPlatformAuthType_YouTube: {
            [self.youtubeOAuth fetchUserInfoWithPresentController:controller completeHandler:^(NSDictionary *userInfo, NSError *error) {
                NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:userInfo];
                if (!error) {
                    [info setObject:userInfo[@"picture"] forKey:@"user_icon"];
                    [info setObject:userInfo[@"name"] forKey:@"user_name"];
                    
                    /*
                    [[CustomUserDefault standardUserDefaults] setObject:userInfo[@"name"] forKey:YouTubeAccountNickName];
                    [[CustomUserDefault standardUserDefaults] setObject:userInfo[@"picture"] forKey:YouTubeAccountIconURL];
                    [[CustomUserDefault standardUserDefaults] setObject:userInfo[@"email"] forKey:GCYouTubeUserAccount];
                    [[CustomUserDefault standardUserDefaults] synchronize];
                    
                    //[[GCFileManager sharedGCFileManager] createUserDirectoryWithBid:jsonDictionaryOrArray[@"email"]]; // 创建目录
                    [[GCFileManager sharedGCFileManager] createYouTubeAccountDirectoryWithAccount:userInfo[@"email"]];
                    //*/
                }
                handler ? handler(info, error) : nil;
            }];
            break;
        }
        case CPPlatformAuthType_Twitch: {
            [self.twitchOAuth fetchUserInfoWithPresentController:controller completeHandler:^(NSDictionary *userInfo, NSError *error) {
                NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:userInfo];
                if (!error) {
                    [info setObject:userInfo[@"logo"] forKey:@"user_icon"];
                    [info setObject:userInfo[@"display_name"] forKey:@"user_name"];
                    /*
                    [[CustomUserDefault standardUserDefaults] setObject:userInfo[@"display_name"] forKey:TwitchAccountNickName];
                    [[CustomUserDefault standardUserDefaults] setObject:userInfo[@"logo"] forKey:TwitchAccountIconURL];
                    [[CustomUserDefault standardUserDefaults] synchronize];
                    //*/
                }
                handler ? handler(info, error) : nil;
            }];
            break;
        }
        case CPPlatformAuthType_Facebook: {
            [self.facebookOAuth fetchUserInfoWithPresentController:controller completeHandler:^(FBSDKProfile *profile, NSError *error) {
                NSMutableDictionary *info = [NSMutableDictionary dictionary];
                if (!error) {
                    [info setObject:profile.name forKey:@"user_name"];
                    [info setObject:[profile imageURLForPictureMode:FBSDKProfilePictureModeNormal size:CGSizeMake(100, 100)].absoluteString forKey:@"user_icon"];
                    [info setObject:profile.userID forKey:@"user_id"];
                    [info setObject:_self.facebookAuthorization.tokenString forKey:@"user_token"];
                    /*
                    [[CustomUserDefault standardUserDefaults] setObject:info[@"user_name"] forKey:FacebookAccountNickName];
                    [[CustomUserDefault standardUserDefaults] setObject:info[@"user_icon"] forKey:FacebookAccountIconURL];
                    [[CustomUserDefault standardUserDefaults] synchronize];
                    //*/
                }
                handler ? handler(info, error) : nil;
            }];
            break;
        }
        case CPPlatformAuthType_Twitter: {
            [self.twitterOAuth fetchUserInfoWithPresentController:controller completeHandler:^(TWTRUser *user, NSError *error) {
                NSMutableDictionary *info = [NSMutableDictionary dictionary];
                if (!error) {
                    [info setObject:user.name forKey:@"user_name"];
                    [info setObject:user.profileImageURL forKey:@"user_icon"];
                    
                    /*
                     [[CustomUserDefault standardUserDefaults] setObject:info[@"user_name"] forKey:TwitterAccountNickName];
                     [[CustomUserDefault standardUserDefaults] setObject:info[@"user_icon"] forKey:TwitterAccountIconURL];
                     [[CustomUserDefault standardUserDefaults] synchronize];
                     //*/
                }
            }];
            break;
        }
            
        default:
            break;
    }
    
}

#pragma mark - broadcast

/*
 {
 @"broadcast_type_facebook" : facebook broadcast type,
 @"broadcast_id_facebook" : 与BroadcastType相对应的ID
 @"title" : 标题 --- 只有YouTube的时候有用
 @"description" : 描述
 }
 */

- (void)startBroadcastWithType:(CPPlatformAuthType)type param:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void (^)(NSString *))handler {
    
    if (self.currentBroadcastPlatform != CPPlatformAuthType_UNKNOW) {
        if ([self.delegate respondsToSelector:@selector(broadcastError:)]) {
            [self.delegate broadcastError:[NSError errorWithDomain:CPPlatformAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"broadcast has been begin, can not start broadcast again", NSLocalizedDescriptionKey : @"broadcast has been begin, can not start broadcast again"}]];
        }
        return;
    }
    
    if (type == CPPlatformAuthType_UNKNOW) {
        if ([self.delegate respondsToSelector:@selector(broadcastError:)]) {
            [self.delegate broadcastError:[NSError errorWithDomain:CPPlatformAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"platform auth type can not be unknow", NSLocalizedDescriptionKey : @"platform auth type can not be unknow"}]];
        }
        return;
    }
    
    if (type == CPPlatformAuthType_Twitter) {
        if ([self.delegate respondsToSelector:@selector(broadcastError:)]) {
            [self.delegate broadcastError:[NSError errorWithDomain:CPPlatformAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"twitter live is not support in our class now", NSLocalizedDescriptionKey : @"twitter live is not support in our class now"}]];
        }
    }
    
    NSString *description = param[@"description"];
    NSString *title = param[@"title"];
    NSString *broadcast_id = param[@"broadcast_id_facebook"];
    NSNumber *broadcast_type = param[@"broadcast_type_facebook"];
    
    __weak typeof(self) _self = self;
    
    switch (type) {
        case CPPlatformAuthType_Facebook: {
            
            NSDictionary *fbparam = @{
                                      @"broadcastType" : broadcast_type,
                                      @"broadcast_id" : broadcast_id,
                                      @"broadcast_description" : description,
                                      };
            [self.facebookOAuth startBroadcastWithParam:fbparam presentController:controller completeHandler:^(NSString *broadcastURL, NSError *error) {
                if (error) {
                    if ([_self.delegate respondsToSelector:@selector(broadcastError:)]) {
                        [_self.delegate broadcastError:error];
                    }
                    return;
                }
                
                _self.currentBroadcastPlatform = type;
                handler ? handler(broadcastURL) : nil;
            }];
            
            break;
        }
        case CPPlatformAuthType_YouTube: {
            
            CPYoutubeBrocastRoomModel *model = [[CPYoutubeBrocastRoomModel alloc] init];
            model.title = title;
            model.detail = description;
            [self.youtubeOAuth startLiveBroadcastWithRoomModel:model presentController:controller completeHandler:^(NSString *broadcastURL, NSError *error) {
                if (error) {
                    if ([_self.delegate respondsToSelector:@selector(broadcastError:)]) {
                        [_self.delegate broadcastError:error];
                    }
                    return;
                }
                
                _self.currentBroadcastPlatform = type;
                handler ? handler(broadcastURL) : nil;
            }];
            
            break;
        }
        case CPPlatformAuthType_Twitch: {
            
            [self.twitchOAuth startBroadcastWithChannelDescription:description presentController:controller completeHandler:^(NSString *broadcastURL, NSError *error) {
                if (error) {
                    if ([_self.delegate respondsToSelector:@selector(broadcastError:)]) {
                        [_self.delegate broadcastError:error];
                    }
                    return;
                }
                
                _self.currentBroadcastPlatform = type;
                handler ? handler(broadcastURL) : nil;
            }];
            
            break;
        }
            
        default: { break; }
    }
}

- (void)stopBroadcast {
    if (self.currentBroadcastPlatform == CPPlatformAuthType_UNKNOW) {
        return;
    }
    
    switch (self.currentBroadcastPlatform) {
        case CPPlatformAuthType_Facebook: {
            [self.facebookOAuth stopBroadcast];
            break;
        }
        case CPPlatformAuthType_YouTube: {
            [self.youtubeOAuth stopLiveBroadcast];
            break;
        }
        case CPPlatformAuthType_Twitch: {
            [self.twitchOAuth stopBroadcast];
            break;
        }
            
        default:
            break;
    }
    
    
    [self stopAutoFetchLiveMessages];
    [self stopAutoFetchBroadcastStatus];
    
    self.currentBroadcastPlatform = CPPlatformAuthType_UNKNOW;
}

- (void)startFacebookBroadcastWithLiveVideoID:(NSString *)liveVideoID {
    self.currentBroadcastPlatform = CPPlatformAuthType_Facebook;
    [self.facebookOAuth startBroadcastWithLiveVideoID:liveVideoID];
}

#pragma mark - live message

- (void)autoFetchLiveMessagesWithPresentController:(UIViewController *)controller {
    if (self.currentBroadcastPlatform == CPPlatformAuthType_UNKNOW || self.isBeginReceiveLiveMessages) {
        return;
    }
    
    self.isBeginReceiveLiveMessages = YES;
    [self fetchLiveMessagesWithPresentController:controller];
}

- (void)fetchLiveMessagesWithPresentController:(UIViewController *)controller {
    if (self.currentBroadcastPlatform == CPPlatformAuthType_UNKNOW || !self.isBeginReceiveLiveMessages) {
        return;
    }
    
    __weak typeof(self) _self = self;
    
    switch (self.currentBroadcastPlatform) {
        case CPPlatformAuthType_Facebook: {
            
            [self.facebookOAuth fetchBroadcastCommentsWithCompleteHandler:^(NSArray *comments, NSError *error) {
                if (error) {
                    if ([_self.delegate respondsToSelector:@selector(broadcastDidReceiveLiveMessagesError:platformType:)]) {
                        [_self.delegate broadcastDidReceiveLiveMessagesError:error platformType:CPPlatformAuthType_Facebook];
                    }
                    return;
                }
                
                if ([_self.delegate respondsToSelector:@selector(broadcastDidReceiveLiveMessages:platformType:)]) {
                    [_self.delegate broadcastDidReceiveLiveMessages:comments platformType:CPPlatformAuthType_Facebook];
                }
                
                if (_self.isBeginReceiveLiveMessages) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [_self fetchLiveMessagesWithPresentController:controller];
                    });
                }
                
            }];
            
            break;
        }
        case CPPlatformAuthType_YouTube: {
            [self.youtubeOAuth fetchLiveMessageWithCompleteHandler:^(GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError *error) {
                
                if (error) {
                    if ([_self.delegate respondsToSelector:@selector(broadcastDidReceiveLiveMessagesError:platformType:)]) {
                        [_self.delegate broadcastDidReceiveLiveMessagesError:error platformType:CPPlatformAuthType_YouTube];
                    }
                    return;
                }
                
                if ([_self.delegate respondsToSelector:@selector(broadcastDidReceiveLiveMessages:platformType:)]) {
                    
                    NSMutableArray *array = [NSMutableArray arrayWithCapacity:liveChats.items.count];
                    for (GTLRYouTube_LiveChatMessage *model in liveChats.items) {
                        NSDictionary *dict = @{
                                               @"name" : model.authorDetails.displayName,
                                               @"message" : model.snippet.displayMessage,
                                               @"message_id" : model.identifier,
                                               };
                        [array addObject:dict];
                    }
                    
                    [_self.delegate broadcastDidReceiveLiveMessages:array platformType:CPPlatformAuthType_YouTube];
                    
                }
                
                if (_self.isBeginReceiveLiveMessages) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((liveChats.pollingIntervalMillis.integerValue /1000.0)  * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [_self fetchLiveMessagesWithPresentController:controller];
                    });
                }
                
            }];

            break;
        }
        case CPPlatformAuthType_Twitch: {
            [self.twitchOAuth autoReceiveChannelChatWithPresentController:controller]; // 必须得这样
            break;
        }
            
        default:
            break;
    }
}

- (void)stopAutoFetchLiveMessages {
    if (!self.isBeginReceiveLiveMessages) {
        return;
    }
    self.isBeginReceiveLiveMessages = NO;
    
    switch (self.currentBroadcastPlatform) {
        case CPPlatformAuthType_Facebook: {
            
            break;
        }
        case CPPlatformAuthType_YouTube: {

            break;
        }
        case CPPlatformAuthType_Twitch: {
            [self.twitchOAuth stopReceiveChannelChat];
            break;
        }
            
        default:
            break;
    }
}

#pragma mark - broadcast status

- (void)autoFetchBroadcastStatusWithPresentController:(UIViewController *)controller {
    if (self.currentBroadcastPlatform == CPPlatformAuthType_UNKNOW || self.isBeginFetchLiveStatus) {
        return;
    }
    
    self.isBeginFetchLiveStatus = YES;
    [self fetchBroadcastStatusWithPresentController:controller];
}

- (void)fetchBroadcastStatusWithPresentController:(UIViewController *)controller {
    if (self.currentBroadcastPlatform == CPPlatformAuthType_UNKNOW || !self.isBeginFetchLiveStatus) {
        return;
    }
    __weak typeof(self) _self = self;
    
    NSLog(@"%@", [NSThread currentThread]);
    
    switch (self.currentBroadcastPlatform) {
        case CPPlatformAuthType_Facebook: {
            
            [self.facebookOAuth fetchBroadcastStatusWithCompleteHandler:^(FacebookBroadcastStatus status, NSError *error) {

                if (error) {
                    if ([_self.delegate respondsToSelector:@selector(broadcastError:)]) {
                        [_self.delegate broadcastError:error];
                    }
                    return;
                }
                
                if ([self.delegate respondsToSelector:@selector(broadcastStatusDidChange:platformType:)]) {
                    
                    CPPlatformBroadcastStatus s = CPPlatformBroadcastStatus_off_line;
                    if (status == FacebookBroadcastStatus_off_line) {
                        s = CPPlatformBroadcastStatus_off_line;
                    } else if (status == FacebookBroadcastStatus_live) {
                        s = CPPlatformBroadcastStatus_live;
                    } else if (status == FacebookBroadcastStatus_live_stopped) {
                        s = CPPlatformBroadcastStatus_live_stopped;
                    }
                    [_self.delegate broadcastStatusDidChange:s platformType:CPPlatformAuthType_Facebook];
                }
                
                if (_self.isBeginFetchLiveStatus) {
                    // 5秒后再获取状态
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
                        [_self fetchBroadcastStatusWithPresentController:controller];
                    });
                }
                
            }];
            
            break;
        }
        case CPPlatformAuthType_YouTube: {
            
            [self.youtubeOAuth fetchLiveBroadcastStatusWithCompleteHandler:^(NSString *status) {
                
                if ([_self.delegate respondsToSelector:@selector(broadcastStatusDidChange:platformType:)]) {
                    
                    CPPlatformBroadcastStatus s = CPPlatformBroadcastStatus_off_line;
                    if ([status isEqualToString:kGTLRYouTube_LiveBroadcastStatus_LifeCycleStatus_LiveStarting] || [status isEqualToString:kGTLRYouTube_LiveBroadcastStatus_LifeCycleStatus_Live]) {
                        s = CPPlatformBroadcastStatus_live;
                    }
                    
                    [_self.delegate broadcastStatusDidChange:s platformType:CPPlatformAuthType_YouTube];
                }
                
                if (_self.isBeginFetchLiveStatus) {
                    // 5秒后再获取状态
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
                        [_self fetchBroadcastStatusWithPresentController:controller];
                    });
                }
                
            }];
            
            break;
        }
        case CPPlatformAuthType_Twitch: {
            [self.twitchOAuth fetchTwitchBroadcastStatusWithPresentController:controller completeHandler:^(TwitchBroadcastStatus broadcastStatus, NSDictionary *streamDict, NSError *error) {
                
                if (error) {
                    if ([_self.delegate respondsToSelector:@selector(broadcastError:)]) {
                        [_self.delegate broadcastError:error];
                    }
                    return;
                }
                
                if ([_self.delegate respondsToSelector:@selector(broadcastStatusDidChange:platformType:)]) {
                    CPPlatformBroadcastStatus s = CPPlatformBroadcastStatus_off_line;
                    if (broadcastStatus == TwitchBroadcastStatus_off_line) {
                        s = CPPlatformBroadcastStatus_off_line;
                    } else if (broadcastStatus == TwitchBroadcastStatus_live) {
                        s = CPPlatformBroadcastStatus_live;
                    }
                    [_self.delegate broadcastStatusDidChange:s platformType:CPPlatformAuthType_Twitch];
                }
                
                if (_self.isBeginFetchLiveStatus) {
                    // 5秒后再获取状态
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
                        [_self fetchBroadcastStatusWithPresentController:controller];
                    });
                }
                
            }];
            break;
        }
            
        default: { break; }
    }
}

- (void)stopAutoFetchBroadcastStatus {
    self.isBeginFetchLiveStatus = NO;
}

#pragma mark -

- (void)fetchBroadcastDetailInfoWithPresentController:(UIViewController *)controller completeHandler:(void (^)(NSInteger, NSInteger))handler {
    if (self.currentBroadcastPlatform == CPPlatformAuthType_UNKNOW) {
        return;
    }
    
    switch (self.currentBroadcastPlatform) {
        case CPPlatformAuthType_Facebook: {
            [self.facebookOAuth fetchBroadcastInfoWithCompleteHandler:^(NSDictionary *dict, NSError *error) {
                handler ? handler([dict[@"live_views"] integerValue], [dict[@"likes"] integerValue]) : nil;
            }];
            break;
        }
        case CPPlatformAuthType_YouTube: { // YouTube暂时没有发现接口
            //self.liveStream.youtubeLiveBroadcast.statistics.concurrentViewers
            //handler ? handler(self.youtubeLiveStream.youtubeLiveBroadcast)
            break;
        }
        case CPPlatformAuthType_Twitch: {
            [self.twitchOAuth fetchTwitchBroadcastStatusWithPresentController:controller completeHandler:^(TwitchBroadcastStatus broadcastStatus, NSDictionary *streamDict, NSError *error) {
                handler ? handler([streamDict[@"viewer"] integerValue], 0) : nil; // 没有喜欢的人数
            }];
            break;
        }
            
        default: { break; }
    }
}

#pragma mark - broadcast delegate

-(void)twitchDidReceiveLiveMessage:(NSArray<NSDictionary *> *)liveMessages {
    if ([self.delegate respondsToSelector:@selector(broadcastDidReceiveLiveMessages:platformType:)]) {
        [self.delegate broadcastDidReceiveLiveMessages:liveMessages platformType:CPPlatformAuthType_Twitch];
    }
}

- (void)twitchDidReceiveLiveMessageError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(broadcastDidReceiveLiveMessagesError:platformType:)]) {
        [self.delegate broadcastDidReceiveLiveMessagesError:error platformType:CPPlatformAuthType_Twitch];
    }
}

// facebook
/*
- (void)facebookDidReceiveLiveComments:(NSArray<NSDictionary *> *)comments {
    if ([self.delegate respondsToSelector:@selector(broadcastDidReceiveLiveMessages:platformType:)]) {
        [self.delegate broadcastDidReceiveLiveMessages:comments platformType:CPPlatformAuthType_Facebook];
    }
}

- (void)facebookDidReceiveLiveCommentsError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(broadcastDidReceiveLiveMessagesError:platformType:)]) {
        [self.delegate broadcastDidReceiveLiveMessagesError:error platformType:CPPlatformAuthType_Facebook];
    }
}

- (void)facebookBroadcastStatusDidChange:(FacebookBroadcastStatus)status error:(NSError *)error {
    
    if (error) {
        if ([self.delegate respondsToSelector:@selector(broadcastError:)]) {
            [self.delegate broadcastError:error];
        }
        return;
    }
    
    if ([self.delegate respondsToSelector:@selector(broadcastStatusDidChange:platformType:)]) {
        
        CPPlatformBroadcastStatus s = CPPlatformBroadcastStatus_off_line;
        if (status == FacebookBroadcastStatus_off_line) {
            s = CPPlatformBroadcastStatus_off_line;
        } else if (status == FacebookBroadcastStatus_live) {
            s = CPPlatformBroadcastStatus_live;
        } else if (status == FacebookBroadcastStatus_live_stopped) {
            s = CPPlatformBroadcastStatus_live_stopped;
        }
        [self.delegate broadcastStatusDidChange:s platformType:CPPlatformAuthType_Facebook];
    }
}//*/

// youtube
/*
- (void)liveBroadcastStatusDidChanged:(NSString *)status {
    if ([self.delegate respondsToSelector:@selector(broadcastStatusDidChange:platformType:)]) {
        
        CPPlatformBroadcastStatus s = CPPlatformBroadcastStatus_off_line;
        if ([status isEqualToString:kGTLRYouTube_LiveBroadcastStatus_LifeCycleStatus_LiveStarting] || [status isEqualToString:kGTLRYouTube_LiveBroadcastStatus_LifeCycleStatus_Live]) {
            s = CPPlatformBroadcastStatus_live;
        }
        
        [self.delegate broadcastStatusDidChange:s platformType:CPPlatformAuthType_YouTube];
    }
}

- (void)liveMessageChanged:(NSArray<GTLRYouTube_LiveChatMessage *> *)liveChats {
    if ([self.delegate respondsToSelector:@selector(broadcastDidReceiveLiveMessages:platformType:)]) {
        
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:liveChats.count];
        for (GTLRYouTube_LiveChatMessage *model in liveChats) {
            NSDictionary *dict = @{
                                   @"name" : model.authorDetails.displayName,
                                   @"message" : model.snippet.displayMessage,
                                   @"message_id" : model.identifier,
                                   };
            [array addObject:dict];
        }
        
        [self.delegate broadcastDidReceiveLiveMessages:array platformType:CPPlatformAuthType_YouTube];
    }
}

- (void)liveMessageDidReceiveError:(GTLRErrorObject *)error {
    if ([self.delegate respondsToSelector:@selector(broadcastDidReceiveLiveMessagesError:platformType:)]) {
        [self.delegate broadcastDidReceiveLiveMessagesError:error.foundationError platformType:CPPlatformAuthType_YouTube];
    }
}

- (void)liveBroadcastError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(broadcastError:)]) {
        [self.delegate broadcastError:error];
    }
}//*/

// twitch
/*
- (void)twitchBroadcastStatusDidChange:(TwitchBroadcastStatus)broadcastStatus error:(NSError *)error {
    
    if (error) {
        if ([self.delegate respondsToSelector:@selector(broadcastError:)]) {
            [self.delegate broadcastError:error];
        }
        return;
    }
    
    if ([self.delegate respondsToSelector:@selector(broadcastStatusDidChange:platformType:)]) {
        CPPlatformBroadcastStatus s = CPPlatformBroadcastStatus_off_line;
        if (broadcastStatus == TwitchBroadcastStatus_off_line) {
            s = CPPlatformBroadcastStatus_off_line;
        } else if (broadcastStatus == TwitchBroadcastStatus_live) {
            s = CPPlatformBroadcastStatus_live;
        }
        [self.delegate broadcastStatusDidChange:s platformType:CPPlatformAuthType_Twitch];
    }
}//*/

#pragma mark - upload method

/*
 上传param
 title : NSString , (Facebook, YouTube, Twitter)
 description : NSString , (Facebook, YouTube)
 tags : string (空格隔开) , (YouTube)
 privacy : NSString , (Facebook, YouTube) (Faebook 和 YouTube 的 pricacy 参数都是不一样的，得注意不能弄错)
 thumbURL : NSString , (Facebook(只能是视频中的某一帧), YouTube)
 resumeString : NSString , (Facebook, YouTube, Twitter) (YouTube 就是 uploadLocationURL, 而 Facebook 就是 session_id, Twitter 就是 media_id)
 send_id : NSString , (Facebook) (就是指要发布的地方:timeline/page/group/event) (page_id / user_id / event_id / group_id)
 videoURL : NSString  , (Facebook, YouTube, Twitter)
 */
- (id)createVideoUploadTicketWithParam:(NSDictionary *)param
                              platformType:(CPPlatformAuthType)platformType
                              videoURL:(NSString *)videoURL
                              presentController:(UIViewController *)presentController
                              progressHandler:(void (^)(id, double))progressHandler
                              completeHandler:(void (^)(id, NSError *, NSDictionary *))completeHandler
{
    // 判断URL是否正确
    if (videoURL.length <= 0) {
        NSAssert(NO, @"video url can not be nil");
        completeHandler ? completeHandler(nil, [NSError errorWithDomain:CPPlatformAuthErrorDoMain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"video url can not be nil"}], nil) : nil;
        return nil;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *fileError = nil;
    NSInteger videoSize = [[fileManager attributesOfItemAtPath:videoURL error:&fileError][NSFileSize] integerValue] ;
    if (videoSize <= 0 || fileError) {
        NSAssert(NO, @"video size can not be nil");
        completeHandler ? completeHandler(nil, [NSError errorWithDomain:CPPlatformAuthErrorDoMain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"video size can not be nil"}], nil) : nil;
        return nil;
    }
    
    NSString *title = param[@"title"];
    NSString *description = param[@"description"];
    NSString *tags = param[@"tags"];
    NSString *privacy = param[@"privacy"];
    NSString *thumbURL = param[@"thumbURL"];
    NSString *resumeString = param[@"resumeString"];
    NSString *send_id = param[@"send_id"];
    
    switch (platformType) {
        case CPPlatformAuthType_Facebook: {
            
            NSMutableDictionary *publishParam = [[NSMutableDictionary alloc] init];
            if (title.length > 0) {
                [publishParam setObject:title forKey:@"title"];
            }
            if (description.length > 0) {
                [publishParam setObject:description forKey:@"description"];
            }
            if (thumbURL.length > 0) {
                NSData *imageData = [NSData dataWithContentsOfFile:thumbURL];
                if (imageData.length > 0) {
                    [publishParam setObject:imageData forKey:@"thumb"];
                }
            }
            if (privacy.length > 0) {
                [publishParam setObject:privacy forKey:@"privacy"];
            }
            // 直接创建
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
            [dict setObject:videoURL forKey:@"videoURL"];
            if (send_id.length > 0) {
                [dict setObject:send_id forKey:@"sendID"];
            }
            if (resumeString.length > 0) {
                [dict setObject:resumeString forKey:@"resumeMediaId"];
            }
            [dict setObject:publishParam forKey:@"publishParam"];
            
            CPFacebookUploader *uploader = [self.facebookOAuth createVideoUploadTicketWithParam:dict precentController:presentController uploadProgressHandler:^(CPUploader * _Nullable progressUploader, double uploadedPercent) {
                progressHandler ? progressHandler(progressUploader, uploadedPercent) : nil;
            } completeHandler:^(CPUploader * _Nullable callbackUploader, NSError * _Nullable error) {
                
                NSDictionary *dict = nil;
                if (!error) {
                    CPFacebookUploader *fbUploader = (CPFacebookUploader *)callbackUploader;
                    if (fbUploader.videoLink.length > 0) {
                        dict = @{@"videoLink" : fbUploader.videoLink};
                    }
                }
                completeHandler ? completeHandler(callbackUploader, error, dict) : nil;
                
            }];
            
            [uploader resume];
            
            return uploader;
            
        }
        case CPPlatformAuthType_YouTube: {
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
            if (title.length > 0) {
                [dict setObject:title forKey:@"title"];
            }
            if (description.length > 0) {
                [dict setObject:description forKey:@"description"];
            }
            if (privacy.length > 0) {
                [dict setObject:privacy forKey:@"privacyStatus"];
            }
            if (tags.length > 0) {
                [dict setObject:tags forKey:@"tags"];
            }
            if (thumbURL.length > 0) {
                [dict setObject:thumbURL forKey:@"thumbnailURL"];
            }
            if (resumeString.length > 0) {
                [dict setObject:resumeString forKey:@"uploadLocationURL"];
            }
            
            GTLRServiceTicket *ticket = [self.youtubeOAuth createYouTubeVideoUploadTicketWithParam:dict presentController:presentController videoUrl:[NSURL fileURLWithPath:videoURL] uploadProgressHandler:^(GTLRServiceTicket * _Nonnull progressTicket, unsigned long long totalBytesUploaded, unsigned long long totalBytesExpectedToUpload) {
                
                double progress = (double)totalBytesUploaded / (double)totalBytesExpectedToUpload;
                progressHandler ? progressHandler(progressTicket, progress) : nil;
                
            } completeHandler:^(GTLRServiceTicket * _Nonnull callbackTicket, GTLRYouTube_Video*  _Nullable object, NSError * _Nullable callbackError) {
                
                NSDictionary *dict = nil;
                if (!callbackError) {
                    dict = @{@"videoLink" : [NSString stringWithFormat:@"https://youtu.be/%@", object.identifier]};
                }
                completeHandler ? completeHandler(callbackTicket, callbackError, dict) : nil;
                
            }];
            return ticket;
        }
        case CPPlatformAuthType_Twitter: {
            
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
            if (description.length > 0) {
                [dict setObject:description forKey:@"tweetText"];
            }
            if (resumeString.length > 0) {
                [dict setObject:resumeString forKey:@"resumeMediaId"];
            }
            [dict setObject:videoURL forKey:@"videoURL"];
            
            CPTwitterUploader *uploader = [self.twitterOAuth createTwitterVideoUploadTicketWithParamDict:dict precentController:presentController uploadProgressHandler:^(CPUploader * _Nullable progressUploader, double uploadedPercent) {
                progressHandler ? progressHandler(progressUploader, uploadedPercent) : nil;
            } completeHandler:^(CPUploader * _Nullable callbackUploader, NSError * _Nullable error) {
                NSDictionary *dict = nil;
                if (!error) {
                    CPTwitterUploader *twitterUploader = (CPTwitterUploader *)callbackUploader;
                    dict = @{@"videoLink" : twitterUploader.tweet.permalink};
                }
                completeHandler ? completeHandler(callbackUploader, error, dict) : nil;
            }];
            
            [uploader resume];
            
            return uploader;
            
        }
        case CPPlatformAuthType_Twitch: {
            NSAssert(NO, @"It is not support twitch video upload now");
            completeHandler ? completeHandler(nil, [NSError errorWithDomain:CPPlatformAuthErrorDoMain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"It is not support twitch video upload now"}], nil) : nil;
            return nil;
        }
            
        default: {
            NSAssert(NO, @"Unknow");
            completeHandler ? completeHandler(nil, [NSError errorWithDomain:CPPlatformAuthErrorDoMain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"Unknow"}], nil) : nil;
            return nil;
        }
    }
}

#pragma mark - notification

- (void)removeNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:YouTubeAuthorizationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TwitchAuthorizationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:FBSDKAccessTokenDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TwitterAuthorizationDidChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)addNotification {
    // youtube
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youtubeAuthDidChange:) name:YouTubeAuthorizationDidChangeNotification object:nil];
    // twitch
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(twitchAuthDidChange:) name:TwitchAuthorizationDidChangeNotification object:nil];
    // facebook
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(facebookAuthDidChange:) name:FBSDKAccessTokenDidChangeNotification object:nil];
    // twitter
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(twitterAuthDidChange:) name:TwitterAuthorizationDidChangeNotification object:nil];
    
    // 进入后台
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(becomeActivity) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)becomeActivity {
    if (self.currentBroadcastPlatform == CPPlatformAuthType_UNKNOW) {
        return;
    }
    if (isLiveStatus_sign) {
        [self autoFetchBroadcastStatusWithPresentController:nil];
    }
    if (isLiveMessage_sign) {
        [self autoFetchLiveMessagesWithPresentController:nil];
    }
}

- (void)enterBackground {
    if (self.currentBroadcastPlatform == CPPlatformAuthType_UNKNOW) {
        return;
    }
    isLiveStatus_sign = self.isBeginFetchLiveStatus;
    isLiveMessage_sign = self.isBeginReceiveLiveMessages;
    
    [self stopAutoFetchLiveMessages];
    [self stopAutoFetchBroadcastStatus];
    
    [self.youtubeOAuth stopBroadcastConnection];
    [self.facebookOAuth stopBroadcastConnection];
    [self.twitchOAuth stopBroadcastConnection];
}

- (void)youtubeAuthDidChange:(NSNotification *)noti {
    GTMAppAuthFetcherAuthorization *auth = noti.userInfo[YouTubeAuthorizationDidChangeNotificationAuthorizationKey];
    [self setYoutubeAuth:auth];
}

- (void)twitchAuthDidChange:(NSNotification *)noti {
    TwitchAppFetcherAuthorization *auth = noti.userInfo[TwitchAuthorizationDidChangeNotificationAuthorizationKey];
    [self setTwitchAuth:auth];
}

- (void)facebookAuthDidChange:(NSNotification *)noti {
    FBSDKAccessToken *auth = noti.userInfo[FBSDKAccessTokenChangeNewKey];
    [self setFacebookAuth:auth];
}

- (void)twitterAuthDidChange:(NSNotification *)noti {
    TWTRSession *auth = noti.userInfo[TwitterAuthorizationDidChangeNotificationAuthorizationKey];
    [self setTwitterAuth:auth];
}

- (void)setYoutubeAuth:(GTMAppAuthFetcherAuthorization *)auth {
    if ([auth isEqual:self.youtubeAuthorization] || (!auth && !self.youtubeAuthorization)) {
        return;
    }
    
    self.youtubeAuthorization = auth;
    
    if (auth) {
        [GTMAppAuthFetcherAuthorization saveAuthorization:auth toKeychainForName:kGTMAppAuthKeychainItemName];
    } else {
        [GTMAppAuthFetcherAuthorization removeAuthorizationFromKeychainForName:kGTMAppAuthKeychainItemName];
        
        [self cleanYoutubeAuth];
    }
}

- (void)setTwitchAuth:(TwitchAppFetcherAuthorization *)auth {
    if ([self.twitchAuthorization isEqual:auth] || (!auth && !self.twitchAuthorization)) {
        return;
    }
    
    self.twitchAuthorization = auth;
    if (auth) {
        [TwitchAppFetcherAuthorization saveAuthorization:auth toKeychainForName:kTWITCHAppAuthKeychainItemName];
    } else {
        [TwitchAppFetcherAuthorization removeAuthorizationForKeychainForName:kTWITCHAppAuthKeychainItemName];
        
        [self cleanTwitchAuth];
    }
}

- (void)setFacebookAuth:(FBSDKAccessToken *)auth {
    if ([self.facebookAuthorization isEqual:auth] || (!auth && !self.facebookAuthorization)) {
        return;
    }
    
    self.facebookAuthorization = auth;
    if (!auth) {
        [self cleanFacebookAuth];
    }
}

- (void)setTwitterAuth:(TWTRSession *)auth {
    if ([self.twitterAuthorization isEqual:auth] || (!auth && !self.twitterAuthorization)) {
        return;
    }
    
    self.twitterAuthorization = auth;
    if (!auth) {
        [self cleanTwitterAuth];
    }
}

#pragma mark - clean app auth

- (void)cleanYoutubeAuth {
    [self.youtubeOAuth cleanAppAuth];
    
//    [GTMAppAuthFetcherAuthorization removeAuthorizationFromKeychainForName:kGTMAppAuthKeychainItemName];
    
    /*
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:YouTubeAccountIconURL];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:YouTubeAccountNickName];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:GCYouTubeUserAccount];
    [[CustomUserDefault standardUserDefaults] synchronize];
    //*/
}

- (void)cleanTwitchAuth {
    [self.twitchOAuth cleanAuthCache];
    
//    [TwitchAppFetcherAuthorization removeAuthorizationForKeychainForName:kTWITCHAppAuthKeychainItemName];
    
    /*
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:TwitchAccountIconURL];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:TwitchAccountNickName];
    [[CustomUserDefault standardUserDefaults] synchronize];
    //*/
}

- (void)cleanFacebookAuth {
    [self.facebookOAuth cleanAppAuth];
    
    /*
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:FacebookJoinedGroupKey];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:FacebookStreamTargetKey];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:FacebookStreamGroupKey];
    
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:FacebookAccountIconURL];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:FacebookAccountNickName];
    [[CustomUserDefault standardUserDefaults] synchronize];
    //*/
}

- (void)cleanTwitterAuth {
    [self.twitterOAuth clearAuth];
    
    /*
     [[CustomUserDefault standardUserDefaults] removeObjectForKey:TwitterAccountIconURL];
     [[CustomUserDefault standardUserDefaults] removeObjectForKey:TwitterAccountNickName];
     [[CustomUserDefault standardUserDefaults] synchronize];
     //*/
}

- (void)cleanAppAuthWithPlatformType:(CPPlatformAuthType)type {
    switch (type) {
        case CPPlatformAuthType_Facebook: {
            [self cleanFacebookAuth];
            break;
        }
        case CPPlatformAuthType_Twitch: {
            [self cleanTwitchAuth];
            break;
        }
        case CPPlatformAuthType_YouTube: {
            [self cleanYoutubeAuth];
            break;
        }
        case CPPlatformAuthType_Twitter: {
            [self cleanTwitterAuth];
            break;
        }
        default:
            break;
    }
}

- (void)cleanAllPlatformAppAuth {
    [self cleanYoutubeAuth];
    [self cleanTwitchAuth];
    [self cleanFacebookAuth];
    [self cleanTwitterAuth];
}

@end

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
#import "GCYoutubeLiveStream.h"

#import "CustomUserDefault.h"
#import "GCFileManager.h"

/* Keychain item name for saving the user's authentication information.*/
NSString *const kGTMAppAuthKeychainItemName = @"com.GoCreate.GoCreate:YouTube.AppAuth";

// twitch keychain
NSString *const kTWITCHAppAuthKeychainItemName = @"hql.twitch.example:Twitch.AppAuth";

@interface CPPlatformAuthManager () <GCYoutubeLiveStreamDelegate, HQLTwitchOAuthDelegate, CPFacebookOAuthDelegate>

@property (strong, nonatomic) CPYouTubeOAuth *youtubeOAuth;
@property (strong, nonatomic) HQLTwitchOAuth *twitchOAuth;
@property (strong, nonatomic) CPFacebookOAuth *facebookOAuth;
@property (strong, nonatomic) GCYoutubeLiveStream *youtubeLiveStream;

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

#pragma mark - prepare

- (void)loadState {
    [self setYoutubeAuth:[GTMAppAuthFetcherAuthorization authorizationFromKeychainForName:kGTMAppAuthKeychainItemName]];
    [self setTwitchAuth:[TwitchAppFetcherAuthorization authorizationFromKeychainForName:kTWITCHAppAuthKeychainItemName]];
    [self setFacebookAuth:[FBSDKAccessToken currentAccessToken]];
    
//    [self setFacebookIsLoginWithBroadcast:[[CustomUserDefault standardUserDefaults] boolForKey:FacebookIsLoginWithBroadcast]];
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
//        self.facebookOAuth.delegate = self;
    }
}

#pragma mark - tool

- (BOOL)platformIsAuthWithPlatformType:(CPPlatformAuthType)type {
    switch (type) {
        case CPPlatformAuthType_YouTube: {
            return self.youtubeAuthorization;
        }
        case CPPlatformAuthType_Twitch: {
            return self.twitchAuthorization;
        }
        case CPPlatformAuthType_Facebook: {
            return self.facebookAuthorization;
        }
            
        default: {
            return NO;
        }
    }
}

#pragma mark - fetch auth

- (void)doAppAuthPlatformType:(CPPlatformAuthType)type presentController:(UIViewController *)controller thenHandler:(void (^)(CPPlatformAuthManager *, NSError *))handler {
    
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
            [self.facebookOAuth doFacebookBroadcastAuthWithPresentController:controller thenHandler:^(FBSDKAccessToken *authorization, NSError *error) {
                [_self setFacebookAuth:authorization];
                handler ? handler(_self, error) : nil;
            }];
            /*
            [self.facebookOAuth doFacebookCommonAuthWithPresentController:controller thenHandler:^(FBSDKAccessToken *authorization, NSError *error) {
                [_self setFacebookAuth:authorization];
                handler ? handler(_self, error) : nil;
            }];//*/
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
                    
                    [[CustomUserDefault standardUserDefaults] setObject:userInfo[@"name"] forKey:YouTubeAccountNickName];
                    [[CustomUserDefault standardUserDefaults] setObject:userInfo[@"picture"] forKey:YouTubeAccountIconURL];
                    [[CustomUserDefault standardUserDefaults] setObject:userInfo[@"email"] forKey:GCYouTubeUserAccount];
                    [[CustomUserDefault standardUserDefaults] synchronize];
                    
                    //[[GCFileManager sharedGCFileManager] createUserDirectoryWithBid:jsonDictionaryOrArray[@"email"]]; // 创建目录
                    [[GCFileManager sharedGCFileManager] createYouTubeAccountDirectoryWithAccount:userInfo[@"email"]];
                    
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
                    
                    [[CustomUserDefault standardUserDefaults] setObject:userInfo[@"display_name"] forKey:TwitchAccountNickName];
                    [[CustomUserDefault standardUserDefaults] setObject:userInfo[@"logo"] forKey:TwitchAccountIconURL];
                    [[CustomUserDefault standardUserDefaults] synchronize];
                    
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
                    [info setObject:_self.facebookAuthorization.tokenString forKey:@"user_token"];
                    
                    [[CustomUserDefault standardUserDefaults] setObject:info[@"user_name"] forKey:FacebookAccountNickName];
                    [[CustomUserDefault standardUserDefaults] setObject:info[@"user_icon"] forKey:FacebookAccountIconURL];
                    [[CustomUserDefault standardUserDefaults] synchronize];
                    
                }
                handler ? handler(info, error) : nil;
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
            [self.delegate broadcastError:[NSError errorWithDomain:CPPlatformAuthErrorDoMain code:-100 userInfo:@{@"message" : @"broadcast has been begin, can not start broadcast again", NSLocalizedDescriptionKey : @"broadcast has been begin, can not start broadcast again"}]];
        }
        return;
    }
    
    if (type == CPPlatformAuthType_UNKNOW) {
        if ([self.delegate respondsToSelector:@selector(broadcastError:)]) {
            [self.delegate broadcastError:[NSError errorWithDomain:CPPlatformAuthErrorDoMain code:-100 userInfo:@{@"message" : @"platform auth type can not be unknow", NSLocalizedDescriptionKey : @"platform auth type can not be unknow"}]];
        }
        return;
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
            self.youtubeLiveStream.presentVC = controller;
            [self.youtubeLiveStream startLiveBrocastWith:model CompleteHandle:^(NSString *broadcastURL, NSError *error) {
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
            
        default:
            break;
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
            [self.youtubeLiveStream stopLiveBroadcast];
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
            [self.youtubeLiveStream fetchLiveMessageWithCompleteHandler:^(GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError *error) {
                
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
            
            self.youtubeLiveStream.presentVC = controller;
            [self.youtubeLiveStream fetchLiveBroadcastStatusWithCompleteHandler:^(NSString *status) {
                
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

#pragma mark - notification

- (void)removeNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:YouTubeAuthorizationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TwitchAuthorizationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:FBSDKAccessTokenDidChangeNotification object:nil];
    
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
    
    [self.youtubeLiveStream stopBroadcastConnection];
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

/*
- (void)setFacebookIsLoginWithBroadcast:(BOOL)yesOrNo {
    if (self.facebookInLoginWithBroadcast == yesOrNo) {
        return;
    }
    self.facebookInLoginWithBroadcast = yesOrNo;
    [[CustomUserDefault standardUserDefaults] setObject:[NSNumber numberWithBool:yesOrNo] forKey:FacebookIsLoginWithBroadcast];
}//*/

#pragma mark - clean app auth

- (void)cleanYoutubeAuth {
    [self.youtubeOAuth cleanAppAuth];
    
//    [GTMAppAuthFetcherAuthorization removeAuthorizationFromKeychainForName:kGTMAppAuthKeychainItemName];
    
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:YouTubeAccountIconURL];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:YouTubeAccountNickName];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:GCYouTubeUserAccount];
    [[CustomUserDefault standardUserDefaults] synchronize];
}

- (void)cleanTwitchAuth {
    [self.twitchOAuth cleanAuthCache];
    
//    [TwitchAppFetcherAuthorization removeAuthorizationForKeychainForName:kTWITCHAppAuthKeychainItemName];
    
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:TwitchAccountIconURL];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:TwitchAccountNickName];
    [[CustomUserDefault standardUserDefaults] synchronize];
}

- (void)cleanFacebookAuth {
    [self.facebookOAuth cleanAppAuth];
    
    //[self setFacebookIsLoginWithBroadcast:NO];
    
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:FacebookJoinedGroupKey];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:FacebookStreamTargetKey];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:FacebookStreamGroupKey];
    
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:FacebookAccountIconURL];
    [[CustomUserDefault standardUserDefaults] removeObjectForKey:FacebookAccountNickName];
    [[CustomUserDefault standardUserDefaults] synchronize];
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
        default:
            break;
    }
}

- (void)cleanAllPlatformAppAuth {
    [self cleanYoutubeAuth];
    [self cleanTwitchAuth];
    [self cleanFacebookAuth];
}

#pragma mark - getter

- (GCYoutubeLiveStream *)youtubeLiveStream {
    if (!_youtubeLiveStream) {
        _youtubeLiveStream = [[GCYoutubeLiveStream alloc] init];
        _youtubeLiveStream.delegate = self;
    }
    return _youtubeLiveStream;
}

@end

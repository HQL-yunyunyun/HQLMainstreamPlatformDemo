//
//  CPPlatformAuthManager.h
//  GoCreate3.0
//
//  Created by 何启亮 on 2017/11/13.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPYouTubeOAuth.h"
#import "HQLTwitchOAuth.h"
#import "CPFacebookOAuth.h"
#import "GCYoutubeLiveStream.h"

typedef NS_ENUM(NSInteger, CPPlatformAuthType) {
    CPPlatformAuthType_Facebook = 1,
    CPPlatformAuthType_YouTube = 2,
    CPPlatformAuthType_Twitch = 3,
    CPPlatformAuthType_UNKNOW = 101,
};

typedef NS_ENUM(NSInteger, CPPlatformBroadcastStatus) { // 三个状态
    CPPlatformBroadcastStatus_off_line = 0,
    CPPlatformBroadcastStatus_live,
    CPPlatformBroadcastStatus_live_stopped, // Facebook独有
};

static NSString *const CPPlatformAuthErrorDoMain = @"GoCreate.thirdlyPlatform.broadcastAuthorization.error.doMain";

static NSString *const YouTubeAccountNickName = @"YouTubeAccountNickName";
static NSString *const YouTubeAccountIconURL = @"YouTubeAccountIconURL";

static NSString *const FacebookAccountNickName = @"FacebookAccountNickName";
static NSString *const FacebookAccountIconURL = @"FacebookAccountIconURL";
static NSString *const FacebookIsLoginWithBroadcast = @"FacebookIsLoginWithBroadcast";

static NSString *const TwitchAccountNickName = @"TwitchAccountNickName";
static NSString *const TwitchAccountIconURL = @"TwitchAccountIconURL";

@protocol CPPlatformAuthManagerDelegate <NSObject>

- (void)broadcastError:(NSError *)error;

- (void)broadcastStatusDidChange:(CPPlatformBroadcastStatus)status platformType:(CPPlatformAuthType)type;

/*
 {
 @"name" : name,
 @"message" : message,
 @"message_id" : message_id,
 }
 */
- (void)broadcastDidReceiveLiveMessages:(NSArray <NSDictionary *>*)messages platformType:(CPPlatformAuthType)type;

- (void)broadcastDidReceiveLiveMessagesError:(NSError *)error platformType:(CPPlatformAuthType)type;

@end

// 保存三方的授权 --- 主要面向于直播
@interface CPPlatformAuthManager : NSObject

+ (CPPlatformAuthManager *)shareManager;

@property (assign, nonatomic) id <CPPlatformAuthManagerDelegate>delegate;

@property (strong, nonatomic, readonly) CPYouTubeOAuth *youtubeOAuth;
@property (strong, nonatomic, readonly) HQLTwitchOAuth *twitchOAuth;
@property (strong, nonatomic, readonly) CPFacebookOAuth *facebookOAuth;
@property (strong, nonatomic, readonly) GCYoutubeLiveStream *youtubeLiveStream;

@property (nonatomic, strong) TwitchAppFetcherAuthorization *twitchAuthorization;
@property (nonatomic, strong) GTMAppAuthFetcherAuthorization *youtubeAuthorization;
@property (nonatomic, strong) FBSDKAccessToken *facebookAuthorization;

//@property (nonatomic, assign) BOOL facebookInLoginWithBroadcast;

// tool

- (BOOL)platformIsAuthWithPlatformType:(CPPlatformAuthType)type;

// fetch auth

- (void)doAppAuthPlatformType:(CPPlatformAuthType)type presentController:(UIViewController *)controller thenHandler:(void(^)(CPPlatformAuthManager *manager, NSError *error))handler;
- (void)fetchUserInfoWithPlatformType:(CPPlatformAuthType)type presentController:(UIViewController *)controller completeHandler:(void(^)(NSDictionary *info, NSError *error))handler;



// clean auth

- (void)cleanAppAuthWithPlatformType:(CPPlatformAuthType)type;
- (void)cleanAllPlatformAppAuth;

// broadcast
/*
 {
 @"broadcast_type_facebook" : facebook broadcast type,
 @"broadcast_id_facebook" : 与BroadcastType相对应的ID
 @"title" : 标题 --- 只有YouTube的时候有用
 @"description" : 描述
 }
 */
- (void)startBroadcastWithType:(CPPlatformAuthType)type param:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void(^)(NSString *broadcastURL))handler;
- (void)startFacebookBroadcastWithLiveVideoID:(NSString *)liveVideoID; // facebook 的特殊情况
- (void)stopBroadcast;

// 获取直播状态
- (void)autoFetchBroadcastStatusWithPresentController:(UIViewController *)controller;
- (void)stopAutoFetchBroadcastStatus;

// 只有在startBroadcast之后才会有用
- (void)autoFetchLiveMessagesWithPresentController:(UIViewController *)controller;
- (void)stopAutoFetchLiveMessages;

// 获取直播信息
- (void)fetchBroadcastDetailInfoWithPresentController:(UIViewController *)controller completeHandler:(void(^)(NSInteger viewer, NSInteger likeCount))handler;

@end


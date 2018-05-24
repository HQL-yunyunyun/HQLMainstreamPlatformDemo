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
#import "CPTwitterOAuth.h"

typedef NS_ENUM(NSInteger, CPPlatformAuthType) {
    CPPlatformAuthType_Facebook = 1,
    CPPlatformAuthType_YouTube = 2,
    CPPlatformAuthType_Twitch = 3,
    CPPlatformAuthType_Twitter = 4,
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

static NSString *const TwitchAccountNickName = @"TwitchAccountNickName";
static NSString *const TwitchAccountIconURL = @"TwitchAccountIconURL";

static NSString *const TwitterAccountNickName = @"TwitterAccountNickName";
static NSString *const TwitterAccountIconURL = @"TwitterAccountIconURL";

@protocol CPPlatformAuthManagerDelegate <NSObject>

/**
 直播时的错误

 @param error 错误
 */
- (void)broadcastError:(NSError *)error;

/**
 直播状态改变

 @param status 直播状态
 @param type 当前进行直播的平台
 */
- (void)broadcastStatusDidChange:(CPPlatformBroadcastStatus)status platformType:(CPPlatformAuthType)type;

/*
 {
 @"name" : name,
 @"message" : message,
 @"message_id" : message_id,
 }
 */
/**
 直播时的评论

 @param messages messages
 @param type 当前进行直播的平台
 */
- (void)broadcastDidReceiveLiveMessages:(NSArray <NSDictionary *>*)messages platformType:(CPPlatformAuthType)type;

/**
 获取评论时出现的问题

 @param error error
 @param type 当前进行直播的平台
 */
- (void)broadcastDidReceiveLiveMessagesError:(NSError *)error platformType:(CPPlatformAuthType)type;

@end

// 保存三方的授权 --- 上传 & 直播
@interface CPPlatformAuthManager : NSObject

+ (CPPlatformAuthManager *)shareManager;

/**
 delegate
 */
@property (assign, nonatomic) id <CPPlatformAuthManagerDelegate>delegate;

// auth object
@property (strong, nonatomic, readonly) CPYouTubeOAuth *youtubeOAuth;
@property (strong, nonatomic, readonly) HQLTwitchOAuth *twitchOAuth;
@property (strong, nonatomic, readonly) CPFacebookOAuth *facebookOAuth;
@property (strong, nonatomic, readonly) CPTwitterOAuth *twitterOAuth;

@property (nonatomic, strong) TwitchAppFetcherAuthorization *twitchAuthorization;
@property (nonatomic, strong) GTMAppAuthFetcherAuthorization *youtubeAuthorization;
@property (nonatomic, strong) FBSDKAccessToken *facebookAuthorization;
@property (nonatomic, strong) TWTRSession *twitterAuthorization;

#pragma mark - tool

/**
 是否有授权

 @param type 平台
 @return yesOrNo
 */
- (BOOL)platformIsAuthWithPlatformType:(CPPlatformAuthType)type;

#pragma mark - fetch auth

/*
 Facebook 授权取消:
 [error.localizedDescription isEqualToString:@"fecth facebook authorization request did cancel"]
 
 YouTube 授权取消:
 error.code == -4
 
 Twitch 授权取消:
 [error.localizedDescription isEqualToString:@"fecth twitch authorization request did cancel"]
 
 Twitter 授权取消:
 error.code = 1;
 */

/**
 授权

 @param type 平台
 @param controller present Controller
 @param otherParam 其他param --- 暂时用在Facebook的授权@{@"permissions" : NSArray}
 @param handler 回调
 */
- (void)doAppAuthPlatformType:(CPPlatformAuthType)type presentController:(UIViewController *)controller otherParam:(NSDictionary *)otherParam thenHandler:(void(^)(CPPlatformAuthManager *manager, NSError *error))handler;

/**
 获取用户信息

 @param type 平台
 @param controller present Controller
 @param handler 回调
 */
- (void)fetchUserInfoWithPlatformType:(CPPlatformAuthType)type presentController:(UIViewController *)controller completeHandler:(void(^)(NSDictionary *info, NSError *error))handler;


/**
 清除某一平台的授权

 @param type 平台
 */
- (void)cleanAppAuthWithPlatformType:(CPPlatformAuthType)type;

/**
 清除全部平台的授权
 */
- (void)cleanAllPlatformAppAuth;

#pragma mark - broadcast

/*
 {
 @"broadcast_type_facebook" : facebook broadcast type,
 @"broadcast_id_facebook" : 与BroadcastType相对应的ID
 @"title" : 标题 --- 只有YouTube的时候有用
 @"description" : 描述
 }
 */

/**
 开始直播 --- 都会进行权限检测

 @param type 平台
 @param param 参数
 @param controller present Controller
 @param handler 回调
 */
- (void)startBroadcastWithType:(CPPlatformAuthType)type param:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void(^)(NSString *broadcastURL))handler;

/**
 通过 live id 开始直播(当应用从后台进入到前台或打开应用时 检测到正在直播)

 @param liveVideoID live video id
 */
- (void)startFacebookBroadcastWithLiveVideoID:(NSString *)liveVideoID; // facebook 的特殊情况

/**
 停止直播
 */
- (void)stopBroadcast;

// 只有在startBroadcast之后才会有用 ----

/**
 开始自动获取直播状态(一次只能直播一个平台)

 @param controller present Controller
 */
- (void)autoFetchBroadcastStatusWithPresentController:(UIViewController *)controller;

/**
 停止自动获取直播状态
 */
- (void)stopAutoFetchBroadcastStatus;

/**
 开始自动获取直播时的评论

 @param controller present Controller
 */
- (void)autoFetchLiveMessagesWithPresentController:(UIViewController *)controller;

/**
 停止自动获取直播时的评论
 */
- (void)stopAutoFetchLiveMessages;

/**
 获取直播信息

 @param controller present Controller
 @param handler 回调(观看数, 喜欢数)
 */
- (void)fetchBroadcastDetailInfoWithPresentController:(UIViewController *)controller completeHandler:(void(^)(NSInteger viewer, NSInteger likeCount))handler;

#pragma mark - upload method

/*
 上传param
 title : NSString , (Facebook, YouTube)
 description : NSString , (Facebook, YouTube, Twitter)
 tags : string (空格隔开) , (YouTube)
 privacy: NSString , (Facebook, YouTube) (注意 Facebook 必须使用[CPFacebookOAuth getPublishPrivacyStringWith:allowArray:denyArray:]来获取string, YouTube则使用正常的privacyStatus 来获取)
 thumbURL : NSString , (Facebook(只能是视频中的某一帧), YouTube)
 resumeString : NSString , (Facebook, YouTube, Twitter) (YouTube 就是 uploadLocationURL, 而 Facebook 就是 session_id, Twitter 就是 media_id)
 send_id : NSString , (Facebook) (就是指要发布的地方:timeline/page/group/event) (page_id / user_id / event_id / group_id)
 videoURL : NSString  , (Facebook, YouTube, Twitter)
 */

/*
 完成回调中的userDictionary 会记录视频上传完成后的URL @"videoLink"
 */

/*
 创建上传任务时，都得保证视频源的正确 --- 不会去检测视频时候有改动
 */

/**
 创建一个上传任务
 Facebook 会返回一个 [CPFacebookUploader class]
 YouTube 会返回一个   [GTLRServiceTicket class]
 Twitter 会返回一个      [CPTwitterUploader class]
 
 @param param param(见上面的说明)
 @param platformType 平台
 @param videoURL videoURL
 @param presentController presentController
 @param progressHandler 上传中的回调
 @param completeHandler 上传完成的回调
 @return uploader
 */
- (id)createVideoUploadTicketWithParam:(NSDictionary *)param
                                             platformType:(CPPlatformAuthType)platformType
                                                  videoURL:(NSString *)videoURL
                                      presentController:(UIViewController *)presentController
                                       progressHandler:(void(^)(id progressUploader, double uploadedPercent))progressHandler
                                       completeHandler:(void(^)(id completeUploader, NSError *error, NSDictionary *userDict))completeHandler;

@end


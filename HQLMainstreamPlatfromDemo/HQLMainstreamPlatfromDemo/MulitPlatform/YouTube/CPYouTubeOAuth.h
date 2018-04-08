//
//  GCGoogleAuthFetcherManager.h
//  GoCreate3.0
//
//  Created by 何启亮 on 2017/9/18.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GTMAppAuth/GTMAppAuth.h>
#import <GTLRYouTube.h>

@class CPYoutubeBrocastRoomModel;

static NSString *const YouTubeErrorDomain = @"cp.YouTubeErrorDomain";

static NSString *const YouTubeAuthorizationDidChangeNotification = @"cp.YouTubeAuthorizationDidChangeNotification";
static NSString *const YouTubeAuthorizationDidChangeNotificationAuthorizationKey = @"cp.YouTubeAuthorizationDidChangeNotificationAuthorizationKey";

@interface CPYouTubeOAuth : NSObject

@property (atomic, strong, readonly) GTMAppAuthFetcherAuthorization *authorization;

- (instancetype)initWithAuthorization:(GTMAppAuthFetcherAuthorization *)authorization;

#pragma mark - auth method

- (void)doYouTubeAuthWithPresentController:(UIViewController *)controller thenHandler:(void(^)(GTMAppAuthFetcherAuthorization *authorization, NSError *error))handler;

- (void)cleanAppAuth;

- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void(^)(NSDictionary *userInfo, NSError *error))handler;

#pragma mark - stream method

/**
 创建YouTube直播连接

 @param room 直播间的设置
 @param presentController presentController
 @param completeHandler 回调
 */
- (void)startLiveBroadcastWithRoomModel:(CPYoutubeBrocastRoomModel *)room presentController:(UIViewController *)presentController completeHandler:(void(^)(NSString *broadcastURL, NSError *error))completeHandler; // 使用默认频道 --- 不会再去创建一个频道

/**
 停止直播
 */
- (void)stopLiveBroadcast;//停止直播

/**
 停止所有直播相关的连接
 */
- (void)stopBroadcastConnection;

/**
 获取直播的状态

 @param handler 回调
 */
- (void)fetchLiveBroadcastStatusWithCompleteHandler:(void (^)(NSString *))handler;

/**
 获取liveMessage

 @param handler 回调
 */
- (void)fetchLiveMessageWithCompleteHandler:(void(^)(GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError *error))handler;

#pragma mark - video upload method

/**
 创建一个youtube上传任务
 
 param = @{
 @"title" : string , // 标题 必须的参数
 @"description" : string , // 描述 可选
 @"tags" : string , // tag 可选
 @"privacyStatus" : string , // 视频权限 必须 直接用YouTube定义的string
 @"thumbnailURL" : string , // 缩略图 可选
 @"uploadLocationURL" : string , // 可选 --- 断点续传的url --- 在response中
 }

 privacyStatus :
     kGTLRYouTube_VideoStatus_PrivacyStatus_Private Value "private"
     kGTLRYouTube_VideoStatus_PrivacyStatus_Public Value "public"
     kGTLRYouTube_VideoStatus_PrivacyStatus_Unlisted Value "unlisted"
 
 @param param 参数字典
 @param presentController presentController
 @param videoUrl 需要上传的video 地址
 @param uploadProgressHandler 上传进度的回调
 @param completeHandler 完成时的回调
 @return 任务ticket
 */
- (GTLRServiceTicket *)createYouTubeVideoUploadTicketWithParam:(NSDictionary *)param
                                                                                   presentController:(UIViewController *)presentController
                                                                                                  videoUrl:(NSURL *)videoUrl
                                                 uploadProgressHandler:(GTLRServiceUploadProgressBlock)uploadProgressHandler
                                                 completeHandler:(GTLRServiceCompletionHandler)completeHandler;

/**
 创建一个youtube上传任务
 
 @param video video的一些参数 具体请看 GTLRYouTube_Video
 @param uploadParam 上传参数 具体请看 GTLRUploadParameters
 @param presentController 授权时present的controller
 @param uploadProgressHandler 上传进度的回调
 @param completeHandler 完成时回调
 */
- (GTLRServiceTicket *)createYouTubeVideoUploadTicketWithVideo:(GTLRYouTube_Video *)video
                                                                                        uploadParam:(GTLRUploadParameters *)uploadParam
                                                                                  presentController:(UIViewController *)presentController
                                               uploadProgressHandler:(GTLRServiceUploadProgressBlock)uploadProgressHandler
                                               completeHandler:(GTLRServiceCompletionHandler)completeHandler;

/**
 删除YouTube频道上的视频

 @param userID YouTubeUserID
 @param videoId 要删除的VideoID
 @param completeHandler 完成时回调
 */
- (void)removeYouTubeVideoWithUserID:(NSString *)userID videoId:(NSString *)videoId completeHandler:(GTLRServiceCompletionHandler)completeHandler;

@end

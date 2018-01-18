//
//  GCYoutubeLiveStream.h
//  GoCreate3.0
//
//  Created by lious_li on 2017/8/14.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GTLRYouTube.h>
#import <GTMAppAuth.h>
#import "CPYoutubeBrocastRoomModel.h"

@protocol GCYoutubeLiveStreamDelegate <NSObject>

@optional
/*
- (void) liveMessageChanged:(NSArray<GTLRYouTube_LiveChatMessage *> *) liveChats;
- (void) liveMessageDidReceiveError:(GTLRErrorObject *)error; // 聊天室错误 --- 403 --- 404
- (void) liveBroadcastStatusDidChanged:(NSString *) status;
- (void) liveBroadcastStatusChanged:(GCYoutubeLiveStreamLiveStatus) status;
- (void) liveBroadcastError:(NSError *) error;
//*/

- (void) updateUserInfo;

- (void)appAuthDidRemove;

@end

@interface GCYoutubeLiveStream : NSObject

//@property (nonatomic, assign) BOOL updateUI;
//@property (nonatomic, assign) BOOL requestingLS;

@property (nonatomic, strong) CPYoutubeBrocastRoomModel *roomModel;
/*
 email = "goplay201705@gmail.com";
 "email_verified" = 1;
 "family_name" = "";
 "given_name" = "GoPlay Game Moments";
 locale = "zh-CN";
 name = "GoPlay Game Moments";
 picture = "https://lh6.googleusercontent.com/-htuJyWmrrIw/AAAAAAAAAAI/AAAAAAAAAHc/NJBPofiWqCk/photo.jpg";
 sub = 106131840738534376500;
 */
@property (nonatomic, strong) NSDictionary *userInfo;

@property (nonatomic, weak) UIViewController *presentVC;
@property (nonatomic, strong) GTLRYouTube_LiveBroadcast *youtubeLiveBroadcast;
@property (nonatomic, weak) id<GCYoutubeLiveStreamDelegate> delegate;

- (void) clearAppAuth;

- (void) startLiveBrocastWith:(CPYoutubeBrocastRoomModel *) room CompleteHandle:(void(^)(NSString * broadcastURL, NSError *error)) completeHandle;//使用默认频道直播
- (void) stopLiveBroadcast;//停止直播

- (void)stopBroadcastConnection;

- (void)fetchLiveBroadcastStatusWithCompleteHandler:(void(^)(NSString *status))handler;

- (void)getUserInfoWithCompleteHandler:(void(^)(NSError *error))completeHandler;

- (void)fetchLiveMessageWithCompleteHandler:(void(^)(GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError *error))handler;

/*
 - (void) backToPreviousPageLiveMessageCompleteHandle:(void(^)(NSArray<GTLRYouTube_LiveChatMessage*> *liveChats)) completeHandle;
 - (void) startAutoLoadLiveChatMessages;
 - (void) stopAutoLoadLiveChatMessages;
 //*/

/*----- YouTube upload video method -----*/

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
 
 @param param 参数字典
 @param videoUrl 需要上传的video 地址
 @param uploadProgressHandler 上传进度的回调
 @param completeHandler 完成时的回调
 */
- (GTLRServiceTicket *)createYouTubeVideoUploadTicketWithParam:(NSDictionary *)param
                                                                                   videoUrl:(NSURL *)videoUrl
                                                            uploadProgressHandler:(GTLRServiceUploadProgressBlock)uploadProgressHandler
                                                                      completeHandler:(GTLRServiceCompletionHandler)completeHandler;

/**
 创建一个youtube上传任务

 @param video video的一些参数 具体请看 GTLRYouTube_Video
 @param uploadParam 上传参数 具体请看 GTLRUploadParameters
 @param uploadProgressHandler 上传进度的回调
 @param completeHandler 完成时回调
 */
- (GTLRServiceTicket *)createYouTubeVideoUploadTicketWithVideo:(GTLRYouTube_Video *)video
                                                                         uploadParam:(GTLRUploadParameters *)uploadParam
                                                          uploadProgressHandler:(GTLRServiceUploadProgressBlock)uploadProgressHandler
                                                                    completeHandler:(GTLRServiceCompletionHandler)completeHandler;

/**
 删除视频

 @param userAccount 要删除的视频的用户账号
 @param videoId 视频id
 @param completeHandler 完成时的回调
 */
- (void)removeYouTubeVideoWithUserAccount:(NSString *)userAccount videoId:(NSString *)videoId completeHandler:(GTLRServiceCompletionHandler)completeHandler;

@end

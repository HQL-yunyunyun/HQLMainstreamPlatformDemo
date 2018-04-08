//
//  CPTwitterOAuth.h
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/14.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TwitterKit/TWTRKit.h>
#import "CPTwitterUploader.h"

static NSString * const TwitterAuthorizationDidChangeNotificationAuthorizationKey = @"cp.TwitterAuthorizationDidChangeNotificationAuthorizationKey";
static NSString * const TwitterAuthorizationDidChangeNotification = @"cp.TwitterAuthorizationDidChangeNotification";

@interface CPTwitterOAuth : NSObject

@property (nonatomic, strong, readonly) TWTRSession *authorization;

- (instancetype)initWithAuthorization:(TWTRSession *)authorization;

#pragma mark - auth method

// 授权 --- twitter SDK 是可以登录多个账号的，但我们只持有一个账号
- (void)doTwitterAuthWithPresentController:(UIViewController *)presentController thenHandler:(void(^)(TWTRSession *authorization, NSError *error))handler;

// 清理auth
- (void)clearAuth;

// 获取当前登录的用户信息
- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void(^)(TWTRUser *user, NSError *error))handler;

#pragma mark - video upload method

/**
 判断视频是否可以符合上传规则
 1、时长不能大于140s
 2、大小不能大于512m
 ---- 暂时不能判断第三和第四
 3、帧率不能高于40fps
 4、声道相关的设置

 @param videoURL video file url
 @return yesOrNo
 */
+ (BOOL)videoCanUploadWithVideoURL:(NSURL *)videoURL;


/**
 创建一个上传任务

 paramDict = @{
 @"videoURL" : NSString, // 视频地址
 @"tweetText" : NSString, // tweetText
 @"resumeMediaId" : NSString, // 断点续传的media_id
 }
 
 @param paramDict 上传param
 @param precentController 弹出授权的controller
 @param uploadProgressHandler 上传中的回调
 @param completeHandler 完成时回调
 @return uploader
 */
- (CPTwitterUploader *)createTwitterVideoUploadTicketWithParamDict:(NSDictionary *)paramDict
                                                 precentController:(UIViewController *)precentController
                                     uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
                                     completeHandler:(CPUploaderCompleteHandler)completeHandler;

@end

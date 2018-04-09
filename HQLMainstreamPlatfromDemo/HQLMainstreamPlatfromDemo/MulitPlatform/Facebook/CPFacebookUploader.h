//
//  CPFacebookUploader.h
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/26.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import "CPFacebookUploadInfoRecord.h"
#import "CPUploader.h"
#import <FBSDKCoreKit/FBSDKCoreKit.h>

/*
 Facebook 断点续传跟Twitter差不多，也是开启一个上传任务 --- 上传视频块 --- 结束上传并发布
 但Facebook上传前需要先检测Facebook权限 @"publish_actions"
 
 Facebook 发布视频拟支持一下字段
 title : NSString
 description : NSString
 thumb : image-data
 privacy : NSString (暂时只支持 EVERYONE, ALL_FRIENDS, FRIENDS_OF_FRIENDS,CUSTOM, SELF)
 https://developers.facebook.com/docs/graph-api/common-scenarios#privacy-param
 */

static NSString *const CPFacebookErrorDomain = @"CPTwitterMediaErrorDomain";
#define kFacebookErrorCode (-10000)

@interface CPFacebookUploader : CPUploader

@property (nonatomic, strong, readonly) CPFacebookUploadInfoRecord *uploadInfoRecord;

@property (nonatomic, copy, readonly) NSString *videoLink;

#pragma mark -

/**
 创建一个上传任务

 @param param param
 @param uploadProgressHandler progress回调
 @param completeHandler complete回调
 @return uploader
 */
+ (instancetype)createFacebookUploadTicketWithParam:(CPUploadParam *)param
                          uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
                          completeHandler:(CPUploaderCompleteHandler)completeHandler;
// 创建一个任务
- (instancetype)initWithParam:(CPUploadParam *)param
                         uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
                         completeHandler:(CPUploaderCompleteHandler)completeHandler;

+ (void)deleteVideoWithVideo_id:(NSString *)video_id completion:(void(^)(BOOL success, NSError *error))completion;

@end

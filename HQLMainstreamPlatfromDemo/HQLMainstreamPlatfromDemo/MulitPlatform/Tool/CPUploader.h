//
//  CPUploader.h
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/27.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CPUploadParam.h"
#import "CPFile.h"

#define k_POST @"POST"
#define k_GET @"GET"
#define k_DELETE @"DELETE"

@class CPUploader;

typedef void(^CPUploaderProgressHandler)(CPUploader * _Nullable progressUploader,
                                         double uploadedPercent);

typedef void(^CPUploaderCompleteHandler)(CPUploader * _Nullable callbackUploader,
                                         NSError * _Nullable error);

@interface CPUploader : NSObject

@property (nonatomic, assign, getter=isCancel) BOOL cancel; // 是否取消
@property (nonatomic, assign, getter=isPause) BOOL pause; // 是否暂停

@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTaskIdentifier;

// 文件
@property (nonatomic, strong) CPFile * _Nullable file;

@property (nonatomic, copy) CPUploaderProgressHandler _Nullable progressHandler;
@property (nonatomic, copy) CPUploaderCompleteHandler _Nullable completeHandler;

#pragma mark - upload method

/**
 取消上传
 */
- (void)cancel;

/**
 恢复上传 --- 刚创建好任务的时候也是通过这个来开始任务
 */
- (void)resume;

/**
 暂停上传
 */
- (void)pause;

#pragma mark -

// 创建一个任务
- (BOOL)createUploadTicketWithParam:(CPUploadParam *_Nonnull)param
               uploadProgressHandler:(CPUploaderProgressHandler _Nonnull )uploadProgressHandler
               completeHandler:(CPUploaderCompleteHandler _Nonnull )completeHandler;

// 开始后台任务
- (void)startBackgroundTask;
// 结束后台任务
- (void)endBackgroundTask;

#pragma mark -

// 写infoRecord
- (BOOL)writeRecrodInfoToDisk:(NSDictionary *_Nonnull)infoRecord media_id:(NSString *_Nonnull)media_id;

// 获取infoRecord
- (NSDictionary *_Nullable)getRecordInfoWithMediaID:(NSString *_Nonnull)mediaID;

// 移除本地记录
- (BOOL)removeRecordInfoWithMediaID:(NSString *_Nonnull)mediaID;

#pragma mark -

// 获取文件大小
- (NSInteger)getVideoSizeWithURL:(NSString *_Nonnull)url;

@end

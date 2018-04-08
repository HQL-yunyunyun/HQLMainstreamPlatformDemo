//
//  CPTwitterUploader.h
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/19.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TwitterKit/TWTRKit.h>
#import "CPUploader.h"

#import "CPTwitterUploadInfoRecord.h"

/**
 上传流程：
 documents : https://developer.twitter.com/en/docs/media/upload-media/api-reference/post-media-upload-init
 1、创建一个上传任务(返回一个mediaId，后面几步都必须带上mediaId) --- 调用Twitter的Api(media/upload(INIT))
 2、上传视频 --- 调用Twitter的Api(media/upload(APPEND))
 3、上传完成 --- 调用Twitter的Api(media/upload(FINALIZE))
 4、发送tweet(只有在media上传完成之后才能发,使用STATUS命令查询media上传情况,只有在成功的情况下可以发推)
 注意:STATUS命令只有在发送FINALIZE命令后才有用？ --- STATUS命令只有在FINALIZE命令后调用才有用，但在INIT的时候，所有参数都得是正确的，不然就会返回400的情况，而reason也是含糊不清。(例:试过上传的视频的格式是MOV，但在media_type参数传的是video/MP4，这样参数是错误的，出现了调用STATUS和FINIALIZE命令时返回400的情况)
 
 注意:
 如果是上传video的时候，在INIT时一定要加入下面的参数 --- 不然使用STATUS命令时会返回400错误
 'media_category': u'amplify_video'
 注意:
 视频格式一定按照文档给定的格式
 
 断点续传：
 1、本地根据mediaID保存uploadInfoRecord
 2、当创建任务的时候，根据传进来的mediaID查找保存到的uploadInfoRecord，如果没有就开始一个新的任务(注意：传进来的videoURL要替换保存的uploadInfoRecord的videoURL，因为每次开关机，沙盒的地址都会有变化)
 3、如果本地有保存，则先检查过期时间，过期时间到了则开始新任务，没到则到线上查找该任务的状态，再根据任务的状态做出相关的操作(失败---重新开始、上传中---继续上传、上传成功---成功的回调并发推(如果没有发推的情况))
 */

static NSString *const CPTwitterMediaErrorDomain = @"CPTwitterMediaErrorDomain";
#define kTwitterErrorCode (-10000)

@interface CPTwitterUploader : CPUploader

@property (nonatomic, strong, readonly) CPTwitterUploadInfoRecord *uploadInfoRecord; // 记录一些上传的参数

// video的tweet
@property (nonatomic, strong, readonly) TWTRTweet *tweet;

#pragma mark -

/**
 创建一个上传任务

 @param param 上传param
 @param uploadProgressHandler 上传中回调
 @param completeHandler 完成时回调
 @return uploader
 */
+ (instancetype)createTwitterVideoUploadTicketWithParam:(CPUploadParam *)param
                          uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
                          completeHandler:(CPUploaderCompleteHandler)completeHandler;

// 创建一个任务
- (instancetype)initWithParam:(CPUploadParam *)param
                         uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
                         completeHandler:(CPUploaderCompleteHandler)completeHandler;

@end

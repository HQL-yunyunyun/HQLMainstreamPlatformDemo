//
//  CPUploadParam.h
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/27.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CPUploadParam : NSObject

/**
 用户id
 */
@property (nonatomic, copy, nonnull) NSString *userID; // 用户ID

/**
 上传的视频地址
 */
@property (nonatomic, copy, nonnull) NSString *videoURL;

/**
 视频发布的参数
 如果是Twitter就是@{@"status" : NSString}
 如果是Facebook 可以参考 https://developers.facebook.com/docs/graph-api/video-uploads
 */
@property (nonatomic, strong, nullable) NSDictionary *publishParam; // 视频发布的参数

/**
 Facebook发布的id page_id / user_id / event_id / group_id
 */
@property (nonatomic, copy, nonnull) NSString *sendID;

/**
 断点上传记录的id --- Twitter是media_id Facebook是 upload_session_id
 */
@property (nonatomic, copy, nullable) NSString *resumeMediaId;

@end

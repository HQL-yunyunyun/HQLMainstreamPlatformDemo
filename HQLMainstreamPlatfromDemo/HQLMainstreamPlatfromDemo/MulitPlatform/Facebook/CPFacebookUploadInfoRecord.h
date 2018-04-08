//
//  CPFacebookUploadInfoRecord.h
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/26.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <YYModel/YYModel.h>

@interface CPFacebookUploadInfoRecord : NSObject <YYModel>

@property (nonatomic, copy) NSString *userID; // ID

@property (nonatomic, copy) NSString *video_id; // 视频编号
@property (nonatomic, copy) NSString *session_id; // 返回的session_id
@property (nonatomic, assign) NSInteger start_offset; // 块开始的index
@property (nonatomic, assign) NSInteger end_offset; // 块结束的index

@property (nonatomic, strong) NSDictionary *publishParam; // 发布param
@property (nonatomic, copy) NSString *sendID; // 视频发布的id --- page_id / user_id / event_id / group_id

@property (nonatomic, copy) NSString *videoName;

@end

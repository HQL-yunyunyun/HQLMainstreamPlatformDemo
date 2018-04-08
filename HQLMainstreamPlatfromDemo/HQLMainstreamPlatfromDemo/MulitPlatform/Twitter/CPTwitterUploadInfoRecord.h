//
//  CPTwitterUploadInfoRecord.h
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/15.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <YYModel/YYModel.h>

// 记录Twitter相关的参数
@interface CPTwitterUploadInfoRecord : NSObject <YYModel>

@property (nonatomic, copy) NSString *userID; // ID
@property (nonatomic, copy) NSString *media_id; // 返回的media_id
@property (nonatomic, assign) NSInteger uploaded_bytes; // 已上传的bytes
@property (nonatomic, assign) NSInteger chunk_bytes; // 每个片段的大小
@property (nonatomic, strong) NSDate *createDate; // 创建时间
@property (nonatomic, copy) NSString *tweetID; // 已发送的tweet的ID
@property (nonatomic, strong) NSDictionary *publishParam;

@property (nonatomic, assign) NSInteger expires_after_secs; // 过期时间
//@property (nonatomic, assign) NSInteger total_bytes; // 总长度
//@property (nonatomic, copy) NSString *videoURL; // 记录上传视频的URL

- (BOOL)taskIsExpires;

@end

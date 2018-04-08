//
//  QNFile.h
//  QiniuSDK
//
//  Created by bailong on 15/7/25.
//  Copyright (c) 2015年 Qiniu. All rights reserved.
//

#import "CPFileDelegate.h"
#import <Foundation/Foundation.h>

@interface CPFile : NSObject <CPFileDelegate>
/**
 *    打开指定文件
 *
 *    @param path      文件路径
 *    @param error     输出的错误信息
 *
 *    @return 实例
 */
- (instancetype)init:(NSString *)path
               error:(NSError *__autoreleasing *)error;

@end

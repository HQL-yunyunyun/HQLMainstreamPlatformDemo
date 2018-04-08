//
//  CPUploader.m
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/27.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import "CPUploader.h"

@implementation CPUploader

- (instancetype)init {
    if (self = [super init]) {
        self.pause = YES;
        self.cancel = NO;
    }
    return self;
}

#pragma mark -

- (void)pause {
    
}

- (void)cancel {
    
}

- (void)resume {
    
}

- (BOOL)createUploadTicketWithParam:(CPUploadParam *)param uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler completeHandler:(CPUploaderCompleteHandler)completeHandler {
    return NO;
}

#pragma mark -

// 后台任务
- (void)startBackgroundTask {
    
    NSString *taskName = [[self class] description];
    
    UIApplication *app = [UIApplication sharedApplication];
    
    // We'll use a locally-scoped task ID variable so the expiration block is guaranteed
    // to refer to this task rather than to whatever task the property has.
    __block UIBackgroundTaskIdentifier bgTaskID =
    [app beginBackgroundTaskWithName:taskName
                   expirationHandler:^{
                       // Background task expiration callback. This block is always invoked by
                       // UIApplication on the main thread.
                       if (bgTaskID != UIBackgroundTaskInvalid) {
                           @synchronized(self) {
                               if (bgTaskID == self.backgroundTaskIdentifier) {
                                   self.backgroundTaskIdentifier = UIBackgroundTaskInvalid;
                               }
                           }
                           // This explicitly ends the captured bgTaskID rather than the backgroundTaskIdentifier
                           // property to ensure expiration is handled even if the property has changed.
                           [app endBackgroundTask:bgTaskID];
                       }
                   }];
    @synchronized(self) {
        self.backgroundTaskIdentifier = bgTaskID;
    }
}

// 后台任务
- (void)endBackgroundTask {
    // Whenever the connection stops or a next page is about to be fetched,
    // tell UIApplication we're done.
    UIBackgroundTaskIdentifier bgTaskID;
    @synchronized(self) {
        bgTaskID = self.backgroundTaskIdentifier;
        self.backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }
    if (bgTaskID != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:bgTaskID];
    }
}

#pragma mark -

// 地址
- (NSString *)cacheDirectory {
    
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    NSString *cacheDirectory = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject;
    NSString *path = [cacheDirectory stringByAppendingPathComponent:@"_Media_Upload_Info_Record"];
    if (![fileMgr fileExistsAtPath:path]) {
        [fileMgr createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return path;
}

// 根据mediaID 获得记录
- (NSString *)pathWithMediaID:(NSString *)mediaID {
    if (mediaID.length <= 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@/%@", [self cacheDirectory], mediaID];
}

// 写infoRecord
- (BOOL)writeRecrodInfoToDisk:(NSDictionary *)infoRecord media_id:(NSString *)media_id {
    if (media_id.length <= 0) {
        return NO;
    }
    if (!infoRecord) {
        return NO;
    }
    
    NSString *path = [self pathWithMediaID:media_id];
    if (path.length <= 0) {
        return NO;
    }
    return [infoRecord writeToFile:path atomically:YES];
}

// 获取recordInfo
- (NSDictionary *)getRecordInfoWithMediaID:(NSString *)mediaID {
    if (mediaID.length <= 0) {
        return nil;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *path = [self pathWithMediaID:mediaID];
    if (![manager fileExistsAtPath:path]) {
        return nil;
    }
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    return dict;
}

// 移除本地记录
- (BOOL)removeRecordInfoWithMediaID:(NSString *)mediaID {
    if (mediaID.length <= 0) {
        return NO;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *path = [self pathWithMediaID:mediaID];
    if (![manager fileExistsAtPath:path]) {
        return YES;
    }
    
    return[manager removeItemAtPath:path error:nil];
}

#pragma mark -

// 获取文件大小
- (NSInteger)getVideoSizeWithURL:(NSString *)url {
    if (url.length <= 0) {
        return 0;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:url]) {
        return 0;
    }
    NSError *error;
    NSDictionary *dict = [manager attributesOfItemAtPath:url error:&error];
    if (error) {
        return 0;
    }
    
    return [[dict objectForKey:NSFileSize] integerValue];
}

@end

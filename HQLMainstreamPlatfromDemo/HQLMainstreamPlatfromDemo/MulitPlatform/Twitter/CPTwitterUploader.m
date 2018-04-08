//
//  CPTwitterUploader.m
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/19.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import "CPTwitterUploader.h"

#define kTwitterVideoUploadURL @"https://upload.twitter.com/1.1/media/upload.json"
#define kTwitterCreateTweetURL @"https://api.twitter.com/1.1/statuses/update.json"
#define kTwitterShowTweetURL @"https://api.twitter.com/1.1/statuses/show.json"
#define kTwitterDestroyTweetURL(tweetID) [NSString stringWithFormat:@"https://api.twitter.com/1.1/statuses/destroy/%@.json", tweetID]

#define kTwitterUploadCommand_INIT @"INIT"
#define kTwitterUploadCommand_APPEND @"APPEND"
#define kTwitterUploadCommand_STATUS @"STATUS"
#define kTwitterUploadCommand_FINALIZE @"FINALIZE"

typedef NS_ENUM(NSInteger, CPTwitterMediaUploadStatus) {
    CPTwitterMediaUploadStatus_notFound = 0, // 没有找到
    CPTwitterMediaUploadStatus_inProgress , // 上传中
    CPTwitterMediaUploadStatus_failed , // 失败
    CPTwitterMediaUploadStatus_succeeded , // 成功
};

typedef NS_ENUM(NSInteger, CPTwitterMediaUploadError) {
    CPTwitterMediaUploadError_none = 0, // 没有错误
    CPTwitterMediaUploadError_InvalidMedia , // 不支持这个media的格式
};

@interface CPTwitterUploader ()

@property (nonatomic, strong) CPTwitterUploadInfoRecord *uploadInfoRecord; // 记录一些上传的参数

// 当前的progress --- 使用Twitter的SDK
@property (nonatomic, strong) NSProgress *currentProgress;

// video的tweet
@property (nonatomic, strong) TWTRTweet *tweet;

// 创建上传任务时，如果有赋值mediaId则表明是一个已存在的任务（断点上传），需要到Twitter服务器中查看这个上传任务的状态，如果已过期（或失败）则重新创建一个任务，如果已完成则表示完成，如果是上传中则继续上传
@property (nonatomic, assign) BOOL shouldCheckUploadState;

@property (nonatomic, strong) TWTRAPIClient *apiClient;

@end

@implementation CPTwitterUploader

#pragma mark - initialize method

+ (instancetype)createTwitterVideoUploadTicketWithParam:(CPUploadParam *)param uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler completeHandler:(CPUploaderCompleteHandler)completeHandler {
    
    CPTwitterUploader *uploader = [[CPTwitterUploader alloc] initWithParam:param uploadProgressHandler:uploadProgressHandler completeHandler:completeHandler];
    return uploader;
}

- (void)dealloc {
    PLog(@"dealloc ---> %@", NSStringFromClass([self class]));
}

- (instancetype)initWithParam:(CPUploadParam *)param uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler completeHandler:(CPUploaderCompleteHandler)completeHandler {
    if (self = [super init]) {
        BOOL yesOrNo = [self createUploadTicketWithParam:param uploadProgressHandler:uploadProgressHandler completeHandler:completeHandler];
        if (!yesOrNo) {
            return nil;
        }
    }
    return self;
}

- (BOOL)createUploadTicketWithParam:(CPUploadParam *)param
              uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
              completeHandler:(CPUploaderCompleteHandler)completeHandler {
    
    if (![self checkTwitterLoginState]) {
        NSAssert(NO, @"Before upload video,you must login twitter");
        return NO;
    }
    
    if (param.videoURL.length <= 0) {
        NSAssert(NO, @"video url can not be nil");
        return NO;
    }
    if (param.userID.length <= 0) {
        NSAssert(NO, @"user id can not be nil");
        return NO;
    }
    
    NSInteger videoSize = [self getVideoSizeWithURL:param.videoURL];
    if (videoSize <= 0) {
        return NO;
    }
    
    // 如果存在resumeMediaId --- 在本地查找记录
    CPTwitterUploadInfoRecord *infoRecord = [CPTwitterUploadInfoRecord yy_modelWithDictionary:[self getRecordInfoWithMediaID:param.resumeMediaId]];
    
    if (infoRecord.userID.length > 0 && ![infoRecord.userID isEqualToString:param.userID]) {
        PLog(@"param.userID do not equal infoRecord.userID");
        return NO;
    }
    
    // 判断是否存在记录
    self.shouldCheckUploadState = infoRecord ? YES : NO;
    
    if (!infoRecord) { // 不存在 --- 初始化参数
        infoRecord = [[CPTwitterUploadInfoRecord alloc] init];
        infoRecord.publishParam = param.publishParam;
        infoRecord.uploaded_bytes = 0;
        infoRecord.userID = param.userID;
        
        infoRecord.media_id = @"";
        infoRecord.tweetID = @"";
    }
    
    self.file = [[CPFile alloc] init:param.videoURL error:nil];
    
    self.uploadInfoRecord = infoRecord;
    
    // 初始化
    @synchronized (self) {
        self.cancel = NO;
        self.pause = YES;
    }
    
    // 回调
    self.progressHandler = uploadProgressHandler;
    self.completeHandler = completeHandler;
    
    return YES;
}

#pragma mark - upload method

- (void)cancel {
    if (self.isCancel) {
        return;
    }
    @synchronized (self) {
        self.cancel = YES;
    }
    
    [self.currentProgress cancel]; // 将当前的上传片段取消
    self.currentProgress = nil;
    
    // 移除
    [self removeRecordInfoWithMediaID:self.uploadInfoRecord.media_id];
}

- (void)pause {
    if (self.isPause) {
        return;
    }
    @synchronized (self) {
        self.pause = YES;
    }
    
    [self.currentProgress cancel]; // 将当前的上传片段取消
    self.currentProgress = nil;
}

- (void)resume {
    if (self.isCancel) { // 已取消的任务 --- 点击resume就重新开始
        [self recreateTask];
        return;
    }
    
    if (!self.isPause) {
        return;
    }
    @synchronized (self) {
        self.pause = NO;
    }
    
    // 断点上传 --- 检测视频上传状态
    if (self.shouldCheckUploadState) {
        [self checkMediaUploadState];
        return;
    }
    
    // 检测是否是新开始的任务
    if (self.uploadInfoRecord.media_id.length <= 0) {
        [self startNewTask];
        return;
    }
    
    // 正常的开始任务
    [self nextTaskWithOffset:self.uploadInfoRecord.uploaded_bytes];
}

- (void)startNewTask {
    // 上传进度的回调
    self.progressHandler ? self.progressHandler(self, 0.0) : nil;
    
    // 新开始的上传任务 --- 创建任务
    __weak typeof(self) _self = self;
    [self _initVideoUploadWithVideoURL:self.file.path completion:^(NSString *mediaID, NSInteger expires_after_secs, NSError *error) {
        
        if (error || mediaID.length <= 0) {
            // 初始化出问题
            if (!error) {
                error = [NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传任务时(INIT命令)返回的media_id为空"}];
            }
            [_self completionCallbackWithError:error];
            return;
        }
        
        _self.uploadInfoRecord.media_id = mediaID;
        _self.uploadInfoRecord.uploaded_bytes = 0;
        _self.uploadInfoRecord.expires_after_secs = expires_after_secs;
        
        // 记录到本地
        [_self writeRecrodInfoToDisk:[_self.uploadInfoRecord yy_modelToJSONObject] media_id:_self.uploadInfoRecord.media_id];
        
        // 上传进度的回调 --- 发送完init命令时 上传进度是2%
        _self.progressHandler ? _self.progressHandler(_self, 0.02) : nil;
        
        [_self nextTaskWithOffset:_self.uploadInfoRecord.uploaded_bytes]; // 开始任务
    }];
}

// 检测视频状态
- (void)checkMediaUploadState {
    if (!self.shouldCheckUploadState) {
        return;
    }
    self.shouldCheckUploadState = NO;
    
    __weak typeof(self) _self = self;
    
    // 如果有tweet_id --- 表明已经发过推了 --- 视频不用上传
    if (self.uploadInfoRecord.tweetID.length > 0) {
        // 获取tweet
        [self getTweetWithTweetID:self.uploadInfoRecord.tweetID completion:^(TWTRTweet *tweet, NSError *error) {
            
            _self.tweet = tweet;
            
            // 有错误表明tweet id 是错误的 --- 一视同仁(不管是网络错误还是其他错误)
            if (error || !tweet) {
                // 重新检测
                _self.uploadInfoRecord.tweetID = @"";
                
                // 到这个方法里面 media id 都是一定会有的
                [_self writeRecrodInfoToDisk:[_self.uploadInfoRecord yy_modelToJSONObject] media_id:_self.uploadInfoRecord.media_id];
                
                // 重新开始任务
                CPUploadParam *param = [[CPUploadParam alloc] init];
                param.resumeMediaId = _self.uploadInfoRecord.media_id;
                param.publishParam = _self.uploadInfoRecord.publishParam;
                param.videoURL = _self.file.path;
                param.userID = _self.uploadInfoRecord.userID;
                [_self createUploadTicketWithParam:param uploadProgressHandler:_self.progressHandler completeHandler:_self.completeHandler];
                return;
            }
            
            // 已经有了tweet --- 直接回调
            [_self completionCallbackWithError:nil];
            
        }];
    }
    
    // 如果没有media_id 表明没有开始这个任务
    if (self.uploadInfoRecord.media_id.length <=0) {
        // 重新开始
        [self recreateTask];
        return;
    }
    
    // 判断时间
    if ([self.uploadInfoRecord taskIsExpires]) { // 过期
        
        [self recreateTask];
        return;
    }
    
    // 判断大小
    if (self.uploadInfoRecord.uploaded_bytes < self.file.size) {
        // 处于上传中 且没有过期
        [self pause]; // 需要设置pause状态
        [self resume];
        return;
    }
    
    // 检测状态
    [self videoUploadStateWithMediaID:self.uploadInfoRecord.media_id completion:^(CPTwitterMediaUploadStatus uploadStatus, CPTwitterMediaUploadError uploadError, NSInteger check_after_secs, NSInteger progress_percent) {
        
        switch (uploadStatus) {
                // 表明需要先发送FINALIZE命令
            case CPTwitterMediaUploadStatus_notFound: {
                
                [_self finishVideoUploadWithMediaID:_self.uploadInfoRecord.media_id completion:^(NSInteger check_after_secs, NSError *error) {
                   
                    if (error) { // 错误
                        // 重新开始
                        [_self recreateTask];
                        return;
                    }
                    
                    // 发送命令
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((check_after_secs > 0 ? check_after_secs : 0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [_self sendTweetWhenFinishUpload];
                    });
                    
                }];
                
                return;
            }
            case CPTwitterMediaUploadStatus_failed: {
                NSError *error = [_self converMediaUploadErrorWithEnum:uploadError];
                if (error) { // 有error就表明视频是错误的 再上传也没有用 直接回调
                    // 直接取消任务
                    [_self cancel];
                    // 错误的回调
                    [_self completionCallbackWithError:error];
                    return;
                }
                
                // 其他的重新开始
                [_self recreateTask];
                return;
            }
            case CPTwitterMediaUploadStatus_inProgress: {
                // 表明需要等待(已经发送过FINALIZE命令了) --- 发推
                [_self sendTweetWhenFinishUpload];
                return;
            }
            case CPTwitterMediaUploadStatus_succeeded: { // 视频已经OK了 --- 可以发推
                [_self sendTweetWithCompletion:^(NSError *error) {
                    // 回调
                    [_self completionCallbackWithError:error];
                }];
                return;
            }
            default: { break; }
        }
        
    }];
}

- (void)recreateTask {
    
    [self removeRecordInfoWithMediaID:self.uploadInfoRecord.media_id];
    
    CPUploadParam *param = [[CPUploadParam alloc] init];
    param.publishParam = self.uploadInfoRecord.publishParam;
    param.userID = self.uploadInfoRecord.userID;
    param.videoURL = self.file.path;
    
    [self createUploadTicketWithParam:param uploadProgressHandler:self.progressHandler completeHandler:self.completeHandler];
    
    // 重新开始
    [self resume];
}

// 开始上传
- (void)nextTaskWithOffset:(NSInteger)offset {
    
    // 记录到本地
    [self writeRecrodInfoToDisk:[self.uploadInfoRecord yy_modelToJSONObject] media_id:self.uploadInfoRecord.media_id];
    
    // 伪造一个上传回调
    [self makeProgressCallbackDurationUpload];
    
    if (self.isCancel || self.isPause) { // 取消任务或者暂停任务
        return;
    }
    // 判断是否已经上传完成
    __weak typeof(self) _self = self;
    if (offset >= self.file.size) {
        
        // 发finish的命令
        [self finishVideoUploadWithMediaID:self.uploadInfoRecord.media_id completion:^(NSInteger check_after_secs, NSError *error) {
            // 当发送完命令之后，检查是否有发推 --- 如果没有则发推
            if (error) {
                [_self completionCallbackWithError:error];
                return;
            }
            
            // 发推
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((check_after_secs >= 0 ? check_after_secs : 0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [_self sendTweetWhenFinishUpload];
            });
        }];
        return;
    }
    
    // 上传
    [self startBackgroundTask];
    
    [self putChunkWithOffset:offset size:self.uploadInfoRecord.chunk_bytes completion:^(NSError *error) {
        if (error) {
            // 错误 -999 是上传取消的回调 --- 取消不做回调
            if (error.code != -999) {
                [_self completionCallbackWithError:error];
            }
            return;
        }
        // 成功 --- 下一个
        _self.uploadInfoRecord.uploaded_bytes += _self.uploadInfoRecord.chunk_bytes;
        if (_self.uploadInfoRecord.uploaded_bytes >= _self.file.size) {
            _self.uploadInfoRecord.uploaded_bytes = _self.file.size;
        }
        [_self nextTaskWithOffset:_self.uploadInfoRecord.uploaded_bytes];
    }];
}

// 发送视频块
- (void)putChunkWithOffset:(NSInteger)offset size:(NSInteger)size completion:(void(^)(NSError *error))completion {
    NSInteger fileSize = self.file.size;
    if (offset + size > fileSize) {
        size = fileSize - offset;
    }
    NSData *data = [self.file read:offset size:size];
    // 计算segmentIndex
    NSInteger currentSegmentIndex = [self getCurrentSegmentIndex]; // 当前的
    // currentSegmentIndex是不需要加一的，因为如果是index是从0开始的
    NSProgress *progress = [self appendChunkWithData:data mediaID:self.uploadInfoRecord.media_id segmentIndex:currentSegmentIndex completion:^(NSError *error) {
        completion ? completion(error) : nil;
    }];
    
    if (!progress) { // 创建失败
        completion ? completion([NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传块的任务失败"}]) : nil;
        return;
    }
    
    [self setCurrentProgress:progress];
}

#pragma mark - media upload method

// 创建
- (void)_initVideoUploadWithVideoURL:(NSString *)videoURL completion:(void(^)(NSString *mediaID, NSInteger expires_after_secs, NSError *error))completion {
    // 判断是否登录
    if (![self checkTwitterLoginState]) {
        NSAssert(NO, @"It is not login twitter");
        completion ? completion(nil, 0, [NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传任务时(INIT命令),用户没有登录"}]) : nil;
        return;
    }
    // url
    if (videoURL.length <= 0) {
        NSAssert(NO, @"video url can not be nil");
        completion ? completion(nil, 0, [NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传任务时(INIT命令),视频地址不能为空"}]) : nil;
        return;
    }
    // 文件大小
    NSInteger videoSize = [self getVideoSizeWithURL:videoURL];
    if (videoSize <= 0) {
        completion ? completion(nil, 0, [NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传任务时(INIT命令),视频文件大小为0"}]) : nil;
        return;
    }
    NSString *lengthVideo = [NSString stringWithFormat:@"%ld", videoSize];
    NSString *mediaType = [self getMediaTypeWithMediaURL:videoURL];
    if (mediaType.length <= 0) {
        NSAssert(NO, @"video extension is nil");
        completion ? completion(nil, 0, [NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传任务时(INIT命令),视频扩展名不能为空"}]) : nil;
        return;
    }
    NSMutableDictionary *message =  [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                    @"command":kTwitterUploadCommand_INIT,
                                                                                    @"media_type":mediaType,
                                                                                    @"total_bytes":lengthVideo,
                                                                                    }];
    if ([mediaType rangeOfString:@"video"].location != NSNotFound) { // 是视频文件
        [message setObject:@"amplify_video" forKey:@"media_category"];
    }
    
    NSURLRequest *request = [self getTwitterRequestWithParam:message requestMethod:k_POST urlString:kTwitterVideoUploadURL errorHandler:^(NSError *error) {
        completion ? completion(nil, 0, error) : nil;
    }];
    if (!request) {
        return;
    }
    
    __weak typeof(self) _self = self;
    [self.apiClient sendTwitterRequest:request completion:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        
        [_self callbackWithData:data connectionError:connectionError completion:^(NSDictionary *userDict, NSError *error) {
            if (error) {
                PLog(@"init video upload method error : %@", error);
            }
            completion ? completion(userDict[@"media_id_string"], [userDict[@"expires_after_secs"] integerValue], error) : nil;
        }];
        
    }];
}

// 上传chunk
- (NSProgress *)appendChunkWithData:(NSData *)data
            mediaID:(NSString *)mediaID
            segmentIndex:(NSInteger)segmentIndex
            completion:(void(^)(NSError *error))completion
{
    if (data.length <= 0 || data.length > (5 * 1024 * 1024)) {
        NSAssert(NO, @"chunk size must between 1B and 5MB");
        completion ? completion([NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传块任务时(APPEND命令),块大小为0"}]) : nil;
        return nil;
    }
    if (mediaID.length <= 0) {
        NSAssert(NO, @"media id can not be nil");
        completion ? completion([NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传块任务时(APPEND命令),media_id为空"}]) : nil;
        return nil;
    }
    if (segmentIndex < 0 || segmentIndex > 999) {
        NSAssert(NO, @"segment index must between 0 and 999");
        completion ? completion([NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传块任务时(APPEND命令),segmentIndex超出范围(0-999)"}]) : nil;
        return nil;
    }
    
    NSString *dataString = [data base64EncodedStringWithOptions:0];
    
    NSDictionary *dict = @{
                           @"command" : kTwitterUploadCommand_APPEND,
                           @"media_id" : mediaID,
                           @"segment_index" : [NSString stringWithFormat:@"%ld", segmentIndex],
                           @"media_data" : dataString,
                           };
    NSURLRequest *request = [self getTwitterRequestWithParam:dict requestMethod:k_POST urlString:kTwitterVideoUploadURL errorHandler:^(NSError *error) {
        completion ? completion(error) : nil;
    }];
    if (!request) {
        return nil;
    }
    
    NSProgress *progress = [self.apiClient sendTwitterRequest:request completion:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        
        // 上传成功是不会有data的
        if (connectionError || data.length > 0) { // 失败
            
            completion ? completion(connectionError ? connectionError : [NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"上传chunk失败"}]) : nil;
            
        } else { // 成功
            completion ? completion(nil) : nil;
        }
        
    }];
    
    return progress;
}

// 结束命令
- (void)finishVideoUploadWithMediaID:(NSString *)mediaID completion:(void(^)(NSInteger check_after_secs, NSError *error))completion {
    if (mediaID.length <= 0) {
        NSAssert(NO, @"media id can not be nil");
        completion ? completion(0, [NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"结束命令的media id不能为空"}]) : nil;
        return;
    }
    NSDictionary *dict = @{
                           @"command" : kTwitterUploadCommand_FINALIZE,
                           @"media_id" : mediaID,
                           };
    NSURLRequest *request = [self getTwitterRequestWithParam:dict requestMethod:k_POST urlString:kTwitterVideoUploadURL errorHandler:^(NSError *error) {
        completion ? completion(0, error) : nil;
    }];
    if (!request) {
        return;
    }
    
    __weak typeof(self) _self = self;
    [self.apiClient sendTwitterRequest:request completion:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        
        [_self callbackWithData:data connectionError:connectionError completion:^(NSDictionary *userDict, NSError *error) {
            if (error || !userDict) {
                PLog(@"finish twitter upload error : %@", error);
                completion ? completion(0, error ? error : [NSError errorWithDomain:CPTwitterMediaErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"finish command response nil"}]) : nil;
                return;
            }
            
            // 发完finish命令后 --- 会有一个 processing_info 的属性 --- 不一定有
            if (![userDict.allKeys containsObject:@"processing_info"]) { // 表明是同步上传的media
                // 可以直接发推
                completion ? completion(0, error) : nil;
                return;
            }
            
            // 表明是异步上传的视频
            NSDictionary *processing_info = userDict[@"processing_info"];
            if (![processing_info isKindOfClass:[NSDictionary class]]) {
                completion ? completion(0, [NSError errorWithDomain:CPTwitterMediaErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"finish command response nil"}]) : nil;
                return;
            }
            
            completion ? completion([processing_info[@"check_after_secs"] integerValue], error) : nil;
            
        }];

    }];
}

// 查询media的状态
- (void)videoUploadStateWithMediaID:(NSString *)mediaID completion:(void(^)(CPTwitterMediaUploadStatus uploadStatus, CPTwitterMediaUploadError uploadError, NSInteger check_after_secs, NSInteger progress_percent))completion {
    if (mediaID.length <= 0) {
        NSAssert(NO, @"media id can not be niu");
        completion ? completion(CPTwitterMediaUploadStatus_notFound, CPTwitterMediaUploadError_none, 0, 0) : nil;
        return;
    }
    
    NSDictionary * dict = @{
                            @"command" : kTwitterUploadCommand_STATUS,
                            @"media_id" : mediaID,
                            };
    NSURLRequest *request = [self getTwitterRequestWithParam:dict requestMethod:k_GET urlString:kTwitterVideoUploadURL errorHandler:^(NSError *error) {
        completion ? completion(CPTwitterMediaUploadStatus_notFound, CPTwitterMediaUploadError_none, 0, 0) : nil;
    }];
    if (!request) {
        return;
    }
    
    __weak typeof(self) _self = self;
    [self.apiClient sendTwitterRequest:request completion:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        
        [_self callbackWithData:data connectionError:connectionError completion:^(NSDictionary *userDict, NSError *error) {
            
            PLog(@"status error : %@", error);
            PLog(@"user dict : %@", userDict);
            
            if (error) {
                completion ? completion(CPTwitterMediaUploadStatus_notFound, CPTwitterMediaUploadError_none, 0, 0) : nil;
                return;
            }
            NSDictionary *progressing_info = userDict[@"processing_info"];
            if (!progressing_info) {
                completion ? completion(CPTwitterMediaUploadStatus_notFound, CPTwitterMediaUploadError_none, 0, 0) : nil;
                return;
            }
            
            NSString *state = progressing_info[@"state"];
            if (state.length <= 0) {
                completion ? completion(CPTwitterMediaUploadStatus_notFound, CPTwitterMediaUploadError_none, 0, 0) : nil;
                return;
            }
            
            // 判断
            CPTwitterMediaUploadStatus status = CPTwitterMediaUploadStatus_notFound;
            CPTwitterMediaUploadError uploadError = CPTwitterMediaUploadError_none;
            NSInteger time = 0;
            NSInteger percent = [progressing_info[@"progress_percent"] integerValue];
            if ([state isEqualToString:@"in_progress"]) { // 上传中
                status = CPTwitterMediaUploadStatus_inProgress;
                time = [progressing_info[@"check_after_secs"] integerValue];
            } else if ([state isEqualToString:@"failed"]) { // 失败
                
                status = CPTwitterMediaUploadStatus_failed;
                NSDictionary *errorDict = progressing_info[@"error"];
                //!!!: 需要整理出错误信息
                if ([errorDict isKindOfClass:[NSDictionary class]]) {
                    NSString *name = errorDict[@"name"];
                    if ([name isEqualToString:@"InvalidMedia"]) {
                        uploadError = CPTwitterMediaUploadError_InvalidMedia;
                    }
                }
                
            } else if ([state isEqualToString:@"succeeded"]) { // 成功
                status = CPTwitterMediaUploadStatus_succeeded;
            } else { // 没找到
                status = CPTwitterMediaUploadStatus_notFound;
            }
            
            completion ? completion(status, uploadError, time, percent) : nil;
        }];
        
    }];
}

#pragma mark - tweet method

// 发推
- (void)sendTweetWithParam:(NSDictionary *)param mediaID:(NSString *)mediaID completion:(TWTRSendTweetCompletion)completion {
    if (!param) {
        NSAssert(NO, @"tweet param can not be nil");
    }
    if (mediaID.length <= 0) {
        NSAssert(NO, @"media id can not be nil");
        return;
    }
    if (!completion) {
        NSAssert(NO, @"completion can not be nil");
        return;
    }
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{@"media_ids": mediaID}];
    if (param) {
        [parameters addEntriesFromDictionary:param];
    }
    NSURLRequest *request = [self getTwitterRequestWithParam:parameters requestMethod:k_POST urlString:kTwitterCreateTweetURL errorHandler:^(NSError *error) {
        completion ? completion(nil, error) : nil;
    }];
    if (!request) {
        return;
    }
    
    __weak typeof(self) _self = self;
    [self.apiClient sendTwitterRequest:request completion:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        
        [_self callbackWithData:data connectionError:connectionError completion:^(NSDictionary *userDict, NSError *error) {
            TWTRTweet *tweet = nil;
            if (userDict) {
                tweet = [[TWTRTweet alloc] initWithJSONDictionary:userDict];
            }
            if (error) {
                PLog(@"send media tweet error : %@", error);
            }
            completion ? completion(tweet, connectionError) : nil;
        }];
        
    }];
}

// 删除推文
- (void)destoryTweetWithTweetID:(NSString *)tweetID completion:(void(^)(NSError *error))completion {
    if (tweetID.length <= 0) {
        NSAssert(NO, @"tweet id can not be nil");
        return;
    }
    if (!completion) {
        NSAssert(NO, @"completion can not be nil");
        return;
    }
    
    NSURLRequest *request = [self getTwitterRequestWithParam:nil requestMethod:k_POST urlString:kTwitterDestroyTweetURL(tweetID) errorHandler:^(NSError *error) {
        completion ? completion(error) : nil;
    }];
    if (!request) {
        return;
    }
    
    [self.apiClient sendTwitterRequest:request completion:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        completion ? completion(connectionError) : nil;
    }];
}

// 根据tweetID 获取tweet
- (void)getTweetWithTweetID:(NSString *)tweetID completion:(void(^)(TWTRTweet *tweet, NSError *error))completion {
    if (tweetID.length <= 0) {
        NSAssert(NO, @"tweet ID can not be nil");
        completion ? completion(nil, [NSError errorWithDomain:CPTwitterMediaErrorDomain code:kTwitterErrorCode userInfo:@{NSLocalizedDescriptionKey : @"获取tweet时tweet id不能为空"}]) : nil;
        return;
    }
    
    NSDictionary *dict = @{
                           @"id" : tweetID
                           };
    NSURLRequest *request = [self getTwitterRequestWithParam:dict requestMethod:k_GET urlString:kTwitterShowTweetURL errorHandler:^(NSError *error) {
        completion ? completion(nil, error) : nil;
    }];
    if (!request) {
        return;
    }
    
    __weak typeof(self) _self = self;
    [self.apiClient sendTwitterRequest:request completion:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        
        [_self callbackWithData:data connectionError:connectionError completion:^(NSDictionary *userDict, NSError *error) {
            TWTRTweet *tweet = [[TWTRTweet alloc] initWithJSONDictionary:userDict];
            completion ? completion(tweet, error) : nil;
        }];
        
    }];
}

#pragma mark - private method

// 在上传完毕之后发推
- (void)sendTweetWhenFinishUpload {
    
    // 上传进度的回调 --- 上传完所有视频时 上传进度为 97%
    self.progressHandler ? self.progressHandler(self, 0.97) : nil;
    
    // 发推 --- 已经发送过finialize命令
    [self sendTweetWhenMediaStatusSuccess];
}

// 最后一步 --- 发送
- (void)sendTweetWhenMediaStatusSuccess {
    
    if (self.isCancel || self.isPause) {
        return;
    }
    
    __weak typeof(self) _self = self;
    [self videoUploadStateWithMediaID:self.uploadInfoRecord.media_id completion:^(CPTwitterMediaUploadStatus uploadStatus, CPTwitterMediaUploadError uploadError, NSInteger check_after_secs, NSInteger progress_percent) {
       
        switch (uploadStatus) {
            // 这两个情况都直接返回错误 --- 因为已经是最后一步的
            case CPTwitterMediaUploadStatus_notFound:
            case CPTwitterMediaUploadStatus_failed: {
                
                NSError *error = [_self converMediaUploadErrorWithEnum:uploadError];
                if (error) {
                    // 删除本地记录 --- 不支持的media格式
                    [_self removeRecordInfoWithMediaID:_self.uploadInfoRecord.media_id];
                } else {
                    error = [NSError errorWithDomain:CPTwitterMediaErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"video upload failed"}];
                }
                
                [_self completionCallbackWithError:error];
                return;
            }
                
            case CPTwitterMediaUploadStatus_inProgress: {
                // 上传中 --- 因为在到这个方法已经是上传完成了 所以只要等待视频状态变成success就OK了
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((check_after_secs >= 0 ? check_after_secs : 0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [_self sendTweetWhenMediaStatusSuccess];
                });
                
                return;
            }
            case CPTwitterMediaUploadStatus_succeeded: {
                // 上传成功 --- 发推
                [_self sendTweetWithCompletion:^(NSError *error) {
                    // 回调
                    [_self completionCallbackWithError:error];
                }];
                return;
            }
                
            default: { return; }
        }

    }];
}

// 发推
- (void)sendTweetWithCompletion:(void(^)(NSError *error))completion {
    __weak typeof(self) _self = self;
    [self sendTweetWithParam:self.uploadInfoRecord.publishParam mediaID:self.uploadInfoRecord.media_id completion:^(TWTRTweet * _Nullable tweet, NSError * _Nullable error) {
        _self.tweet = tweet;
        _self.uploadInfoRecord.tweetID = tweet.tweetID;
        completion ? completion(error) : nil;
    }];
}

#pragma mark -

// progress回调 --- 上传中
- (void)makeProgressCallbackDurationUpload {
    CGFloat uploaded = self.uploadInfoRecord.uploaded_bytes;
    CGFloat total = self.file.size;
    CGFloat percent = 0.02 + (uploaded / total) * 0.95;
    PLog(@"total : %f, uploaded : %f, percent : %f", total, uploaded, percent);
    self.progressHandler ? self.progressHandler(self, percent) : nil;
}

// 任务的完成回调 --- 如果error为空 则视为是成功
- (void)completionCallbackWithError:(NSError *)error {
    if (!error) {
        // 回调
        self.progressHandler ? self.progressHandler(self, 1.0) : nil;
        [self removeRecordInfoWithMediaID:self.uploadInfoRecord.media_id];
    }
    [self pause];
    self.completeHandler ? self.completeHandler(self, error) : nil;
}

#pragma mark -

// 当前已上传块的index
- (NSInteger)getCurrentSegmentIndex {
    NSInteger uploaded = self.uploadInfoRecord.uploaded_bytes;
    NSInteger chunkSize = self.uploadInfoRecord.chunk_bytes;
    return (uploaded / chunkSize);
}

// callback
- (void)callbackWithData:(NSData *)data connectionError:(NSError *)connectionError completion:(void(^)(NSDictionary *userDict, NSError *error))completion {
    if (connectionError) {
        completion ? completion(nil, connectionError) : nil;
        return;
    };
    NSError *jsonSerializationErr;
    NSDictionary *userDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonSerializationErr];
    if (jsonSerializationErr) {
        completion ? completion(nil, jsonSerializationErr) : nil;
        return;
    }
    
    // 不是字典
    if (![userDict isKindOfClass:[NSDictionary class]]) {
        userDict = nil;
    }
    // 成功
    completion ? completion(userDict, connectionError) : nil;
}

// request
- (NSURLRequest *)getTwitterRequestWithParam:(NSDictionary *)param requestMethod:(NSString *)requestMethod urlString:(NSString *)urlString errorHandler:(void(^)(NSError *error))errorHandler {
    NSError *error = nil;
    NSURLRequest *request = [self.apiClient URLRequestWithMethod:requestMethod URLString:urlString parameters:param error:&error];
    if (error) { // 创建request的时候出错
        PLog(@"create request error : %@", error);
        errorHandler ? errorHandler(error) : nil;
        return nil;
    }
    return request;
}

- (BOOL)checkTwitterLoginState {
    // 判断是否有登录
    TWTRTwitter *twitter = [TWTRTwitter sharedInstance];
    return [twitter.sessionStore hasLoggedInUsers];
}

- (NSError *)converMediaUploadErrorWithEnum:(CPTwitterMediaUploadError)uploadError {
    NSError *error = nil;
    switch (uploadError) {
        case CPTwitterMediaUploadError_InvalidMedia : {
            // 错误信息待整理
            // 视频格式不支持 --- 直接返回错误信息
            error = [NSError errorWithDomain:CPTwitterMediaErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"Unsupported media format"}];
            break;
        }
        case CPTwitterMediaUploadError_none: { break; }
        default: { break; }
    }
    
    return error;
}

// 获得上传类型
- (NSString *)getMediaTypeWithMediaURL:(NSString *)mediaURL {
    // 只有图片跟video
    NSString *pathExtension = [[mediaURL pathExtension] lowercaseString];
    
    if (pathExtension.length <= 0) {
        return nil;
    }
    
    NSString *type = @"";
    NSArray *imageTypeArray = @[@"jpg", @"jpeg", @"png", @"gif", @"webp"];
    if ([imageTypeArray containsObject:pathExtension]) { // 就是图片
        type = @"image/";
    } else {
        type = @"video/";
    }
    return [type stringByAppendingString:pathExtension];
}

#pragma mark - getter & setter

- (void)setCurrentProgress:(NSProgress *)currentProgress {
    if (_currentProgress == currentProgress) {
        return;
    }
    
    _currentProgress = currentProgress;
}

- (TWTRAPIClient *)apiClient {
    if (!_apiClient) {
        _apiClient = [TWTRAPIClient clientWithCurrentUser];
    }
    return _apiClient;
}

@end

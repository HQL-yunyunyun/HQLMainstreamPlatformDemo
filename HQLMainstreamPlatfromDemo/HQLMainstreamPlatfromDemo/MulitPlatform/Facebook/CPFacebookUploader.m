//
//  CPFacebookUploader.m
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/26.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import "CPFacebookUploader.h"

#define CPFBCreateVideoUploadURL(send_id) [NSString stringWithFormat:@"/%@/%@", send_id, @"videos"]

@interface CPFacebookUploader () <FBSDKGraphRequestConnectionDelegate>

@property (nonatomic, strong) CPFacebookUploadInfoRecord *uploadInfoRecord;

@property (nonatomic, assign) BOOL shouldCheckUploadState;

@property (nonatomic, strong) FBSDKGraphRequestConnection *currentConnection;

@property (nonatomic, copy) NSString *videoLink;

@end

@implementation CPFacebookUploader

#pragma mark - initialize method

+ (instancetype)createFacebookUploadTicketWithParam:(CPUploadParam *)param
                          uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
                          completeHandler:(CPUploaderCompleteHandler)completeHandler
{
    CPFacebookUploader *uploader = [[CPFacebookUploader alloc] initWithParam:param uploadProgressHandler:uploadProgressHandler completeHandler:completeHandler];
    return uploader;
}

- (void)dealloc {
    PLog(@"dealloc ---> %@", NSStringFromClass([self class]));
}

- (instancetype)initWithParam:(CPUploadParam *)param
             uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
             completeHandler:(CPUploaderCompleteHandler)completeHandler
{
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
               completeHandler:(CPUploaderCompleteHandler)completeHandler
{
    if (![self checkFacebookLoginState]) {
        NSAssert(NO, @"Before upload video,you must login facebook");
        return NO;
    }
    
    if (param.sendID.length <= 0) {
        NSAssert(NO, @"facebook send id can not be nil");
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
    
    self.file = [[CPFile alloc] init:param.videoURL error:nil];
    
    NSInteger videoSize = self.file.size;
    if (videoSize <= 0) {
        return NO;
    }
    
    // 如果存在resumeMediaId --- 在本地查找记录
    CPFacebookUploadInfoRecord *infoRecord = [CPFacebookUploadInfoRecord yy_modelWithDictionary:[self getRecordInfoWithMediaID:param.resumeMediaId]];
    
    if (infoRecord.userID.length > 0 && ![infoRecord.userID isEqualToString:param.userID]) {
        PLog(@"param.userID do not equal infoRecord.userID");
        return NO;
    }
    
    // 判断是否存在记录
    self.shouldCheckUploadState = infoRecord ? YES : NO;
    
    if (!infoRecord) { // 不存在 --- 初始化参数
        infoRecord = [[CPFacebookUploadInfoRecord alloc] init];
        infoRecord.publishParam = param.publishParam;
        infoRecord.start_offset = 0;
        infoRecord.end_offset = 0;
        infoRecord.userID = param.userID;
        infoRecord.session_id = @"";
        infoRecord.sendID = param.sendID;
        
        infoRecord.videoName = [param.videoURL lastPathComponent];
    }

    self.uploadInfoRecord = infoRecord;
    
    self.videoLink = @"";
    
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
    
    [self.currentConnection cancel]; // 将当前的上传片段取消
    self.currentConnection = nil;
    
    // 删除视频
    if (self.uploadInfoRecord.video_id.length > 0) {
        [[self class] deleteVideoWithVideo_id:self.uploadInfoRecord.video_id completion:nil];
    }
    
    // 移除
    [self removeRecordInfoWithMediaID:self.uploadInfoRecord.session_id];
}

- (void)pause {
    if (self.isPause) {
        return;
    }
    @synchronized (self) {
        self.pause = YES;
    }
    
    [self.currentConnection cancel]; // 将当前的上传片段取消
    self.currentConnection = nil;
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
    if (self.uploadInfoRecord.session_id.length <= 0 || self.uploadInfoRecord.video_id) {
        [self startNewTask];
        return;
    }
    
    // 正常的开始任务
    [self nextTaskWithStart_offset:self.uploadInfoRecord.start_offset end_offset:self.uploadInfoRecord.end_offset];
}

#pragma mark -

// 检测视频状态
- (void)checkMediaUploadState {
    if (!self.shouldCheckUploadState) {
        return;
    }
    self.shouldCheckUploadState = NO;
    // 如果没有session_id 或 video_id 表明没有开始这个任务
    if (self.uploadInfoRecord.session_id.length <=0 || self.uploadInfoRecord.video_id.length <= 0) {
        // 重新开始
        [self recreateTask];
        return;
    }
    
    // 如果 end_offset 和 start_offset 相等且都不为0，则表示已经上传完毕
    if ((self.uploadInfoRecord.end_offset == self.uploadInfoRecord.start_offset) && (self.uploadInfoRecord.end_offset != 0) ) {
        [self finishUploadVideoAndPublishVideo];
        return;
    }
    
    // 到这就表示上传中 --- 继续上传
    self.pause = YES;
    [self resume];
}

// 新任务
- (void)startNewTask {
    // 上传进度的回调
    self.progressHandler ? self.progressHandler(self, 0.0) : nil;
    
    // 新开始的上传任务 --- 创建任务
    __weak typeof(self) _self = self;
    [self startUploadSessionWithVideoURL:self.file.path send_id:self.uploadInfoRecord.sendID completion:^(NSString *session_id, NSString *video_id, NSInteger start_offset, NSInteger end_offse, NSError *error) {
        
        if (error) {
            // 创建失败 --- 直接回调
            [_self completionCallbackWithError:error];
            return;
        }
        
        // 成功 --- 开始
        _self.uploadInfoRecord.session_id = session_id;
        _self.uploadInfoRecord.video_id = video_id;
        _self.uploadInfoRecord.start_offset = start_offset;
        _self.uploadInfoRecord.end_offset = end_offse;
        
        // 记录到本地
        [_self writeRecrodInfoToDisk:[_self.uploadInfoRecord yy_modelToJSONObject] media_id:_self.uploadInfoRecord.session_id];
        
        // 上传进度的回调 --- 发送完init命令时 上传进度是2%
        _self.progressHandler ? _self.progressHandler(_self, 0.02) : nil;
        
        // next task
        [_self nextTaskWithStart_offset:start_offset end_offset:end_offse];
    }];
}

// 上传块
- (void)nextTaskWithStart_offset:(NSInteger)start_offset end_offset:(NSInteger)end_offset {
    
    // 记录到本地
    [self writeRecrodInfoToDisk:[self.uploadInfoRecord yy_modelToJSONObject] media_id:self.uploadInfoRecord.session_id];
    
    // 伪造一个上传回调
    [self makeProgressCallbackDurationUploadWithUploaded_bytes:self.uploadInfoRecord.start_offset];
    
    if (self.isCancel || self.isPause) { // 取消任务或者暂停任务
        return;
    }
    
    // 判断是否已经上传完成
    if ((start_offset == end_offset) && (start_offset != 0)) {
        [self finishUploadVideoAndPublishVideo];
        return;
    }
    
    [self startBackgroundTask];
    
    __weak typeof(self) _self = self;
    [self putChunkWithStart_offset:start_offset end_offset:end_offset completion:^(NSInteger next_start_offset, NSInteger next_end_offset, NSError *error) {
        if (error) {
            [_self completionCallbackWithError:error];
            return;
        }
        
        // 下一个
        _self.uploadInfoRecord.start_offset = next_start_offset;
        _self.uploadInfoRecord.end_offset = next_end_offset;
        [_self nextTaskWithStart_offset:next_start_offset end_offset:next_end_offset];
    }];
}

- (void)putChunkWithStart_offset:(NSInteger)start_offset end_offset:(NSInteger)end_offset completion:(void(^)(NSInteger next_start_offset, NSInteger next_end_offset, NSError *error))completion {
    
    if (end_offset == 0) {
        NSAssert(NO, @"上传视频时，end_offset 不能为0");
        completion ? completion(0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"上传视频时，end_offset 不能为0"}]) : nil;
        return;
    }
    
    if (start_offset == end_offset) {
        // 已完成
        NSAssert(NO, @"视频上传完成");
        completion ? completion(end_offset, end_offset, nil) : nil;
        return;
    }
    
    NSData *data = [self.file read:start_offset size:(end_offset - start_offset)];
    
    FBSDKGraphRequestConnection *connection = [self appendChunkWithData:data send_id:self.uploadInfoRecord.sendID session_id:self.uploadInfoRecord.session_id start_offset:start_offset videoName:self.uploadInfoRecord.videoName completion:^(NSInteger start_offset, NSInteger end_offset, NSError *error) {
       
        completion ? completion(start_offset, end_offset, error) : nil;
        
    }];
    
    if (!connection) {
        // 创建失败
        completion ? completion(0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传块任务失败"}]) : nil;
        return;
    }
    
    // 设置 connection
    [self setCurrentConnection:connection];
}

// 结束上传视频并发布视频
- (void)finishUploadVideoAndPublishVideo {
    
    self.progressHandler ? self.progressHandler(self, 0.97) : nil;
    
    __weak typeof(self) _self = self;
    [self finishUploadAndPublishVideoWithParam:self.uploadInfoRecord.publishParam send_id:self.uploadInfoRecord.sendID session_id:self.uploadInfoRecord.session_id completion:^(NSString *videoLink, NSError *error) {
        
        if (videoLink.length <= 0) {
            if (!error) {
                error = [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"获取视频地址失败"}];
            }
        }
        
        // 回调
        [_self completionCallbackWithError:error];
        
    }];
}

// 重新开始
- (void)recreateTask {
    
    [self removeRecordInfoWithMediaID:self.uploadInfoRecord.session_id];
    
    CPUploadParam *param = [[CPUploadParam alloc] init];
    param.publishParam = self.uploadInfoRecord.publishParam;
    param.userID = self.uploadInfoRecord.userID;
    param.videoURL = self.file.path;
    
    [self createUploadTicketWithParam:param uploadProgressHandler:self.progressHandler completeHandler:self.completeHandler];
    
    // 重新开始
    [self resume];
}

#pragma mark - Facebook upload method

- (void)startUploadSessionWithVideoURL:(NSString *)videoURL send_id:(NSString *)send_id completion:(void(^)(NSString *session_id, NSString *video_id, NSInteger start_offset, NSInteger end_offse, NSError *error))completion {
    
    // 判断是否登录
    if (![self checkFacebookLoginState]) {
        NSAssert(NO, @"It is not login facebook");
        completion ? completion(nil, nil, 0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传任务时,用户没有登录"}]) : nil;
        return;
    }
    // url
    if (videoURL.length <= 0) {
        NSAssert(NO, @"video url can not be nil");
        completion ? completion(nil, nil, 0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传任务时,视频地址不能为空"}]) : nil;
        return;
    }
    if (send_id.length <= 0) {
        NSAssert(NO, @"send id can not be nil");
        completion ? completion(nil, nil, 0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传任务时,send id不能为空"}]) : nil;
        return;
    }
    // 文件大小
    NSInteger videoSize = [self getVideoSizeWithURL:videoURL];
    if (videoSize <= 0) {
        completion ? completion(nil, nil, 0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"创建上传任务时,视频文件大小为0"}]) : nil;
        return;
    }
    
    NSDictionary *param = @{
                            @"upload_phase" : @"start",
                            @"file_size" : [NSString stringWithFormat:@"%ld", videoSize],
                            };
    
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc] initWithGraphPath:CPFBCreateVideoUploadURL(send_id) parameters:param HTTPMethod:k_POST];
    
    __weak typeof(self) _self = self;
    [request startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        NSDictionary *dict = [[self class] callbackWithResult:result error:error completion:^(NSError *callbackError) {
            completion ? completion(nil, nil, 0, 0, callbackError) : nil;
        }];
        if (!dict) {
            return;
        }
        
        NSString *session_id = dict[@"upload_session_id"];
        NSString *video_id = dict[@"video_id"];
        if (session_id.length <= 0 || video_id.length <= 0) {
            completion ? completion(nil, nil, 0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"upload_session_id or video_id get nil"}]) : nil;
            return;
        }
        
        NSInteger start_offset = [dict[@"start_offset"] integerValue];
        NSInteger end_offset = [dict[@"end_offset"] integerValue];
        if (start_offset != 0 || end_offset <= 0) {
            completion ? completion(nil, nil, 0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"start_offset or end_offset get error"}]) : nil;
            return;
        }
        
        completion ? completion(session_id, video_id, start_offset, end_offset, error) : nil;
    }];
}

- (FBSDKGraphRequestConnection *)appendChunkWithData:(NSData *)data send_id:(NSString *)send_id session_id:(NSString *)session_id start_offset:(NSInteger)start_offset videoName:(NSString *)videoName completion:(void(^)(NSInteger start_offset, NSInteger end_offset, NSError *error))completion {
    if (data.length <= 0) {
        NSAssert(NO, @"chunk data can not be nil");
        completion ? completion(0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"上传视频块时,视频块不能为空"}]) : nil;
        return nil;
    }
    if (send_id.length <= 0) {
        NSAssert(NO, @"send id can not be nil");
        completion ? completion(0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"上传视频块时,send id不能为空"}]) : nil;
        return nil;
    }
    if (session_id.length <= 0) {
        NSAssert(NO, @"session id can not be nil");
        completion ? completion(0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"上传视频块时,session id不能为空"}]) : nil;
        return nil;
    }
    if (start_offset < 0) {
        NSAssert(NO, @"start offset can not less than 0");
        completion ? completion(0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"上传视频块时,start offset 不能小于0"}]) : nil;
        return nil;
    }
    if (videoName.length <= 0) {
        videoName = @"facebook_video_upload_chunk";
    }
    FBSDKGraphRequestDataAttachment *chunk = [[FBSDKGraphRequestDataAttachment alloc] initWithData:data filename:videoName contentType:nil];
    if (!chunk) {
        NSAssert(NO, @"FBSDKGraphRequestDataAttachment 创建失败");
        completion ? completion(0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"上传视频块时,FBSDKGraphRequestDataAttachment 创建失败"}]) : nil;
        return nil;
    }
    
    NSDictionary *dict = @{
                           @"upload_phase" : @"transfer",
                           @"upload_session_id" : session_id,
                           @"start_offset" : [NSString stringWithFormat:@"%ld", start_offset],
                           @"video_file_chunk" : chunk,
                           };
    
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc] initWithGraphPath:CPFBCreateVideoUploadURL(send_id) parameters:dict HTTPMethod:k_POST];
    
     FBSDKGraphRequestConnection *connection = [request startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        NSDictionary *dict = [[self class] callbackWithResult:result error:error completion:^(NSError *callbackError) {
            completion ? completion(0, 0, callbackError) : nil;
        }];
        if (!dict) {
            return;
        }
        
        NSInteger start_offset = [dict[@"start_offset"] integerValue];
        NSInteger end_offset = [dict[@"end_offset"] integerValue];
        if (start_offset <= 0 || end_offset <= 0) {
            completion ? completion(0, 0, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"get start offset or end offset failed"}]) : nil;
            return;
        }
        
        completion ? completion(start_offset, end_offset, error) : nil;
    }];
    return connection;
}

- (void)finishUploadAndPublishVideoWithParam:(NSDictionary *)publishParam send_id:(NSString *)send_id session_id:(NSString *)session_id completion:(void(^)(NSString *videoLink, NSError *error))completion {
    if (send_id.length <= 0) {
        NSAssert(NO, @"send id can not be nil");
        completion ? completion(nil, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"发布视频时,send id不能为空"}]) : nil;
        return;
    }
    if (session_id.length <= 0) {
        NSAssert(NO, @"session id can not be nil");
        completion ? completion(nil, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"发布视频时,session id不能为空"}]) : nil;
        return;
    }
    if (!publishParam) {
        NSAssert(NO, @"publish param can not less than 0");
    }
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                @"upload_phase" : @"finish",
                                                                                @"upload_session_id" : session_id,
                                                                                }];
    if (publishParam) {
        
        NSMutableDictionary *aPublishParam = [NSMutableDictionary dictionaryWithDictionary:publishParam];
        if ([aPublishParam.allKeys containsObject:@"thumb"]) {
            NSData *imageData = aPublishParam[@"thumb"];
            if (imageData && [imageData isKindOfClass:[NSData class]]) {
                FBSDKGraphRequestDataAttachment *attachment = [[FBSDKGraphRequestDataAttachment alloc] initWithData:imageData filename:@"thumb.png" contentType:nil];
                [aPublishParam setObject:attachment forKey:@"thumb"];
            }
        }
        
        [dict addEntriesFromDictionary:aPublishParam];
    }
    
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc] initWithGraphPath:CPFBCreateVideoUploadURL(send_id) parameters:dict HTTPMethod:k_POST];
    
    __weak typeof(self) _self = self;
    [request startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        NSDictionary *userDict = [[self class] callbackWithResult:result error:error completion:^(NSError *callbackError) {
            completion ? completion(nil, callbackError) : nil;
        }];
        if (!userDict) {
            return;
        }
        
        BOOL yesOrNo = [userDict[@"success"] boolValue]; // 如果没有这个属性就是为NO
        if (!yesOrNo) {
            completion ? completion(nil, [NSError errorWithDomain:CPFacebookErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"finish upload failed"}]) : nil;
            return;
        }
        // 拼接URL https://www.facebook.com/MrBean/videos/10156046890901469/
        NSString *string = [NSString stringWithFormat:@"%@/%@/%@/%@", @"https://www.facebook.com", _self.uploadInfoRecord.sendID, @"videos", _self.uploadInfoRecord.video_id];
        _self.videoLink = string;
        completion ? completion(string, nil) : nil;
    }];
}

// 删除视频 --- 取消上传的时候
+ (void)deleteVideoWithVideo_id:(NSString *)video_id completion:(void(^)(BOOL success, NSError *error))completion {
    if (video_id.length <= 0) {
        NSAssert(NO, @"video id can not be nil");
        completion ? completion(NO, [NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"video id is nil"}]) : nil;
        return;
    }
    
    // 删除
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc] initWithGraphPath:[NSString stringWithFormat:@"/%@", video_id] parameters:nil HTTPMethod:k_DELETE];
    [request startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        NSDictionary *userDict = [[self class] callbackWithResult:result error:error completion:^(NSError *callbackError) {
            completion ? completion(NO, error) : nil;
        }];
        if (!userDict) {
            return;
        }
        
        BOOL yesOrNo = [userDict[@"success"] boolValue];
        completion ? completion(yesOrNo, error) : nil;
        
    }];
}

# pragma mark -

// 任务的完成回调 --- 如果error为空 则视为是成功
- (void)completionCallbackWithError:(NSError *)error {
    if (!error) {
        NSString *baseLink = @"https://www.facebook.com";
        self.videoLink = [NSString stringWithFormat:@"%@/%@/%@/%@", baseLink, self.uploadInfoRecord.sendID, @"videos", self.uploadInfoRecord.video_id];
        self.progressHandler ? self.progressHandler(self, 1.0) : nil;
        [self removeRecordInfoWithMediaID:self.uploadInfoRecord.session_id];
    }
    [self pause];
    self.completeHandler ? self.completeHandler(self, error) : nil;
}

// progress回调 --- 上传中
- (void)makeProgressCallbackDurationUploadWithUploaded_bytes:(NSInteger)uploaded_bytes {
    CGFloat uploaded = uploaded_bytes;
    CGFloat total = self.file.size;
    CGFloat percent = 0.02 + (uploaded / total) * 0.95;
    PLog(@"total : %f, uploaded : %f, percent : %f", total, uploaded, percent);
    self.progressHandler ? self.progressHandler(self, percent) : nil;
}

#pragma mark - private method

+ (NSDictionary *)callbackWithResult:(id)result error:(NSError *)error completion:(void(^)(NSError *callbackError))completion {
    if (error) {
        completion ? completion(error) : nil;
        return nil;
    }
    
    NSDictionary *dict = (NSDictionary *)result;
    if (![dict isKindOfClass:[NSDictionary class]] || !dict) {
        completion ? completion([NSError errorWithDomain:CPFacebookErrorDomain code:kFacebookErrorCode userInfo:@{NSLocalizedDescriptionKey : @"response is nil"}]) : nil;
        return nil;
    }
    
    return dict;
}

- (BOOL)checkFacebookLoginState {
    FBSDKAccessToken *token = [FBSDKAccessToken currentAccessToken];
    return (token ? YES : NO);
}

#pragma mark - FBSDKGraphRequestConnectionDelegate

// 上传回调
- (void)requestConnection:(FBSDKGraphRequestConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite {
    
    [self makeProgressCallbackDurationUploadWithUploaded_bytes:(self.uploadInfoRecord.start_offset + bytesWritten)];
    
}

#pragma mark - setter

- (void)setCurrentConnection:(FBSDKGraphRequestConnection *)currentConnection {
    _currentConnection = currentConnection;
    currentConnection.delegate = self;
}

@end

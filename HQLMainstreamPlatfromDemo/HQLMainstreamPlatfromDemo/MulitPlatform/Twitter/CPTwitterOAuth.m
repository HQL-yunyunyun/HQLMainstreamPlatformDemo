//
//  CPTwitterOAuth.m
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/14.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import "CPTwitterOAuth.h"

#define kTwitterVideoLimitTime 140
#define kTwitterVideoLimitSize (512 * 1024 * 1024)

@interface CPTwitterOAuth ()

@property (nonatomic, strong) TWTRSession *authorization;

// 负责与授权相关的manager
@property (nonatomic, strong) TWTRTwitter *twitter;
@property (nonatomic, strong) TWTRAPIClient *apiClient;

@end

@implementation CPTwitterOAuth

- (instancetype)initWithAuthorization:(TWTRSession *)authorization {
    if (self = [super init]) {
        [self setCurrentAuthorization:authorization];
        if (authorization) {
            self.apiClient = [[TWTRAPIClient alloc] initWithUserID:authorization.userID];
        }
    }
    return self;
}

- (void)dealloc {
    PLog(@"dealloc ---> %@", NSStringFromClass([self class]));
}

#pragma mark - auth method

- (void)doTwitterAuthWithPresentController:(UIViewController *)presentController thenHandler:(void (^)(TWTRSession *, NSError *))handler {
    // 授权
    __weak typeof(self) _self = self;
    // 判断是否已有登录 --- 只能登录一个Twitter账号(TwitterSDK可以持有多个)
    if (self.authorization) {
        handler ? handler(self.authorization, nil) : nil;
        return;
    }
    
    [self.twitter logInWithViewController:presentController completion:^(TWTRSession * _Nullable session, NSError * _Nullable error) {
        __strong typeof(_self) strongSelf = _self;
        if (error || !session) {
            // 对于session不用做太多的操作，因为TwitterSDK会自己持有每一个session
            handler ? handler(nil, error) : nil;
            return;
        }
        strongSelf.apiClient = [[TWTRAPIClient alloc] initWithUserID:session.userID];
        [strongSelf setCurrentAuthorization:session];
        handler ? handler(session, nil) : nil;
    }];
}

// 清除授权
- (void)clearAuth {
    if (!self.authorization) {
        return;
    }
    [self.twitter.sessionStore logOutUserID:self.authorization.userID];
    self.apiClient = nil;
    [self setCurrentAuthorization:nil];
}

- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void (^)(TWTRUser *, NSError *))handler {
    // 判断当前权限
    __weak typeof(self) _self = self;
    if (!self.authorization) {
        [self doTwitterAuthWithPresentController:controller thenHandler:^(TWTRSession *authorization, NSError *error) {
            __strong typeof(_self) strongSelf = _self;
            if (error || !authorization) {
                handler ? handler(nil, error) : nil;
                return;
            }
            [strongSelf fetchUserInfoWithPresentController:controller completeHandler:handler];
        }];
        return;
    }
    
    // 有权限
    [self.apiClient loadUserWithID:self.authorization.userID completion:^(TWTRUser * _Nullable user, NSError * _Nullable error) {
        if (error || !user) {
            handler ? handler(nil, error) : nil;
            return;
        }
        
        handler ? handler(user, error) : nil;
    }];
}

- (void)setCurrentAuthorization:(TWTRSession *)authorization {
    
    if ([self.authorization isEqual:authorization] || (!authorization && !self.authorization)) {
        return;
    }
    
    self.authorization = authorization;
    
    NSDictionary *dict = nil;
    if (authorization) {
        dict = @{TwitterAuthorizationDidChangeNotificationAuthorizationKey : authorization};
    }
    
    NSNotification *noti = [NSNotification notificationWithName:TwitterAuthorizationDidChangeNotification object:nil userInfo:dict];
    [[NSNotificationCenter defaultCenter] postNotification:noti];
}

#pragma mark - video upload method

// 判断视频是否符合要求
+ (BOOL)videoCanUploadWithVideoURL:(NSURL *)videoURL {
    if (!videoURL) {
        return NO;
    }
    AVURLAsset *asset = [AVURLAsset assetWithURL:videoURL];
    if (!asset) {
        return NO;
    }
    // 判断时长
    CMTime time = [asset duration];
    int seconds = ceil(time.value / time.timescale);
    if (seconds > kTwitterVideoLimitTime) {
        return NO;
    }
    // 判断大小
    if ([[NSFileManager defaultManager] attributesOfItemAtPath:videoURL.absoluteString error:nil].fileSize > kTwitterVideoLimitSize) {
        return NO;
    }
    
    return YES;
}

// 创建上传任务
- (CPTwitterUploader *)createTwitterVideoUploadTicketWithParamDict:(NSDictionary *)paramDict
                                     precentController:(UIViewController *)precentController
                                     uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
                                     completeHandler:(CPUploaderCompleteHandler)completeHandler {
    // 判断是否有登录
    if (self.authorization == nil) { // 没有登录
        [self doTwitterAuthWithPresentController:precentController thenHandler:nil];
        return nil;
    }
    
    if (!paramDict) {
        NSAssert(NO, @"paramDict can not be nil");
        completeHandler ? completeHandler(nil, [NSError errorWithDomain:CPTwitterMediaErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"paramDict can not be nil"}]) : nil;
        return nil;
    }
    
    NSString *url = paramDict[@"videoURL"];
    if (url.length <= 0) {
        NSAssert(NO, @"video url can not be nil");
        completeHandler ? completeHandler(nil, [NSError errorWithDomain:CPTwitterMediaErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"video url can not be nil"}]) : nil;
        return nil;
    }
    
    // 检测
    if (![[self class] videoCanUploadWithVideoURL:[NSURL fileURLWithPath:url]]) {
        NSAssert(NO, @"视频不符合规格");
        completeHandler ? completeHandler(nil, [NSError errorWithDomain:CPTwitterMediaErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"视频不符合规格"}]) : nil;
        return nil;
    }
    
    // 创建param
    CPUploadParam *param = [[CPUploadParam alloc] init];
    param.userID = self.authorization.userID;
    param.videoURL = url;
    NSString *tweetText = paramDict[@"tweetText"];
    param.publishParam = @{@"status" : tweetText ? tweetText : @""};
    param.resumeMediaId = paramDict[@"resumeMediaId"];
    
    return [CPTwitterUploader createTwitterVideoUploadTicketWithParam:param uploadProgressHandler:uploadProgressHandler completeHandler:completeHandler];
}

#pragma mark - getter & setter

- (TWTRTwitter *)twitter {
    if (!_twitter) {
        _twitter = [TWTRTwitter sharedInstance];
    }
    return _twitter;
}

@end

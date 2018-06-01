//
//  HQLTwitchOAuth.m
//  HQLTwitchBroadcast
//
//  Created by 何启亮 on 2017/11/2.
//  Copyright © 2017年 HQL. All rights reserved.
//

#import "HQLTwitchOAuth.h"
#import <AFNetworking/AFNetworking.h>
#import "HQLAuthWebViewController.h"
#import "GCDAsyncSocket.h"

#define TwitchBaseURL @"https://api.twitch.tv/kraken"
#define TwitchChatURL @"irc.chat.twitch.tv"
#define TwitchRtmpURL @"rtmp://live.twitch.tv/app"

#define TwitchAuthURL @"oauth2/authorize"
#define TwitchTokenURL @"oauth2/token"
#define TwitchRevokeTokenURL @"oauth2/revoke"

#define TwitchChannelsURL @"channel"
#define TwitchUserURL @"users"
#define TwitchStreamsURL @"streams"
#define TwitchIngestsURL @"ingests"

// client ID
static NSString *const twitchClientID = @"dkm4sqj5skphk55tk5uf5tsg5q0c6f";
// client secret
static NSString *const twitchClientSecret = @"q3sh4ismimjyvmr2m7xlxgn0wa7d4t";
// redirect uri
static NSString *const twitchRedirectUri = @"http://localhost";

//static NSString *const kTWITCHAppAuthKeychainItemName = @"hql.twitch.example:Twitch.AppAuth";

// param
static NSString *const kClient_id = @"client_id";
static NSString *const kClient_secret = @"client_secret";
static NSString *const kCode = @"code";
static NSString *const kGrant_type = @"grant_type";
static NSString *const kRedirect_uri = @"redirect_uri";
static NSString *const kResponse_type = @"response_type";
static NSString *const kLogin = @"login";
static NSString *const kToken = @"token";
static NSString *const kAccess_token = @"access_token";
static NSString *const kRefresh_token = @"refresh_token";
static NSString *const kExpires_in = @"expires_in";
static NSString *const kScope = @"scope";
static NSString *const kOAuth_token = @"oauth_token";
static NSString *const kMessage = @"message";
static NSString *const kUpdated_at = @"updated_at";
static NSString *const kUser_name = @"user_name";
static NSString *const kStream_key = @"stream_key";
// response type
static NSString *const twitch_response_type_code = @"code";
static NSString *const twitch_response_type_token = @"token";
// scope
static NSString *const twitch_scope_user_edit = @"user:edit";
static NSString *const twitch_scope_user_read_email = @"user:read:email";
// grant type
static NSString *const twitch_grant_type_authorization_code = @"authorization_code";
static NSString *const twitch_grant_type_refresh_token = @"refresh_token";
static NSString *const twitch_grant_type_client_credentials = @"client_credentials";

// socket ----
double TIMEOUT_CONNECT = 30;
double TIMEOUT_NONE = -1;
NSString *CRLF = @"\r\n";
int TwitchChatPort = 6667;
NSString *PRIVMSG = @"PRIVMSG";

typedef NS_ENUM(NSInteger, TwitchChatSocketTag) {
    TwitchChatSocketTagNormal = -1,
    TwitchChatSocketTagPass = 0,
    TwitchChatSocketTagNick = 1,
    TwitchChatSocketTagUser = 2,
    TwitchChatSocketTagNickServPassword = 3,
    TwitchChatSocketTagChannel = 4,
};

@interface HQLTwitchOAuth () <GCDAsyncSocketDelegate>

@property (nonatomic, strong) AFHTTPSessionManager *networkManager;
@property (nonatomic, strong) TwitchAppFetcherAuthorization *authorization;
@property (nonatomic, copy) NSString *channelName;
@property (nonatomic, copy) NSString *channelID;

@property (nonatomic, strong) GCDAsyncSocket *chatSocket;
@property (nonatomic, assign) BOOL isAutoReveiceLiveMessage;
//@property (nonatomic, strong) NSTimer *chatTimer;

@property (nonatomic, strong) NSMutableArray *broadcastConnectionArray;

//@property (nonatomic, assign) BOOL isReceiveData; // 每次socket readData 的标志

//@property (nonatomic, strong) NSTimer *statusTimer;

@end

@implementation HQLTwitchOAuth {
    BOOL isConnecting;
    UIViewController *presentController;
}

- (instancetype)initWithAuthorization:(TwitchAppFetcherAuthorization *)authorization {
    if (self = [super init]) {
        [self setCurrentAuthorization:authorization];
    }
    return self;
}

/*
 获取授权 --- 步骤
 1 - 检查token是否有过期
 2 - 使用code获取授权
 3 - 重新获取授权
 */
- (void)doTwitchAuthWithPresentController:(UIViewController *)controller thenHandler:(TwitchOAuthCompleteHandler)handler {
    
    __weak typeof(self) _self = self;
    
    if (self.authorization) {
        if ([self.authorization canAuthorization]) {
            handler ? handler(self.authorization, nil) : nil;
        } else { // 更新token
            [self refreshTokenWithCompleteHandler:^(TwitchAppFetcherAuthorization *authorization, NSError *error) {
                if (!error) {
                    handler ? handler(authorization, nil) : nil;
                } else {
                    
                    __strong typeof(_self) __self = _self;
                    [_self doAuthWithPresentController:controller code:_self.authorization.code completeHandler:^(TwitchAppFetcherAuthorization *authorization, NSError *error) {
                        if (!error) {
                            handler ? handler(authorization, error) : nil;
                        } else {
                            // 重新获取
                            [__self doAuthWithPresentController:controller code:nil completeHandler:handler];
                        }
                    }];
                    
                }
            }];
        }
    } else {
        // 重新获取
        [self doAuthWithPresentController:controller code:nil completeHandler:handler];
    }
}

- (void)refreshTokenWithCompleteHandler:(TwitchOAuthCompleteHandler)handler {
    
    if (!self.authorization.refreshToken || [self.authorization.refreshToken isEqualToString:@""]) {
        handler ? handler(nil, [NSError errorWithDomain:TwitchAuthErrorDoMain code:-10000 userInfo:@{kMessage : @"could not have refresh token", NSLocalizedDescriptionKey : @"could not have refresh token"}]) : nil;
        return;
    }
    
    __weak typeof(self) _self = self;
    
    NSDictionary *param = @{
                            kClient_id : twitchClientID,
                            kClient_secret : twitchClientSecret,
                            kRefresh_token : self.authorization.refreshToken,
                            kGrant_type : twitch_grant_type_refresh_token
                            };
    NSString *url = [self stitchingURLWithURL:TwitchTokenURL param:param];
    [self.networkManager POST:url parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
        
        NSDictionary *dict = (NSDictionary *)responseObject;
        if ([dict[kAccess_token] isEqualToString:@""] || !dict[kAccess_token]) {
            
            handler ? handler(nil, [NSError errorWithDomain:TwitchAuthErrorDoMain code:-10000 userInfo:@{@"message" : dict[kMessage], NSLocalizedDescriptionKey : dict[kMessage]}]) : nil;
            return;
        }
        
        _self.authorization.refreshToken = dict[kRefresh_token];
        _self.authorization.accessToken = dict[kAccess_token];
        _self.authorization.updateTime = [NSDate date];
        _self.authorization.scopes = dict[kScope];
        
        [_self setCurrentAuthorization:_self.authorization];
        
        handler ? handler(_self.authorization, nil) : nil;
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        handler ? handler(nil, error) : nil;
    }];
}

- (void)revokeAccessTokenWithToken:(NSString *)token completeHandler:(void (^)(NSError *))handler {
    if (token.length == 0) {
        handler ? handler([NSError errorWithDomain:TwitchAuthErrorDoMain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"token can not be nil", kMessage : @"token can not be nil"}]) : nil;
        return;
    }
    __weak typeof(self) _self = self;
//    if (self.authorization.accessToken) {
        NSDictionary *param = @{
                                kClient_id : twitchClientID,
                                kToken : token,
//                                @"code" : token
                                };
        NSString *url = [self stitchingURLWithURL:TwitchRevokeTokenURL param:param];
        
        [self.networkManager POST:url parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
            _self.authorization.accessToken = nil;
            _self.authorization.refreshToken = nil;
            _self.authorization.expires_in = nil;
            
            [_self setCurrentAuthorization:_self.authorization];
            
            NSError *error = nil;
            
            NSDictionary *dict = (NSDictionary *)responseObject;
            if (![dict[@"status"] isEqualToString:@"ok"]) {
                error = [NSError errorWithDomain:TwitchAuthErrorDoMain code:-10000 userInfo:@{kMessage : @"revoke token failed", NSLocalizedDescriptionKey : @"revoke token failed"}];
            }
            
            handler ? handler(error) : nil;
            
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            handler ? handler(error) : nil;
        }];
        
//    } else {
//        handler ? handler(nil) : nil;
//    }
}

- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void (^)(NSDictionary *, NSError *))handler {
    
    __weak typeof(self) _self = self;
    if (![self.authorization canAuthorization] || !self.authorization) {
        [self doTwitchAuthWithPresentController:controller thenHandler:^(TwitchAppFetcherAuthorization *authorization, NSError *error) {
            if (error) {
                handler ? handler(nil, error) : nil;
                return;
            }
            
            [_self fetchUserInfoWithPresentController:controller completeHandler:handler];
            
        }];
        return;
    }
    
    
    [self fetchTokenInfoWithToken:self.authorization.accessToken completeHandler:^(NSDictionary *response, NSError *error) {
        
        if (!error) {
            
            NSDictionary *token = response[kToken];
            
            NSDictionary *authorization = token[@"authorization"];
            _self.authorization.updateTime = [[_self dateFormatter] dateFromString:authorization[kUpdated_at]];
            
            [_self setCurrentAuthorization:_self.authorization];
            
            NSDictionary *param = @{
                                    kOAuth_token : _self.authorization.accessToken,
                                    kLogin : token[kUser_name],
                                    };
            
            _self.channelName = token[kUser_name];
            _self.channelID = token[@"user_id"];
            
            NSString *url = [_self stitchingURLWithURL:TwitchUserURL param:param];
            [_self setupNetWorkHeader];
            NSURLSessionDataTask *task = [_self.networkManager GET:url parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
                
                [_self.broadcastConnectionArray removeObject:task];
                
                NSDictionary *dict = (NSDictionary *)responseObject;
                NSArray *users = dict[@"users"];
                handler ? handler(users.firstObject, nil) : nil;
                
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                handler ? handler(nil, error) : nil;
            }];
            [_self.broadcastConnectionArray addObject:task];
            
        } else {
            handler ? handler(nil, error) : nil;
        }
        
    }];
}

- (void)fetchIngestsServerWithPresentController:(UIViewController *)controller completeHandler:(void(^)(NSString *server, NSError *error))handler {
    __weak typeof(self) _self = self;
    if (![self.authorization canAuthorization] || !self.authorization) {
        [self doTwitchAuthWithPresentController:controller thenHandler:^(TwitchAppFetcherAuthorization *authorization, NSError *error) {
            if (error) {
                handler ? handler(TwitchRtmpURL, error) : nil;
                return;
            }
            
            [_self fetchIngestsServerWithPresentController:controller completeHandler:handler];
            
        }];
        return;
    }
    
    NSDictionary *param = @{
                            kOAuth_token : self.authorization.accessToken,
                            };
    NSString *url = [self stitchingURLWithURL:TwitchIngestsURL param:param];
    [self setupNetWorkHeader];
    NSURLSessionDataTask *task = [self.networkManager GET:url parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nonnull responseObject) {
       
        [_self.broadcastConnectionArray removeObject:task];
        
        NSDictionary *dict = (NSDictionary *)responseObject;
        NSArray *ingests = dict[@"ingests"];
        
        /*
        if (ingests.count == 0) {
            handler ? handler(nil, [NSError errorWithDomain:TwitchAuthErrorDoMain code:-10000 userInfo:@{kMessage : @"fetch broadcast ingest server failed", NSLocalizedDescriptionKey : @"fetch broadcast ingest server failed"}]) : nil;
            return;
        }//*/
        
        NSDictionary *target = nil;
        for (NSDictionary *server in ingests) {
            if ([server[@"default"] isEqual:@(1)]) {
                target = server;
                break;
            }
        }
        
        NSString *serverURL = TwitchRtmpURL;
        NSString *url = target[@"url_template"];
        if (url.length > 0) {
            NSRange range = [url rangeOfString:@"/" options:NSBackwardsSearch];
            serverURL = [url substringWithRange:NSMakeRange(0, range.location)];
        }
        
        handler ? handler(serverURL, nil) : nil;
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        handler ? handler(TwitchRtmpURL, error) : nil;
    }];
    [self.broadcastConnectionArray addObject:task];
}

-(void)fetchTwitchBroadcastURLWithPresentController:(UIViewController *)controller completeHandler:(void (^)(NSString *, NSError *))completeHandler {
    __weak typeof(self) _self = self;
    if (![self.authorization canAuthorization] || !self.authorization) {
        [self doTwitchAuthWithPresentController:controller thenHandler:^(TwitchAppFetcherAuthorization *authorization, NSError *error) {
            if (error) {
                completeHandler ? completeHandler(nil, error) : nil;
                return;
            }
            
            [_self fetchTwitchBroadcastURLWithPresentController:controller completeHandler:completeHandler];
            
        }];
        return;
    }
    
    NSDictionary *param = @{
                            kOAuth_token : self.authorization.accessToken,
                            };
    NSString *url = [self stitchingURLWithURL:TwitchChannelsURL param:param];
    [self setupNetWorkHeader];
    NSURLSessionDataTask *task = [self.networkManager GET:url parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
        
        [_self.broadcastConnectionArray removeObject:task];
        
        NSDictionary *dict = (NSDictionary *)responseObject;
        NSString *streamKey = dict[kStream_key];
        
        //NSString *broadcastURL = [NSString stringWithFormat:@"%@/%@", TwitchRtmpURL, dict[kStream_key]];
        _self.channelName = dict[@"display_name"];
        _self.channelID = dict[@"_id"];
        
        [_self fetchIngestsServerWithPresentController:controller completeHandler:^(NSString *server, NSError *error) {
           //直接拼
            NSString *broadcastURL = [NSString stringWithFormat:@"%@/%@", server, streamKey];
            completeHandler ? completeHandler(broadcastURL, nil) : nil;
        }];
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        completeHandler ? completeHandler(nil, error) : nil;
    }];
    [self.broadcastConnectionArray addObject:task];
}

- (void)fetchTwitchBroadcastStatusWithPresentController:(UIViewController *)controller completeHandler:(void (^)(TwitchBroadcastStatus, NSDictionary *, NSError *))handler {
    __weak typeof(self) _self = self;
    [self checkAuthorizationStatusAndChannelInfoWithPresentController:controller callbackHandler:^(NSError *error) {
        if (error) {
            handler ? handler(TwitchBroadcastStatus_off_line, nil, error) : nil;
            return;
        }
        
        NSDictionary *param = @{
                                kOAuth_token : _self.authorization.accessToken,
                                };
        NSString *url = [_self stitchingURLWithURL:[NSString stringWithFormat:@"%@/%@", TwitchStreamsURL, _self.channelID] param:param];
        [_self setupNetWorkHeader];
        NSURLSessionDataTask *task = [_self.networkManager GET:url parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
            [_self.broadcastConnectionArray removeObject:task];
            
            NSDictionary *dict = (NSDictionary *)responseObject;
            NSDictionary *stream = dict[@"stream"];
            TwitchBroadcastStatus status = TwitchBroadcastStatus_off_line;
            if ([stream isEqual:[NSNull null]] || stream == nil || stream.allKeys.count == 0) {
                status = TwitchBroadcastStatus_off_line;
            } else {
                status = TwitchBroadcastStatus_live;
            }
            
            PLog(@"twitch status : %d, stream : %@", status, stream);
            
            handler ? handler(status, stream, nil) : nil;
            
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            handler ? handler(TwitchBroadcastStatus_off_line, nil, error) : nil;
        }];
        [_self.broadcastConnectionArray addObject:task];
    }];
}

- (void)updateTwitchChannelStatusWithPresentController:(UIViewController *)controller status:(NSString *)status completeHandler:(void (^)(NSError *))handler {
    if (status.length == 0) {
        status = @"GoCreate";
    }
    __weak typeof(self) _self = self;
    [self checkAuthorizationStatusAndChannelInfoWithPresentController:controller callbackHandler:^(NSError *error) {
        if (error) {
            handler ? handler(error) : nil;
            return;
        }
       
        NSDictionary *param = @{
                                kOAuth_token : _self.authorization.accessToken,
                                @"channel[status]" : status,
                                };
        NSString *url = [_self stitchingURLWithURL:[NSString stringWithFormat:@"%@/%@", @"channels", _self.channelID] param:param];
        [_self setupNetWorkHeader];
        NSURLSessionDataTask *task = [_self.networkManager PUT:url parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
            [_self.broadcastConnectionArray removeObject:task];
            
            NSDictionary *dict = (NSDictionary *)responseObject;
            NSError *error = nil;
            
            if (![dict[@"status"] isEqualToString:status]) {
                error = [NSError errorWithDomain:TwitchAuthErrorDoMain code:-10000 userInfo:@{kMessage : @"update channel status failed", NSLocalizedDescriptionKey : @"update channel status failed"}];
            }
            
            handler ? handler(error) : nil;
            
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            handler ? handler(error) : nil;
        }];
        [_self.broadcastConnectionArray addObject:task];
    }];
}

/*
- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void (^)(NSDictionary *, NSError *))handler {
    __weak typeof(self) _self = self;
    if ([self.authorization canAppAuthorization]) { // 判断app_accessToken 是否有用
        [self doTwitchAuthWithPresentController:controller thenHandler:^(TwitchAppFetcherAuthorization *authorization, NSError *error) {
            if (error) {
                handler ? handler(nil, error) : nil;
            } else {
                
                NSDictionary *param = @{
                                        kOAuth_token : authorization.accessToken,
                                        };
                NSString *url = [_self stitchingURLWithURL:TwitchUserURL param:param];
                [_self setupNetWorkHeader];
                [_self.networkManager GET:url parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
                    
//                    NSLog(@"user info %@", responseObject);
                    
                    NSDictionary *dict = (NSDictionary *)responseObject;
                    
                    handler ? handler(dict, nil) : nil;
                    
                } failure:^(NSURLSessionDataTask *task, NSError *error) {
                    handler ? handler(nil, error) : nil;
                }];
            }
        }];
    } else {
        [self doTwitchAppAuthWithCompleteHandler:^(TwitchAppFetcherAuthorization *authorization, NSError *error) {
            if (!error) {
                [_self fetchUserInfoWithPresentController:controller completeHandler:handler];
            } else {
                handler ? handler(nil, error) : nil;
            }
        }];
    }
    
}//*/

- (void)doTwitchAppAuthWithCompleteHandler:(TwitchOAuthCompleteHandler)handler {
    
    __weak typeof(self) _self = self;
    
    NSDictionary *param = @{
                            kClient_id : twitchClientID,
                            kClient_secret : twitchClientSecret,
                            kGrant_type : twitch_grant_type_client_credentials,
                            kScope : [self scope],
                            };
    NSString *url = [self stitchingURLWithURL:TwitchTokenURL param:param];
    [self.networkManager POST:url parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
        
//        NSLog(@"fetch app access token success %@", responseObject);
        
        NSDictionary *dict = (NSDictionary *)responseObject;
        if (!_self.authorization) {
            _self.authorization = [[TwitchAppFetcherAuthorization alloc] init];
        }
        _self.authorization.app_accessToken = dict[kAccess_token];
        _self.authorization.app_accessToken_expires_in = dict[kExpires_in];
        _self.authorization.app_accessToken_scopes = dict[kScope];
        _self.authorization.app_accsssToken_updateTime = [NSDate dateWithTimeIntervalSinceNow:(-60)];
        
        [_self setCurrentAuthorization:_self.authorization];
        
        handler ? handler(_self.authorization, nil) : nil;
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
//        NSLog(@"fetch app access token error %@", error);
        
        handler ? handler(nil, error) : nil;
        
    }];
}

- (void)fetchTokenInfoWithToken:(NSString *)token completeHandler:(void(^)(NSDictionary *response, NSError *error))handler {
    NSDictionary *param = @{
                            kOAuth_token : token,
                            };
    NSString *url = [self stitchingURLWithURL:@"" param:param];
    __weak typeof(self) _self = self;
    [self setupNetWorkHeader];
    NSURLSessionDataTask *task =  [self.networkManager GET:url parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
        
        [_self.broadcastConnectionArray removeObject:task];
        
        NSDictionary *dict = (NSDictionary *)responseObject;
        handler ? handler(dict, nil) : nil;
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        handler ? handler(nil, error) : nil;
    }];
    [self.broadcastConnectionArray addObject:task];
}

- (void)cleanAuthCache {
    [self setCurrentAuthorization:nil];
    [HQLAuthWebViewController cleanCach];
}

#pragma mark - broadcast

- (void)startBroadcastWithChannelDescription:(NSString *)description presentController:(UIViewController *)controller completeHandler:(void (^)(NSString *, NSError *))handler {
    // 更新channel
    [self updateTwitchChannelStatusWithPresentController:controller status:description completeHandler:^(NSError *error) {
        
    }];
    
    //__weak typeof(self) _self = self;
    [self fetchTwitchBroadcastURLWithPresentController:controller completeHandler:^(NSString *broadcastURL, NSError *error) {
        
        //if (!error) {
            //[_self autoLaunchFetchBroadcastStatus];
            //[_self autoReceiveChannelChatWithPresentController:controller];
        //}
        
        handler ? handler(broadcastURL, error) : nil;
    }];
}


- (void)stopBroadcast {
    //[self stopAutoLaunchFetchBroadcastStatus];
    //[self stopReceiveChannelChat];
    [self stopBroadcastConnection];
}

- (void)stopBroadcastConnection {
    for (NSURLSessionDataTask *task in self.broadcastConnectionArray) {
        [task cancel];
    }
    [self.broadcastConnectionArray removeAllObjects];
}

/*
- (void)autoLaunchFetchBroadcastStatus {
    
    if (!self.statusTimer) {
        self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(fetchBroadcastStatusTimerMethod) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:self.statusTimer forMode:NSDefaultRunLoopMode];
    }
    
}

- (void)fetchBroadcastStatusTimerMethod {
    __weak typeof(self) _self = self;
    [self fetchTwitchBroadcastStatusWithPresentController:presentController completeHandler:^(TwitchBroadcastStatus broadcastStatus, NSDictionary *streamDict, NSError *error) {
        if ([_self.delegate respondsToSelector:@selector(twitchBroadcastStatusDidChange:error:)]) {
            [_self.delegate twitchBroadcastStatusDidChange:broadcastStatus error:error];
        }
    }];
}

- (void)stopAutoLaunchFetchBroadcastStatus {
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}
//*/

- (void)autoReceiveChannelChatWithPresentController:(UIViewController *)controller {
    if (isConnecting) {
        return;
    }
    presentController = controller;
    __weak typeof(self) _self = self;
    [self checkAuthorizationStatusAndChannelInfoWithPresentController:controller callbackHandler:^(NSError *error) {
        if (error) {
            if ([_self.delegate respondsToSelector:@selector(twitchDidReceiveLiveMessageError:)]) {
                [_self.delegate twitchDidReceiveLiveMessageError:error];
            }
            return;
        }
        
        isConnecting = YES;
        // 开始连接
        if (_self.chatSocket) {
            return;
        }
        _self.chatSocket = [[GCDAsyncSocket alloc] initWithDelegate:_self delegateQueue:dispatch_get_main_queue()];
        _self.chatSocket.IPv4PreferredOverIPv6 = NO;
        
        NSError *socketError = nil;
        BOOL yesOrNo = [_self.chatSocket connectToHost:TwitchChatURL onPort:TwitchChatPort withTimeout:TIMEOUT_CONNECT error:&socketError];
        if (!yesOrNo) {
            if ([_self.delegate respondsToSelector:@selector(twitchDidReceiveLiveMessageError:)]) {
                [_self.delegate twitchDidReceiveLiveMessageError:socketError];
            }
            
            [_self stopReceiveChannelChat];
            [_self resetSocket];
            
            return;
        }
        
    }];
}

- (void)stopReceiveChannelChat {
    [self.chatSocket disconnect];
    isConnecting = NO;
}

#pragma mark - socket method

- (void)sendNickMessage {
    [self writeToSocket:[NSString stringWithFormat:@"%@ %@", @"NICK", self.channelName] tag:TwitchChatSocketTagNick];
}

- (void)sendChannelMessage {
    [self writeToSocket:[NSString stringWithFormat:@"%@ #%@", @"JOIN", self.channelName] tag:TwitchChatSocketTagChannel];
}

- (void)sendPassMessage {
    [self writeToSocket:[NSString stringWithFormat:@"%@ %@:%@", @"PASS", @"oauth", self.authorization.accessToken] tag:TwitchChatSocketTagPass];
}

- (void)writeToSocket:(NSString *)string tag:(int)tag {
    NSString *appendedString = [NSString stringWithFormat:@"%@%@", string, CRLF];
    uint8_t *bytes = (uint8_t *)[appendedString UTF8String];
    [self.chatSocket writeData:[NSData dataWithBytes:bytes length:strlen((char *)bytes)] withTimeout:TIMEOUT_NONE tag:tag];
}

- (void)resetSocket {
    self.chatSocket.delegate = nil;
    self.chatSocket.delegateQueue = nil;
    self.chatSocket = nil;
}

- (void)autoReadSocketMessage {
    if (!isConnecting) {
        return;
    }
    [self.chatSocket readDataWithTimeout:TIMEOUT_NONE tag:TwitchChatSocketTagNormal];
}

#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    [self.chatSocket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:TIMEOUT_NONE tag:TwitchChatSocketTagNormal];
    if (sock == self.chatSocket) {
        [self sendPassMessage];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    if (tag == TwitchChatSocketTagPass) {
        [self sendNickMessage];
    } else if (tag == TwitchChatSocketTagNick) {
        [self sendChannelMessage];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    
    if (isConnecting) {
        // 5秒后才获取信息
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self autoReadSocketMessage];
        });
    }
    
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // 判断是否是信息 ---
    if ([string rangeOfString:PRIVMSG].location == NSNotFound) {
        return;
    }
    
    // 拆解字符串
    NSLog(@"\n%@", string);
    
    NSMutableArray *targetArray = [NSMutableArray array];
    for (NSString *commdLine in [string componentsSeparatedByString:@"\n"]) {
        if ([commdLine rangeOfString:PRIVMSG].location == NSNotFound) {
            continue;
        }
        // :hql_caiyun!hql_caiyun@hql_caiyun.tmi.twitch.tv PRIVMSG #hql_caiyun :abcdefg\n
        NSString *nameAndMessage = [commdLine componentsSeparatedByString:PRIVMSG].lastObject;
        nameAndMessage = [[[nameAndMessage stringByReplacingOccurrencesOfString:@"#" withString:@""] stringByReplacingOccurrencesOfString:@" " withString:@""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        NSLog(@"target string ---%@---", nameAndMessage);
        
        NSArray *array = [nameAndMessage componentsSeparatedByString:@":"];
        NSDictionary *dict = @{
                               @"name" : array.firstObject,
                               @"message" : array.lastObject,
                               };
        
        [targetArray addObject:dict];
    }
    if ([self.delegate respondsToSelector:@selector(twitchDidReceiveLiveMessage:)]) {
        [self.delegate twitchDidReceiveLiveMessage:targetArray];
    }
    
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    if (err != nil) {
        switch (err.code) {
            case GCDAsyncSocketNoError: {
                
                break;
            }
            case GCDAsyncSocketBadConfigError: {
                
                break;
            }
            case GCDAsyncSocketBadParamError: {
                
                break;
            }
            case GCDAsyncSocketConnectTimeoutError: {
                
                break;
            }
            case GCDAsyncSocketReadTimeoutError: {
                
                break;
            }
            case GCDAsyncSocketWriteTimeoutError: {
                break;
            }
            case GCDAsyncSocketReadMaxedOutError: {
                break;
            }
            case GCDAsyncSocketClosedError: {
                break;
            }
            case GCDAsyncSocketOtherError: {
                break;
            }
            default:
                break;
        }
    }
    
    if ([self.delegate respondsToSelector:@selector(twitchDidReceiveLiveMessageError:)]) {
        [self.delegate twitchDidReceiveLiveMessageError:err];
    }
    
    [self resetSocket];
    
    if (isConnecting) {
        [self stopReceiveChannelChat];
        [self autoReceiveChannelChatWithPresentController:presentController];
    }
}

#pragma mark - scope

- (NSArray <NSString *>*)scope {
    //return @[twitch_scope_user_edit, twitch_scope_user_read_email];
    return @[
             @"channel_editor",
             @"channel_stream",
             @"channel_read",
             @"user_read",
             @"openid",
             @"viewing_activity_read",
             @"chat_login",
             //@"user_blocks_edit",
             //@"channel_subscriptions"
             //@"channel_feed_read",
             ];
}

#pragma mark - private method

- (void)doAuthWithPresentController:(UIViewController *)controller code:(NSString *)code completeHandler:(TwitchOAuthCompleteHandler)handler {
    
    __weak typeof(self) _self = self;
    
    if (code && ![code isEqualToString:@""]) {
        // 拼接URL
        NSDictionary *param = @{
                                kClient_id:twitchClientID,
                                kRedirect_uri:twitchRedirectUri,
                                kCode:code,
                                kClient_secret:twitchClientSecret,
                                kGrant_type:twitch_grant_type_authorization_code
                                };
        NSString *url = [self stitchingURLWithURL:TwitchTokenURL param:param];
        [self.networkManager POST:url parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
            NSDictionary *dict = (NSDictionary *)responseObject;
            if ([dict[kAccess_token] isEqualToString:@""] || !dict[kAccess_token]) {
                
                handler ? handler(nil, [NSError errorWithDomain:TwitchAuthErrorDoMain code:-10000 userInfo:@{@"message" : dict[kMessage], NSLocalizedDescriptionKey : dict[kMessage]}]) : nil;
                return;
            }
            
            if (!_self.authorization) {
                _self.authorization = [[TwitchAppFetcherAuthorization alloc] init];
            }
            _self.authorization.accessToken = dict[kAccess_token];
            _self.authorization.refreshToken = dict[kRefresh_token];
            _self.authorization.expires_in = dict[kExpires_in];
            _self.authorization.scopes = dict[kScope];
            
            [_self setCurrentAuthorization:_self.authorization];
            
            handler ? handler(_self.authorization, nil) : nil;
            
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
//            [_self doAuthWithPresentController:controller code:nil completeHandler:handler];
            handler ? handler(nil, error) : nil;
        }];
        
    } else {
        // 初始的申请
        NSDictionary *param = @{
                                kClient_id : twitchClientID,
                                kRedirect_uri : twitchRedirectUri,
                                kResponse_type : twitch_response_type_code,
                                kScope : [self scope],
                                };
        NSString *url = [self stitchingURLWithURL:TwitchAuthURL param:param];
        
        HQLAuthWebViewController *authWebController = [[HQLAuthWebViewController alloc] initWithURL:url callbackURL:twitchRedirectUri completeHandler:^(NSURL *callbackURL, NSError *error) {
            if (error) {
                if (error.code == -1) {
                    error = [NSError errorWithDomain:TwitchAuthErrorDoMain code:kTwitchLoginCancelErrorCode userInfo:@{@"message" : @"fecth twitch authorization request did cancel" , NSLocalizedDescriptionKey : @"fecth twitch authorization request did cancel"}];
                }
                handler ? handler(nil, error) : nil;
                return;
            }
                
            NSString *code = [_self getRequestParaStringWithName:@"code" url:callbackURL.absoluteString];
            if (code && ![code isEqualToString:@""]) {
                // 获取到了code
                if (!_self.authorization) {
                    _self.authorization = [[TwitchAppFetcherAuthorization alloc] init];
                }
                _self.authorization.code = code;
                
                [_self setCurrentAuthorization:_self.authorization];
                
                [_self doAuthWithPresentController:controller code:code completeHandler:handler];
            } else {
                // 没有获取到code
                NSString *errorString = [_self getRequestParaStringWithName:@"error" url:callbackURL.absoluteString];
                if (errorString && ![errorString isEqualToString:@""]) {

                } else {
                    errorString = @"fetch oauth code failed";
                }
                NSError *callbackError = [NSError errorWithDomain:TwitchAuthErrorDoMain code:-10000 userInfo:@{@"message" : errorString, NSLocalizedDescriptionKey : errorString}];
                handler ? handler(nil, callbackError) : nil;
            }
            
        }];
        
        [controller presentViewController:authWebController animated:YES completion:^{
            
        }];
        
    }
}

#pragma mark - tool

- (void)setCurrentAuthorization:(TwitchAppFetcherAuthorization *)authorization {
    
    if ([self.authorization isEqual:authorization] || (!authorization && !self.authorization)) {
        return;
    }
    
    self.authorization = authorization;
    
    NSDictionary *dict = nil;
    if (authorization) {
        dict = @{TwitchAuthorizationDidChangeNotificationAuthorizationKey : authorization};
    }
    
    NSNotification *noti = [NSNotification notificationWithName:TwitchAuthorizationDidChangeNotification object:nil userInfo:dict];
    [[NSNotificationCenter defaultCenter] postNotification:noti];
}

- (void)checkAuthorizationStatusAndChannelInfoWithPresentController:(UIViewController *)controller callbackHandler:(void(^)(NSError *error))handler {
    __weak typeof(self) _self = self;
    
    if (![self.authorization canAuthorization] || !self.authorization) {
        [self doTwitchAuthWithPresentController:controller thenHandler:^(TwitchAppFetcherAuthorization *authorization, NSError *error) {
            if (error) {
                handler ? handler(error) : nil;
                return;
            }
            
            [_self checkAuthorizationStatusAndChannelInfoWithPresentController:controller callbackHandler:handler];
            
        }];
        return;
    }
    
    if (!self.channelID || [self.channelID isEqualToString:@""]) {
        [self fetchUserInfoWithPresentController:controller completeHandler:^(NSDictionary *userInfo, NSError *error) {
            if (!error) {
                
                _self.channelName = userInfo[@"display_name"];
                _self.channelID = userInfo[@"_id"];
                handler ? handler(nil) : nil;
                
            } else {
                handler ? handler(nil) : nil;
            }
        }];
        return;
    }
    
    handler ? handler(nil) : nil;
}

// e.g. 2014-03-02T11:12:46Z
- (NSDateFormatter *)dateFormatter {
    static NSDateFormatter *formatter = nil;
    
    if ( !formatter )
    {
        formatter = [NSDateFormatter new];
        [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
    }
    
    return formatter;
}

- (void)setupNetWorkHeader {
    [self.networkManager.requestSerializer setValue:@"application/vnd.twitchtv.v5+json" forHTTPHeaderField:@"Accept"];
//    [self.networkManager.requestSerializer setValue:[NSString stringWithFormat:@"OAuth %@", self.authorization.app_accessToken] forHTTPHeaderField:@"Authorization"];
}

- (NSString *)getRequestParaStringWithName:(NSString *)name url:(NSString *)url {
    
    NSRange nameRange = [url rangeOfString:name];
    if (nameRange.location == NSNotFound) {
        return nil;
    }
    
    NSString *string = [url componentsSeparatedByString:name].lastObject;
    // 查找第一个&符号
    NSRange range = [string rangeOfString:@"&"];
    if (range.location == NSNotFound) {
        return [string substringFromIndex:1];
    } else {
        return [string substringWithRange:NSMakeRange(1, range.location-1)];
    }
}

- (NSString *)stitchingURLWithURL:(NSString *)url param:(NSDictionary *)param {
    NSString *target = TwitchBaseURL;
    
    target = [target stringByAppendingString:[NSString stringWithFormat:@"/%@", url]];
    
    NSString *paramString = @"";
    for (NSString * key in param.allKeys) {
        id value = param[key];
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSArray class]]) {
            paramString = [paramString stringByAppendingString:[NSString stringWithFormat:@"%@=", key]];
            
            NSString *vString = @"";
            if ([value isKindOfClass:[NSString class]]) {
                vString = (NSString *)value;
            } else {
                NSArray *array = (NSArray *)value;
                for (NSString *string in array) {
                    
                    NSString *sign = @" ";
                    if ([vString isEqualToString:@""]) {
                        sign = @"";
                    }
                    
                    vString = [vString stringByAppendingString:[NSString stringWithFormat:@"%@%@", sign, string]];
                }
            }
            
            NSString *sign = @"&";
            if ([param.allKeys indexOfObject:key] == (param.allKeys.count - 1)) {
                sign = @"";
            }
            paramString = [paramString stringByAppendingString:[NSString stringWithFormat:@"%@%@",vString, sign]];
        }
    }
    
    if (![paramString isEqualToString:@""]) {
        paramString = [paramString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        target = [target stringByAppendingString:[NSString stringWithFormat:@"?%@", paramString]];
    }
    
    return target;
}

#pragma mark - getter

- (AFHTTPSessionManager *)networkManager {
    if (!_networkManager) {
        _networkManager = [AFHTTPSessionManager manager];
    }
    return _networkManager;
}

- (NSMutableArray *)broadcastConnectionArray {
    if (!_broadcastConnectionArray) {
        _broadcastConnectionArray = [NSMutableArray array];
    }
    return _broadcastConnectionArray;
}

@end

//
//  GCGoogleAuthFetcherManager.m
//  GoCreate3.0
//
//  Created by 何启亮 on 2017/9/18.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import "CPYouTubeOAuth.h"

#import "CPYoutubeBrocastRoomModel.h"
#import <GTLRYouTube.h>

#import "AppDelegate.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import <GTMSessionFetcher/GTMSessionFetcherService.h>

// 定义一个默认的时间间隔
#define kDefaultPollingIntervalMillis (10 * 1000)

/*! @brief The OIDC issuer from which the configuration will be discovered.
 */
static NSString *const kIssuer = @"https://accounts.google.com";

/*! @brief The OAuth client ID.
 @discussion For Google, register your client at
 https://console.developers.google.com/apis/credentials?project=_
 The client should be registered with the "iOS" type.
 */
static NSString *const kClientID = @"117770256090-eesgrjqput2cs5dp9hlscch2u6j6ab80.apps.googleusercontent.com";

/*! @brief The OAuth redirect URI for the client @c kClientID.
 @discussion With Google, the scheme of the redirect URI is the reverse DNS notation of the
 client ID. This scheme must be registered as a scheme in the project's Info
 property list ("CFBundleURLTypes" plist key). Any path component will work, we use
 'oauthredirect' here to help disambiguate from any other use of this scheme.
 */
static NSString *const kRedirectURI = @"com.googleusercontent.apps.117770256090-eesgrjqput2cs5dp9hlscch2u6j6ab80:/oauthredirect";

@interface CPYouTubeOAuth () <OIDAuthStateErrorDelegate, OIDAuthStateChangeDelegate>
//@property (strong, nonatomic) NSMutableArray <id <GCGoogleAuthFetchManagerObserver>>*observerArray;

@property (nonatomic, readonly) GTLRYouTubeService *youTubeService;
@property (nonatomic, strong) GTLRYouTube_LiveBroadcast *youtubeLiveBroadcast;
@property (nonatomic, strong) GTLRYouTube_LiveStream *youtubeLiveStream;

@property (nonatomic, strong) NSMutableArray <GTLRServiceTicket *>*serviceTicketArray;
@property (nonatomic, strong) CPYoutubeBrocastRoomModel *room;
@property (nonatomic, assign) BOOL stoped;

@property (nonatomic, copy) NSString *currentPage;
@property (nonatomic, strong) NSMutableArray *liveChatPages;
@property (nonatomic, assign) NSUInteger pollingIntervalMillis; // liveChatMessages 删除后 再执行与 liveChatMessages 相关操作的时间间隔

@end

@implementation CPYouTubeOAuth {
    GTMAppAuthFetcherAuthorization * _authorization;
    OIDAuthState *_authState;
}

#pragma mark - initialization

- (instancetype)initWithAuthorization:(GTMAppAuthFetcherAuthorization *)authorization {
    if (self = [super init]) {
        _authorization = authorization;
        self.stoped = NO;
        self.room = nil;
    }
    return self;
}

#pragma mark - auth method

- (void)doYouTubeAuthWithPresentController:(UIViewController *)controller thenHandler:(void (^)(GTMAppAuthFetcherAuthorization *, NSError *))handler {
    if ([_authorization canAuthorize]) {
        //self.isAuthorization = YES;
        handler ? handler(_authorization, nil) : nil;
        return;
    }
    
    NSURL *issuer = [NSURL URLWithString:kIssuer];
    NSURL *redirectURI = [NSURL URLWithString:kRedirectURI];
    
    [OIDAuthorizationService discoverServiceConfigurationForIssuer:issuer completion:^(OIDServiceConfiguration * _Nullable configuration, NSError * _Nullable error) {
        if (!configuration) {
            [self logMessage:@"Error retrieving discovery document: %@", [error localizedDescription]];
            // remove app auth
            //[self clearAppAuthWithIsNotification:YES];
            
            [self cleanAppAuth];
            
            handler ? handler(nil, error) : nil;
            
            return;
        }
        
        [self logMessage:@"Got configuration: %@", configuration];
        
        // bulids authentication request
        OIDAuthorizationRequest *request = [[OIDAuthorizationRequest alloc] initWithConfiguration:configuration clientId:kClientID scopes:@[kGTLRAuthScopeYouTube, kGTLRAuthScopeYouTubeForceSsl,kGTLRAuthScopeYouTubeReadonly, OIDScopeEmail, OIDScopeOpenID, OIDScopeProfile] redirectURL:redirectURI responseType:OIDResponseTypeCode additionalParameters:nil];
        
        // init authorization request
        [self logMessage:@"Initiating authorization request with scope: %@", request.scope];
        
        AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
        appDelegate.currentAuthorizationFlow = [OIDAuthState authStateByPresentingAuthorizationRequest:request presentingViewController:controller callback:^(OIDAuthState * _Nullable authState, NSError * _Nullable error) {
            
            _authState = authState;
            _authState.errorDelegate = self;
            _authState.stateChangeDelegate = self;
            
            GTMAppAuthFetcherAuthorization *authorization = nil;
            if (authState) { // 创建成功
                [self logMessage:@"Got authorization tokens. Access token: %@", authState.lastTokenResponse.accessToken];
                
                authorization = [[GTMAppAuthFetcherAuthorization alloc] initWithAuthState:authState];
                [self setGtmAuthorization:authorization];
                
            } else { // 创建失败
                //[self clearAppAuthWithIsNotification:YES];
                
                [self cleanAppAuth];
                
                [self logMessage:@"Authorization error: %@", [error localizedDescription]];
            }
            
            handler ? handler(authorization, error) : nil;
            
        }];
    }];
}

- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void (^)(NSDictionary *, NSError *))handler {
    // 检查权限
    if (!_authorization || ![_authorization canAuthorize]) {
        [self doYouTubeAuthWithPresentController:controller thenHandler:^(GTMAppAuthFetcherAuthorization *authorization, NSError *error) {
            [self fetchUserInfoWithPresentController:controller completeHandler:handler];
        }];
        return;
    }
    
    // Creates a GTMSessionFetcherService with the authorization.
    // Normally you would save this service object and re-use it for all REST API calls.
    GTMSessionFetcherService *fetcherService = [[GTMSessionFetcherService alloc] init];
    fetcherService.authorizer = _authorization;
    
    // Creates a fetcher for the API call.
    NSURL *userinfoEndpoint = [NSURL URLWithString:@"https://www.googleapis.com/oauth2/v3/userinfo"];
    GTMSessionFetcher *fetcher = [fetcherService fetcherWithURL:userinfoEndpoint];
    [fetcher beginFetchWithCompletionHandler:^(NSData *data, NSError *error) {
        // Checks for an error.
        if (error) {
            // OIDOAuthTokenErrorDomain indicates an issue with the authorization.
            if ([error.domain isEqual:OIDOAuthTokenErrorDomain]) {
                //[self setGtmAuthorization:nil];
                //[self clearAppAuthWithIsNotification:YES];
                
                [self cleanAppAuth];
                
                [self logMessage:@"Authorization error during token refresh, clearing state. %@", error];
                // Other errors are assumed transient.
            } else {
                [self logMessage:@"Transient error during token refresh. %@", error];
            }
            
            handler ? handler(nil, error) : nil;
            return;
        }
        
        // Parses the JSON response.
        NSError *jsonError = nil;
        id jsonDictionaryOrArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        // JSON error.
        if (jsonError) {
            [self logMessage:@"JSON decoding error %@", jsonError];
            handler ? handler(nil, jsonError) : nil;
            return;
        }
        
        // Success response!
        [self logMessage:@"Success: %@", jsonDictionaryOrArray];
        NSDictionary *userInfo = jsonDictionaryOrArray;
        
        handler ? handler(userInfo, error) : nil;
    }];
}

#pragma mark -

- (void)cleanAppAuth {
    if (!_authorization) {
        return;
    }
    
    [self setGtmAuthorization:nil];
}

- (void)setGtmAuthorization:(GTMAppAuthFetcherAuthorization *)authorization {
    if ([_authorization isEqual:authorization] || (!_authorization && !authorization)) {
        return;
    }
    _authorization = authorization;
    self.youTubeService.authorizer = authorization;
    [self stateChanged];
}

- (void)stateChanged {
    [self saveState];
}

/*! @brief Saves the @c GTMAppAuthFetcherAuthorization to @c NSUSerDefaults.
 */
- (void)saveState {
    
    // 发送通知
    NSDictionary *dict = nil;
    if (_authorization) {
        dict = @{YouTubeAuthorizationDidChangeNotificationAuthorizationKey : _authorization};
    }
    NSNotification *noti = [NSNotification notificationWithName:YouTubeAuthorizationDidChangeNotification object:nil userInfo:dict];
    [[NSNotificationCenter defaultCenter] postNotification:noti];
    
}

#pragma mark - live stream method

- (void)startLiveBroadcastWithRoomModel:(CPYoutubeBrocastRoomModel *)room presentController:(UIViewController *)presentController completeHandler:(void (^)(NSString *, NSError *))completeHandler {
    
    if (!room) {
        NSAssert(NO, @"broadcast room model can not be nil");
        completeHandler ? completeHandler(nil, [NSError errorWithDomain:YouTubeErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"创建直播时，room参数为空"}]) : nil;
        return;
    }
    
    for (GTLRServiceTicket *ticket in self.serviceTicketArray) {
        [ticket cancelTicket];
    }
    
    __weak typeof(self) _self = self;
    [self doYouTubeAuthWithPresentController:presentController thenHandler:^(GTMAppAuthFetcherAuthorization *authorization, NSError *error) {
        if (error) {
            completeHandler ? completeHandler(nil, error) : nil;
            return;
        }
        
        // 成功
        [_self setGtmAuthorization:authorization];
        
        _self.stoped = NO;
        
        // kGTLRYouTubeBroadcastTypePersistent --- 默认的直播频道
        [_self getLiveBroadcastwithType:kGTLRYouTubeBroadcastTypePersistent CompleteHandle:^(NSArray<GTLRYouTube_LiveBroadcast *> *broadcastList, NSError *callbackError) {
            
            if (error) {
                completeHandler ? completeHandler(nil, error) : nil;
                return;
            }
            if (broadcastList.count == 0) {
                completeHandler ? completeHandler(nil, error) : nil;
                return;
            }
            GTLRYouTube_LiveBroadcast *broadcast = broadcastList[0];
            _self.youtubeLiveBroadcast = broadcast;
            [_self updateBroadcastInfo];
            
            NSString *streamId = broadcast.contentDetails.boundStreamId;
            [_self getLiveStreamWith:streamId CompleteHandle:^(NSArray<GTLRYouTube_LiveStream *> *streamList, NSError *error) {
                if (error) {
                    completeHandler ? completeHandler(nil, error) : nil;
                    return;
                }
                if (_self.stoped) {
                    // 如果是已经停止了，则不会有回调
                    return ;
                }
                if (streamList.count == 0) {
                    completeHandler ? completeHandler(nil, [NSError errorWithDomain:YouTubeErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"创建直播时,服务器返回的streamList为空"}]) : nil;
                    return;
                }
                
                GTLRYouTube_LiveStream *stream = streamList[0];
                self.youtubeLiveStream = stream;
                
                if (completeHandler) {
                    NSString *streamURL = [NSString stringWithFormat:@"%@/%@",stream.cdn.ingestionInfo.ingestionAddress,stream.cdn.ingestionInfo.streamName];
                    completeHandler(streamURL, nil);
                }
            }];
            
        }];
        
    }];
}

- (void) stopLiveBroadcast {
    self.stoped = YES;
    
    [self stopBroadcastConnection];
    
    [self liveBroadcastTransition:self.youtubeLiveBroadcast status:kGTLRYouTubeBroadcastStatusComplete];
    self.youtubeLiveStream = nil;
    self.youtubeLiveBroadcast = nil;
}

- (void)stopBroadcastConnection {
    for (GTLRServiceTicket *ticket in self.serviceTicketArray) {
        [ticket cancelTicket];
    }
    [self.serviceTicketArray removeAllObjects];
}

- (void)fetchLiveBroadcastStatusWithCompleteHandler:(void (^)(NSString *))handler {
    if (self.youtubeLiveBroadcast.identifier.length <= 0) {
        return;
    }
    
    __weak typeof(self) _self = self;
    [self getLiveBroadcastWith:self.youtubeLiveBroadcast.identifier CompleteHandle:^(NSArray<GTLRYouTube_LiveBroadcast *> *broadcastList, NSError *callbackError) {
        if (_self.stoped) {
            // 停止没有回调
            return;
        }
        
        if (broadcastList.count == 0) {
            handler ? handler(nil) : nil;
            return;
        }
        
        GTLRYouTube_LiveBroadcast *broadcast = broadcastList[0];
        _self.youtubeLiveBroadcast = broadcast;
        
        handler ? handler(broadcast.status.lifeCycleStatus) : nil;
    }];
}

/*
- (void) loadLiveBroadcastNowStatus
{
    if (launchTimer) {
        [launchTimer invalidate];
        launchTimer = nil;
    }
    launchTimer = [NSTimer timerWithTimeInterval:3.0f target:self selector:@selector(loadTimerCall:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:launchTimer forMode:NSRunLoopCommonModes];
    if (self.delegate&&[self.delegate respondsToSelector:@selector(liveBroadcastStatusDidChanged:)]) {
        liveNowStatus = kGTLRYouTube_LiveBroadcastStatus_LifeCycleStatus_Ready;
        [self.delegate liveBroadcastStatusDidChanged:liveNowStatus];
    }
}

- (void) loadTimerCall:(NSTimer *) timer
{
    [self getLiveBroadcastwith:self.youtubeLiveBroadcast.identifier CompleteHandle:^(NSArray<GTLRYouTube_LiveBroadcast *> *broadcastList) {
        if (stoped) {
            return ;
        }
        if (broadcastList.count == 0) {
            return;
        }
        GTLRYouTube_LiveBroadcast *broadcast = broadcastList[0];
        self.youtubeLiveBroadcast = broadcast;
        
        if (self.delegate&&[self.delegate respondsToSelector:@selector(liveBroadcastStatusDidChanged:)]) {
            [self.delegate liveBroadcastStatusDidChanged:broadcast.status.lifeCycleStatus];
        }
        
    }];
}
//*/

// !!!:get live Broadcast list --- 获取频道

- (void) getLiveBroadcastWith:(NSString *) identifire CompleteHandle:(void(^)(NSArray<GTLRYouTube_LiveBroadcast *> *broadcastList, NSError *callbackError)) completeHandle
{
    GTLRYouTubeQuery_LiveBroadcastsList *broadQuery = [GTLRYouTubeQuery_LiveBroadcastsList queryWithPart:@"id,snippet,contentDetails,status,statistics"];
    broadQuery.identifier = identifire;
    __weak typeof(self) _self = self;
    GTLRServiceTicket *broadlistTicket = [self.youTubeService executeQuery:broadQuery
                                                         completionHandler:^(GTLRServiceTicket *callbackTicket,
                                                                             GTLRYouTube_LiveBroadcastListResponse *broadcast,
                                                                             NSError *callbackError) {
                                                             [_self.serviceTicketArray removeObject:callbackTicket];
                                                             
                                                             // Callback
                                                             if (callbackError == nil) {
                                                                 
                                                                 [_self logMessage:@"Got callbackTicket: %@ live broadcast list %@", callbackTicket,broadcast.items];
                                                                 for (GTLRYouTube_LiveBroadcast *liveBroadcast in broadcast.items) {
                                                                     if ([liveBroadcast.identifier isEqualToString:_self.youtubeLiveBroadcast.identifier]) {
                                                                         [_self logMessage:@"live broacast status %@",liveBroadcast.status.lifeCycleStatus];
                                                                         break;
                                                                     }
                                                                 }
                                                                 if (completeHandle) {
                                                                     completeHandle(broadcast.items, nil);
                                                                 }
                                                             } else {
                                                                 completeHandle ? completeHandle(nil, callbackError) : nil;
                                                                 [_self logMessage:@"service error: %@", callbackError];
                                                             }
                                                             
                                                         }];
    [self.serviceTicketArray addObject:broadlistTicket];
}

- (void) getLiveBroadcastwithType:(NSString *) type CompleteHandle:(void(^)(NSArray<GTLRYouTube_LiveBroadcast *> *broadcastList, NSError *callbackError)) completeHandle
{
    GTLRYouTubeQuery_LiveBroadcastsList *broadQuery = [GTLRYouTubeQuery_LiveBroadcastsList queryWithPart:@"id,snippet,contentDetails,status,statistics"];
    broadQuery.broadcastType = type;
    broadQuery.mine = YES;
    __weak typeof(self) _self = self;
    GTLRServiceTicket *broadlistTicket = [self.youTubeService executeQuery:broadQuery
                                                         completionHandler:^(GTLRServiceTicket *callbackTicket,
                                                                             GTLRYouTube_LiveBroadcastListResponse *broadcast,
                                                                             NSError *callbackError) {
                                                             [_self.serviceTicketArray removeObject:callbackTicket];
                                                             
                                                             // Callback
                                                             if (callbackError == nil) {
                                                                 
                                                                 [_self logMessage:@"Got callbackTicket: %@ live broadcast list %@", callbackTicket,broadcast.items];
                                                                 for (GTLRYouTube_LiveBroadcast *liveBroadcast in broadcast.items) {
                                                                     if ([liveBroadcast.identifier isEqualToString:_self.youtubeLiveBroadcast.identifier]) {
                                                                         [_self logMessage:@"live broacast status %@",liveBroadcast.status.lifeCycleStatus];
                                                                         break;
                                                                     }
                                                                 }
                                                                 if (completeHandle) {
                                                                     completeHandle(broadcast.items, nil);
                                                                 }
                                                             } else {
                                                                 if (completeHandle) {
                                                                     completeHandle(nil, callbackError);
                                                                 }
                                                                 [_self logMessage:@"service error: %@", callbackError];
                                                             }
                                                             
                                                         }];
    [self.serviceTicketArray addObject:broadlistTicket];
}

// !!!: get live stream --- 获取流

- (void)getLiveStreamWith:(NSString *) identifire CompleteHandle:(void(^)(NSArray<GTLRYouTube_LiveStream *> *streamList, NSError *error)) completeHandle {
    GTLRYouTubeQuery_LiveStreamsList *streamListQuery = [GTLRYouTubeQuery_LiveStreamsList queryWithPart:@"id,snippet,cdn,status"];
    streamListQuery.identifier = identifire;
    if (identifire.length <= 0) {
        streamListQuery.mine = YES;
    }
    __weak typeof(self) _self = self;
    GTLRServiceTicket *streamlistTicket = [self.youTubeService executeQuery:streamListQuery
                                                          completionHandler:^(GTLRServiceTicket *callbackTicket,
                                                                              GTLRYouTube_LiveStreamListResponse *liveStream,
                                                                              NSError *callbackError) {
                                                              [_self.serviceTicketArray removeObject:callbackTicket];
                                                              // Callback
                                                              if (callbackError == nil) {
                                                                  [_self logMessage:@"Got callbackTicket: %@ live stream list %@", callbackTicket,liveStream.items];
                                                                  if (completeHandle) {
                                                                      completeHandle(liveStream.items, nil);
                                                                  }
                                                              } else {
                                                                  if (completeHandle) {
                                                                      completeHandle(nil, callbackError);
                                                                  }
                                                                  [_self logMessage:@"service error: %@", callbackError];
                                                              }
                                                              
                                                          }];
    [self.serviceTicketArray addObject:streamlistTicket];
}

// 停止直播时调用
- (void)liveBroadcastTransition:(GTLRYouTube_LiveBroadcast *) liveBroadcast status:(NSString *)broadcastStatus {
    GTLRYouTubeQuery_LiveBroadcastsTransition *transitionQuery = [GTLRYouTubeQuery_LiveBroadcastsTransition queryWithBroadcastStatus:broadcastStatus identifier:liveBroadcast.identifier part:@"id,snippet,contentDetails,status"];
    __weak typeof(self) _self = self;
    [self.youTubeService executeQuery:transitionQuery completionHandler:^(GTLRServiceTicket * _Nonnull callbackTicket, id  _Nullable object, NSError * _Nullable callbackError) {
        // Callback
        if (callbackError == nil) {
            [_self logMessage:@"Got callbackTicket: %@ live stream list %@", callbackTicket,liveBroadcast];
        } else {
            [_self logMessage:@"service error: %@", callbackError];
        }
    }];
}

// !!!: update broadcast info
- (void) updateBroadcastInfo
{
    // Status.
    GTLRYouTube_LiveBroadcastStatus *status = [GTLRYouTube_LiveBroadcastStatus object];
    [status setPrivacyStatus:kGTLRYouTube_ChannelStatus_PrivacyStatus_Public];
    
    // Snippet.
    GTLRYouTube_LiveBroadcastSnippet *snippet = [GTLRYouTube_LiveBroadcastSnippet object];
    //snippet.descriptionProperty = @"GoCreate.youtube.live";
    snippet.descriptionProperty = self.room.detail;
    snippet.title = self.room.title;
    //2006-11-17T15:10:46Z   2024-01-30T00:00:00.000Z
    snippet.scheduledStartTime = [GTLRDateTime dateTimeWithDate:[NSDate date]];
    // 还可以设置其他元素
    
    GTLRYouTube_LiveBroadcastContentDetails *details = [GTLRYouTube_LiveBroadcastContentDetails object];
    details.enableLowLatency = @(YES);
    details.startWithSlate = @(NO);
    details.enableDvr = @(YES);
    details.recordFromStart = @(YES);
    details.enableEmbed = @(NO);
    details.enableContentEncryption = @(NO);
    
    GTLRYouTube_MonitorStreamInfo *monitor = [GTLRYouTube_MonitorStreamInfo object];
    details.monitorStream = monitor;
    
    details.monitorStream.enableMonitorStream = @(YES);
    details.monitorStream.broadcastStreamDelayMs = @(0);
    
    GTLRYouTube_LiveBroadcast *broadCast = [GTLRYouTube_LiveBroadcast object];
    broadCast.status = status;
    broadCast.snippet = snippet;
    broadCast.kind = @"youtube#liveBroadcast";
    broadCast.contentDetails = details;
    broadCast.identifier = self.youtubeLiveBroadcast.identifier;
    
    GTLRYouTubeQuery_LiveBroadcastsUpdate *updateQuery = [GTLRYouTubeQuery_LiveBroadcastsUpdate queryWithObject:broadCast part:@"id,snippet,contentDetails,status"];
    __weak typeof(self) _self = self;
    GTLRServiceTicket *updateTicket = [self.youTubeService executeQuery:updateQuery
                                                      completionHandler:^(GTLRServiceTicket *callbackTicket,
                                                                          GTLRYouTube_LiveBroadcast *broadcast,
                                                                          NSError *callbackError) {
                                                          [_self.serviceTicketArray removeObject:callbackTicket];
                                                          
                                                          // Callback
                                                          if (callbackError == nil) {
                                                              _self.youtubeLiveBroadcast = broadcast;
                                                              
                                                              [_self logMessage:@"Got callbackTicket: %@ live broadcast %@", callbackTicket,broadcast];
                                                              
                                                          } else {
                                                              [_self logMessage:@"service error: %@", callbackError];
                                                          }
                                                          
                                                      }];
    [self.serviceTicketArray addObject:updateTicket];
}

// !!!: live chat message 相关的方法

// 获取
- (void)getLiveChatMessageWithId:(NSString *)identify pageToken:(NSString *) token completeHandle:(void(^)(GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError *error)) completeHandle
{
    GTLRYouTubeQuery_LiveChatMessagesList * listQuery = [GTLRYouTubeQuery_LiveChatMessagesList queryWithLiveChatId:identify part:@"id,snippet,authorDetails"];
    listQuery.maxResults = 200;
    if (token.length > 0) {
        listQuery.pageToken = token;
    } else {
        listQuery.pageToken = nil;
    }
    __weak typeof(self) _self = self;
    GTLRServiceTicket *listTicket = [self.youTubeService executeQuery:listQuery completionHandler:^(GTLRServiceTicket * _Nonnull callbackTicket, GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError * _Nullable callbackError) {
        [_self.serviceTicketArray removeObject:callbackTicket];
        
        if (callbackError) { // 有错误
            GTLRErrorObject *error = callbackError.userInfo[@"GTLRStructuredError"];
            GTLRErrorObjectErrorItem *item = error.errors.firstObject;
            if ([item.reason isEqualToString:@"rateLimitExceeded"]) { // 太过于频繁刷新liveChatMessages
                // 自己创建一个liveChats
            } else {
                // 其他错误
                completeHandle ? completeHandle(nil, callbackError) : nil;
                return;
            }
        }
        
        if (!liveChats) {
            liveChats = [[GTLRYouTube_LiveChatMessageListResponse alloc] init];
            liveChats.nextPageToken = _self.currentPage;
            liveChats.pollingIntervalMillis =@(kDefaultPollingIntervalMillis);
        }
        
        if (liveChats.items.count == listQuery.maxResults) {
            _self.currentPage = liveChats.nextPageToken;
            if ([_self.liveChatPages containsObject:_self.currentPage] == NO) {
                [_self.liveChatPages addObject:_self.currentPage];
            }
        }
        
        if (completeHandle) {
            completeHandle(liveChats, callbackError);
        }
        
    }];
    [self.serviceTicketArray addObject:listTicket];
}

// 删除
- (void)deleteLiveChatMessageWithId:(NSString *)identify completeHandle:(void(^)(NSArray<GTLRYouTube_LiveChatMessage *> *liveChat)) completeHandle
{
    GTLRYouTubeQuery_LiveChatMessagesDelete * deleteQuery = [GTLRYouTubeQuery_LiveChatMessagesDelete queryWithIdentifier:identify];
    __weak typeof(self) _self = self;
    GTLRServiceTicket *listTicket = [self.youTubeService executeQuery:deleteQuery completionHandler:^(GTLRServiceTicket * _Nonnull callbackTicket,  id object, NSError * _Nullable callbackError) {
        [_self.liveChatPages removeAllObjects];
        [_self.liveChatPages addObject:@""];
        
        _self.pollingIntervalMillis = kDefaultPollingIntervalMillis; // 暂时是30秒
        
        if (callbackError) {
            GTLRErrorObject *error = callbackError.userInfo[@"GTLRStructuredError"];
            PLog(@"delete live chat messages error : %@, code %@", error.message, error.code);
        }
    }];
    [self.serviceTicketArray addObject:listTicket];
}

// 获取liveMessage
- (void)fetchLiveMessageWithCompleteHandler:(void(^)(GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError *error))handler {
    
    if (self.pollingIntervalMillis > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.pollingIntervalMillis / 1000.0) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self fetchLiveMessageWithCompleteHandler:handler];
        });
        self.pollingIntervalMillis = 0;
        return;
    }
    
    NSString *identifier = self.youtubeLiveBroadcast.snippet.liveChatId;
    [self getLiveChatMessageWithId:identifier pageToken:self.currentPage completeHandle:^(GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError *error) {
        handler ? handler(liveChats, error) : nil;
    }];
}

/* 自动获取liveMessage相关的方法(弃用)
- (void) backToPreviousPageLiveMessageCompleteHandle:(void(^)(NSArray<GTLRYouTube_LiveChatMessage*> *liveChats)) completeHandle
{
    NSInteger index = [liveChatPages indexOfObject:currentPage];
    if (index == 0) {
        if (completeHandle) {
            completeHandle(nil);
        }
    }else{
        [self stopAutoLoadLiveChatMessages];
        
        [self getLiveChatMessageWithId:self.youtubeLiveBroadcast.snippet.liveChatId pageToken:[liveChatPages objectAtIndex:index - 1] completeHandle:^(GTLRYouTube_LiveChatMessageListResponse *liveChats) {
            if (completeHandle) {
                completeHandle(liveChats.items);
            }
        }];
    }
    
}

- (void) startAutoLoadLiveChatMessages
{
    liveChatStopLoading = NO;
    
    if (pollingIntervalMillis > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pollingIntervalMillis / 1000.0) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self startAutoLoadLiveChatMessages];
        });
        pollingIntervalMillis = 0;
        return;
    }
    
    NSString *identifier = self.youtubeLiveBroadcast.snippet.liveChatId;
    [self getLiveChatMessageWithId:identifier pageToken:currentPage completeHandle:^(GTLRYouTube_LiveChatMessageListResponse *liveChats) {
        
        
        if (self.delegate&&[self.delegate respondsToSelector:@selector(liveMessageChanged:)]) {
            [self.delegate liveMessageChanged:liveChats.items];
        }
        
        if (liveChatStopLoading == NO) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((liveChats.pollingIntervalMillis.integerValue /1000.0)  * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self startAutoLoadLiveChatMessages];
            });
        }
        
    }];
    
}

- (void) stopAutoLoadLiveChatMessages
{
    liveChatStopLoading = YES;
}//*/

#pragma mark - youtube video upload method

/*
 param = @{
 @"title" : string , // 标题 必须的参数
 @"description" : string , // 描述 可选
 @"tags" : string , // tag 可选
 @"privacyStatus" : string , // 视频权限 必须 直接用YouTube定义的string
 @"thumbnailURL" : string , // 缩略图 可选
 @"uploadLocationURL" : string , // 可选 --- 断点续传的url --- 在response中
 }
 */
- (GTLRServiceTicket *)createYouTubeVideoUploadTicketWithParam:(NSDictionary *)param presentController:(UIViewController *)presentController videoUrl:(NSURL *)videoUrl uploadProgressHandler:(GTLRServiceUploadProgressBlock)uploadProgressHandler completeHandler:(GTLRServiceCompletionHandler)completeHandler {
    GTLRYouTube_VideoSnippet *snippet = [[GTLRYouTube_VideoSnippet alloc] init];
    
    if ([[param allKeys] containsObject:@"title"]) {
        snippet.title = param[@"title"];
    } else {
        snippet.title = @"GoCreate video";
    }
    snippet.descriptionProperty = [param objectForKey:@"description"];
    if ([param objectForKey:@"tags"]) {
        NSArray *tags = [(NSString *)[param objectForKey:@"tags"] componentsSeparatedByString:@" "];
        snippet.tags = [NSArray arrayWithArray:tags];
    }
    
    NSString *thumbnailURL = [param objectForKey:@"thumbnailURL"];
    if (thumbnailURL) {
        GTLRYouTube_Thumbnail *thumbnail = [[GTLRYouTube_Thumbnail alloc] init];
        thumbnail.url = thumbnailURL;
        GTLRYouTube_ThumbnailDetails *details = [[GTLRYouTube_ThumbnailDetails alloc] init];
        details.high = thumbnail;
        
        snippet.thumbnails = details;
    }
    
    GTLRYouTube_VideoStatus *status = [[GTLRYouTube_VideoStatus alloc] init];
    if ([[self privacyStatus] containsObject:[param objectForKey:@"privacyStatus"]]) {
        status.privacyStatus = [param objectForKey:@"privacyStatus"];
    }
    
    GTLRYouTube_Video *video = [GTLRYouTube_Video object];
    video.snippet = snippet;
    video.status = status;
    
    NSString *filename = [videoUrl.path lastPathComponent];
    NSString *mimeType = [self MIMETypeForFilename:filename
                                   defaultMIMEType:@"video/mp4"];
    GTLRUploadParameters *uploadParam = [GTLRUploadParameters uploadParametersWithFileURL:videoUrl MIMEType:mimeType];
    uploadParam.useBackgroundSession = YES;
    if ([[param objectForKey:@"uploadLocationURL"] isKindOfClass:[NSString class]]) { // 断点上传的url
        uploadParam.uploadLocationURL = [NSURL URLWithString:[param objectForKey:@"uploadLocationURL"]];
        PLog(@"uploadLocationURL %@", uploadParam.uploadLocationURL);
    }
    
    return [self createYouTubeVideoUploadTicketWithVideo:video uploadParam:uploadParam presentController:presentController uploadProgressHandler:uploadProgressHandler completeHandler:completeHandler];
}

- (GTLRServiceTicket *)createYouTubeVideoUploadTicketWithVideo:(GTLRYouTube_Video *)video uploadParam:(GTLRUploadParameters *)uploadParam presentController:(UIViewController *)presentController uploadProgressHandler:(GTLRServiceUploadProgressBlock)uploadProgressHandler completeHandler:(GTLRServiceCompletionHandler)completeHandler {
    
    __block GTLRServiceTicket *ticket;
    
    // 上传和直播都是使用同一个service
    // 需要先授权
    __weak typeof(self) _self = self;
    [self doYouTubeAuthWithPresentController:presentController thenHandler:^(GTMAppAuthFetcherAuthorization *authorization, NSError *error) {
        if (error) {
            completeHandler ? completeHandler(nil, nil, error) : nil;
            return;
        }
        
        GTLRYouTubeQuery_VideosInsert *query = [GTLRYouTubeQuery_VideosInsert queryWithObject:video part:@"snippet,status,id,contentDetails" uploadParameters:uploadParam];
        query.additionalURLQueryParameters = @{@"uploadType" : @"resumable"};
        query.executionParameters.uploadProgressBlock = uploadProgressHandler;
        ticket = [_self.youTubeService executeQuery:query completionHandler:completeHandler];
        
    }];
    return ticket;
}

// userID 是authorization.userID
- (void)removeYouTubeVideoWithUserID:(NSString *)userID videoId:(NSString *)videoId completeHandler:(GTLRServiceCompletionHandler)completeHandler {
    // 删除频道上的视频 --- 其实可以不用判断，如果userID不对的话，会直接返回错误
    if ([self.authorization.userID isEqualToString:userID]) {
        GTLRYouTubeQuery_VideosDelete *query = [GTLRYouTubeQuery_VideosDelete queryWithIdentifier:videoId];
        [self.youTubeService executeQuery:query completionHandler:completeHandler];
    } else {
        completeHandler ? completeHandler(nil,nil,[NSError errorWithDomain:YouTubeErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"userID与当前账号不符合"}]) : nil;
    }
}

#pragma mark -

- (NSString *)MIMETypeForFilename:(NSString *)filename
                  defaultMIMEType:(NSString *)defaultType {
    NSString *result = defaultType;
    NSString *extension = [filename pathExtension];
    CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                            (__bridge CFStringRef)extension, NULL);
    if (uti) {
        CFStringRef cfMIMEType = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType);
        if (cfMIMEType) {
            result = CFBridgingRelease(cfMIMEType);
        }
        CFRelease(uti);
    }
    return result;
}

- (NSArray *)privacyStatus {
    return @[
             kGTLRYouTube_VideoStatus_PrivacyStatus_Private,
             kGTLRYouTube_VideoStatus_PrivacyStatus_Public,
             kGTLRYouTube_VideoStatus_PrivacyStatus_Unlisted
             ];
}

#pragma mark -

/*! @brief Logs a message to stdout and the textfield.
 @param format The format string and arguments.
 */
- (void)logMessage:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) {
    // gets message as string
    va_list argp;
    va_start(argp, format);
    NSString *log = [[NSString alloc] initWithFormat:format arguments:argp];
    va_end(argp);
    
    // appends to output log
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"hh:mm:ss";
    NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
    
    PLog(@"%@",[NSString stringWithFormat:@"%@: %@",
                dateString,
                log]);
}

#pragma mark - auth state delegate

- (void)didChangeState:(OIDAuthState *)state {
    if (state.isAuthorized) {
        [self setGtmAuthorization:[[GTMAppAuthFetcherAuthorization alloc] initWithAuthState:state]];
    } else {
//        [self clearAppAuthWithIsNotification:YES];
        [self cleanAppAuth];
    }
}

- (void)authState:(OIDAuthState *)state didEncounterAuthorizationError:(NSError *)error {
    [self logMessage:@"Received authorization error: %@", error];
//    [self clearAppAuthWithIsNotification:YES];
    [self cleanAppAuth];
}

#pragma mark - getter

- (GTMAppAuthFetcherAuthorization *)authorization {
    return _authorization;
}

- (NSMutableArray<GTLRServiceTicket *> *)serviceTicketArray {
    if (!_serviceTicketArray) {
        _serviceTicketArray = [NSMutableArray array];
    }
    return _serviceTicketArray;
}

- (NSMutableArray *)liveChatPages {
    if (!_liveChatPages) {
        _liveChatPages = [NSMutableArray array];
    }
    return _liveChatPages;
}

- (GTLRYouTubeService *)youTubeService {
    
    static GTLRYouTubeService *service = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[GTLRYouTubeService alloc] init];
        
        // Have the service object set tickets to fetch consecutive pages
        // of the feed so we do not need to manually fetch them.
        service.shouldFetchNextPages = NO;
        
        // Have the service object set tickets to retry temporary error conditions
        // automatically.
        service.retryEnabled = YES;
    });
    return service;//*/
}

@end

//
//  GCYoutubeLiveStream.m
//  GoCreate3.0
//
//  Created by lious_li on 2017/8/14.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import "GCYoutubeLiveStream.h"
#import "AppDelegate.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import "CustomUserDefault.h"

//#import <GTMSessionFetcher/GTMSessionFetcherService.h>
//#import "GCFileManager.h"
//#import "GCGoogleAuthFetcherManager.h"

#import "CPPlatformAuthManager.h"

#define kDefaultPollingIntervalMillis (10 * 1000)

@interface GCYoutubeLiveStream ()

@property (nonatomic, readonly) GTLRYouTubeService *youTubeService;

@property (nonatomic, strong) GTLRYouTube_LiveStream *youtubeLiveStream;

@end

@implementation GCYoutubeLiveStream
{
//    NSTimer *launchTimer;
    BOOL stoped;
    
    NSMutableArray *serviceTicketArray;
    BOOL createLive;
    
//    GCYoutubeLiveStreamLiveStatus liveStatus;
//    NSString *liveNowStatus;
    
//    BOOL liveChatStopLoading;
    NSString *currentPage;
    NSMutableArray *liveChatPages;
    
    NSUInteger pollingIntervalMillis; // liveChatMessages 删除后 再执行与 liveChatMessages 相关操作的时间间隔
    
    RACDisposable *dispose;
}

#pragma mark - life cycle

- (instancetype)init
{
    self = [super init];
    if (self) {
        stoped = NO;
        
        self.youTubeService.authorizer = [CPPlatformAuthManager shareManager].youtubeAuthorization;

        serviceTicketArray = [[NSMutableArray alloc] init];
        liveChatPages = [[NSMutableArray alloc]init];

        @weakify(self);
        dispose = [RACObserve([CPPlatformAuthManager shareManager], youtubeAuthorization) subscribeNext:^(id x) {
            @strongify(self);
            GTMAppAuthFetcherAuthorization *authorization = [CPPlatformAuthManager shareManager].youtubeAuthorization;
            if (authorization) {
                [self setGtmAuthorization:[CPPlatformAuthManager shareManager].youtubeAuthorization];
            } else {
                [self clearAppAuth];
            }
        }];
    }
    return self;
}

- (void)dealloc {
    [dispose dispose];
    PLog(@"dealloc ---> %@", NSStringFromClass([self class]));
}

#pragma mark - live broadcast

- (void) updateBroadcastInfo
{
    // Status.
    GTLRYouTube_LiveBroadcastStatus *status = [GTLRYouTube_LiveBroadcastStatus object];
    [status setPrivacyStatus:kGTLRYouTube_ChannelStatus_PrivacyStatus_Public];
    
    // Snippet.
    GTLRYouTube_LiveBroadcastSnippet *snippet = [GTLRYouTube_LiveBroadcastSnippet object];
    //snippet.descriptionProperty = @"GoCreate.youtube.live";
    snippet.descriptionProperty = self.roomModel.detail;
    snippet.title = self.roomModel.title;
    //2006-11-17T15:10:46Z   2024-01-30T00:00:00.000Z
    snippet.scheduledStartTime = [GTLRDateTime dateTimeWithDate:[NSDate date]];
    //snippet.scheduledEndTime = [GTLRDateTime dateTimeWithDate:[NSDate dateWithTimeIntervalSinceNow:7200]];
    // contentDetail
    
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
    GTLRServiceTicket *updateTicket = [self.youTubeService executeQuery:updateQuery
                                                         completionHandler:^(GTLRServiceTicket *callbackTicket,
                                                                             GTLRYouTube_LiveBroadcast *broadcast,
                                                                             NSError *callbackError) {
                                                             [serviceTicketArray removeObject:callbackTicket];
                                                             
                                                             // Callback
                                                             if (callbackError == nil) {
                                                                 self.youtubeLiveBroadcast = broadcast;
                                                                 
                                                                 [self logMessage:@"Got callbackTicket: %@ live broadcast %@", callbackTicket,broadcast];
                                                                 
                                                             } else {
                                                                 [self logMessage:@"service error: %@", callbackError];
                                                             }
                                                             
                                                         }];
    [serviceTicketArray addObject:updateTicket];
    
}

- (void) getLiveBroadcastwith:(NSString *) identifire CompleteHandle:(void(^)(NSArray<GTLRYouTube_LiveBroadcast *> *broadcastList)) completeHandle
{
    GTLRYouTubeQuery_LiveBroadcastsList *broadQuery = [GTLRYouTubeQuery_LiveBroadcastsList queryWithPart:@"id,snippet,contentDetails,status,statistics"];
    broadQuery.identifier = identifire;
    GTLRServiceTicket *broadlistTicket = [self.youTubeService executeQuery:broadQuery
                                                         completionHandler:^(GTLRServiceTicket *callbackTicket,
                                                                             GTLRYouTube_LiveBroadcastListResponse *broadcast,
                                                                             NSError *callbackError) {
                                                             [serviceTicketArray removeObject:callbackTicket];
                                                             
                                                             // Callback
                                                             if (callbackError == nil) {
                                                                 
                                                                 [self logMessage:@"Got callbackTicket: %@ live broadcast list %@", callbackTicket,broadcast.items];
                                                                 for (GTLRYouTube_LiveBroadcast *liveBroadcast in broadcast.items) {
                                                                     if ([liveBroadcast.identifier isEqualToString:self.youtubeLiveBroadcast.identifier]) {
                                                                         [self logMessage:@"live broacast status %@",liveBroadcast.status.lifeCycleStatus];
                                                                         break;
                                                                     }
                                                                 }
                                                                 if (completeHandle) {
                                                                     completeHandle(broadcast.items);
                                                                 }
                                                             } else {
                                                                 [self logMessage:@"service error: %@", callbackError];
                                                             }
                                                             
                                                         }];
    [serviceTicketArray addObject:broadlistTicket];
}

- (void) getLiveBroadcastwithType:(NSString *) type CompleteHandle:(void(^)(NSArray<GTLRYouTube_LiveBroadcast *> *broadcastList, NSError *callbackError)) completeHandle
{
    GTLRYouTubeQuery_LiveBroadcastsList *broadQuery = [GTLRYouTubeQuery_LiveBroadcastsList queryWithPart:@"id,snippet,contentDetails,status,statistics"];
    broadQuery.broadcastType = type;
    broadQuery.mine = YES;
    GTLRServiceTicket *broadlistTicket = [self.youTubeService executeQuery:broadQuery
                                                         completionHandler:^(GTLRServiceTicket *callbackTicket,
                                                                             GTLRYouTube_LiveBroadcastListResponse *broadcast,
                                                                             NSError *callbackError) {
                                                             [serviceTicketArray removeObject:callbackTicket];
                                                             
                                                             // Callback
                                                             if (callbackError == nil) {
                                                                 
                                                                 [self logMessage:@"Got callbackTicket: %@ live broadcast list %@", callbackTicket,broadcast.items];
                                                                 for (GTLRYouTube_LiveBroadcast *liveBroadcast in broadcast.items) {
                                                                     if ([liveBroadcast.identifier isEqualToString:self.youtubeLiveBroadcast.identifier]) {
                                                                         [self logMessage:@"live broacast status %@",liveBroadcast.status.lifeCycleStatus];
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
                                                                 [self logMessage:@"service error: %@", callbackError];
                                                             }
                                                             
                                                         }];
    [serviceTicketArray addObject:broadlistTicket];
}

- (void) getLiveChatMessageWithId:(NSString *)identify pageToken:(NSString *) token completeHandle:(void(^)(GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError *error)) completeHandle
{
    GTLRYouTubeQuery_LiveChatMessagesList * listQuery = [GTLRYouTubeQuery_LiveChatMessagesList queryWithLiveChatId:identify part:@"id,snippet,authorDetails"];
    listQuery.maxResults = 200;
    if (token.length > 0) {
        listQuery.pageToken = token;
    } else {
        listQuery.pageToken = nil;
    }
    GTLRServiceTicket *listTicket = [self.youTubeService executeQuery:listQuery completionHandler:^(GTLRServiceTicket * _Nonnull callbackTicket, GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError * _Nullable callbackError) {
        [serviceTicketArray removeObject:callbackTicket];

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
            liveChats.nextPageToken = currentPage;
            liveChats.pollingIntervalMillis =@(kDefaultPollingIntervalMillis);
        }
        
        if (liveChats.items.count == listQuery.maxResults) {
            currentPage = liveChats.nextPageToken;
            if ([liveChatPages containsObject:currentPage] == NO) {
                [liveChatPages addObject:currentPage];
            }
        }
        
        if (completeHandle) {
            completeHandle(liveChats, callbackError);
        }
        
    }];
    [serviceTicketArray addObject:listTicket];
}

- (void) deleteLiveChatMessageWithId:(NSString *)identify completeHandle:(void(^)(NSArray<GTLRYouTube_LiveChatMessage *> *liveChat)) completeHandle
{
    GTLRYouTubeQuery_LiveChatMessagesDelete * deleteQuery = [GTLRYouTubeQuery_LiveChatMessagesDelete queryWithIdentifier:identify];
    GTLRServiceTicket *listTicket = [self.youTubeService executeQuery:deleteQuery completionHandler:^(GTLRServiceTicket * _Nonnull callbackTicket,  id object, NSError * _Nullable callbackError) {
        [liveChatPages removeAllObjects];
        [liveChatPages addObject:@""];
        
        pollingIntervalMillis = kDefaultPollingIntervalMillis; // 暂时是30秒
        
        if (callbackError) {
            GTLRErrorObject *error = callbackError.userInfo[@"GTLRStructuredError"];
            PLog(@"delete live chat messages error : %@, code %@", error.message, error.code);
        }
    }];
    [serviceTicketArray addObject:listTicket];
}

- (void) getLiveStreamWith:(NSString *) identifire CompleteHandle:(void(^)(NSArray<GTLRYouTube_LiveStream *> *streamList, NSError *error)) completeHandle
{
    GTLRYouTubeQuery_LiveStreamsList *streamListQuery = [GTLRYouTubeQuery_LiveStreamsList queryWithPart:@"id,snippet,cdn,status"];
    streamListQuery.identifier = identifire;
    if (identifire.length <= 0) {
        streamListQuery.mine = YES;
    }
    GTLRServiceTicket *streamlistTicket = [self.youTubeService executeQuery:streamListQuery
                                                          completionHandler:^(GTLRServiceTicket *callbackTicket,
                                                                              GTLRYouTube_LiveStreamListResponse *liveStream,
                                                                              NSError *callbackError) {
                                                              [serviceTicketArray removeObject:callbackTicket];
                                                              // Callback
                                                              if (callbackError == nil) {
                                                                  [self logMessage:@"Got callbackTicket: %@ live stream list %@", callbackTicket,liveStream.items];
                                                                  if (completeHandle) {
                                                                      completeHandle(liveStream.items, nil);
                                                                  }
                                                              } else {
                                                                  if (completeHandle) {
                                                                      completeHandle(nil, callbackError);
                                                                  }
                                                                  [self logMessage:@"service error: %@", callbackError];
                                                              }
                                                              
                                                          }];
    
    [serviceTicketArray addObject:streamlistTicket];
    
}

- (void) liveBroadcastTransition:(GTLRYouTube_LiveBroadcast *) liveBroadcast status:(NSString *)broadcastStatus
{
    GTLRYouTubeQuery_LiveBroadcastsTransition *transitionQuery = [GTLRYouTubeQuery_LiveBroadcastsTransition queryWithBroadcastStatus:broadcastStatus identifier:liveBroadcast.identifier part:@"id,snippet,contentDetails,status"];
    GTLRServiceTicket *transitionTicket = [self.youTubeService executeQuery:transitionQuery
                                                          completionHandler:^(GTLRServiceTicket *callbackTicket,
                                                                              GTLRYouTube_LiveBroadcast *liveBroadcast,
                                                                              NSError *callbackError) {
                                                              // Callback
                                                              if (callbackError == nil) {
                                                                 
                                                                  [self logMessage:@"Got callbackTicket: %@ live stream list %@", callbackTicket,liveBroadcast];
                                                              } else {
                                                                  [self logMessage:@"service error: %@", callbackError];
                                                              }
                                                              
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
}//*/

#pragma mark -- public methods

- (void) startLiveBrocastWith:(CPYoutubeBrocastRoomModel *) room CompleteHandle:(void(^)(NSString * broadcastURL, NSError *error)) completeHandle
{
    self.roomModel  = room;
    
    @synchronized (self) {
        createLive = YES;
    }
    
    for (GTLRServiceTicket *ticket in serviceTicketArray) {
        [ticket cancelTicket];
    }
    
    [[CPPlatformAuthManager shareManager] doAppAuthPlatformType:CPPlatformAuthType_YouTube presentController:self.presentVC thenHandler:^(CPPlatformAuthManager *manager, NSError *error) {
        
        if (error) {
            completeHandle ? completeHandle(nil, error) : nil;
            return;
        }
        
        // 成功
        [self setGtmAuthorization:manager.youtubeAuthorization];
        
        @synchronized (self) {
            createLive = NO;
        }
        
        stoped = NO;
        [self getLiveBroadcastwithType:kGTLRYouTubeBroadcastTypePersistent CompleteHandle:^(NSArray<GTLRYouTube_LiveBroadcast *> *broadcastList, NSError *error) {
            if (error) {
                completeHandle ? completeHandle(nil, error) : nil;
                return;
            }
            if (broadcastList.count == 0) {
                completeHandle ? completeHandle(nil, error) : nil;
                return;
            }
            GTLRYouTube_LiveBroadcast *broadcast = broadcastList[0];
            self.youtubeLiveBroadcast = broadcast;
            [self updateBroadcastInfo];
            //[self deleteLiveChatMessageWithId:self.youtubeLiveBroadcast.snippet.liveChatId completeHandle:nil];
            
            //[self loadLiveBroadcastNowStatus];
            
            NSString *streamId = broadcast.contentDetails.boundStreamId;
            [self getLiveStreamWith:streamId CompleteHandle:^(NSArray<GTLRYouTube_LiveStream *> *streamList, NSError *error) {
                if (error) {
                    completeHandle ? completeHandle(nil, error) : nil;
                    return;
                }
                if (stoped) {
                    return ;
                }
                if (streamList.count == 0) {
                    completeHandle ? completeHandle(nil, error) : nil;
                    return;
                }
                
                GTLRYouTube_LiveStream *stream = streamList[0];
                self.youtubeLiveStream = stream;
                
                if (completeHandle) {
                    NSString *streamURL = [NSString stringWithFormat:@"%@/%@",stream.cdn.ingestionInfo.ingestionAddress,stream.cdn.ingestionInfo.streamName];
                    completeHandle(streamURL, nil);
                }
            }];
        }];
        
    }];
}

- (void) stopLiveBroadcast
{
    /*
     @synchronized (self) {
     liveStatus = GCYoutubeLiveStreamLiveStatusUnknown;
     }
     _requestingLS = NO;
     
     if (launchTimer) {
     [launchTimer invalidate];
     launchTimer = nil;
     }
     
     [self stopAutoLoadLiveChatMessages]; //*/
    
    stoped = YES;
    
    [self stopBroadcastConnection];
    
    [self liveBroadcastTransition:self.youtubeLiveBroadcast status:kGTLRYouTubeBroadcastStatusComplete];
    self.youtubeLiveStream = nil;
    self.youtubeLiveBroadcast = nil;
}

- (void)stopBroadcastConnection {
    for (GTLRServiceTicket *ticket in serviceTicketArray) {
        [ticket cancelTicket];
    }
    [serviceTicketArray removeAllObjects];
}

- (void)fetchLiveBroadcastStatusWithCompleteHandler:(void (^)(NSString *))handler {
    if (self.youtubeLiveBroadcast.identifier.length <= 0) {
        return;
    }
    
    [self getLiveBroadcastwith:self.youtubeLiveBroadcast.identifier CompleteHandle:^(NSArray<GTLRYouTube_LiveBroadcast *> *broadcastList) {
        if (stoped) {
            return ;
        }
        if (broadcastList.count == 0) {
            return;
        }
        GTLRYouTube_LiveBroadcast *broadcast = broadcastList[0];
        self.youtubeLiveBroadcast = broadcast;
        
        handler ? handler(broadcast.status.lifeCycleStatus) : nil;
        
    }];
}

- (void)fetchLiveMessageWithCompleteHandler:(void(^)(GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError *error))handler {
    
    if (pollingIntervalMillis > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pollingIntervalMillis / 1000.0) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self fetchLiveMessageWithCompleteHandler:handler];
        });
        pollingIntervalMillis = 0;
        return;
    }
    
    NSString *identifier = self.youtubeLiveBroadcast.snippet.liveChatId;
    [self getLiveChatMessageWithId:identifier pageToken:currentPage completeHandle:^(GTLRYouTube_LiveChatMessageListResponse *liveChats, NSError *error) {
        
        handler ? handler(liveChats, error) : nil;
        
    }];
}

/*
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
- (GTLRServiceTicket *)createYouTubeVideoUploadTicketWithParam:(NSDictionary *)param videoUrl:(NSURL *)videoUrl uploadProgressHandler:(GTLRServiceUploadProgressBlock)uploadProgressHandler completeHandler:(GTLRServiceCompletionHandler)completeHandler {
    
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
    
    return [self createYouTubeVideoUploadTicketWithVideo:video uploadParam:uploadParam uploadProgressHandler:uploadProgressHandler completeHandler:completeHandler];
}

- (GTLRServiceTicket *)createYouTubeVideoUploadTicketWithVideo:(GTLRYouTube_Video *)video uploadParam:(GTLRUploadParameters *)uploadParam uploadProgressHandler:(GTLRServiceUploadProgressBlock)uploadProgressHandler completeHandler:(GTLRServiceCompletionHandler)completeHandler {
    
    __block GTLRServiceTicket *ticket;
    
    // 上传和直播都是使用同一个service
    __weak typeof(self) weakSelf = self;
    [[CPPlatformAuthManager shareManager] doAppAuthPlatformType:CPPlatformAuthType_YouTube presentController:self.presentVC thenHandler:^(CPPlatformAuthManager *manager, NSError *error) {
        if (error) {
            completeHandler ? completeHandler(nil, nil, error) : nil;
            return;
        }
        
        // 成功
        [weakSelf setGtmAuthorization:manager.youtubeAuthorization];
        
        NSString *userEmail = [[CustomUserDefault standardUserDefaults] objectForKey:GCYouTubeUserAccount];
        if (userEmail) {
            
            GTLRYouTubeQuery_VideosInsert *query = [GTLRYouTubeQuery_VideosInsert queryWithObject:video part:@"snippet,status,id,contentDetails" uploadParameters:uploadParam];
            query.additionalURLQueryParameters = @{@"uploadType" : @"resumable"};
            query.executionParameters.uploadProgressBlock = uploadProgressHandler;
            ticket = [weakSelf.youTubeService executeQuery:query completionHandler:completeHandler];
            
        } else {
            
            __strong typeof(weakSelf) strongWeakSelf = weakSelf;
            [weakSelf getUserInfoWithCompleteHandler:^(NSError *error) {
                GTLRYouTubeQuery_VideosInsert *query = [GTLRYouTubeQuery_VideosInsert queryWithObject:video part:@"snippet,status,id,contentDetails" uploadParameters:uploadParam];
                query.additionalURLQueryParameters = @{@"uploadType" : @"resumable"};
                query.executionParameters.uploadProgressBlock = uploadProgressHandler;
                ticket = [strongWeakSelf.youTubeService executeQuery:query completionHandler:completeHandler];
            }];
            
        }
        
    }];
    return ticket;
}

- (void)removeYouTubeVideoWithUserAccount:(NSString *)userAccount videoId:(NSString *)videoId completeHandler:(GTLRServiceCompletionHandler)completeHandler {
    NSString *account = [[CustomUserDefault standardUserDefaults] objectForKey:GCYouTubeUserAccount];
    if ([account isEqualToString:userAccount]) {
        GTLRYouTubeQuery_VideosDelete *query = [GTLRYouTubeQuery_VideosDelete queryWithIdentifier:videoId];
        [self.youTubeService executeQuery:query completionHandler:completeHandler];
    } else {
        completeHandler ? completeHandler(nil,nil,[NSError errorWithDomain:@"" code:-1000 userInfo:@{NSLocalizedFailureReasonErrorKey : @"userAccount与当前账号不符合"}]) : nil;
    }
}

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

// Get a service object with the current username/password.
//
// A "service" object handles networking tasks.  Service objects
// contain user authentication information as well as networking
// state information such as cookies set by the server in response
// to queries.

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

- (void)setGtmAuthorization:(GTMAppAuthFetcherAuthorization*)authorization {
    if ([self.youTubeService.authorizer isEqual:authorization]) {
        return;
    }
    self.youTubeService.authorizer = authorization;
}

- (void) clearAppAuth
{
    [self setGtmAuthorization:nil];
    self.userInfo = nil;
    
    if ([self.delegate respondsToSelector:@selector(appAuthDidRemove)]) {
        [self.delegate appAuthDidRemove];
    }
    
}

- (void)getUserInfoWithCompleteHandler:(void (^)(NSError *))completeHandler {
    
    [[CPPlatformAuthManager shareManager] fetchUserInfoWithPlatformType:CPPlatformAuthType_YouTube presentController:self.presentVC completeHandler:^(NSDictionary *info, NSError *error) {
        
        if (!error) {
            self.userInfo = info;
            
            if ([self.delegate respondsToSelector:@selector(updateUserInfo)]) {
                [self.delegate updateUserInfo];
            }
        }
        
        completeHandler ? completeHandler(error) : nil;
        
    }];
    
}

//@brief Logs a message to stdout and the textfield.
//@param format The format string and arguments.
- (void)logMessage:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) {
    //gets message as string
    va_list argp;
    va_start(argp, format);
    NSString *log = [[NSString alloc] initWithFormat:format arguments:argp];
    va_end(argp);
    
    //appends to output log
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"hh:mm:ss";
    NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
    
    PLog(@"%@",[NSString stringWithFormat:@"%@: %@",
                dateString,
                log]);
}


@end

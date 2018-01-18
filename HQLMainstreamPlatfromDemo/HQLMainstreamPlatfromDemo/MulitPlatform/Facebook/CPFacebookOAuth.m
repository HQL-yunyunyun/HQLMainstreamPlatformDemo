//
//  CPFacebookOAuth.m
//  GoCreate3.0
//
//  Created by 何启亮 on 2017/11/14.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import "CPFacebookOAuth.h"
#import <FBSDKLoginKit/FBSDKLoginKit.h>

@interface CPFacebookOAuth ()

@property (strong, nonatomic) FBSDKAccessToken *authorization;
@property (strong, nonatomic) FBSDKLoginManager *loginManager;

@property (copy, nonatomic) NSString *searchGroupAfterKey;
@property (copy, nonatomic) NSString *searchGroupBeforeKey;
@property (copy, nonatomic) NSString *currentSearchGroupKeyWord;

@property (copy, nonatomic) NSString *currentLiveVideo_id;
@property (copy, nonatomic) NSString *last_comment_time;
@property (copy, nonatomic) NSString *liveCommentsAfterKey;

//@property (strong, nonatomic) NSTimer *timer;
//@property (strong, nonatomic) NSTimer *statusTimer;

@property (strong, nonatomic) FBSDKGraphRequestConnection *currentBroadcastStatusConnection;

@property (strong, nonatomic) NSMutableArray *broadcastConnectionArray;

@end

@implementation CPFacebookOAuth

- (instancetype)initWithAuthorization:(FBSDKAccessToken *)authorization {
    if (self = [super init]) {
        self.authorization = authorization;
        
        [FBSDKProfile enableUpdatesOnAccessTokenChange:YES];
    }
    return self;
}

- (void)dealloc {
    PLog(@"dealloc ---> %@", NSStringFromClass([self class]));
}

#pragma mark - method

// 普通权限
- (void)doFacebookCommonAuthWithPresentController:(UIViewController *)controller thenHandler:(void (^)(FBSDKAccessToken *, NSError *))handler {
    
    __weak typeof(self) _self = self;
    
    // 查找需要的权限
    //@"user_managed_groups",
    NSArray *needAuthArray = [self checkPermissionWithWantPermissions:[self commentPermissions]];
    
    if (needAuthArray.count > 0) {
        [self.loginManager logInWithReadPermissions:needAuthArray fromViewController:controller handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
            
            if (error) {
                handler ? handler(nil, error) : nil;
                return;
            }
            
            if (result.isCancelled) {
                handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"fecth facebook authorization request did cancel" , NSLocalizedDescriptionKey : @"fecth facebook authorization request did cancel"}]) : nil;
                return;
            }
            
            // 因为email权限是必须的，所以检查用户是否已经授权了
            if ([_self checkPermissionWithWantPermissions:[_self commentPermissions]].count > 0) {
                handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"user did not auth" , NSLocalizedDescriptionKey : @"user did not auth"}]) : nil;
                return;
            }
            
            handler ? handler(result.token, nil) : nil;
            
        }];
    } else {
        handler ? handler([FBSDKAccessToken currentAccessToken], nil) : nil;
    }
}

// 直播权限
- (void)doFacebookBroadcastAuthWithPresentController:(UIViewController *)controller thenHandler:(void (^)(FBSDKAccessToken *, NSError *))handler {
    // 查找权限
    __weak typeof(self) _self = self;
    
    NSArray *needAuthArray = [self checkPermissionWithWantPermissions:[self broadcastPermissions]];
    if (needAuthArray.count > 0) {
        
        [self.loginManager logInWithPublishPermissions:needAuthArray fromViewController:controller handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
            
            if (error) {
                handler ? handler(nil, error) : nil;
                return;
            }
            
            if (result.isCancelled) {
                handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"fecth facebook authorization request did cancel" , NSLocalizedDescriptionKey : @"fecth facebook authorization request did cancel"}]) : nil;
                return;
            }
            
            // 判断授权
            if ([_self checkPermissionWithWantPermissions:[_self broadcastPermissions]].count > 0) {
                handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"user did not auth" , NSLocalizedDescriptionKey : @"user did not auth"}]) : nil;
                return;
            }
            
            handler ? handler(result.token, nil) : nil;
        }];
        
    } else {
        handler ? handler([FBSDKAccessToken currentAccessToken], nil) : nil;
    }
//    else {
//        //@"user_managed_groups",
//        needAuthArray = [self checkPermissionWithWantPermissions:@[@"public_profile", @"email", @"user_friends" , @"pages_show_list"]];
//        if (needAuthArray.count > 0) {
//            [self doFacebookCommonAuthWithPresentController:controller thenHandler:^(FBSDKAccessToken *authorization, NSError *error) {
//                if (error) {
//                    handler ? handler(nil, error) : nil;
//                    return;
//                }
//
//                handler ? handler(authorization, nil) : nil;
//            }];
//        } else {
//            handler ? handler([FBSDKAccessToken currentAccessToken], nil) : nil;
//        }
//    }
    
    
    //@"user_managed_groups",
//    NSArray *needAuthArray = [self checkPermissionWithWantPermissions:@[@"public_profile", @"email", @"user_friends" , ]];
//    if (needAuthArray.count > 0) {
//        [self doFacebookCommonAuthWithPresentController:controller thenHandler:^(FBSDKAccessToken *authorization, NSError *error) {
//            if (error) {
//                handler ? handler(nil, error) : nil;
//                return;
//            }
//
//            [_self doFacebookBroadcastAuthWithPresentController:controller thenHandler:handler];
//        }];
//    } else {
//        //@"manage_pages", @"publish_pages",
//        needAuthArray = [self checkPermissionWithWantPermissions:@[@"publish_actions", ]];
//
//        if (needAuthArray.count > 0) {
//
//            [self.loginManager logInWithPublishPermissions:needAuthArray fromViewController:controller handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
//
//                if (error) {
//                    handler ? handler(nil, error) : nil;
//                    return;
//                }
//
//                if (result.isCancelled) {
//                    handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"fecth facebook authorization request did cancel" , NSLocalizedDescriptionKey : @"fecth facebook authorization request did cancel"}]) : nil;
//                    return;
//                }
//
//                handler ? handler(result.token, nil) : nil;
//
//            }];
//
//        } else {
//            handler ? handler([FBSDKAccessToken currentAccessToken], nil) : nil;
//        }
//
//    }
}

- (void)doFacebookGroupAuthWithPresentController:(UIViewController *)controller thenHandler:(void (^)(FBSDKAccessToken *, NSError *))handler {
    __weak typeof(self) _self = self;
    
    NSArray *needAuthArray = [self checkPermissionWithWantPermissions:[self groupPermissions]];
    if (needAuthArray.count > 0) {
        
        [self.loginManager logInWithReadPermissions:needAuthArray fromViewController:controller handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
            if (error) {
                handler ? handler(nil, error) : nil;
                return;
            }
            
            if (result.isCancelled) {
                handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"fecth facebook authorization request did cancel" , NSLocalizedDescriptionKey : @"fecth facebook authorization request did cancel"}]) : nil;
                return;
            }
            
            // 判断授权
            if ([_self checkPermissionWithWantPermissions:[_self broadcastPermissions]].count > 0) {
                handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"user did not auth" , NSLocalizedDescriptionKey : @"user did not auth"}]) : nil;
                return;
            }
            
            handler ? handler(result.token, nil) : nil;
            
        }];
        
    } else {
        handler ? handler([FBSDKAccessToken currentAccessToken], nil) : nil;
    }
}

/*
- (void)doFacebookAuthWithPresentController:(UIViewController *)controller thenHandler:(void (^)(FBSDKAccessToken *, NSError *))handler {
    
    FBSDKAccessToken *token = [FBSDKAccessToken currentAccessToken];
    if (token) {
        handler ? handler(token, nil) : nil;
        return;
    }
    
    if (!controller) {
        handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"present controller can not be nil", NSLocalizedDescriptionKey : @"present controller can not be nil"}]) : nil;
        return;
    }
    
    __weak typeof(self) _self = self;
    
    [self.loginManager logInWithPublishPermissions:@[@"publish_actions", @"manage_pages", @"publish_pages",] fromViewController:controller handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
       
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
        
        if (result.isCancelled) {
            handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"fecth facebook authorization request did cancel" , NSLocalizedDescriptionKey : @"fecth facebook authorization request did cancel"}]) : nil;
            return;
        }
        
        // 检查所需要的权限用户是否有授权 --- 不需要这一步，就算没有授权也没关系
        
        // 申请权限
        [_self.loginManager logInWithReadPermissions:@[@"public_profile", @"email", @"user_friends", @"user_managed_groups",] fromViewController:controller handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
            
            if (error) {
                handler ? handler(nil, error) : nil;
                return;
            }
            
            if (result.isCancelled) {
                handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"fecth facebook authorization request did cancel" , NSLocalizedDescriptionKey : @"fecth facebook authorization request did cancel"}]) : nil;
                return;
            }
            
            handler ? handler(result.token, nil) : nil;
            
        }];
//        handler ? handler(result.token, nil) : nil;
        
    }];
}
//*/

- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void (^)(FBSDKProfile *, NSError *))handler {
    
    __weak typeof(self) _self = self;
    // userInfo 只要一个 profile就OK了
    if ([self checkPermissionWithWantPermissions:@[@"public_profile"]].count > 0) {
        [self doFacebookCommonAuthWithPresentController:controller thenHandler:^(FBSDKAccessToken *authorization, NSError *error) {
            if (error) {
                handler ? handler(nil, error) : nil;
                return;
            }
            
            // 刚获取完token 马上就获取profile 就会出现一种没有获取到profile的情况 --- 所以在这里做延迟获取的处理
            [_self fetchUserInfoWithPresentController:controller completeHandler:handler];
        }];
        return;
    }
    
    FBSDKProfile *profile = [FBSDKProfile currentProfile];
    
    if (profile) {
        handler ? handler(profile, nil) : nil;
    } else {
        [FBSDKProfile loadCurrentProfileWithCompletion:^(FBSDKProfile *profile, NSError *error) {
            
            if (!profile) {
                handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"fetch user info error", NSLocalizedDescriptionKey : @"fetch user info error"}]) : nil;
                return;
            }
            handler ? handler(profile, nil) : nil;
            
        }];
    }
    
}

- (void)fetchFacebookBroadcastURLWithParam:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void (^)(NSString *, NSError *))handler {
    // 判断param
    FacebookBoradcastType type = [param[FacebookBroadcastType_string] integerValue];
    NSString *broadcast_id = param[FacebookBroadcast_id];
    NSString *broadcast_description = param[FacebookBroadcast_description];
    
    if ([broadcast_id isEqualToString:@""] || !broadcast_id) {
        handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"broadcast id can not be nil", NSLocalizedDescriptionKey : @"broadcast id can not be nil"}]) : nil;
        return;
    }
    
    __weak typeof(self) _self = self;
    if (![self isBroadcastAuthorization]) {
        [self doFacebookBroadcastAuthWithPresentController:controller thenHandler:^(FBSDKAccessToken *authorization, NSError *error) {
            if (error) {
                handler ? handler(nil, error) : nil;
                return;
            }
            [_self fetchFacebookBroadcastURLWithParam:param presentController:controller completeHandler:handler];
        }];
        return;
    }
    
    // 获取rtmp url
    NSDictionary *privacy = nil;
    if (type == FacebookBroadcastType_SELF) {
        privacy = @{@"privacy" : @"{'value':'SELF'}"};
    } else if (type == FacebookBroadcastType_PUBLISH) {
        privacy = @{@"privacy" : @"{'value':'EVERYONE'}"};
    }
    NSString *url = [NSString stringWithFormat:@"/%@/%@", broadcast_id, @"live_videos"];
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc] initWithGraphPath:url parameters:privacy HTTPMethod:@"POST"];
    
    FBSDKGraphRequestConnection *con = [request startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        
        [_self.broadcastConnectionArray removeObject:connection];
        
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
        
        NSDictionary *dict = (NSDictionary *)result;
        _self.currentLiveVideo_id = dict[@"id"];
        NSString *stream_url = dict[@"stream_url"];
        
        // 更新说明
        if (broadcast_description && ![broadcast_description isEqualToString:@""]) {
            [_self updateBroadcastDescription:broadcast_description liveVideoID:_self.currentLiveVideo_id completeHandler:^(NSError *error) {
                if (!error) {
                    PLog(@"update broadcast description success");
                } else {
                    PLog(@"update broadcast description failed");
                }
            }];
        }
        
        handler ? handler(stream_url, nil) : nil;
        
    }];
    [self.broadcastConnectionArray addObject:con];
}

- (void)updateBroadcastDescription:(NSString *)string completeHandler:(void (^)(NSError *))handler {
    [self updateBroadcastDescription:string liveVideoID:self.currentLiveVideo_id completeHandler:handler];
}

-(void)fetchBroadcastStatusWithCompleteHandler:(void(^)(FacebookBroadcastStatus, NSError *))handler {
    [self.currentBroadcastStatusConnection cancel];
    
    self.currentBroadcastStatusConnection = [self fetchBroadcastStatusWithLiveVideoID:self.currentLiveVideo_id completeHandler:^(NSDictionary *dict, NSError *error) {
        if (error) {
            handler ? handler(FacebookBroadcastStatus_off_line, error) : nil;
            return;
        }
        
        NSString *statusString = dict[@"status"];
        FacebookBroadcastStatus status = FacebookBroadcastStatus_off_line;
        if ([statusString isEqualToString:@"UNPUBLISHED"]) {
            status = FacebookBroadcastStatus_off_line;
        } else if ([statusString isEqualToString:@"LIVE_NOW"]) {
            status = FacebookBroadcastStatus_live;
        } else if ([statusString isEqualToString:@"LIVE"]) {
            status = FacebookBroadcastStatus_live;
        } else if ([statusString isEqualToString:@"LIVE_STOPPED"]) {
            status = FacebookBroadcastStatus_live_stopped;
        }
        PLog(@"facebook broadcast status %@", statusString);
        handler ? handler(status, nil) : nil;
        
    }];
}

/*
data =     (
            {
                "created_time" = "2017-11-22T06:42:32+0000";
                from =             {
                    id = 119735858803992;
                    name = "Betty Albcjbgceidbf Martinazzisen";
                };
                id = "119981852112726_119983892112522";
                message = pinglun;
            }
            );
paging =     {
    cursors =         {
        after = WTI5dGJXVnVkRjlqZAFhKemIzSTZANVEU1T1Rnek9Ea3lNVEV5TlRJeU9qRTFNVEV6TXpJNU5UTT0ZD;
        before = WTI5dGJXVnVkRjlqZAFhKemIzSTZANVEU1T1Rnek9Ea3lNVEV5TlRJeU9qRTFNVEV6TXpJNU5UTT0ZD;
    };
};*/

- (void)fetchBroadcastCommentsWithCompleteHandler:(void (^)(NSArray *, NSError *))handler {
    
    if (!self.currentLiveVideo_id || [self.currentLiveVideo_id isEqualToString:@""]) {
        return;
    }
    
    __weak typeof(self) _self = self;
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                           @"fields" : @"created_time,from,message,id",
                                                                           @"limit":@(kFacebookMaximumLimitComments),
                                                                           @"order":@"chronological",
                                                                           }];
    // 当需要加载下一页的时候,就会加载下一页
    if (self.liveCommentsAfterKey.length > 0) {
        [dict setObject:self.liveCommentsAfterKey forKey:@"after"];
    }
    // 如果有最后时间
    if (self.last_comment_time.length > 0) {
        [dict setObject:self.last_comment_time forKey:@"since"];
    }
    
    FBSDKGraphRequestConnection *con = [[[FBSDKGraphRequest alloc]
                                                     initWithGraphPath:[NSString stringWithFormat:@"/%@/%@", self.currentLiveVideo_id, @"comments"]
                                                     parameters:dict
                                                     HTTPMethod:@"GET"]
     startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
         PLog(@"facebook live comments result %@, error : %@", result, error);
         
         [_self.broadcastConnectionArray removeObject:connection];
         
         if (error) {
             handler ? handler(nil, error) : nil;
             return;
         }
         
         NSDictionary *dict = (NSDictionary *)result;
         NSArray *data = dict[@"data"];
         
         NSMutableArray *comments = [NSMutableArray array];
         for (NSDictionary *comment in data) {
             NSDictionary *from = comment[@"from"];
             NSDictionary *target = @{
                                      @"name" : from[@"name"],
                                      @"message" : comment[@"message"],
                                      @"message_id" : comment[@"id"],
                                      };
             _self.last_comment_time = comment[@"created_time"];
             [comments addObject:target];
         }
         
         NSDictionary *paging = dict[@"paging"];
         NSString *next = paging[@"next"]; // 最要有显示next 则表示需要加载分页
         if (next.length > 0) {
             NSDictionary *cursors = paging[@"cursors"];
             _self.liveCommentsAfterKey = cursors[@"after"];
         }
         
         handler ? handler(comments, nil) : nil;
         
         /*
         if (data.count >= kFacebookMaximumLimitComments) {
         }//*/
    }];
    [self.broadcastConnectionArray addObject:con];
    /*
    [self getBroadcastInfoWithLiveVideoID:self.currentLiveVideo_id param:@{ @"fields": @"comments{comment_count,created_time}",@"limit":@1000} completeHandler:^(NSDictionary *dict, NSError *error) {
       
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
    }];//*/
}

- (void)fetchBroadcastInfoWithCompleteHandler:(void (^)(NSDictionary *, NSError *))handler {
    [self getBroadcastInfoWithLiveVideoID:self.currentLiveVideo_id param:@{ @"fields": @"live_views,likes,status",} completeHandler:^(NSDictionary *dict, NSError *error) {
        
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
        
        handler ? handler(dict, nil) : nil;
        
    }];
}

#pragma mark - search

- (void)searchGroupResultNextPageWithPresentController:(UIViewController *)controller completeHandler:(void (^)(NSArray<NSDictionary *> *, NSError *))handler {
    if (!self.searchGroupAfterKey || [self.searchGroupAfterKey isEqualToString:@""]) {
        handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"after key can not be nil", NSLocalizedDescriptionKey : @"after key can not be nil"}]) : nil;
        return;
    }
    
    __weak typeof(self) _self = self;
    
    NSDictionary *param = @{@"fields" : @"cover,icon,name,id", @"after" : self.searchGroupAfterKey};
    [self searchKeyWordWithType:FacebookSearchType_group keyWord:self.currentSearchGroupKeyWord param:param presentController:controller completeHandler:^(NSDictionary *dict, NSError *error) {
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
        
        NSArray *data = dict[@"data"];
        NSDictionary *paging = dict[@"paging"];
        NSDictionary *cursors = paging[@"cursors"];
        
        _self.searchGroupAfterKey = cursors[@"after"];
        _self.searchGroupBeforeKey = cursors[@"before"];
        
        handler ? handler(data, nil) : nil;
        
    }];
}

- (void)searchGroupResultBeforePageWithPresentController:(UIViewController *)controller completeHandler:(void (^)(NSArray<NSDictionary *> *, NSError *))handler {
    if (!self.searchGroupBeforeKey || [self.searchGroupBeforeKey isEqualToString:@""]) {
        handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"before key can not be nil", NSLocalizedDescriptionKey : @"before key can not be nil"}]) : nil;
        return;
    }
    
    __weak typeof(self) _self = self;
    
    NSDictionary *param = @{@"fields" : @"cover,icon,name,id", @"before" : self.searchGroupBeforeKey};
    [self searchKeyWordWithType:FacebookSearchType_group keyWord:self.currentSearchGroupKeyWord param:param presentController:controller completeHandler:^(NSDictionary *dict, NSError *error) {
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
        
        NSArray *data = dict[@"data"];
        NSDictionary *paging = dict[@"paging"];
        NSDictionary *cursors = paging[@"cursors"];
        
        _self.searchGroupAfterKey = cursors[@"after"];
        _self.searchGroupBeforeKey = cursors[@"before"];
        
        handler ? handler(data, nil) : nil;
        
    }];
}

- (void)searchGroupWithKeyWord:(NSString *)keyWord presentController:(UIViewController *)controller completeHandler:(void(^)(NSArray<NSDictionary *> *, NSError *))handler {
    NSDictionary *param = @{@"fields" : @"cover,icon,name,id"};
    
    __weak typeof(self) _self = self;
    
    self.currentSearchGroupKeyWord = keyWord;
    
    [self searchKeyWordWithType:FacebookSearchType_group keyWord:keyWord param:param presentController:controller completeHandler:^(NSDictionary *dict, NSError *error) {
        
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
        
        NSArray *data = dict[@"data"];
        NSDictionary *paging = dict[@"paging"];
        NSDictionary *cursors = paging[@"cursors"];
        
        _self.searchGroupAfterKey = cursors[@"after"];
        _self.searchGroupBeforeKey = cursors[@"before"];
        
        handler ? handler(data, nil) : nil;
        
    }];
}

- (void)searchKeyWordWithType:(FacebookSearchType)type keyWord:(NSString *)keyWord param:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void(^)(NSDictionary *, NSError *))handler {
    
    if (!keyWord || [keyWord isEqualToString:@""]) {
        return;
    }
    
    __weak typeof(self) _self = self;
    if (![self isCommentAuthorization] && ![self isBroadcastAuthorization]) {
        [self doFacebookCommonAuthWithPresentController:controller thenHandler:^(FBSDKAccessToken *authorization, NSError *error) {
            if (error) {
                handler ? handler(nil, error) : nil;
                return;
            }
            
            [_self searchKeyWordWithType:type keyWord:keyWord param:param presentController:controller completeHandler:handler];
        }];
        return;
    }
    
    NSString *typeString = @"user";
    switch (type) {
        case FacebookSearchType_page: {
            typeString = @"page";
            break;
        }
        case FacebookSearchType_user: {
            typeString = @"user";
            break;
        }
        case FacebookSearchType_event: {
            typeString = @"event";
            break;
        }
        case FacebookSearchType_group: {
            typeString = @"group";
            break;
        }
            
        default:
            break;
    }
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:param];
    [dict addEntriesFromDictionary:@{@"q": keyWord,@"type": typeString, @"limit" : @(kFacebookMaximumLimitResult)}];
    //[dict setDictionary:@{@"q": keyWord,@"type": typeString, @"limit" : @(kFacebookMaximumLimitResult)}];
    
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc]
                                  initWithGraphPath:@"/search"
                                  parameters:dict
                                  HTTPMethod:@"GET"];
    [request startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
        NSDictionary *dict = (NSDictionary *)result;
        handler ? handler(dict, nil) : nil;
        
    }];
    
}

#pragma mark -

- (void)checkGroupPermissionsWithGroupID:(NSString *)group_id presentController:(UIViewController *)controller completeHandler:(void (^)(BOOL))handler {
    
    if ([group_id isEqualToString:@""] || !group_id) {
        handler ? handler(NO) : nil;
        return;
    }
    
    NSDictionary *param = @{
                            FacebookBroadcastType_string : [NSNumber numberWithInteger:FacebookBroadcastType_GROUP],
                            FacebookBroadcast_id : group_id,
                            };
    
    [self fetchFacebookBroadcastURLWithParam:param presentController:controller completeHandler:^(NSString *broadcastURL, NSError *error) {
        if (broadcastURL && ![broadcastURL isEqualToString:@""]) {
            handler ? handler(YES) : nil;
        } else {
            handler ? handler(NO) : nil;
        }
    }];
}

#pragma mark - broadcast

- (void)startBroadcastWithParam:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void (^)(NSString *, NSError *))handler {
    
    //__weak typeof(self) _self = self;
    [self fetchFacebookBroadcastURLWithParam:param presentController:controller completeHandler:^(NSString *broadcastURL, NSError *error) {
        
        if (!error) {
            //[_self autoFetchBroadcastStatus];
            //[_self autoFetchBroadcastComments];
        }
        
        handler ? handler(broadcastURL, error) : nil;
    }];
}

- (void)stopBroadcast {
    
    [self postBoradcastInfoWithLiveVideoID:self.currentLiveVideo_id param:@{ @"end_live_video": @"true",} commpleteHandler:^(NSError *error) {
        if (error) {
            PLog(@"stop broadcast failed");
        } else {
            PLog(@"stop broadcast success");
        }
    }];
    
    //[self stopAutoFetchBroadcastStatus];
    //[self stopAutoFetchBroadcastComments];
    
    self.currentLiveVideo_id = @"";
    self.last_comment_time = @"";
    self.liveCommentsAfterKey = @"";
    
    [self stopBroadcastConnection];
}

- (void)stopBroadcastConnection {
    for (FBSDKGraphRequestConnection *con in self.broadcastConnectionArray) {
        [con cancel];
    }
    [self.broadcastConnectionArray removeAllObjects];
}

#pragma mark -

- (void)checkLiveVideoID:(NSString *)liveVideoID completeHandler:(void (^)(BOOL, NSString *))handler {
    
    if (![self isBroadcastAuthorization]) {
        // 没有登录
        handler ? handler(NO, @"do not login facebook") : nil;
        return;
    }
    
    [self fetchBroadcastStatusWithLiveVideoID:liveVideoID completeHandler:^(NSDictionary *dict, NSError *error) {
        NSString *statusString = dict[@"status"];
        
        BOOL canUse = NO;
        NSString *message = @"";
        if ([statusString isEqualToString:@"UNPUBLISHED"]) { // 三种情况
            canUse = YES;
        } else if ([statusString isEqualToString:@"LIVE_NOW"]) { // 三种情况
            canUse = YES;
        } else if ([statusString isEqualToString:@"LIVE"]) { // 三种情况
            canUse = YES;
        } else {
            canUse = NO;
            message = @"live video is can not be use";
        }
        
        handler ? handler(canUse, message) : nil;
    }];
}

- (void)startBroadcastWithLiveVideoID:(NSString *)liveVideoID {
    if (liveVideoID.length <= 0) {
        return;
    }
    
    self.currentLiveVideo_id = liveVideoID;
}

#pragma mark -

/*
- (void)autoFetchBroadcastStatus {
    if (!self.currentLiveVideo_id || [self.currentLiveVideo_id isEqualToString:@""]) {
//        if ([self.delegate respondsToSelector:@selector(facebookDidReceiveLiveCommentsError:)]) {
//            [self.delegate facebookDidReceiveLiveCommentsError:[NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"current live video id is nil", NSLocalizedDescriptionKey : @"current live video id is nil"}]];
//        }
        return;
    }
    
    if (!self.statusTimer) {
        self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(fetchBroadcastStatusTimerMethod) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:self.statusTimer forMode:NSDefaultRunLoopMode];
    }
}

- (void)stopAutoFetchBroadcastStatus {
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}

- (void)fetchBroadcastStatusTimerMethod {
    __weak typeof(self) _self = self;
    [self fetchBroadcastStatusWithCompleteHandler:^(FacebookBroadcastStatus status, NSError *error) {
        if ([_self.delegate respondsToSelector:@selector(facebookBroadcastStatusDidChange:error:)]) {
            [_self.delegate facebookBroadcastStatusDidChange:status error:error];
        }
    }];
}//*/

/*
- (void)autoFetchBroadcastComments {
    if (!self.currentLiveVideo_id || [self.currentLiveVideo_id isEqualToString:@""]) {
        if ([self.delegate respondsToSelector:@selector(facebookDidReceiveLiveCommentsError:)]) {
            [self.delegate facebookDidReceiveLiveCommentsError:[NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"current live video id is nil", NSLocalizedDescriptionKey : @"current live video id is nil"}]];
        }
        return;
    }
    
    self.liveCommentsAfterKey = @"";
    self.last_comment_time = @"";
    
    if (!self.timer) {
        self.timer = [NSTimer timerWithTimeInterval:1 target:self selector:@selector(fetchLiveCommentsTimerMethod) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSDefaultRunLoopMode];
    }
}

- (void)stopAutoFetchBroadcastComments {
    [self.timer invalidate];
    self.timer = nil;
    
    self.liveCommentsAfterKey = @"";
    self.last_comment_time = @"";
}

- (void)fetchLiveCommentsTimerMethod {
    __weak typeof(self) _self = self;
    [self fetchBroadcastCommentsWithCompleteHandler:^(NSArray *comments, NSError *error) {
        if (error) {
            if ([_self.delegate respondsToSelector:@selector(facebookDidReceiveLiveCommentsError:)]) {
                [_self.delegate facebookDidReceiveLiveCommentsError:error];
            }
            
            // 停止获取
            [_self.timer invalidate];
            _self.timer = nil;
            
            return;
        }
        
        if ([_self.delegate respondsToSelector:@selector(facebookDidReceiveLiveComments:)]) {
            [_self.delegate facebookDidReceiveLiveComments:comments];
        }
        
    }];
} //*/

#pragma mark  tool

- (void)updateBroadcastDescription:(NSString *)string liveVideoID:(NSString *)liveVideoID completeHandler:(void(^)(NSError *error))handler {
    [self postBoradcastInfoWithLiveVideoID:liveVideoID param:@{@"description" : string} commpleteHandler:handler];
}

- (void)postBoradcastInfoWithLiveVideoID:(NSString *)liveVideoID param:(NSDictionary *)param commpleteHandler:(void(^)(NSError *error))handler {
    if (!liveVideoID || [liveVideoID isEqualToString:@""]) {
        handler ? handler([NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"live video id can not be nil", NSLocalizedDescriptionKey : @"live video id can not be nil"}]) : nil;
        return;
    }
    
    __weak typeof(self) _self = self;
    
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc]
                                  initWithGraphPath:[NSString stringWithFormat:@"/%@", liveVideoID]
                                  parameters:param
                                  HTTPMethod:@"POST"];
    FBSDKGraphRequestConnection *con = [request startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        [_self.broadcastConnectionArray removeObject:connection];
        handler ? handler(error) : nil;
    }];
    [self.broadcastConnectionArray addObject:con];
}

// ---

//UNPUBLISHED, LIVE_NOW, SCHEDULED_UNPUBLISHED, SCHEDULED_LIVE, SCHEDULED_CANCELED
//@{ @"fields": @"comments{comment_count},live_views,likes,status",}
- (FBSDKGraphRequestConnection *)fetchBroadcastStatusWithLiveVideoID:(NSString *)liveVideoID completeHandler:(void(^)(NSDictionary *dict, NSError *error))handler {
    
    return [self getBroadcastInfoWithLiveVideoID:liveVideoID param:@{ @"fields": @"status,errors",} completeHandler:handler];
}

- (FBSDKGraphRequestConnection *)getBroadcastInfoWithLiveVideoID:(NSString *)liveVideoID param:(NSDictionary *)param completeHandler:(void(^)(NSDictionary *dict, NSError *error))handler {
    if (!liveVideoID || [liveVideoID isEqualToString:@""]) {
        handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-100 userInfo:@{@"message" : @"live video id can not be nil", NSLocalizedDescriptionKey : @"live video id can not be nil"}]) : nil;
        return nil;
    }
    __weak typeof(self) _self = self;
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc]
                                  initWithGraphPath:[NSString stringWithFormat:@"/%@", liveVideoID]
                                  parameters:param
                                  HTTPMethod:@"GET"];
    
    FBSDKGraphRequestConnection *con = [request startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        
        [_self.broadcastConnectionArray removeObject:connection];
        
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
        
        NSDictionary *dict = (NSDictionary *)result;
        handler ? handler(dict, nil) : nil;
    }];
    [self.broadcastConnectionArray addObject:con];
    
    return con;
}

- (void)cleanAppAuth {
    [self.loginManager logOut];
    
    // 撤销权限
    /*
    [[[FBSDKGraphRequest alloc] initWithGraphPath:@"me/permissions"
                                       parameters:nil
                                       HTTPMethod:@"DELETE"]
    startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        PLog(@"delete auth : %@, error : %@", result, error);
    }];//*/
}

#pragma mark - permissions

//- (BOOL)isAuthorization {
//return ([FBSDKAccessToken currentAccessToken] != nil);
//}

- (NSArray <NSString *>*)checkPermissionWithWantPermissions:(NSArray <NSString *>*)wantPermissions {
    FBSDKAccessToken *token = [FBSDKAccessToken currentAccessToken];
    NSMutableArray *needAuthArray = [NSMutableArray array];
    for (NSString *permission in wantPermissions) {
        if (![token.permissions containsObject:permission]) {
            [needAuthArray addObject:permission];
        }
    }
    return needAuthArray;
}

// 判断普通权限
- (BOOL)isCommentAuthorization {
    return ([self checkPermissionWithWantPermissions:[self commentPermissions]].count > 0 ? NO : YES);
}

// 判断直播权限
- (BOOL)isBroadcastAuthorization {
    return ([self checkPermissionWithWantPermissions:[self broadcastPermissions]].count > 0 ? NO : YES);
}

// 判断小组权限
- (BOOL)isGroupAuthorization {
    return ([self checkPermissionWithWantPermissions:[self groupPermissions]].count > 0 ? NO : YES);
}

- (NSArray <NSString *>*)commentPermissions {
    //, @"pages_show_list"
    return @[@"public_profile", @"email" ];
}

- (NSArray <NSString *>*)broadcastPermissions {
    return @[@"publish_actions",];
}

- (NSArray <NSString *>*)groupPermissions {
    return @[@"user_managed_groups"];
}

//- (NSArray <NSString *>*)permissions {
//    return @[@"public_profile", @"email", @"user_friends", @"publish_actions", @"manage_pages", @"user_managed_groups", @"publish_pages"];
//    return @[@"public_profile", @"email", @"user_friends",];
//}

#pragma mark - getter

- (FBSDKLoginManager *)loginManager {
    if (!_loginManager) {
        _loginManager = [[FBSDKLoginManager alloc] init];
        _loginManager.defaultAudience = FBSDKDefaultAudienceFriends;
        _loginManager.loginBehavior = FBSDKLoginBehaviorNative;
    }
    return _loginManager;
}

- (NSMutableArray *)broadcastConnectionArray {
    if (!_broadcastConnectionArray) {
        _broadcastConnectionArray = [NSMutableArray array];
    }
    return _broadcastConnectionArray;
}

@end

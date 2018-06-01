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

@property (strong, nonatomic) FBSDKGraphRequestConnection *currentBroadcastStatusConnection;

@property (strong, nonatomic) NSMutableArray *broadcastConnectionArray;

//@property (strong, nonatomic) NSTimer *timer;
//@property (strong, nonatomic) NSTimer *statusTimer;

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

#pragma mark - auth medhot
/**
 授权
 */
- (void)doFacebookAuthWithPresentController:(UIViewController *)controller
           permissionsArray:(NSArray <NSString *>*)permissionsArray
           thenHandler:(CPFacebookAuthCompletion)handler {
    
    if (permissionsArray.count <= 0) {
        NSAssert(NO, @"permissions array can not be nil");
        handler ? handler([FBSDKAccessToken currentAccessToken], nil, permissionsArray, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"permissions array can not be nil"}]) : nil;
        return;
    }
    
    // 先检测权限是否已经授权
    NSArray *needAuthArray = [self checkPermissionWithWantPermissions:[[self class] groupPermissions]];
    if (needAuthArray.count <= 0) { // 都已经授权了
        handler ? handler([FBSDKAccessToken currentAccessToken], permissionsArray, nil, nil) : nil;
        return;
    }
    
    // 将授权分开成read 和 publish
    NSArray *readArray = nil;
    NSArray *publishArray = nil;
    [self separatePermissionsArray:permissionsArray readSet:&readArray publishSet:&publishArray];
    
     __weak typeof(self) _self = self;
    if (readArray) {
        [self.loginManager logInWithReadPermissions:readArray fromViewController:controller handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
            [_self authCallbackWithDeclinedPermission:publishArray originPermissionArray:permissionsArray result:result error:error thenHandler:handler];
        }];
    } else {
        [self.loginManager logInWithPublishPermissions:publishArray fromViewController:controller handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
            [_self authCallbackWithDeclinedPermission:readArray originPermissionArray:permissionsArray result:result error:error thenHandler:handler];
        }];
    }
}

/**
 授权的callback
 */
- (void)authCallbackWithDeclinedPermission:(NSArray <NSString *>*)decliendPermission originPermissionArray:(NSArray <NSString *>*)originPermissionArray result:(FBSDKLoginManagerLoginResult *)result error:(NSError *)error thenHandler:(CPFacebookAuthCompletion)handler {
    
    self.authorization = result.token;
    
    if (error) {
        handler ? handler(result.token, nil, originPermissionArray, error) : nil;
        return;
    }
    
    if (result.isCancelled) {
        handler ? handler(result.token, nil, originPermissionArray, [NSError errorWithDomain:FacebookAuthErrorDoMain code:kFacebookAuthCancelCode userInfo:@{@"message" : @"fecth facebook authorization request did cancel" , NSLocalizedDescriptionKey : @"fecth facebook authorization request did cancel"}]) : nil;
        return;
    }
    
    // 如果某个权限被拒绝了 也返回错误
    NSError *decliendError = nil;
    NSMutableArray *array = [NSMutableArray arrayWithArray:decliendPermission];
    if (result.declinedPermissions.count > 0) {
        [array addObjectsFromArray:[result.declinedPermissions allObjects]];
    }
    if (array.count > 0) {
        decliendError = [NSError errorWithDomain:CPFacebookErrorDomain code:-10000 userInfo:@{
                                                                                              NSLocalizedDescriptionKey : @"Facebook auth has been refuse some permission",
                                                                                              @"DecliendPermissions" : array,
                                                                                              }];
    }
    
    handler ? handler(result.token, [result.grantedPermissions allObjects], array, decliendError) : nil;
}

/**
 将permissions 分成两类 --- read and publish
 */
- (void)separatePermissionsArray:(NSArray <NSString *>*)permissionsArray readSet:(NSArray <NSString *>**)readSet publishSet:(NSArray <NSString *>**)publishSet {
    NSMutableArray *aReadSet = [[NSMutableArray alloc] init];
    NSMutableArray *aPublishSet = [[NSMutableArray alloc] init];
    
    for (NSString *permission in permissionsArray) {
        if ([[self class] isPublishPermission:permission]) { // publish permission
            [aPublishSet addObject:permission];
        } else {
            [aReadSet addObject:permission];
        }
    }
    
    if (aReadSet.count > 0) {
        *readSet = aReadSet;
    } else {
        *readSet = nil;
    }
    
    if (aPublishSet.count > 0) {
        *publishSet = aPublishSet;
    } else {
        *publishSet = nil;
    }
}

/**
 是否是publish权限
 */
+ (BOOL)isPublishPermission:(NSString *)permission
{
    return [permission hasPrefix:@"publish"] ||
    [permission hasPrefix:@"manage"] ||
    [permission isEqualToString:@"ads_management"] ||
    [permission isEqualToString:@"create_event"] ||
    [permission isEqualToString:@"rsvp_event"];
}

- (void)cleanAppAuth {
    [self.loginManager logOut];
    self.authorization = nil;
    // 撤销权限
    /*
     [[[FBSDKGraphRequest alloc] initWithGraphPath:@"me/permissions"
     parameters:nil
     HTTPMethod:@"DELETE"]
     startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
     PLog(@"delete auth : %@, error : %@", result, error);
     }];//*/
}

#pragma mark -

+ (NSString *)getPublishPrivacyStringWith:(NSString *)pricacyString allowArray:(NSArray<NSString *> *)allowArray denyArray:(NSArray<NSString *> *)denyArray {
    NSArray *privacyArray = @[FacebookPublishPrivacyKey_SELF,
                                                 FacebookPublishPrivacyKey_CUSTOM,
                                                 FacebookPublishPrivacyKey_EVERYONE,
                                                 FacebookPublishPrivacyKey_ALL_FRIENDS,
                                                 FacebookPublishPrivacyKey_FRIENDS_OF_FRIENDS];
    if (![privacyArray containsObject:pricacyString]) {
        return @"";
    }
    if ([pricacyString isEqualToString:FacebookPublishPrivacyKey_CUSTOM]) {
        NSString *customString = @"allow";
        NSString *arrayString = @"";
        if (denyArray.count > 0) {
            customString = @"deny";
            arrayString = [self convertStringArrayToString:denyArray separateString:@","];
        }
        if (allowArray.count > 0) {
            customString = @"allow";
            arrayString = [self convertStringArrayToString:allowArray separateString:@","];
        }
        
        return [NSString stringWithFormat:@"{'%@':'%@','%@':'%@'}",@"value", pricacyString, customString, arrayString];
    }
    
    // 其他情况
    return [NSString stringWithFormat:@"{'%@':'%@'}",@"value", pricacyString];
}

+ (NSString *)convertStringArrayToString:(NSArray <NSString *>*)stringArray separateString:(NSString *)separateString {
    if (!separateString) {
        NSAssert(NO, @"%s error", __FUNCTION__);
        return @"";
    }
    NSMutableString *string = [NSMutableString string];
    for (NSString *aString in stringArray) {
        if (![aString isKindOfClass:[NSString class]]) {
            NSAssert(NO, @"%s error", __FUNCTION__);
            return @"";
        }
        if (string.length > 0) {
            [string appendString:separateString];
        }
        [string appendString:aString];
    }
    
    return string.copy;
}

#pragma mark - fetch user info

/**
 获取用户信息
 */

- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void (^)(FBSDKProfile *, NSError *))handler {
    __weak typeof(self) _self = self;
    // userInfo 只要一个 profile就OK了
    NSArray *needPermissions = @[@"public_profile"];
    if ([self checkPermissionWithWantPermissions:needPermissions].count > 0) {
        [self doFacebookAuthWithPresentController:controller permissionsArray:needPermissions thenHandler:^(FBSDKAccessToken *token, NSArray<NSString *> *grantedPermissions, NSArray<NSString *> *declinedPermissions, NSError *error) {
            
            // 只要有declinedPermissions 就表示有权限被拒绝 --- 那么接下来的操作就不能进行下去了
            if (error || declinedPermissions.count > 0) {
                if (!error) {
                    error = [NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"public_profile 被拒绝"}];
                }
                handler ? handler(nil,error) : nil;
                return;
            }
            
            // 刚获取完token 马上就获取profile 就会出现一种没有获取到profile的情况 --- 所以在这里做延迟获取的处理
            [_self fetchUserInfoWithPresentController:controller completeHandler:handler];
        }];
        return;
    }
    
    // 修改方式 不获取profile
    FBSDKProfile *profile = [FBSDKProfile currentProfile];
    
    if (profile) {
        handler ? handler(profile, nil) : nil;
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            [FBSDKProfile loadCurrentProfileWithCompletion:^(FBSDKProfile *profile, NSError *error) {
                
                if (!profile) {
                    handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"fetch user info error", NSLocalizedDescriptionKey : @"fetch user info error"}]) : nil;
                    return;
                }
                handler ? handler(profile, nil) : nil;
                
            }];
            
        });
    }//*/
    
    /* // 获取个人信息
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc] initWithGraphPath:@"/me" parameters:@{@"fields" : @"id,name"} HTTPMethod:k_GET];
    [request startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
        
        NSDictionary *dict = (NSDictionary *)result;
        if (!dict || ![dict isKindOfClass:[NSDictionary class]]) {
            handler ? handler(nil, [NSError errorWithDomain:CPFacebookErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"fetch user info response is nil"}]) : nil;
            return;
        }
        
        NSString *user_id = dict[@"id"];
        NSString *user_name = dict[@"name"];
        // icon 的拼接 : https://graph.facebook.com/v2.11/154317088511429/picture?type=normal&width=100&height=100
        NSString *user_icon = [NSString stringWithFormat:@"%@%@%@", @"https://graph.facebook.com/v2.11/", user_id, @"/picture?type=normal&width=100&height=100"];
        
        if (user_id.length <= 0 || !user_name) {
            handler ? handler(nil, [NSError errorWithDomain:CPFacebookErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"fetch user info user_id or user_name is nil"}]) : nil;
            return;
        }
        
        NSDictionary *user_dict = @{
                                    @"user_id" : user_id,
                                    @"user_name" : user_name,
                                    @"user_icon" : user_icon,
                                    };
        handler ? handler(user_dict, error) : nil;
    }];//*/
}

#pragma mark - fetch braodcast url

/**
 获取直播的URL --- 发布到个人的时间线
 */
- (void)fetchFacebookBroadcastURLWithParam:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void (^)(NSString *, NSError *))handler {
    // 判断param
    FacebookBoradcastType type = [param[FacebookBroadcastType_string] integerValue];
    NSString *broadcast_id = param[FacebookBroadcast_id];
    NSString *broadcast_description = param[FacebookBroadcast_description];
    
    if ([broadcast_id isEqualToString:@""] || !broadcast_id) {
        handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"broadcast id can not be nil", NSLocalizedDescriptionKey : @"broadcast id can not be nil"}]) : nil;
        return;
    }
    
    __weak typeof(self) _self = self;
    if (![self isBroadcastAuthorization]) {
        [self doFacebookAuthWithPresentController:controller permissionsArray:[[self class] publishActionsPermissions] thenHandler:^(FBSDKAccessToken *token, NSArray<NSString *> *grantedPermissions, NSArray<NSString *> *declinedPermissions, NSError *error) {
            if (error || declinedPermissions.count > 0) {
                if (!error) {
                    error = [NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"publish 权限被拒绝"}];
                }
                handler ? handler(nil,error) : nil;
                return;
            }
            
            [_self fetchFacebookBroadcastURLWithParam:param presentController:controller completeHandler:handler];
        }];
    }
    
    // 获取rtmp url
    NSDictionary *privacy = nil;
    if (type == FacebookBroadcastType_SELF) {
        privacy = @{@"privacy" : [[self class] getPublishPrivacyStringWith:FacebookPublishPrivacyKey_SELF allowArray:nil denyArray:nil]};
    } else if (type == FacebookBroadcastType_PUBLISH) {
        privacy = @{@"privacy" : [[self class] getPublishPrivacyStringWith:FacebookPublishPrivacyKey_EVERYONE allowArray:nil denyArray:nil]};
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

/**
 更新live 信息
 */
- (void)updateBroadcastDescription:(NSString *)string completeHandler:(void (^)(NSError *))handler {
    [self updateBroadcastDescription:string liveVideoID:self.currentLiveVideo_id completeHandler:handler];
}

/**
 获取直播状态
 */
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

/**
 获取直播时的评论
 */
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

/**
 获取直播信息
 */
- (void)fetchBroadcastInfoWithCompleteHandler:(void (^)(NSDictionary *, NSError *))handler {
    [self getBroadcastInfoWithLiveVideoID:self.currentLiveVideo_id param:@{ @"fields": @"live_views,likes,status",} completeHandler:^(NSDictionary *dict, NSError *error) {
        
        if (error) {
            handler ? handler(nil, error) : nil;
            return;
        }
        
        handler ? handler(dict, nil) : nil;
        
    }];
}

#pragma mark - search method

/**
 搜索小组的结果 --- 下一页
 */
- (void)searchGroupResultNextPageWithPresentController:(UIViewController *)controller completeHandler:(void (^)(NSArray<NSDictionary *> *, NSError *))handler {
    if (!self.searchGroupAfterKey || [self.searchGroupAfterKey isEqualToString:@""]) {
        handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"after key can not be nil", NSLocalizedDescriptionKey : @"after key can not be nil"}]) : nil;
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

/**
 搜索小组的结果 --- 上一页
 */
- (void)searchGroupResultBeforePageWithPresentController:(UIViewController *)controller completeHandler:(void (^)(NSArray<NSDictionary *> *, NSError *))handler {
    if (!self.searchGroupBeforeKey || [self.searchGroupBeforeKey isEqualToString:@""]) {
        handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"before key can not be nil", NSLocalizedDescriptionKey : @"before key can not be nil"}]) : nil;
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
/**
 搜索小组
 */
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

/**
 搜索
 */
- (void)searchKeyWordWithType:(FacebookSearchType)type keyWord:(NSString *)keyWord param:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void(^)(NSDictionary *, NSError *))handler {
    
    if (!keyWord || [keyWord isEqualToString:@""]) {
        return;
    }
    
    __weak typeof(self) _self = self;
    NSArray *needPermissions = @[@"public_profile"]; // 搜索Api只要 public_profile 这个权限就够了
    if ([self checkPermissionWithWantPermissions:needPermissions].count > 0) {
        [self doFacebookAuthWithPresentController:controller permissionsArray:needPermissions thenHandler:^(FBSDKAccessToken *token, NSArray<NSString *> *grantedPermissions, NSArray<NSString *> *declinedPermissions, NSError *error) {
            if (error || declinedPermissions.count > 0) {
                if (!error) {
                    error = [NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"public_profile 权限被拒绝"}];
                }
                handler ? handler(nil,error) : nil;
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

/**
 检查用户是否有小组的直播权限
 */
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

/**
 开始直播
 */
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

/**
 停止直播
 */
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

#pragma mark - upload method

/*
 param:
 videoURL : NSString
 publishParam : NSDictionary
 sendID : NSString
 resumeMediaId : NSString
 */
- (CPFacebookUploader *)createVideoUploadTicketWithParam:(NSDictionary *)param
                                          precentController:(UIViewController *)precentController
                                          uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
                                          completeHandler:(CPUploaderCompleteHandler)completeHandler
{
    
    if (!param) {
        NSAssert(NO, @"param can not be nil");
        completeHandler ? completeHandler(nil, [NSError errorWithDomain:CPFacebookErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"paramDict can not be nil"}]) : nil;
        return nil;
    }
    
    NSString *url = param[@"videoURL"];
    if (url.length <= 0) {
        NSAssert(NO, @"video url can not be nil");
        completeHandler ? completeHandler(nil, [NSError errorWithDomain:CPFacebookErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"video url can not be nil"}]) : nil;
        return nil;
    }
    
    // 检测send_id
    NSString *send_id = param[@"sendID"];
    if (send_id.length <= 0) {
        NSAssert(NO, @"send id can not be nil");
        completeHandler ? completeHandler(nil, [NSError errorWithDomain:CPFacebookErrorDomain code:-10000 userInfo:@{NSLocalizedDescriptionKey : @"send id can not be nil"}]) : nil;
        return nil;
    }
    
    // 判断是否有权限上传
    if (![self isBroadcastAuthorization]) {
        [self doFacebookAuthWithPresentController:precentController permissionsArray:[[self class] publishActionsPermissions] thenHandler:nil];
        return nil;
    }
    
    CPUploadParam *uploadParam = [[CPUploadParam alloc] init];
    uploadParam.videoURL =url;
    uploadParam.userID = self.authorization.userID;
    uploadParam.resumeMediaId = param[@"resumeMediaId"];
    uploadParam.publishParam = param[@"publishParam"];
    uploadParam.sendID = send_id;
    
    CPFacebookUploader *uploader = [CPFacebookUploader createFacebookUploadTicketWithParam:uploadParam uploadProgressHandler:uploadProgressHandler completeHandler:completeHandler];
    
    return uploader;
}

#pragma mark -

/*
- (void)autoFetchBroadcastStatus {
    if (!self.currentLiveVideo_id || [self.currentLiveVideo_id isEqualToString:@""]) {
//        if ([self.delegate respondsToSelector:@selector(facebookDidReceiveLiveCommentsError:)]) {
//            [self.delegate facebookDidReceiveLiveCommentsError:[NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"current live video id is nil", NSLocalizedDescriptionKey : @"current live video id is nil"}]];
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
            [self.delegate facebookDidReceiveLiveCommentsError:[NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"current live video id is nil", NSLocalizedDescriptionKey : @"current live video id is nil"}]];
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

#pragma mark - tool

- (void)updateBroadcastDescription:(NSString *)string liveVideoID:(NSString *)liveVideoID completeHandler:(void(^)(NSError *error))handler {
    [self postBoradcastInfoWithLiveVideoID:liveVideoID param:@{@"description" : string} commpleteHandler:handler];
}

- (void)postBoradcastInfoWithLiveVideoID:(NSString *)liveVideoID param:(NSDictionary *)param commpleteHandler:(void(^)(NSError *error))handler {
    if (!liveVideoID || [liveVideoID isEqualToString:@""]) {
        handler ? handler([NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"live video id can not be nil", NSLocalizedDescriptionKey : @"live video id can not be nil"}]) : nil;
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
        handler ? handler(nil, [NSError errorWithDomain:FacebookAuthErrorDoMain code:-10000 userInfo:@{@"message" : @"live video id can not be nil", NSLocalizedDescriptionKey : @"live video id can not be nil"}]) : nil;
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

#pragma mark - permissions

// 检测权限
- (NSArray <NSString *>*)checkPermissionWithWantPermissions:(NSArray <NSString *>*)wantPermissions {
    return [[self class] checkPermissionWithToken:[FBSDKAccessToken currentAccessToken] wantPermissions:wantPermissions];
}

// 检测权限
+ (NSArray<NSString *> *)checkPermissionWithToken:(FBSDKAccessToken *)token wantPermissions:(NSArray<NSString *> *)wantPermissions {
    NSMutableArray *needAuthArray = [NSMutableArray array];
    for (NSString *permission in wantPermissions) {
        if (![token.permissions containsObject:permission]) {
            [needAuthArray addObject:permission];
        }
    }
    return needAuthArray;
}

// 判断普通权限
- (BOOL)isCommonAuthorization {
    return ([self checkPermissionWithWantPermissions:[[self class] commonPermissions]].count > 0 ? NO : YES);
}

// 判断直播权限
- (BOOL)isBroadcastAuthorization {
    return ([self checkPermissionWithWantPermissions:[[self class] publishActionsPermissions]].count > 0 ? NO : YES);
}

// 判断小组权限
- (BOOL)isGroupAuthorization {
    return ([self checkPermissionWithWantPermissions:[[self class] groupPermissions]].count > 0 ? NO : YES);
}

/**
 通用的登录permission(public_profile, eamil)

 @return 权限
 */
+ (NSArray <NSString *>*)commonPermissions {
    //, @"pages_show_list"
    return @[@"public_profile", @"email" ];
}

/**
 publish_actions permission 适用于 Broadcast 和 发布Facebook(视频、图片等)

 @return 权限
 */
+ (NSArray <NSString *>*)publishActionsPermissions {
    return @[@"publish_actions",];
}

/**
 小组管理的permission(user_managed_groups)

 @return 权限
 */
+ (NSArray <NSString *>*)groupPermissions {
    return @[@"user_managed_groups"];
}

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

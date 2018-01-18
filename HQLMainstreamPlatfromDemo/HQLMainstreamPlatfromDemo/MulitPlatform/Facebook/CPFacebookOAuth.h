//
//  CPFacebookOAuth.h
//  GoCreate3.0
//
//  Created by 何启亮 on 2017/11/14.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <FBSDKCoreKit/FBSDKCoreKit.h>

static NSString *const FacebookAuthErrorDoMain = @"GoCreate.facebook.broadcastAuthorization.error.doMain";

// param key
static NSString *const FacebookBroadcastType_string = @"broadcastType";
static NSString *const FacebookBroadcast_id = @"broadcast_id";
static NSString *const FacebookBroadcast_description = @"broadcast_description";

#define kFacebookMaximumLimitResult 25
#define kFacebookMaximumLimitComments 100

// 直播类型 ---
typedef NS_ENUM(NSInteger, FacebookBoradcastType) {
    FacebookBroadcastType_PUBLISH = 0, // 公开 --- 默认在时间线上
    FacebookBroadcastType_SELF, // 只有自己看 --- 默认在时间线上
    FacebookBroadcastType_GROUP, // 公布到小组 --- 默认privacy是公开
};

typedef NS_ENUM(NSInteger, FacebookBroadcastStatus) {
    FacebookBroadcastStatus_off_line,
    FacebookBroadcastStatus_live,
    FacebookBroadcastStatus_live_stopped, // 已停止
};

typedef NS_ENUM(NSInteger, FacebookSearchType) {
    FacebookSearchType_user,
    FacebookSearchType_page,
    FacebookSearchType_event,
    FacebookSearchType_group,
};

@protocol CPFacebookOAuthDelegate <NSObject>

@optional

//- (void)facebookBroadcastStatusDidChange:(FacebookBroadcastStatus)status error:(NSError *)error;

/*
 {
 @"name" : name,
 @"message" : message,
 @"message_id" : message_id,
 }
 */
//- (void)facebookDidReceiveLiveComments:(NSArray <NSDictionary *>*)comments;

//- (void)facebookDidReceiveLiveCommentsError:(NSError *)error;

@end

@interface CPFacebookOAuth : NSObject

@property (strong, nonatomic, readonly) FBSDKAccessToken *authorization;
//@property (assign, nonatomic) id <CPFacebookOAuthDelegate> delegate;

- (instancetype)initWithAuthorization:(FBSDKAccessToken *)authorization;

    // @[@"public_profile", @"email", @"user_friends", @"publish_actions", @"manage_pages", @"user_managed_groups", @"publish_pages"];

- (void)doFacebookCommonAuthWithPresentController:(UIViewController *)controller thenHandler:(void(^)(FBSDKAccessToken *authorization, NSError *error))handler;
- (void)doFacebookBroadcastAuthWithPresentController:(UIViewController *)controller thenHandler:(void(^)(FBSDKAccessToken *authorization, NSError *error))handler;
- (void)doFacebookGroupAuthWithPresentController:(UIViewController *)controller thenHandler:(void(^)(FBSDKAccessToken *authorization, NSError *error))handler;

//- (void)doFacebookAuthWithPresentController:(UIViewController *)controller thenHandler:(void(^)(FBSDKAccessToken *authorization, NSError *error))handler;

- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void(^)(FBSDKProfile *profile, NSError *error))handler;

- (void)cleanAppAuth;

/*
 param = @{
 @"broadcastType" : FacebookBoradcastType,
 @"broadcast_id" : @"123456", // 需要和type相对应 --- publish和self使用的是user_id, group使用的是group_id
 @"broadcast_description" : @"abcdefg",
 }
 */
- (void)fetchFacebookBroadcastURLWithParam:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void(^)(NSString *broadcastURL, NSError *error))handler;

- (void)updateBroadcastDescription:(NSString *)string completeHandler:(void(^)(NSError *error))handler;

// ---
- (void)fetchBroadcastStatusWithCompleteHandler:(void(^)(FacebookBroadcastStatus status, NSError *error))handler;

- (void)fetchBroadcastCommentsWithCompleteHandler:(void(^)(NSArray *comments, NSError *error))handler;

- (void)fetchBroadcastInfoWithCompleteHandler:(void(^)(NSDictionary *dict, NSError *error))handler;

// search ---

/* // group dict
 {
     "cover": {
         "cover_id": "513027972214700",
         "offset_x": 0,
         "offset_y": 59,
         "source": "https://fb-s-a-a.akamaihd.net/h-ak-fbx/v/t31.0-8/s720x720/13072846_513027972214700_3487798194668664759_o.jpg?oh=f26e4f24a7ed39ef11383d039187a3f4&oe=5A95D977&__gda__=1520671449_e3f573b7935cb3b12a329e97cd166f6b",
         "id": "513027972214700"
     },
     "icon": "https://static.xx.fbcdn.net/rsrc.php/v3/yq/r/zFDa8yqE6U1.png",
     "name": "Desapega abc.",
     "id": "523705811105401"
 }
 */
- (void)searchGroupResultNextPageWithPresentController:(UIViewController *)controller completeHandler:(void(^)(NSArray <NSDictionary *>*groups, NSError *error))handler;
- (void)searchGroupResultBeforePageWithPresentController:(UIViewController *)controller completeHandler:(void(^)(NSArray <NSDictionary *>*groups, NSError *error))handler;

- (void)searchGroupWithKeyWord:(NSString *)keyWord presentController:(UIViewController *)controller completeHandler:(void(^)(NSArray <NSDictionary *>*groups, NSError *error))handler;

- (void)searchKeyWordWithType:(FacebookSearchType)type keyWord:(NSString *)keyWord param:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void(^)(NSDictionary *dict, NSError *error))handler;

- (void)checkGroupPermissionsWithGroupID:(NSString *)group_id presentController:(UIViewController *)controller completeHandler:(void(^)(BOOL isPermissions))handler;

#pragma mark - broadcast

- (void)startBroadcastWithParam:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void(^)(NSString *broadcastURL, NSError *error))handler;
// 停止
- (void)stopBroadcast;

- (void)stopBroadcastConnection;

//- (void)autoFetchBroadcastComments;
//- (void)stopAutoFetchBroadcastComments;

//- (void)autoFetchBroadcastStatus;
//- (void)stopAutoFetchBroadcastStatus;

- (void)checkLiveVideoID:(NSString *)liveVideoID completeHandler:(void(^)(BOOL canUse, NSString *message))handler;
- (void)startBroadcastWithLiveVideoID:(NSString *)liveVideoID;

@end

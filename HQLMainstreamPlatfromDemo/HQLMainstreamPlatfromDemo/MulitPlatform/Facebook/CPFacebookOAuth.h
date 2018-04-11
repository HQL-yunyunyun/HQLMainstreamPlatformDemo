//
//  CPFacebookOAuth.h
//  GoCreate3.0
//
//  Created by 何启亮 on 2017/11/14.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <FBSDKCoreKit/FBSDKCoreKit.h>
#import "CPFacebookUploader.h"

/*
 Facebook 的授权应该是检测授权，当需要的权限没有，再去申请权限。
 Facebook的权限分为 read permission 和 publish permission，两者不能同时申请[loginWith(read/publish)Permission]，也不能在申请完一个类型之后，在block回调中调用另外一个类型的申请权限方法，也不能同时调用两个方法。
 */

static NSString *const FacebookAuthErrorDoMain = @"GoCreate.facebook.broadcastAuthorization.error.doMain";

// param key
static NSString *const FacebookBroadcastType_string = @"broadcastType";
static NSString *const FacebookBroadcast_id = @"broadcast_id";
static NSString *const FacebookBroadcast_description = @"broadcast_description";

// facebook privacy key
static NSString *const FacebookPublishPrivacyKey_EVERYONE = @"EVERYONE";
static NSString *const FacebookPublishPrivacyKey_ALL_FRIENDS = @"ALL_FRIENDS";
static NSString *const FacebookPublishPrivacyKey_FRIENDS_OF_FRIENDS = @"FRIENDS_OF_FRIENDS";
static NSString *const FacebookPublishPrivacyKey_CUSTOM = @"CUSTOM";
static NSString *const FacebookPublishPrivacyKey_SELF = @"SELF";

typedef void(^CPFacebookAuthCompletion)(FBSDKAccessToken *token, NSArray <NSString *>*grantedPermissions, NSArray <NSString *>*declinedPermissions, NSError *error);

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

//@property (assign, nonatomic) id <CPFacebookOAuthDelegate> delegate;

@property (strong, nonatomic, readonly) FBSDKAccessToken *authorization;

- (instancetype)initWithAuthorization:(FBSDKAccessToken *)authorization;

#pragma mark - auth method

/**
 申请权限

 @param controller presentController
 @param permissionsArray 需要申请的权限
 @param handler 回调
 */
- (void)doFacebookAuthWithPresentController:(UIViewController *)controller
                           permissionsArray:(NSArray <NSString *>*)permissionsArray
                                thenHandler:(CPFacebookAuthCompletion)handler;

/**
 通用的登录permission(public_profile, eamil)
 
 @return 权限
 */
+ (NSArray <NSString *>*)commonPermissions;

/**
 publish_actions permission 适用于 Broadcast 和 发布Facebook(视频、图片等)
 
 @return 权限
 */
+ (NSArray <NSString *>*)publishActionsPermissions;

/**
 小组管理的permission(user_managed_groups)
 
 @return 权限
 */
+ (NSArray <NSString *>*)groupPermissions;

/**
 检测是否有权限

 @param wantPermissions 被检测的权限
 @return 没有授权的权限
 */
- (NSArray <NSString *>*)checkPermissionWithWantPermissions:(NSArray <NSString *>*)wantPermissions;

/**
 调用logout --- 不会主动去接触权限
 */
- (void)cleanAppAuth;

#pragma mark -

/**
 将Facebook发布的隐私转换成string形式

 @param pricacyString pricacy string
 @param allowArray 在CUSTOM模式下允许的用户编号及好友编号(逗号隔开)
 @param denyArray 在CUSTOM模式下不允许的用户编号及好友编号(逗号隔开)
 @return string
 */
+ (NSString *)getPublishPrivacyStringWith:(NSString *)pricacyString allowArray:(NSArray <NSString *>*)allowArray denyArray:(NSArray <NSString *>*)denyArray;

#pragma mark - fetch user info

 /* // 回调获取的用户信息
  @{
       @"user_icon" : NSString,
       @"user_name" : NSString,
       @"user_id" : NSString,
      }
  */
    
/**
 获取Facebook的用户信息

 @param controller present controller
 @param handler 回调
 */
- (void)fetchUserInfoWithPresentController:(UIViewController *)controller completeHandler:(void(^)(FBSDKProfile *profile, NSError *error))handler;

#pragma mark - broadcast method

/*
 param = @{
 @"broadcastType" : FacebookBoradcastType,
 @"broadcast_id" : @"123456", // 需要和type相对应 --- publish和self使用的是user_id, group使用的是group_id
 @"broadcast_description" : @"abcdefg",
 }
 */

/**
 获取Broadcast URL --- 在获取前会检测权限

 @param param live param
 @param controller present controller
 @param handler 回调
 */
- (void)fetchFacebookBroadcastURLWithParam:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void(^)(NSString *broadcastURL, NSError *error))handler;

/**
 更新live description

 @param string description
 @param handler 回调
 */
- (void)updateBroadcastDescription:(NSString *)string completeHandler:(void(^)(NSError *error))handler;

/**
 获取Broadcast STATUS

 @param handler 回调
 */
- (void)fetchBroadcastStatusWithCompleteHandler:(void(^)(FacebookBroadcastStatus status, NSError *error))handler;

/**
 获取直播时的评论

 @param handler 回调
 */
- (void)fetchBroadcastCommentsWithCompleteHandler:(void(^)(NSArray *comments, NSError *error))handler;

/**
 获取Broadcast 相关的Info

 @param handler 回调
 */
- (void)fetchBroadcastInfoWithCompleteHandler:(void(^)(NSDictionary *dict, NSError *error))handler;

#pragma mark - search method

/*
 搜索当前只会搜索group
 当前只会持有一次搜索结果
 */

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

/**
 搜索小组的结果 --- 下一页

 @param controller presentController
 @param handler 回调
 */
- (void)searchGroupResultNextPageWithPresentController:(UIViewController *)controller completeHandler:(void(^)(NSArray <NSDictionary *>*groups, NSError *error))handler;

/**
 搜索小组的结果 --- 上一页

 @param controller presentController
 @param handler 回调
 */
- (void)searchGroupResultBeforePageWithPresentController:(UIViewController *)controller completeHandler:(void(^)(NSArray <NSDictionary *>*groups, NSError *error))handler;

/**
 搜索小组

 @param keyWord 关键字
 @param controller present Controller
 @param handler 回调
 */
- (void)searchGroupWithKeyWord:(NSString *)keyWord presentController:(UIViewController *)controller completeHandler:(void(^)(NSArray <NSDictionary *>*groups, NSError *error))handler;

/**
 搜索

 @param type 搜索的类型
 @param keyWord 关键字
 @param param param
 @param controller present Controller
 @param handler 回调
 */
- (void)searchKeyWordWithType:(FacebookSearchType)type keyWord:(NSString *)keyWord param:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void(^)(NSDictionary *dict, NSError *error))handler;

/**
 检查是否有该小组的权限

 @param group_id 小组的id
 @param controller present Controller
 @param handler 回调
 */
- (void)checkGroupPermissionsWithGroupID:(NSString *)group_id presentController:(UIViewController *)controller completeHandler:(void(^)(BOOL isPermissions))handler;

#pragma mark - broadcast

/*
 broadcast 的相关操作 --- 之前是在这个类里面完成所有直播相关的操作，现在改成只提供基础的方法，其他相关的逻辑都交给另外的类
 */

/**
 开始直播

 @param param 直播param
 @param controller present Controller
 @param handler 回调
 */
- (void)startBroadcastWithParam:(NSDictionary *)param presentController:(UIViewController *)controller completeHandler:(void(^)(NSString *broadcastURL, NSError *error))handler;

/**
 停止直播
 */
- (void)stopBroadcast;

/**
 停止直播相关的连接
 */
- (void)stopBroadcastConnection;

/*
 live video id 是Facebook更新 live 相关信息(description、comment)需要的id。
 Facebook 的 live 跟发布帖子一样。
 */

/**
 检测live video id 是否可用

 @param liveVideoID live video id
 @param handler 回调
 */
- (void)checkLiveVideoID:(NSString *)liveVideoID completeHandler:(void(^)(BOOL canUse, NSString *message))handler;

/**
 通过live video id 就开始直播

 @param liveVideoID live video id
 */
- (void)startBroadcastWithLiveVideoID:(NSString *)liveVideoID;

//- (void)autoFetchBroadcastComments;
//- (void)stopAutoFetchBroadcastComments;

//- (void)autoFetchBroadcastStatus;
//- (void)stopAutoFetchBroadcastStatus;

#pragma mark - upload method

/*
 param:
 videoURL : NSString
 publishParam : NSDictionary
 sendID : NSString
 resumeMediaId : NSString
 */

/**
 创建一个上传任务

 @param param param
 @param precentController present Controller
 @param uploadProgressHandler 上传中的回调
 @param completeHandler 上传完成的回调
 @return uploader
 */
- (CPFacebookUploader *)createVideoUploadTicketWithParam:(NSDictionary *)param
                                          precentController:(UIViewController *)precentController
                                          uploadProgressHandler:(CPUploaderProgressHandler)uploadProgressHandler
                                          completeHandler:(CPUploaderCompleteHandler)completeHandler;

@end

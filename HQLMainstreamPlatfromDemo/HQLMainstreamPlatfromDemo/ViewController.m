//
//  ViewController.m
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/1/13.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import "ViewController.h"
#import "CPPlatformAuthManager.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIButton *loginButton;
@property (weak, nonatomic) IBOutlet UIButton *uploadButton;
@property (weak, nonatomic) IBOutlet UIImageView *iconImage;
@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UIButton *cancelButton;

@property (strong, nonatomic) NSDictionary *facebookUserDict;

@property (nonatomic, strong) CPPlatformAuthManager *manager;
@property (nonatomic, strong) CPFacebookUploader *facebookUploader;

@property (assign, nonatomic) BOOL isRequesting;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
}

- (void)dealloc {
    PLog(@"dealloc ---> %@", NSStringFromClass([self class]));
}

#pragma mark - event

- (IBAction)loginButtonDidClick:(UIButton *)sender {
    
    if (self.isRequesting && !sender.isSelected) {
        return;
    }
    
    if (sender.isSelected) { // 登出
        [self.manager cleanAppAuthWithPlatformType:CPPlatformAuthType_Facebook];
        self.isRequesting = NO;
        self.nameLabel.text = @"Label";
    } else { // 登录
        self.isRequesting = YES;
        __weak typeof(self) _self = self;
        [self.manager fetchUserInfoWithPlatformType:CPPlatformAuthType_Facebook presentController:self completeHandler:^(NSDictionary *info, NSError *error) {
            _self.isRequesting = NO;
            if (error) {
                PLog(@"login error : %@", error);
                return;
            }
            _self.nameLabel.text = info[@"user_name"];
            _self.facebookUserDict = info;
            PLog(@"facebook user id %@", info[@"user_id"]);
            PLog(@"icon image url : %@", info[@"user_icon"]);
        }];
        
    }
    
    [sender setSelected:!sender.isSelected];
}

- (IBAction)uploadButtonDidClick:(UIButton *)sender {
    
    if (!self.manager.facebookAuthorization) {
        [self loginButtonDidClick:self.loginButton];
        return;
    }
    
    if (!self.facebookUploader) { // 新建任务
        
        NSString *userID = self.facebookUserDict[@"user_id"];
        if (userID.length <= 0) {
            return;
        }
        
        NSString *videoURL = [[NSBundle mainBundle] pathForResource:@"upload_test_video" ofType:@"MP4"];
        NSDictionary *dict = @{
                               @"title" : @"Video upload test",
                               @"description" : @"Video upload description",
                               @"privacy" : [CPFacebookOAuth getPublishPrivacyStringWith:FacebookPublishPrivacyKey_EVERYONE allowArray:nil denyArray:nil],
//                               @"resumeString" : @""
                               @"send_id" : userID,
                               };
        self.facebookUploader = [self.manager createVideoUploadTicketWithParam:dict platformType:CPPlatformAuthType_Facebook videoURL:videoURL presentController:self progressHandler:^(CPFacebookUploader *progressUploader, double uploadedPercent) {
            
            PLog(@"video id : %@, session_id : %@, send_id : %@", progressUploader.uploadInfoRecord.video_id, progressUploader.uploadInfoRecord.session_id, progressUploader.uploadInfoRecord.sendID);
            PLog(@"percent : %.2f%%", uploadedPercent);
            
        } completeHandler:^(CPFacebookUploader * completeUploader, NSError *error, NSDictionary *userDict) {
           
            PLog(@"video id : %@, session_id : %@, send_id : %@", completeUploader.uploadInfoRecord.video_id, completeUploader.uploadInfoRecord.session_id, completeUploader.uploadInfoRecord.sendID);
            PLog(@"error : %@, userDict : %@", error, userDict);
            
        }];
        
        [sender setTitle:@"pause" forState:UIControlStateNormal];
        
    } else {
        
        if (self.facebookUploader.isPause) {
            [self.facebookUploader resume];
            [sender setTitle:@"pause" forState:UIControlStateNormal];
        } else {
            [self.facebookUploader pause];
            [sender setTitle:@"resume" forState:UIControlStateNormal];
        }
        
    }
    
}

- (IBAction)cancelButtonDidClick:(UIButton *)sender {
    if (self.facebookUploader) {
        [self.facebookUploader cancel];
        self.facebookUploader = nil;
        [sender setTitle:@"upload" forState:UIControlStateNormal];
    }
}

#pragma mark - getter

- (CPPlatformAuthManager *)manager {
    if (!_manager) {
        _manager = [CPPlatformAuthManager shareManager];
    }
    return _manager;
}

@end

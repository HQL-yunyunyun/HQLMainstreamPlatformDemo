//
//  CPFacebookUploadInfoRecord.m
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/26.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import "CPFacebookUploadInfoRecord.h"

@implementation CPFacebookUploadInfoRecord

- (instancetype)init {
    if (self = [super init]) {
        self.userID = @"";
        self.video_id = @"";
        self.session_id = @"";
        self.start_offset = 0;
        self.end_offset = 0;
        self.sendID = @"";
    }
    return self;
}

@end

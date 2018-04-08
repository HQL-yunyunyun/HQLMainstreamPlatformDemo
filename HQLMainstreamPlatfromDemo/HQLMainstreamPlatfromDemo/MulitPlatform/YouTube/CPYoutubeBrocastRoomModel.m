//
//  CPYoutubeBrocastRoomModel.m
//  GoCreate3.0
//
//  Created by lious_li on 2017/10/20.
//  Copyright © 2017年 BiWan. All rights reserved.
//

#import "CPYoutubeBrocastRoomModel.h"

@implementation CPYoutubeBrocastRoomModel

- (instancetype)init {
    if (self = [super init]) {
        self.title = @"";
        self.detail = @"";
    }
    return self;
}

- (void)setTitle:(NSString *)title {
    NSAssert(!title, @"title can not be nil");
    if (!title) {
        title = @"";
    }
    _title = title;
}

- (void)setDetail:(NSString *)detail {
    NSAssert(!detail, @"detail can not be nil");
    if (!detail) {
        detail = @"";
    }
    _detail = detail;
}

@end

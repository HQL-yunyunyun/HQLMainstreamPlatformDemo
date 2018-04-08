//
//  CPTwitterUploadInfoRecord.m
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/3/15.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import "CPTwitterUploadInfoRecord.h"

#define kUploadChunkBytes (4 * 1024 * 1024)

@implementation CPTwitterUploadInfoRecord

- (instancetype)init {
    if (self = [super init]) {
        self.userID = @"";
        self.media_id = @"";
        self.uploaded_bytes = 0;
        self.chunk_bytes = kUploadChunkBytes;
        self.createDate = [NSDate date];
        self.expires_after_secs = 0;
    }
    return self;
}

- (NSInteger)chunk_bytes {
    return kUploadChunkBytes;
}

- (BOOL)taskIsExpires {
    return ([self.createDate timeIntervalSinceDate:[NSDate date]] >= self.expires_after_secs);
}

@end

//
//  AppDelegate.h
//  HQLMainstreamPlatfromDemo
//
//  Created by 何启亮 on 2018/1/13.
//  Copyright © 2018年 topCreator. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <OIDAuthorizationService.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property(nonatomic, strong, nullable) id<OIDAuthorizationFlowSession> currentAuthorizationFlow;

@end


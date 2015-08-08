//
//  AppDelegate.h
//  MTerminal
//
//  Created by lijunge on 15/8/8.
//  Copyright © 2015年 A. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MTController.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate> {
    MTController* controller;
}

@property (strong, nonatomic) UIWindow *window;


@end


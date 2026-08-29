#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
@property (nonatomic, assign, getter=isExpanded) BOOL expanded;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
- (void)cb_handleModuleExpand:(NSNotification *)notification;
- (void)cb_handleModuleDismiss:(NSNotification *)notification;
@end

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;

- (void)layoutSubviews {
    %orig;

    // 1. 非低电量模块直接隐藏
    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) {
            self.cbPercentLabel.hidden = YES;
        }
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    // 2. 尺寸异常或处于展开态，隐藏
    BOOL isExpanded = NO;
    if ([self respondsToSelector:@selector(isExpanded)]) {
        isExpanded = self.isExpanded;
    }

    if (isExpanded || width > 85.0f || height > 85.0f || width <= 0 || height <= 0) {
        if (self.cbPercentLabel) {
            self.cbPercentLabel.hidden = YES;
        }
        return;
    }

    // 3. 正常创建并布局 Label（9.5pt Regular）
    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 20.0f, width, 12.0f)];
        lab.font = [UIFont systemFontOfSize:9.5f weight:UIFontWeightRegular];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [self addSubview:lab];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        
        // 监听电量与低电量开关状态
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercentText)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
                                                   
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercentText)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil];

        // 核心修复：监听控制中心二级菜单展开/收起系统通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_handleModuleExpand:)
                                                     name:@"CCUIExpandedModuleWillPresentNotification"
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_handleModuleDismiss:)
                                                     name:@"CCUIExpandedModuleWillDismissNotification"
                                                   object:nil];
    } else {
        self.cbPercentLabel.hidden = NO;
        self.cbPercentLabel.frame = CGRectMake(0, height - 20.0f, width, 12.0f);
    }

    [self bringSubviewToFront:self.cbPercentLabel];
    [self cb_updatePercentText];
}

%new
- (void)cb_handleModuleExpand:(NSNotification *)notification {
    // 只要有任何模块（包括低电量自己或其他模块）展开二级菜单，立刻隐藏百分比
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cbPercentLabel) {
            self.cbPercentLabel.hidden = YES;
        }
    });
}

%new
- (void)cb_handleModuleDismiss:(NSNotification *)notification {
    // 二级菜单关闭，恢复显示百分比
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cbPercentLabel && [self cb_isLowPowerModule]) {
            self.cbPercentLabel.hidden = NO;
            [self cb_updatePercentText];
        }
    });
}

%new
- (BOOL)cb_isLowPowerModule {
    if ([self respondsToSelector:@selector(moduleIdentifier)]) {
        NSString *modID = [self performSelector:@selector(moduleIdentifier)];
        if ([modID isEqualToString:@"com.apple.control-center.LowPowerModule"] || 
            [modID containsString:@"LowPowerModule"]) {
            return YES;
        }
    }

    UIResponder *responder = self;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"CCUILowPowerModeModule"]) {
            return YES;
        }
        responder = [responder nextResponder];
    }

    return NO;
}

%new
- (void)cb_updatePercentText {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.cbPercentLabel) return;

        // 1. 获取并刷新电量百分比
        float level = [UIDevice currentDevice].batteryLevel;
        int percent = (level >= 0) ? (int)round(level * 100.0f) : 100;
        self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];

        // 2. 文字颜色跟随低电量模式状态反转
        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        if (isLowPowerMode) {
            self.cbPercentLabel.textColor = [UIColor blackColor];
        } else {
            self.cbPercentLabel.textColor = [UIColor whiteColor];
        }
    });
}

%end

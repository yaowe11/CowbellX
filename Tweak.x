#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
@property (nonatomic, readonly) UIView *contentView; // 原生存放图标的子视图
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
@end

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;

- (void)layoutSubviews {
    %orig;

    // 1. 非低电量模块直接移除/隐藏 Label
    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) {
            self.cbPercentLabel.hidden = YES;
        }
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    // 尺寸异常直接隐藏
    if (width <= 0 || height <= 0 || width > 85.0f || height > 85.0f) {
        if (self.cbPercentLabel) {
            self.cbPercentLabel.hidden = YES;
        }
        return;
    }

    // 2. 挂载节点关键修复：优先挂载到系统原生的 contentView 上！
    // 这样当二级菜单展开时，系统隐藏 contentView，Label 就会跟随自动隐藏，不会留残影
    UIView *targetContainer = [self respondsToSelector:@selector(contentView)] && self.contentView ? self.contentView : self;

    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 20.0f, width, 12.0f)];
        lab.font = [UIFont systemFontOfSize:9.5f weight:UIFontWeightRegular];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [targetContainer addSubview:lab];

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
    } else {
        // 如果之前挂错在 self 上，重新移到 targetContainer 里
        if (self.cbPercentLabel.superview != targetContainer) {
            [self.cbPercentLabel removeFromSuperview];
            [targetContainer addSubview:self.cbPercentLabel];
        }
        self.cbPercentLabel.hidden = NO;
        self.cbPercentLabel.frame = CGRectMake(0, height - 20.0f, width, 12.0f);
    }

    [targetContainer bringSubviewToFront:self.cbPercentLabel];
    [self cb_updatePercentText];
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

        // 获取并刷新电量百分比
        float level = [UIDevice currentDevice].batteryLevel;
        int percent = (level >= 0) ? (int)round(level * 100.0f) : 100;
        self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];

        // 文字颜色跟随低电量模式状态反转
        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        if (isLowPowerMode) {
            self.cbPercentLabel.textColor = [UIColor blackColor];
        } else {
            self.cbPercentLabel.textColor = [UIColor whiteColor];
        }
    });
}

%end

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - Hook CCUICAPackageView (核心逻辑)

@interface CCUICAPackageView : UIView
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (BOOL)cb_isLowPowerModule;
- (void)cb_updateBatteryState;
@end

%hook CCUICAPackageView

%property (nonatomic, strong) UILabel *cbPercentLabel;

- (void)didMoveToWindow {
    %orig;
    if (self.window && [self cb_isLowPowerModule]) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        
        // 监听电量与低电量模式变化
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceBatteryLevelDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSProcessInfoPowerStateDidChangeNotification object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(cb_updateBatteryState) 
                                                     name:UIDeviceBatteryLevelDidChangeNotification 
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(cb_updateBatteryState) 
                                                     name:NSProcessInfoPowerStateDidChangeNotification 
                                                   object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerModule]) return;

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    // 1. 确保百分比 Label 存在并处于完美位置
    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] init];
        // 使用与控制中心完全一致的系统 Medium 字体
        lab.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;
        self.cbPercentLabel = lab;
        [self addSubview:lab];
    }

    // 2. 布局调整：把 PackageView 调整回原始中心，Label 放在下方
    // 计算百分比 Label 位置 (居中，距底部保留合适间距)
    CGFloat labelH = 14.0f;
    self.cbPercentLabel.frame = CGRectMake(0, h - labelH - 2.0f, w, labelH);
    [self bringSubviewToFront:self.cbPercentLabel];

    // 3. 刷新电量数据与颜色
    [self cb_updateBatteryState];
}

%new
- (BOOL)cb_isLowPowerModule {
    UIResponder *responder = self;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"LowPower"]) {
            return YES;
        }
        responder = responder.nextResponder;
    }
    return NO;
}

%new
- (void)cb_updateBatteryState {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;
        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;

        // A. 注入 CAPackage 内部电量填充
        @try {
            [strongSelf.layer setValue:@(level) forKeyPath:@"publishedObjects.fill.strokeEnd"];
        } @catch (NSException *e) {}

        // B. 刷新百分比数字与文字颜色
        if (strongSelf.cbPercentLabel) {
            int percent = (int)round(level * 100.0f);
            strongSelf.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];
            
            // 开启低电量模式时为黑色，未开启时为白色
            UIColor *textColor = isLowPowerMode ? [UIColor blackColor] : [UIColor whiteColor];
            strongSelf.cbPercentLabel.textColor = textColor;
        }
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

%end

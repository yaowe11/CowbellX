#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

extern NSString* const kCAFilterDestOut;

@interface CALayer (Private)
@property (nonatomic, retain) NSString *compositingFilter;
@property (nonatomic, assign) BOOL allowsGroupBlending;
@property (nonatomic, assign) BOOL allowsGroupOpacity;
@end

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@property (nonatomic, strong) UILabel *cb_percentLabel;
@end

%hook CCUICAPackageView

%property (nonatomic, strong) UILabel *cb_percentLabel;

- (void)layoutSubviews {
    %orig;

    // 1. 精准判断：只处理低电量模块的 CAPackage
    NSString *pkgName = @"";
    if ([self respondsToSelector:@selector(packageName)]) {
        pkgName = self.packageName ? self.packageName : @"";
    }

    if (![pkgName containsString:@"LowPower"] && ![pkgName containsString:@"Battery"]) {
        return;
    }

    // 2. 初始化镂空 Label
    if (!self.cb_percentLabel) {
        UILabel *label = [[UILabel alloc] init];
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:9.5f weight:UIFontWeightMedium];
        label.textAlignment = NSTextAlignmentCenter;
        
        // 关键点 1：开启局部组隔离，防止 DestOut 滤镜污染控制中心其他组件（如亮度/音量条）
        self.layer.allowsGroupBlending = NO;
        label.layer.allowsGroupOpacity = YES;

        self.cb_percentLabel = label;
        [self addSubview:self.cb_percentLabel];

        // 监听系统电量广播
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercent)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercent)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil];
        [self cb_updatePercent];
    }

    // 3. 实时调整位置与滤镜
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w > 0 && h > 0) {
        [self.cb_percentLabel sizeToFit];
        CGFloat lblW = self.cb_percentLabel.bounds.size.width;
        CGFloat lblH = self.cb_percentLabel.bounds.size.height;
        
        // 置于原生电池图标正下方
        self.cb_percentLabel.frame = CGRectMake((w - lblW) / 2.0f, h * 0.68f, lblW, lblH);

        // 关键点 2：根据当前低电量开关状态应用 DestOut 滤镜
        BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        if (isLowPower) {
            // 黄色背景高亮时：直接挖空文字区域，露出底层颜色
            self.cb_percentLabel.layer.compositingFilter = kCAFilterDestOut;
        } else {
            // 未激活时：清除滤镜，正常显示白色文字
            self.cb_percentLabel.layer.compositingFilter = nil;
        }
    }
}

%new
- (void)cb_updatePercent {
    dispatch_async(dispatch_get_main_queue(), ^{
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;
        
        if (self.cb_percentLabel) {
            self.cb_percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)round(level * 100)];
            [self setNeedsLayout];
        }
    });
}

%end

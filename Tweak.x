#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface CCUIRoundButton : UIView
@property (nonatomic, strong) UIImageView *cbCustomBatteryImageView;
- (void)cb_updateDynamicBattery;
- (BOOL)cb_isLowPowerButton;
@end

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
@end

#pragma mark - Hook 按钮（处理 100% 原生图标 + 1% 动态 Mask 裁剪）

%hook CCUIRoundButton

%property (nonatomic, strong) UIImageView *cbCustomBatteryImageView;

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerButton]) return;

    // 1. 彻底隐藏所有原生子控件（包括 iOS 动画 Package），防止重影
    for (UIView *sub in self.subviews) {
        if (sub != self.cbCustomBatteryImageView) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
    }

    // 2. 初始化自定义的图片 View（直接采用系统官方原生 battery.100 SF Symbol）
    if (!self.cbCustomBatteryImageView) {
        UIImageView *imgView = [[UIImageView alloc] init];
        imgView.contentMode = UIViewContentModeScaleAspectFit;
        imgView.userInteractionEnabled = NO;

        // 加载 100% 官方原生的 SF Symbol 图标，保证尺寸线宽和控制中心完全一致
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
        UIImage *nativeSymbol = [UIImage systemImageNamed:@"battery.100" withConfiguration:config];
        imgView.image = [nativeSymbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        imgView.tintColor = [UIColor whiteColor];

        // 精确居中对齐
        imgView.bounds = CGRectMake(0, 0, 28, 14);
        imgView.center = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0 - 2);

        self.cbCustomBatteryImageView = imgView;
        [self addSubview:imgView];
    } else {
        self.cbCustomBatteryImageView.center = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0 - 2);
    }

    // 3. 刷新 1% 动态电量蒙版
    [self cb_updateDynamicBattery];
}

%new
- (void)cb_updateDynamicBattery {
    if (!self.cbCustomBatteryImageView) return;

    [self bringSubviewToFront:self.cbCustomBatteryImageView];

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;

    // 根据开关状态调整图标颜色
    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    self.cbCustomBatteryImageView.tintColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];

    // 动态生成 Mask 遮罩，实现 1% 级别的平滑填充裁剪
    // 保留左侧电池框（约 15% 宽度），右侧 85% 宽度根据电量 0.0~1.0 精细计算
    CGFloat totalW = self.cbCustomBatteryImageView.bounds.size.width;
    CGFloat totalH = self.cbCustomBatteryImageView.bounds.size.height;

    CGFloat minBorderW = totalW * 0.15f; 
    CGFloat fillableW = totalW - minBorderW;
    CGFloat visibleW = minBorderW + (fillableW * level);

    CAShapeLayer *maskLayer = (CAShapeLayer *)self.cbCustomBatteryImageView.layer.mask;
    if (![maskLayer isKindOfClass:[CAShapeLayer class]]) {
        maskLayer = [CAShapeLayer layer];
        self.cbCustomBatteryImageView.layer.mask = maskLayer;
    }

    UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, visibleW, totalH)];
    maskLayer.path = path.CGPath;
}

%new
- (BOOL)cb_isLowPowerButton {
    UIResponder *responder = self;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"LowPower"]) {
            return YES;
        }
        responder = [responder nextResponder];
    }
    return NO;
}

%end

#pragma mark - Hook 容器（处理底部百分比 Label）

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) self.cbPercentLabel.hidden = YES;
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    if (width <= 0 || height <= 0 || width > 100 || height > 100) return;

    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 18, width, 12)];
        lab.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [self addSubview:lab];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercentText)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
                                                   
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercentText)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil];
    } else {
        self.cbPercentLabel.hidden = NO;
        self.cbPercentLabel.frame = CGRectMake(0, height - 18, width, 12);
    }

    [self bringSubviewToFront:self.cbPercentLabel];
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

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        int percent = (level >= 0) ? (int)round(level * 100.0f) : 100;

        self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];
        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        self.cbPercentLabel.textColor = isLowPowerMode ? [UIColor blackColor] : [UIColor whiteColor];
    });
}

%end

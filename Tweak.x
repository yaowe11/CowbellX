#import <UIKit/UIKit.h>

@interface CCUIRoundButtonViewController : UIViewController
@property (nonatomic, strong) UILabel *cb_percentLabel;
@property (nonatomic, strong) UIImageView *cb_batteryIconView;
- (void)cb_updatePercent;
@end

%hook CCUIRoundButtonViewController

%property (nonatomic, strong) UILabel *cb_percentLabel;
%property (nonatomic, strong) UIImageView *cb_batteryIconView;

- (void)viewDidLoad {
    %orig;

    NSString *className = NSStringFromClass([self class]);
    NSString *title = [self respondsToSelector:@selector(title)] ? [self performSelector:@selector(title)] : @"";
    BOOL isLowPower = [className containsString:@"LowPower"] || [title containsString:@"低电量"];

    if (isLowPower && !self.cb_percentLabel) {
        // 1. 创建动态电池 SF Symbol 图标
        self.cb_batteryIconView = [[UIImageView alloc] init];
        self.cb_batteryIconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.view addSubview:self.cb_batteryIconView];

        // 2. 创建电量/容量百分比文字
        self.cb_percentLabel = [[UILabel alloc] init];
        self.cb_percentLabel.font = [UIFont systemFontOfSize:9.0f weight:UIFontWeightBold];
        self.cb_percentLabel.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:self.cb_percentLabel];

        // 监听电量广播
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
}

- (void)viewDidLayoutSubviews {
    %orig;

    if (self.cb_percentLabel && self.cb_batteryIconView) {
        CGFloat w = self.view.bounds.size.width;
        CGFloat h = self.view.bounds.size.height;

        if (w > 0 && h > 0) {
            BOOL isSelected = [NSProcessInfo processInfo].isLowPowerModeEnabled;
            UIColor *themeColor = isSelected ? [UIColor colorWithWhite:0.1 alpha:1.0] : [UIColor whiteColor];

            // 布局电池图标（置于上半部分）
            self.cb_batteryIconView.frame = CGRectMake((w - 24.0f) / 2.0f, h * 0.22f, 24.0f, 14.0f);
            self.cb_batteryIconView.tintColor = themeColor;

            // 布局文字（置于图标下方）
            [self.cb_percentLabel sizeToFit];
            CGFloat lblW = self.cb_percentLabel.bounds.size.width;
            CGFloat lblH = self.cb_percentLabel.bounds.size.height;
            self.cb_percentLabel.frame = CGRectMake((w - lblW) / 2.0f, h * 0.65f, lblW, lblH);
            self.cb_percentLabel.textColor = themeColor;
        }
    }
}

%new
- (void)cb_updatePercent {
    dispatch_async(dispatch_get_main_queue(), ^{
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;
        int percent = (int)round(level * 100);

        if (self.cb_batteryIconView && self.cb_percentLabel) {
            // 根据百分比选择最匹配的原生 SF Symbol 图标名
            NSString *symbolName = @"battery.100";
            if (percent <= 10) {
                symbolName = @"battery.0";
            } else if (percent <= 35) {
                symbolName = @"battery.25";
            } else if (percent <= 65) {
                symbolName = @"battery.50";
            } else if (percent <= 85) {
                symbolName = @"battery.75";
            }

            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
            self.cb_batteryIconView.image = [UIImage systemImageNamed:symbolName withConfiguration:config];

            // 显示电量与容量（以 3200mAh 为例）
            int mAh = (int)round(level * 3200);
            self.cb_percentLabel.text = [NSString stringWithFormat:@"%d%% · %dmAh", percent, mAh];

            [self.view setNeedsLayout];
        }
    });
}

%end

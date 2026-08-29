#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

extern NSString* const kCAFilterDestOut;

@interface CCUIToggleViewController : UIViewController
@property (nonatomic, assign) BOOL cb_isLowPowerModule;
@property (nonatomic, strong) UILabel *cb_percentLabel;
@property (nonatomic, strong) id module;
- (BOOL)isSelected;
@end

%hook CCUIToggleViewController

%property (nonatomic, assign) BOOL cb_isLowPowerModule;
%property (nonatomic, strong) UILabel *cb_percentLabel;

- (void)viewDidLoad {
    %orig;

    // 1. 适配 iOS 16 的模块判定：同时检查模块类名和控制器类名
    NSString *moduleClass = NSStringFromClass([self.module class]);
    NSString *selfClass = NSStringFromClass([self class]);
    
    if ([moduleClass containsString:@"LowPower"] || [selfClass containsString:@"LowPower"]) {
        self.cb_isLowPowerModule = YES;
    }

    if (self.cb_isLowPowerModule && !self.cb_percentLabel) {
        UILabel *label = [[UILabel alloc] init];
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:9.3f weight:UIFontWeightRegular];
        label.textAlignment = NSTextAlignmentCenter;
        
        // 关键：iOS 16 的图层混合属性
        label.layer.allowsGroupBlending = NO;
        label.layer.allowsGroupOpacity = YES;
        
        self.cb_percentLabel = label;
        [self.view addSubview:self.cb_percentLabel];
        
        // 监听电量广播，实时更新百分比
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updateBatteryPercent)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
    }
}

%new
- (void)cb_updateBatteryPercent {
    if (!self.cb_isLowPowerModule || !self.cb_percentLabel) return;

    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;

    dispatch_async(dispatch_get_main_queue(), ^{
        self.cb_percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)round(level * 100)];
        [self.cb_percentLabel sizeToFit];
        [self.view setNeedsLayout];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (self.cb_isLowPowerModule) {
        [self cb_updateBatteryPercent];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (self.cb_isLowPowerModule && self.cb_percentLabel) {
        // 调整位置：置于视图下方（约 70% 高度处）
        CGFloat w = self.view.bounds.size.width;
        CGFloat h = self.view.bounds.size.height;
        CGFloat lblW = self.cb_percentLabel.bounds.size.width;
        CGFloat lblH = self.cb_percentLabel.bounds.size.height;
        
        if (w > 0 && h > 0) {
            self.cb_percentLabel.frame = CGRectMake((w - lblW) / 2.0f, h * 0.70f, lblW, lblH);
        }
    }
}

- (void)refreshState {
    %orig;
    if (!self.cb_isLowPowerModule || !self.cb_percentLabel) return;

    // 2. 状态切换时的滤镜响应
    BOOL selected = NO;
    if ([self respondsToSelector:@selector(isSelected)]) {
        selected = [self isSelected];
    } else if ([self.module respondsToSelector:@selector(isSelected)]) {
        selected = [self.module isSelected];
    }

    if (selected) {
        // 激活状态（黄色背景）：使用 DestOut 滤镜把文字区域镂空（变黑）
        self.cb_percentLabel.layer.compositingFilter = kCAFilterDestOut;
    } else {
        // 未激活状态（灰色背景）：清除滤镜，显示正常白色文字
        self.cb_percentLabel.layer.compositingFilter = nil;
    }
}

- (void)dealloc {
    if (self.cb_isLowPowerModule) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
    %orig;
}

%end

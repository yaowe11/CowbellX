#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

extern NSString* const kCAFilterDestOut;

// 1. 补全 CALayer 私有属性声明
@interface CALayer (Private)
@property (nonatomic, assign) BOOL allowsGroupBlending;
@property (nonatomic, assign) BOOL allowsGroupOpacity;
@property (nonatomic, retain) NSString *compositingFilter;
@end

// 2. 在 @interface 中添加 %new 方法的声明
@interface CCUIToggleViewController : UIViewController
@property (nonatomic, assign) BOOL cb_isLowPowerModule;
@property (nonatomic, strong) UILabel *cb_percentLabel;
@property (nonatomic, strong) id module;
- (BOOL)isSelected;
- (void)cb_updateBatteryPercent; // <-- 加上这行声明
@end

%hook CCUIToggleViewController

%property (nonatomic, assign) BOOL cb_isLowPowerModule;
%property (nonatomic, strong) UILabel *cb_percentLabel;

- (void)viewDidLoad {
    %orig;

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
        
        label.layer.allowsGroupBlending = NO;
        label.layer.allowsGroupOpacity = YES;
        
        self.cb_percentLabel = label;
        [self.view addSubview:self.cb_percentLabel];
        
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

    BOOL selected = NO;
    if ([self respondsToSelector:@selector(isSelected)]) {
        selected = [self isSelected];
    } else if ([self.module respondsToSelector:@selector(isSelected)]) {
        selected = [self.module isSelected];
    }

    if (selected) {
        self.cb_percentLabel.layer.compositingFilter = kCAFilterDestOut;
    } else {
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

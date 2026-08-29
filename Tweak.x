#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
- (BOOL)cb_isLowPowerModule;
- (UILabel *)cb_findNativeLabelInView:(UIView *)view;
- (void)cb_updateNativeLabel;
@end

%hook CCUIContentModuleContainerView

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerModule]) return;

    // 找到原生模块内部的文本 Label
    UILabel *nativeLabel = [self cb_findNativeLabelInView:self];
    if (nativeLabel) {
        // 1. 设置字体风格（9.5pt Regular）
        nativeLabel.font = [UIFont systemFontOfSize:9.5f weight:UIFontWeightRegular];
        
        // 2. 开启电量监听
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceBatteryLevelDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updateNativeLabel)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
                                                   
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSProcessInfoPowerStateDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updateNativeLabel)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil];

        [self cb_updateNativeLabel];
    }
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
- (UILabel *)cb_findNativeLabelInView:(UIView *)view {
    if ([view isKindOfClass:[UILabel class]]) {
        return (UILabel *)view;
    }
    for (UIView *subview in view.subviews) {
        UILabel *found = [self cb_findNativeLabelInView:subview];
        if (found) return found;
    }
    return nil;
}

%new
- (void)cb_updateNativeLabel {
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *nativeLabel = [self cb_findNativeLabelInView:self];
        if (!nativeLabel) return;

        // 1. 获取并更新百分比文本
        float level = [UIDevice currentDevice].batteryLevel;
        int percent = (level >= 0) ? (int)round(level * 100.0f) : 100;
        nativeLabel.text = [NSString stringWithFormat:@"%d%%", percent];

        // 2. 补回颜色自动反转逻辑（开启低电量黄背景时变黑字，未开启圆圈黑背景时变白字）
        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        if (isLowPowerMode) {
            nativeLabel.textColor = [UIColor blackColor];
        } else {
            nativeLabel.textColor = [UIColor whiteColor];
        }
    });
}

%end

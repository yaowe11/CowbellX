#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CCUICAPackageView : UIView
- (BOOL)cb_isLowPowerPackage;
- (void)cb_updateBatteryFillLayer;
@end

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
@end

#pragma mark - 1. 动态缩放原生 CAPackage 内部填充 Layer

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    if ([self cb_isLowPowerPackage]) {
        [self cb_updateBatteryFillLayer];
    }
}

%new
- (BOOL)cb_isLowPowerPackage {
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

%new
- (void)cb_updateBatteryFillLayer {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;

        // 递归查找名为 Fill / Level / Battery 的内部子图层
        NSMutableArray *nodes = [NSMutableArray arrayWithObject:self.layer];
        while (nodes.count > 0) {
            CALayer *layer = [nodes firstObject];
            [nodes removeObjectAtIndex:0];

            NSString *name = layer.name.lowercaseString;
            // 锁定原生 CAPackage 里的电量填充图层
            if ([name containsString:@"fill"] || [name containsString:@"level"] || [name containsString:@"body"]) {
                // 恢复默认矩阵后，按电量比例横向缩放 (X轴)
                layer.transform = CATransform3DIdentity;
                layer.transform = CATransform3DMakeScale(level, 1.0, 1.0);
            }

            if (layer.sublayers.count > 0) {
                [nodes addObjectsFromArray:layer.sublayers];
            }
        }
    });
}

%end

#pragma mark - 2. 底部百分比 Label

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

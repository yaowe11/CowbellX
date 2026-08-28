#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CAStateController : NSObject
- (void)setState:(id)state ofLayer:(CALayer *)layer transitionSpeed:(float)speed transitionDuration:(double)duration;
@end

@interface CCUICAPackageView : UIView
@property (nonatomic, strong) CAStateController *stateController;
- (BOOL)cb_isLowPowerPackage;
- (void)cb_updateStateProgress;
@end

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
@end

#pragma mark - 1. 控制 CAStateController 动画进度（平滑改变内部填充）

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    if ([self cb_isLowPowerPackage]) {
        [self cb_updateStateProgress];
    }
}

- (void)setStateName:(NSString *)stateName {
    %orig;

    if ([self cb_isLowPowerPackage]) {
        [self cb_updateStateProgress];
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
- (void)cb_updateStateProgress {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;

        // 清理之前残留的 mask（防止之前代码的影响）
        if (self.layer.mask) {
            self.layer.mask = nil;
        }

        // 遍历 Package 内部所有的 CALayer 动画，定位关键帧动画并控制 timeOffset
        NSMutableArray *queue = [NSMutableArray arrayWithObject:self.layer];
        while (queue.count > 0) {
            CALayer *ly = [queue firstObject];
            [queue removeObjectAtIndex:0];

            // 如果该图层包含 Key 动画
            NSArray *animationKeys = [ly animationKeys];
            if (animationKeys.count > 0) {
                for (NSString *key in animationKeys) {
                    CAAnimation *anim = [ly animationForKey:key];
                    if (anim) {
                        // 暂停当前 layer 自动播放，手动调整时间偏移量
                        ly.speed = 0.0;
                        CFTimeInterval duration = anim.duration > 0 ? anim.duration : 1.0;
                        // 将 batteryLevel (0.0~1.0) 映射到关键帧动画时间点
                        ly.timeOffset = level * duration;
                    }
                }
            }

            if (ly.sublayers.count > 0) {
                [queue addObjectsFromArray:ly.sublayers];
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

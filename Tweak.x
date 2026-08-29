#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
- (void)cb_updateNativeIconFillWithLevel:(float)level inView:(UIView *)parentView;
@end

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;

- (void)layoutSubviews {
    %orig;

    // 1. 非低电量模块直接隐藏并返回
    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) {
            self.cbPercentLabel.hidden = YES;
        }
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    if (width <= 0 || height <= 0 || width > 100 || height > 100) return;

    // 2. 电池图标完全保持原生位置，不动它
    for (UIView *subview in self.subviews) {
        if (subview != self.cbPercentLabel) {
            subview.transform = CGAffineTransformIdentity;
        }
    }

    // 3. 保持你调好的百分比 Label 位置（Y轴 height - 22，字体大小 10 Bold）
    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 22, width, 12)];
        lab.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [self addSubview:lab];

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
        self.cbPercentLabel.hidden = NO;
        self.cbPercentLabel.frame = CGRectMake(0, height - 22, width, 12);
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
        responder = responder.nextResponder;
    }

    return NO;
}

%new
- (void)cb_updatePercentText {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1. 获取电量数值 (0.0 ~ 1.0)
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f; // 防护：未开启或读取失败时按100%算

        // 2. 刷新百分比文字与颜色（保持你原有的文字逻辑）
        if (self.cbPercentLabel) {
            int percent = (int)round(level * 100.0f);
            self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];

            BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
            if (isLowPowerMode) {
                self.cbPercentLabel.textColor = [UIColor blackColor];
            } else {
                self.cbPercentLabel.textColor = [UIColor whiteColor];
            }
        }

        // 3. 让原生的 CA 矢量电池图标按百分比实时填充
        [self cb_updateNativeIconFillWithLevel:level inView:self];
    });
}

%new
- (void)cb_updateNativeIconFillWithLevel:(float)level inView:(UIView *)parentView {
    if (!parentView) return;

    // 先尝试通过 CAPackage 系统的 KeyPath 直接注入
    @try {
        [parentView.layer setValue:@(level) forKeyPath:@"publishedObjects.fill.strokeEnd"];
    } @catch (NSException *e) {}

    // 递归遍历该 View 下的所有 CALayer，精确定位到电池内部的 Fill 图层
    NSMutableArray *layersToVisit = [NSMutableArray arrayWithObject:parentView.layer];
    while (layersToVisit.count > 0) {
        CALayer *currentLayer = [layersToVisit firstObject];
        [layersToVisit removeObjectAtIndex:0];

        NSString *layerName = currentLayer.name.lowercaseString;
        
        // 系统原生低电量 CAPackage 中，内部填充图层的 Name 通常包含 "fill" 或 "level"
        if (layerName && ([layerName containsString:@"fill"] || [layerName containsString:@"level"]) && ![layerName containsString:@"body"] && ![layerName containsString:@"border"]) {
            
            // 如果是 CAShapeLayer
            if ([currentLayer isKindOfClass:[CAShapeLayer class]]) {
                ((CAShapeLayer *)currentLayer).strokeEnd = level;
            } else {
                // 如果是普通 CALayer，调整锚点为左中，进行 X 轴百分比缩放
                if (currentLayer.anchorPoint.x != 0) {
                    CGRect oldFrame = currentLayer.frame;
                    currentLayer.anchorPoint = CGPointMake(0, 0.5);
                    currentLayer.frame = oldFrame;
                }
                currentLayer.transform = CATransform3DMakeScale(level, 1.0, 1.0);
            }
        }

        if (currentLayer.sublayers.count > 0) {
            [layersToVisit addObjectsFromArray:currentLayer.sublayers];
        }
    }

    // 递归查找子视图（防层级嵌套）
    for (UIView *subview in parentView.subviews) {
        if (subview != self.cbPercentLabel) {
            [self cb_updateNativeIconFillWithLevel:level inView:subview];
        }
    }
}

%end

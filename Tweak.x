#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
- (void)cb_updateNativeBatteryFillInView:(UIView *)parentView level:(float)level;
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

    // 3. 完全保留你调好的百分比 Label 布局
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
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;

        // 1. 获取并刷新电量百分比文字
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

        // 2. 递归寻找原生 PackageView 中的电池填充 Layer，并改变其水平缩放
        [self cb_updateNativeBatteryFillInView:self level:level];
    });
}

%new
- (void)cb_updateNativeBatteryFillInView:(UIView *)parentView level:(float)level {
    if (!parentView) return;

    // 递归遍历子 View 和 Layer 树
    for (UIView *subview in parentView.subviews) {
        if (subview == self.cbPercentLabel) continue;

        // 找到 CAPackageView 或带有矢量 Layer 的视图
        if ([NSStringFromClass([subview class]) containsString:@"Package"] || 
            [NSStringFromClass([subview class]) containsString:@"CCUI"]) {
            
            CALayer *rootLayer = subview.layer;
            NSMutableArray *queue = [NSMutableArray arrayWithObject:rootLayer];

            while (queue.count > 0) {
                CALayer *layer = [queue firstObject];
                [queue removeObjectAtIndex:0];

                // 核心逻辑：iOS 原生电池矢量包中，内部电量填充 Layer 的名字或者子 Layer 必定包含 fill / level / battery
                NSString *name = layer.name.lowercaseString;
                if (name && ([name containsString:@"fill"] || [name containsString:@"level"]) && ![name containsString:@"bg"] && ![name containsString:@"border"]) {
                    
                    // 1. 如果是路径 shape，直接改 strokeEnd
                    if ([layer isKindOfClass:[CAShapeLayer class]]) {
                        ((CAShapeLayer *)layer).strokeEnd = level;
                    } 
                    // 2. 如果是普通 CALayer，将左中设为锚点，进行 X 轴缩放
                    else {
                        if (layer.anchorPoint.x != 0.0f) {
                            CGRect oldFrame = layer.frame;
                            layer.anchorPoint = CGPointMake(0.0f, 0.5f);
                            layer.frame = oldFrame;
                        }
                        layer.transform = CATransform3DMakeScale(level, 1.0f, 1.0f);
                    }
                }

                if (layer.sublayers.count > 0) {
                    [queue addObjectsFromArray:layer.sublayers];
                }
            }
        }

        // 继续向下递归
        [self cb_updateNativeBatteryFillInView:subview level:level];
    }
}

%end

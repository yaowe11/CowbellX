#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// 1. 在 @interface 中显式声明自定义方法
@interface CCUIToggleViewController : UIViewController
- (void)cb_applyBatteryLevel:(float)level toView:(UIView *)view;
@end

%hook CCUIToggleViewController

- (void)viewDidLayoutSubviews {
    %orig;

    // 判断当前 View Controller 是否是低电量模块
    NSString *className = NSStringFromClass([self class]);
    NSString *desc = self.description;
    
    if ([className containsString:@"LowPower"] || [desc containsString:@"LowPower"]) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f; // 模拟器或异常时默认全满

        // 遍历找到内部那个电池图案的 UIImageView
        [self cb_applyBatteryLevel:level toView:self.view];
    }
}

%new
- (void)cb_applyBatteryLevel:(float)level toView:(UIView *)view {
    if (!view) return;

    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        // 电池图标的 Frame 尺寸通常在 20~50 之间
        if (imageView.bounds.size.width > 20 && imageView.bounds.size.width < 50) {
            
            // 创建一个按真实电量裁剪的 CALayer 作为 Mask
            CALayer *maskLayer = imageView.layer.mask;
            if (!maskLayer) {
                maskLayer = [CALayer layer];
                maskLayer.backgroundColor = [UIColor blackColor].CGColor;
                imageView.layer.mask = maskLayer;
            }

            // 保持高度不变，宽度按真实电量比例 (level) 进行缩放
            CGRect bounds = imageView.bounds;
            CGRect maskFrame = CGRectMake(0, 0, bounds.size.width * level, bounds.size.height);

            // 增加过渡动画，保持与控制中心平滑同步
            [CATransaction begin];
            [CATransaction setAnimationDuration:0.25];
            maskLayer.frame = maskFrame;
            [CATransaction commit];
            return;
        }
    }

    for (UIView *subview in view.subviews) {
        [self cb_applyBatteryLevel:level toView:subview];
    }
}

%end

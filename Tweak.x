#import <UIKit/UIKit.h>

@interface CCUILowPowerModeToggle : NSObject
- (UIView *)contentView;
@end

// 动态绘制带实时电量百分比的电池 Icon
static UIImage *cb_drawBatteryImage(float level, BOOL isSelected) {
    CGSize size = CGSizeMake(28, 14);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    UIColor *tintColor = isSelected ? [UIColor systemYellowColor] : [UIColor whiteColor];
    if (!isSelected) {
        tintColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    }

    // 1. 绘制电池外框 (Rounded Rect)
    CGRect borderRect = CGRectMake(1, 1, 22, 12);
    UIBezierPath *borderPath = [UIBezierPath bezierPathWithRoundedRect:borderRect cornerRadius:3.0];
    borderPath.lineWidth = 1.5;
    [tintColor setStroke];
    [borderPath stroke];

    // 2. 绘制电池正极头 (Cap)
    CGRect capRect = CGRectMake(24, 4.5, 2, 5);
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:capRect cornerRadius:1.0];
    [tintColor setFill];
    [capPath fill];

    // 3. 绘制内部电量填充 (Fill)
    CGFloat maxFillWidth = 18.0;
    CGFloat fillWidth = maxFillWidth * level;
    if (fillWidth < 1.5) fillWidth = 1.5; // 保持最低显示

    CGRect fillRect = CGRectMake(3, 3, fillWidth, 8);
    UIBezierPath *fillPath = [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:1.5];
    [fillPath fill];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// 递归查找 View 层级中的 ImageView
static UIImageView *cb_findImageView(UIView *view) {
    if ([view isKindOfClass:[UIImageView class]]) {
        return (UIImageView *)view;
    }
    for (UIView *subview in view.subviews) {
        UIImageView *imgView = cb_findImageView(subview);
        if (imgView) return imgView;
    }
    return nil;
}

%hook CCUILowPowerModeToggle

- (void)containerViewWillLayoutSubviews {
    %orig;

    // 获取开关当前的容器 View
    UIView *container = nil;
    if ([self respondsToSelector:@selector(contentView)]) {
        container = [self contentView];
    }

    if (!container) return;

    // 找到放置电池图标的 ImageView
    UIImageView *iconView = cb_findImageView(container);
    if (!iconView) return;

    // 获取当前电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;

    // 判断当前低电量模式是否处于开启选中的状态
    BOOL isSelected = [ProcessInfo processInfo].isLowPowerModeEnabled;

    // 替换为我们精确重绘的实时电量图标
    iconView.image = cb_drawBatteryImage(level, isSelected);
}

%end

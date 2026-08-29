#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CCUIToggleViewController : UIViewController
@end

static char kCBMaskLayerKey;

%hook UIImageView

- (void)layoutSubviews {
    %orig;

    // 1. 判断当前 View 是否属于低电量模式 / 电池模块
    UIResponder *responder = self;
    BOOL isLowPower = NO;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"LowPower"] || [clsName containsString:@"Battery"]) {
            isLowPower = YES;
            break;
        }
        responder = responder.nextResponder;
    }

    if (!isLowPower) return;

    // 2. 命中控制中心中央 33x33 左右的电池图标 View
    if (self.bounds.size.width > 25 && self.bounds.size.width < 45) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;
        if (level < 0.05f) level = 0.05f;

        // 3. 获取或创建绑定的 CAShapeLayer 遮罩
        CAShapeLayer *maskLayer = objc_getAssociatedObject(self, &kCBMaskLayerKey);
        if (!maskLayer) {
            maskLayer = [CAShapeLayer layer];
            self.layer.mask = maskLayer;
            objc_setAssociatedObject(self, &kCBMaskLayerKey, maskLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        CGRect bounds = self.bounds;
        CGFloat width = bounds.size.width;
        CGFloat height = bounds.size.height;

        // 4. 精确计算内部填充与左右外框的边距比例
        CGFloat leftPadding = width * 0.18f;  // 保留左外框
        CGFloat rightPadding = width * 0.28f; // 保留右外框及极耳
        CGFloat fillAreaWidth = width - leftPadding - rightPadding;

        // 计算当前实际电量在内部填满的宽度
        CGFloat currentFillWidth = fillAreaWidth * level;

        // 5. 构建复合绘制路径（左右外框全显，中间容量按电量缩放）
        UIBezierPath *path = [UIBezierPath bezierPath];
        
        // 区域一：左侧电池框
        [path appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(0, 0, leftPadding, height)]];
        
        // 区域二：动态电池容量块
        [path appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(leftPadding, 0, currentFillWidth, height)]];
        
        // 区域三：右侧电池框及极耳
        [path appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(width - rightPadding, 0, rightPadding, height)]];

        [CATransaction begin];
        [CATransaction setDisableActions:NO];
        [CATransaction setAnimationDuration:0.25];
        maskLayer.path = path.CGPath;
        [CATransaction commit];
    }
}

%end

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
- (id)publishedObjectWithName:(NSString *)name;
@end

// 使用 objc_setAssociatedObject 存储扩展属性，避免 Ivar 编译兼容问题
#import <objc/runtime.h>

static char kCBIsLowPowerKey;
static char kCBLastAppliedLevelKey;

%hook CCUICAPackageView

- (void)didMoveToWindow {
    %orig;

    BOOL isLowPower = NO;
    UIResponder *responder = self;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"LowPower"] || [clsName containsString:@"Battery"]) {
            isLowPower = YES;
            break;
        }
        responder = responder.nextResponder;
    }

    objc_setAssociatedObject(self, &kCBIsLowPowerKey, @(isLowPower), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kCBLastAppliedLevelKey, @(-1.0f), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (isLowPower && self.window) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    }
}

- (void)layoutSubviews {
    %orig;

    BOOL isLowPower = [objc_getAssociatedObject(self, &kCBIsLowPowerKey) boolValue];
    if (!isLowPower) return;

    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    float lastAppliedLevel = [objc_getAssociatedObject(self, &kCBLastAppliedLevelKey) floatValue];
    if (fabs(level - lastAppliedLevel) < 0.01f) return;
    objc_setAssociatedObject(self, &kCBLastAppliedLevelKey, @(level), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self cb_scaleBatteryFillInLayer:self.layer level:level containerWidth:self.bounds.size.width];
}

%new
- (void)cb_scaleBatteryFillInLayer:(CALayer *)layer level:(float)level containerWidth:(CGFloat)containerWidth {
    if (!layer) return;

    for (CALayer *sub in layer.sublayers) {
        BOOL isLeaf = (sub.sublayers.count == 0);
        // 过滤：宽度小于容器 82% 的叶子 Layer (即内部充能块)
        BOOL isNarrowFill = (sub.bounds.size.width > 0 && sub.bounds.size.width < containerWidth * 0.82f);

        if (isLeaf && isNarrowFill) {
            // 修正：使用 Bounds + KeyPath 形式缩放，避免修改 anchorPoint 导致的坐标累加错位
            [CATransaction begin];
            [CATransaction setDisableActions:NO];
            [CATransaction setAnimationDuration:0.25];

            // 1. 将 Transform 的基准直接按当前 bounds.size 进行 X 轴缩放
            CATransform3D transform = CATransform3DMakeScale(level, 1.0f, 1.0f);
            
            // 2. 补偿锚点默认在中心 (0.5, 0.5) 导致的向两边缩放问题，左移偏移量
            CGFloat xOffset = -(sub.bounds.size.width * (1.0f - level)) / 2.0f;
            transform = CATransform3DTranslate(transform, xOffset / level, 0, 0);

            sub.transform = transform;
            [CATransaction commit];
        } else {
            [self cb_scaleBatteryFillInLayer:sub level:level containerWidth:containerWidth];
        }
    }
}

%end

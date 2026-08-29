#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
- (id)publishedObjectWithName:(NSString *)name;
- (void)cb_applyBatteryFillMask:(float)level forLayer:(CALayer *)layer;
@end

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

    // 精准给内部填充层做 Mask 裁剪，不影响外框和极耳
    [self cb_applyBatteryFillMask:level forLayer:self.layer];
}

%new
- (void)cb_applyBatteryFillMask:(float)level forLayer:(CALayer *)layer {
    if (!layer) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *layerName = sub.name.lowercaseString;
        
        // 精准判断：只有名字带 fill / level / body-fill，或者属于内部色块的 ShapeLayer 才是充能条
        // 避开包含 cap / tip / border / outline / body 的外框和极耳
        BOOL isFillLayer = (layerName && ([layerName containsString:@"fill"] || [layerName containsString:@"level"])) ||
                            ([sub isKindOfClass:[CAShapeLayer class]] && sub.bounds.size.width > 10 && sub.bounds.size.width < 30);
        
        BOOL isBorderOrCap = layerName && ([layerName containsString:@"cap"] || [layerName containsString:@"tip"] || [layerName containsString:@"border"] || [layerName containsString:@"outline"]);

        if (isFillLayer && !isBorderOrCap) {
            // 给 Fill Layer 单独加 Mask 遮罩
            CALayer *maskLayer = sub.mask;
            if (!maskLayer) {
                maskLayer = [CALayer layer];
                maskLayer.backgroundColor = [UIColor blackColor].CGColor;
                sub.mask = maskLayer;
            }

            // 根据真实电量只裁剪 Fill Layer 的宽度
            CGRect bounds = sub.bounds;
            CGRect maskFrame = CGRectMake(0, 0, bounds.size.width * level, bounds.size.height);

            [CATransaction begin];
            [CATransaction setDisableActions:NO];
            [CATransaction setAnimationDuration:0.25];
            maskLayer.frame = maskFrame;
            [CATransaction commit];
        } else {
            [self cb_applyBatteryFillMask:level forLayer:sub];
        }
    }
}

%end

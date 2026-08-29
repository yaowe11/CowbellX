#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
- (id)publishedObjectWithName:(NSString *)name;

// 显式声明 %new 方法，解决编译器报错
- (void)cb_applyLevel:(float)level toLayer:(CALayer *)layer;
@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 1. 严格判断：确保只对低电量/电池包生效，避免污染专注模式等其他图标
    BOOL isBatteryPackage = NO;
    if (self.packageName && ([self.packageName containsString:@"Battery"] || [self.packageName containsString:@"LowPower"])) {
        isBatteryPackage = YES;
    } else {
        UIResponder *responder = self;
        while (responder) {
            NSString *clsName = NSStringFromClass([responder class]);
            if ([clsName containsString:@"LowPower"] || [clsName containsString:@"Battery"]) {
                isBatteryPackage = YES;
                break;
            }
            responder = responder.nextResponder;
        }
    }

    if (!isBatteryPackage) return;

    // 2. 获取手机当前真实电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    // 3. 递归遍历，精准寻找并修改内部的电池填充块
    [self cb_applyLevel:level toLayer:self.layer];
}

%new
- (void)cb_applyLevel:(float)level toLayer:(CALayer *)layer {
    if (!layer) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;
        
        // 核心排除：只要是外框(border/body)或极耳(cap/tip)，绝对不切掉
        BOOL isBorderOrCap = name && ([name containsString:@"cap"] || [name containsString:@"tip"] || [name containsString:@"border"] || [name containsString:@"body"] || [name containsString:@"outline"]);

        // 核心定位：命中填充色块 (fill / level / capacity / content)
        BOOL isFill = name && ([name containsString:@"fill"] || [name containsString:@"level"] || [name containsString:@"capacity"] || [name containsString:@"content"]);

        // 如果名字没有标记，根据尺寸特征匹配内部色块 (宽度在 10~30 之间)
        if (!isFill && !isBorderOrCap) {
            if (sub.bounds.size.width >= 10 && sub.bounds.size.width <= 30 && sub.bounds.size.height >= 5) {
                isFill = YES;
            }
        }

        if (isFill && !isBorderOrCap) {
            // 使用遮罩 Mask 裁切内部填充宽度
            if (!sub.mask) {
                CALayer *mask = [CALayer layer];
                mask.backgroundColor = [UIColor blackColor].CGColor;
                sub.mask = mask;
            }

            CGRect bounds = sub.bounds;
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            sub.mask.frame = CGRectMake(0, 0, bounds.size.width * level, bounds.size.height);
            [CATransaction commit];
        }

        // 继续向下递归找子节点
        [self cb_applyLevel:level toLayer:sub];
    }
}

%end

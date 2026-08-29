#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// 1. 显式声明 CCUICAPackageView 继承自 UIView，并补充自定义方法接口
@interface CCUICAPackageView : UIView
- (void)cb_dumpLayer:(CALayer *)layer depth:(int)depth;
@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 判断是不是低电量模块里的 PackageView
    UIResponder *responder = self;
    BOOL isLowPower = NO;
    while (responder) {
        if ([NSStringFromClass([responder class]) containsString:@"LowPower"]) {
            isLowPower = YES;
            break;
        }
        responder = responder.nextResponder;
    }

    if (isLowPower) {
        static BOOL hasPrinted = NO;
        if (!hasPrinted) {
            hasPrinted = YES;
            NSLog(@"\n\n================ [LowPower Package Layers] ================");
            [self cb_dumpLayer:self.layer depth:0];
            NSLog(@"===========================================================\n\n");
        }
    }
}

%new
- (void)cb_dumpLayer:(CALayer *)layer depth:(int)depth {
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];

    // 打印 Layer 的类名、Layer Name、Frame 以及 KeyPath 信息
    NSLog(@"%@├─ Class: %@ | Name: '%@' | Bounds: %@", 
          indent, 
          NSStringFromClass([layer class]), 
          layer.name ? layer.name : @"(null)", 
          NSStringFromCGRect(layer.bounds));

    for (CALayer *sub in layer.sublayers) {
        [self cb_dumpLayer:sub depth:depth + 1];
    }
}

%end

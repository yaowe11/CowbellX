#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface UIView (CBLog)
- (void)cb_logHierarchyWithLevel:(int)level;
@end

@implementation UIView (CBLog)
- (void)cb_logHierarchyWithLevel:(int)level {
    NSMutableString *padding = [NSMutableString string];
    for (int i = 0; i < level; i++) [padding appendString:@"  "];
    
    NSLog(@"[CowbellDebug] %@View: %@ | frame: %@", padding, NSStringFromClass([self class]), NSStringFromCGRect(self.frame));
    
    if (self.layer.sublayers.count > 0) {
        for (CALayer *sub in self.layer.sublayers) {
            NSLog(@"[CowbellDebug] %@  └─ Layer: %@ | name: %@ | bounds: %@", padding, NSStringFromClass([sub class]), sub.name, NSStringFromCGRect(sub.bounds));
        }
    }
    
    for (UIView *subview in self.subviews) {
        [subview cb_logHierarchyWithLevel:level + 1];
    }
}
@end

// 拦截所有 UIView 的 layoutSubviews，抓取低电量模块
%hook UIView

- (void)layoutSubviews {
    %orig;

    UIResponder *responder = self;
    BOOL isLowPower = NO;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"LowPower"]) {
            isLowPower = YES;
            break;
        }
        responder = responder.nextResponder;
    }

    if (isLowPower && self.bounds.size.width > 20 && self.bounds.size.width < 50) {
        static BOOL logged = NO;
        if (!logged) {
            logged = YES;
            NSLog(@"================ [CowbellDebug Start] ================");
            [self cb_logHierarchyWithLevel:0];
            NSLog(@"================ [CowbellDebug End] ==================");
        }
    }
}

%end

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
// 在接口里声明新增的递归方法，防止 Clang 编译报错
- (void)cb_logLayers:(CALayer *)layer depth:(int)depth;
@end

%hook CCUICAPackageView

- (void)setState:(NSString *)state animated:(BOOL)animated {
    %orig;
    
    // 自动遍历并打印内部所有图层
    [self cb_logLayers:self.layer depth:0];
}

%new
- (void)cb_logLayers:(CALayer *)layer depth:(int)depth {
    if (!layer) return;
    
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) {
        [indent appendString:@"  "];
    }
    
    NSLog(@"[Cowbell] %@Layer: '%@' | bounds: %@", indent, layer.name, NSStringFromCGRect(layer.bounds));
    
    for (CALayer *sub in layer.sublayers) {
        [self cb_logLayers:sub depth:depth + 1];
    }
}

%end

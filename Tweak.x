#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@end

%hook CCUICAPackageView

- (void)setState:(NSString *)state animated:(BOOL)animated {
    %orig; // 先让系统自己做完动画状态切换
    
    // 自动把内部所有子图层（Sublayer）的名字打印出来
    [self cb_logLayers:self.layer depth:0];
}

%new
- (void)cb_logLayers:(CALayer *)layer depth:(int)depth {
    if (!layer) return;
    
    // 拼接空格，区分层级
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];
    
    // 打印当前 Layer 的名字和尺寸
    NSLog(@"[Cowbell] %@Layer: '%@' | bounds: %@", indent, layer.name, NSStringFromCGRect(layer.bounds));
    
    for (CALayer *sub in layer.sublayers) {
        [self cb_logLayers:sub depth:depth + 1];
    }
}

%end

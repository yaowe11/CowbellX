#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
- (NSString *)cb_dumpLayers:(CALayer *)layer depth:(int)depth;
@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 1. 视觉验证：如果 Hook 成功触发，图标背景会变成红块
    self.backgroundColor = [UIColor redColor];

    // 2. 导出图层结构到 /tmp/cowbell_layers.txt
    NSString *hierarchy = [self cb_dumpLayers:self.layer depth:0];
    [hierarchy writeToFile:@"/tmp/cowbell_layers.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

%new
- (NSString *)cb_dumpLayers:(CALayer *)layer depth:(int)depth {
    if (!layer) return @"";
    
    NSMutableString *result = [NSMutableString string];
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) {
        [indent appendString:@"  "];
    }
    
    NSString *layerName = layer.name ? layer.name : @"<无名>";
    [result appendFormat:@"%@• %@ (%.0fx%.0f)\n", indent, layerName, layer.bounds.size.width, layer.bounds.size.height];
    
    for (CALayer *sub in layer.sublayers) {
        [result appendString:[self cb_dumpLayers:sub depth:depth + 1]];
    }
    return result;
}

%end

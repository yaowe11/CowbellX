#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@end

static void cb_dumpPackageLayers(CALayer *layer, int depth) {
    if (!layer) return;
    
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) { [indent appendString:@"  "]; }
    
    NSLog(@"[CowbellTree]%@ Layer: %@ | Name: '%@' | Bounds: %@ | Anchor: %@", 
          indent, 
          NSStringFromClass([layer class]), 
          layer.name ? layer.name : @"(null)", 
          NSStringFromCGRect(layer.bounds),
          NSStringFromCGPoint(layer.anchorPoint));

    for (CALayer *sub in layer.sublayers) {
        cb_dumpPackageLayers(sub, depth + 1);
    }
}

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    UIResponder *r = self;
    BOOL isLowPower = NO;
    while (r) {
        NSString *cls = NSStringFromClass([r class]);
        if ([cls containsString:@"LowPower"] || [cls containsString:@"Battery"]) {
            isLowPower = YES;
            break;
        }
        r = r.nextResponder;
    }

    if (!isLowPower) return;

    NSLog(@"[CowbellTree] ============= LOW POWER PACKAGE LAYER DUMP =============");
    cb_dumpPackageLayers(self.layer, 0);
    NSLog(@"[CowbellTree] ========================================================");
}

%end

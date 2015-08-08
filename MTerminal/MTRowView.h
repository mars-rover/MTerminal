#import <CoreText/CoreText.h>
#import <UIKit/UIKit.h>

#define kMTBackgroundColorAttributeName CFSTR("MTBackgroundColor")
#define kMTStrikethroughColorAttributeName CFSTR("MTStrikethroughColor")

@interface MTRowView : UIView {
  CGColorRef bgColor;
  CGFloat glyphAscent,glyphHeight,glyphMidY;
  CTLineRef ctLine;
  CFMutableDictionaryRef bgMap,stMap;
}
-(id)initWithBackgroundColor:(CGColorRef)_bgColor ascent:(CGFloat)_glyphAscent height:(CGFloat)_glyphHeight midY:(CGFloat)_glyphMidY;
-(void)renderString:(CFAttributedStringRef)string;
@end

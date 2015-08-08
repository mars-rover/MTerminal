#import "MTKBAvoiding.h"

@interface MTScratchpad : MTKBAvoiding {
  NSString* content;
  UIFont* font;
  UIColor* textColor;
  UIViewController* refController;
}
-(id)initWithTitle:(NSString*)title content:(NSString*)_content font:(UIFont*)_font textColor:(UIColor*)_textColor refController:(UIViewController*)_refController;
@end

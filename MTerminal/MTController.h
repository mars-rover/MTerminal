#import <AudioToolbox/AudioServices.h>
#import <CoreText/CoreText.h>
#import "MTKBAvoiding.h"
#import "VT100.h"

@interface MTController : MTKBAvoiding <UIActionSheetDelegate,UIKeyInput,UITableViewDataSource,VT100Delegate> {
  CGColorRef colorTable[256],nullColor;
  CGColorRef bgDefault,bgCursor;
  CGColorRef fgDefault,fgBold,fgCursor;
  CTFontRef ctFont;
  CTFontRef ctFontBold;
  CTFontRef ctFontItalic;
  CTFontRef ctFontBoldItalic;
  CFNumberRef ctUnderlineStyleSingle;
  CFNumberRef ctUnderlineStyleDouble;
  CGFloat glyphAscent,glyphHeight,glyphMidY;
  CGFloat colWidth,rowHeight;
  BOOL bellSound;
  SystemSoundID bellSoundID;
  BOOL ctrlLock;
  NSTimer* repeatTimer;
  NSIndexSet* screenSection;
  NSMutableArray* allTerminals;
  VT100* activeTerminal;
  NSUInteger activeIndex,previousIndex;
}
-(BOOL)isRunning;
@end

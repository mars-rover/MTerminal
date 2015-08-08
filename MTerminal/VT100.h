#include <stdlib.h>
#import <Foundation/Foundation.h>
@class VT100;

typedef enum {
  kVT100KeyTab='\t',
  kVT100KeyEnter='\n',
  kVT100KeyEsc=033,
  kVT100KeyBackArrow=0x100,
  kVT100KeyInsert,
  kVT100KeyDelete,
  kVT100KeyPageUp,
  kVT100KeyPageDown,
  kVT100KeyUpArrow,
  kVT100KeyDownArrow,
  kVT100KeyLeftArrow,
  kVT100KeyRightArrow,
  kVT100KeyHome,
  kVT100KeyEnd,
} VT100Key;  

typedef struct screen_char_t {
  unichar c;
  unsigned char bgcolor;
  unsigned char fgcolor;
  BOOL bgcolor_isset:1;
  BOOL fgcolor_isset:1;
  enum {
    kFontWeightNormal,
    kFontWeightBold,
    kFontWeightFaint,
  } weight:2;
  BOOL italicize:1;
  enum {
    kUnderlineNone,
    kUnderlineSingle,
    kUnderlineDouble,
  } underline:2;
  BOOL blink:1;
  BOOL inverse:1;
  BOOL hidden:1;
  BOOL strikethrough:1;
  BOOL wrapped:1;
} screen_char_t;

typedef struct screen_line_t {
  volatile int32_t retain_count;
  size_t size;// size of character buffer in bytes
  screen_char_t buf[];// the actual characters
} screen_line_t;

@protocol VT100Delegate
-(BOOL)terminalShouldReportChanges:(VT100*)terminal;
-(void)terminal:(VT100*)terminal changed:(CFSetRef)changes deleted:(CFSetRef)deletions inserted:(CFSetRef)insertions bell:(BOOL)bell;
@end

@interface VT100 : NSObject {
  // bit fields
  BOOL bDECBKM:1,mDECBKM:1;
  BOOL bDECCKM:1,mDECCKM:1;
  BOOL bDECOM:1,mDECOM:1,swapDECOM:1;
  BOOL bDECAWM:1,mDECAWM:1,swapDECAWM:1;
  BOOL bDECTCEM:1,mDECTCEM:1;
  BOOL bIRM:1;
  BOOL bLNM:1;
  BOOL bPastEOL:1;
  BOOL bTrackChanges:1;
  // sequence parser
  enum {
    kSequenceNone,
    kSequenceESC,
    kSequenceCSI,
    kSequenceDEC,
    kSequenceSCS,
    kSequenceIgnore,
    kSequencePossibleST,
    kSequenceSkipNext,
  } sequence;
  enum {
    kCSIModifierNone,
    kCSIModifierQM,
    kCSIModifierGT,
    kCSIModifierEQ,
  } CSIModifier;
  unsigned int SCSIndex;
  unsigned long CSIParam;
  CFMutableArrayRef CSIParams;
  CFMutableStringRef OSCString;
  // screen settings
  CFIndex currentIndex;
  CFIndex cursorX,saveCursorX,swapCursorX;
  CFIndex cursorY,saveCursorY,swapCursorY;
  CFIndex windowTop,swapWindowTop;
  CFIndex windowBottom,swapWindowBottom;
  CFIndex screenWidth,swapScreenWidth;
  CFIndex screenHeight,swapScreenHeight;
  // graphical settings
  screen_char_t nullChar,saveNullChar,swapNullChar;
  unsigned char glCharset,saveGLCharset,swapGLCharset;
  unsigned char charsets[4],saveCharsets[4],swapCharsets[4];
  // multi-byte character encoding
  unsigned char* encbuf;
  CFIndex encbuf_size,encbuf_index;
  // tab stops
  BOOL* tabstops;
  size_t tabstops_size;
  // line buffers
  CFMutableArrayRef lineBuffer;
  CFArrayRef swapLineBuffer;
  screen_line_t* currentLine;
  // change tracking
  CFMutableArrayRef indexMap;
  CFMutableSetRef linesChanged;
  CFIndex indexTop,prevCursorX,prevCursorY;
  // pty process
  CFFileDescriptorRef ptyref;
}
@property(nonatomic,assign) id<VT100Delegate> delegate;
@property(nonatomic,assign) CFStringEncoding encoding;
@property(nonatomic,readonly) CFStringRef title;
@property(nonatomic,readonly) pid_t processID;
@property(nonatomic,readonly) BOOL bellDeferred;
-(id)initWithWidth:(CFIndex)_screenWidth height:(CFIndex)_screenHeight;
-(CFIndex)numberOfLines;
-(screen_char_t*)charactersAtLineIndex:(CFIndex)index length:(CFIndex*)length cursorColumn:(CFIndex*)cursorColumn;
-(CFStringRef)copyProcessName;
-(BOOL)isRunning;
-(void)sendKey:(VT100Key)key;
-(void)sendString:(CFStringRef)string;
-(void)setWidth:(CFIndex)newWidth height:(CFIndex)newHeight;
@end

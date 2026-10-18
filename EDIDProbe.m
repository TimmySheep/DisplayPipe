// Independent read-only probe. Does not call any display setter.
// Reports the EDID descriptor 0xFC monitor name (percent-encoded, so the line stays
// a space-separated key=value record) and never prints serial strings.
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
typedef CFTypeRef (*CreateFn)(CFAllocatorRef, io_service_t);
typedef IOReturn (*CopyFn)(CFTypeRef, CFDataRef *);

// Descriptor 0xFC: printable ASCII, '%' and space encoded as %XX, terminated at padding.
static NSString *MonitorName(const unsigned char *b, CFIndex n, BOOL *found) {
    *found = NO;
    if (!b || n < 126) return @"";
    for (CFIndex o = 54; o + 18 <= 126; o += 18) {
        const unsigned char *d = b + o;
        if (d[0] || d[1] || d[3] != 0xfc) continue;
        NSMutableString *s = [NSMutableString string];
        for (int i = 5; i < 18; i++) {
            unsigned char c = d[i];
            if (c == '\n' || c == '\r') break;
            if (c >= 32 && c < 127 && c != '%') [s appendFormat:@"%c", c];
            else [s appendFormat:@"%%%02X", c];
        }
        *found = YES;
        return s;
    }
    return @"";
}

int main(void) { @autoreleasepool {
 void *h=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_LAZY|RTLD_LOCAL);
 CreateFn create=(CreateFn)dlsym(h,"IOAVServiceCreateWithService");
 CopyFn copy=(CopyFn)dlsym(h,"IOAVServiceCopyEDID");
 if(!create||!copy) return 2;
 io_iterator_t it=0;
 kern_return_t kr=IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("DCPAVServiceProxy"),&it);
 if(kr) return 3;
 io_service_t s; unsigned total=0;
 while((s=IOIteratorNext(it))) {
  uint64_t rid=0; IORegistryEntryGetRegistryEntryID(s,&rid);
  CFTypeRef loc=IORegistryEntryCreateCFProperty(s,CFSTR("Location"),kCFAllocatorDefault,0);
  NSString *location=loc?[(__bridge id)loc description]:@"UNKNOWN";
  printf("SERVICE id=%llu location=%s\n",rid,location.UTF8String);
  // Never open an internal or unidentified target.
  if([location isEqualToString:@"External"]) {
   CFTypeRef av=create(kCFAllocatorDefault,s);
   if(av) {
    CFDataRef data=NULL; IOReturn rc=copy(av,&data);
    printf("COPY result=0x%08x\n",rc);
    if(rc==0 && data) {
     CFIndex n=CFDataGetLength(data); const UInt8 *b=CFDataGetBytePtr(data);
     BOOL valid=n>=128 && n%128==0;
     if(n>=128) { valid=valid && b[0]==0 && b[1]==255 && b[7]==0 && n==(b[126]+1)*128; }
     for(CFIndex off=0;off+128<=n;off+=128){unsigned sum=0;for(int j=0;j<128;j++)sum+=b[off+j]; if(sum%256)valid=NO;}
     unsigned vendor=n>=12?((unsigned)b[8]<<8)|b[9]:0;
     unsigned model=n>=12?b[10]|((unsigned)b[11]<<8):0;
     BOOL named=NO; NSString *name=MonitorName(valid?b:NULL,n,&named);
     printf("EDID bytes=%ld checksumAndLengthValid=%s vendor=0x%04x model=0x%04x name=%s named=%s\n",
            (long)n,valid?"true":"false",vendor,model,name.UTF8String,named?"true":"false");
     total++;
    }
    if(data)CFRelease(data);CFRelease(av);
   } else printf("CREATE unavailable\n");
  }
  if(loc)CFRelease(loc); IOObjectRelease(s);
 }
 IOObjectRelease(it);printf("READ_ONLY completed externalEDIDs=%u\n",total);
 return total?0:4;
} }

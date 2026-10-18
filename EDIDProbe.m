// Independent read-only probe. Does not call any display setter.
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
typedef CFTypeRef (*CreateFn)(CFAllocatorRef, io_service_t);
typedef IOReturn (*CopyFn)(CFTypeRef, CFDataRef *);
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
     printf("EDID bytes=%ld checksumAndLengthValid=%s vendor=0x%04x model=0x%04x\n",(long)n,valid?"true":"false",vendor,model);
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

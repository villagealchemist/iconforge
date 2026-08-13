#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <sys/xattr.h>

static const int kExitOperationFailed = 1;
static const int kExitUsage = 64;
static const int kExitInput = 66;
static const uint16_t kFinderHasCustomIcon = 0x0400;

static void PrintError(NSString *message) {
  fprintf(stderr, "iconforge-native-icon: %s\n", message.UTF8String);
}

static BOOL IsAppBundle(NSString *path) {
  BOOL isDirectory = NO;
  NSFileManager *manager = NSFileManager.defaultManager;
  return [manager fileExistsAtPath:path isDirectory:&isDirectory] &&
         isDirectory &&
         [manager fileExistsAtPath:[path stringByAppendingPathComponent:@"Contents/Info.plist"]];
}

static BOOL HasCustomIconFlag(NSString *path) {
  unsigned char finderInfo[32] = {0};
  ssize_t size = getxattr(path.fileSystemRepresentation,
                          "com.apple.FinderInfo",
                          finderInfo,
                          sizeof(finderInfo),
                          0,
                          0);
  if (size < 10) {
    return NO;
  }

  uint16_t finderFlags = ((uint16_t)finderInfo[8] << 8) | finderInfo[9];
  return (finderFlags & kFinderHasCustomIcon) != 0;
}

static BOOL HasCustomIconPayload(NSString *path) {
  NSString *iconResource = [path stringByAppendingPathComponent:@"Icon\r"];
  return [NSFileManager.defaultManager fileExistsAtPath:iconResource];
}

static BOOL HasUsableCustomIcon(NSString *path) {
  return HasCustomIconFlag(path) && HasCustomIconPayload(path);
}

static int TestCustomIcon(NSString *appPath, BOOL printFailure) {
  if (HasUsableCustomIcon(appPath)) {
    return 0;
  }

  if (printFailure) {
    PrintError([NSString stringWithFormat:@"no usable Finder custom icon is set on %@", appPath]);
  }
  return kExitOperationFailed;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 3) {
      PrintError(@"usage: iconforge-native-icon set <app-path> <icon-path> | test <app-path> | remove <app-path>");
      return kExitUsage;
    }

    NSString *command = [NSString stringWithUTF8String:argv[1]];
    NSString *appPath = [[NSString stringWithUTF8String:argv[2]] stringByStandardizingPath];

    if (!IsAppBundle(appPath)) {
      PrintError([NSString stringWithFormat:@"app bundle not found or invalid: %@", appPath]);
      return kExitInput;
    }

    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;

    if ([command isEqualToString:@"test"]) {
      if (argc != 3) {
        PrintError(@"usage: iconforge-native-icon test <app-path>");
        return kExitUsage;
      }
      return TestCustomIcon(appPath, YES);
    }

    if ([command isEqualToString:@"remove"]) {
      if (argc != 3) {
        PrintError(@"usage: iconforge-native-icon remove <app-path>");
        return kExitUsage;
      }
      if (![workspace setIcon:nil forFile:appPath options:0]) {
        PrintError([NSString stringWithFormat:@"AppKit failed to remove the Finder custom icon from %@", appPath]);
        return kExitOperationFailed;
      }
      if (HasCustomIconFlag(appPath) || HasCustomIconPayload(appPath)) {
        PrintError([NSString stringWithFormat:@"Finder custom icon metadata remains on %@ after removal", appPath]);
        return kExitOperationFailed;
      }
      return 0;
    }

    if ([command isEqualToString:@"set"]) {
      if (argc != 4) {
        PrintError(@"usage: iconforge-native-icon set <app-path> <icon-path>");
        return kExitUsage;
      }

      NSString *iconPath = [[NSString stringWithUTF8String:argv[3]] stringByStandardizingPath];
      BOOL isDirectory = NO;
      if (![NSFileManager.defaultManager fileExistsAtPath:iconPath isDirectory:&isDirectory] || isDirectory) {
        PrintError([NSString stringWithFormat:@"icon file not found: %@", iconPath]);
        return kExitInput;
      }

      NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
      if (icon == nil) {
        PrintError([NSString stringWithFormat:@"could not decode icon image: %@", iconPath]);
        return kExitInput;
      }
      if (![workspace setIcon:icon forFile:appPath options:0]) {
        PrintError([NSString stringWithFormat:@"AppKit failed to set the Finder custom icon on %@", appPath]);
        return kExitOperationFailed;
      }
      if (TestCustomIcon(appPath, NO) != 0) {
        PrintError([NSString stringWithFormat:@"Finder custom icon verification failed for %@", appPath]);
        return kExitOperationFailed;
      }
      return 0;
    }

    PrintError([NSString stringWithFormat:@"unknown command: %@", command]);
    return kExitUsage;
  }
}

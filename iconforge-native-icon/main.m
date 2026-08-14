#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <pwd.h>
#include <unistd.h>
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
  return [path.pathExtension caseInsensitiveCompare:@"app"] == NSOrderedSame &&
         [manager fileExistsAtPath:path isDirectory:&isDirectory] &&
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

static NSString *NormalizeMatchToken(NSString *value) {
  NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  NSString *normalized = value.precomposedStringWithCanonicalMapping;
  normalized = [normalized stringByFoldingWithOptions:NSCaseInsensitiveSearch locale:locale];
  normalized = [[normalized lowercaseStringWithLocale:locale] precomposedStringWithCanonicalMapping];
  if ([normalized hasSuffix:@".app"]) {
    normalized = [normalized substringToIndex:normalized.length - 4];
  }

  NSCharacterSet *separators = NSCharacterSet.alphanumericCharacterSet.invertedSet;
  NSArray<NSString *> *rawParts = [normalized componentsSeparatedByCharactersInSet:separators];
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  for (NSString *part in rawParts) {
    if (part.length > 0) {
      [parts addObject:part];
    }
  }
  return [parts componentsJoinedByString:@" "];
}

static NSString *NormalizePathCollisionKey(NSString *value) {
  NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  NSString *normalized = value.precomposedStringWithCanonicalMapping;
  normalized = [normalized stringByFoldingWithOptions:NSCaseInsensitiveSearch locale:locale];
  normalized = [normalized lowercaseStringWithLocale:locale];
  return normalized.precomposedStringWithCanonicalMapping;
}

static int ValidateIcon(NSString *iconPath) {
  BOOL isDirectory = NO;
  NSFileManager *manager = NSFileManager.defaultManager;
  if (![manager fileExistsAtPath:iconPath isDirectory:&isDirectory] || isDirectory) {
    PrintError([NSString stringWithFormat:@"icon file not found: %@", iconPath]);
    return kExitInput;
  }

  NSData *data = [NSData dataWithContentsOfFile:iconPath];
  if (data.length < 8 || memcmp(data.bytes, "icns", 4) != 0) {
    PrintError([NSString stringWithFormat:@"not a valid ICNS container: %@", iconPath]);
    return kExitInput;
  }

  const uint8_t *bytes = data.bytes;
  uint32_t declaredLength = ((uint32_t)bytes[4] << 24) |
                            ((uint32_t)bytes[5] << 16) |
                            ((uint32_t)bytes[6] << 8) |
                            (uint32_t)bytes[7];
  if (declaredLength < 8 || declaredLength != data.length) {
    PrintError([NSString stringWithFormat:@"ICNS container length is invalid: %@", iconPath]);
    return kExitInput;
  }

  NSImage *icon = [[NSImage alloc] initWithData:data];
  if (icon == nil || !icon.valid || icon.representations.count == 0) {
    PrintError([NSString stringWithFormat:@"could not decode ICNS image: %@", iconPath]);
    return kExitInput;
  }
  return 0;
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
    if (argc < 2) {
      PrintError(@"usage: iconforge-native-icon user-home | set <app-path> <icon-path> | test <app-path> | present <app-path> | remove <app-path> | validate <icon-path> | normalize <name> | path-key <path> | link-exclusive <source> <target> | rename-exact <source> <target>");
      return kExitUsage;
    }

    NSString *command = [NSString stringWithUTF8String:argv[1]];

    if ([command isEqualToString:@"user-home"]) {
      if (argc != 2) {
        PrintError(@"usage: iconforge-native-icon user-home");
        return kExitUsage;
      }

      struct passwd *account = getpwuid(geteuid());
      if (account == NULL || account->pw_dir == NULL || account->pw_dir[0] != '/') {
        PrintError(@"could not resolve the current account's home directory");
        return kExitOperationFailed;
      }

      NSString *home = [NSFileManager.defaultManager
          stringWithFileSystemRepresentation:account->pw_dir
                                       length:strlen(account->pw_dir)];
      home = home.stringByStandardizingPath.stringByResolvingSymlinksInPath;
      BOOL isDirectory = NO;
      if ([home isEqualToString:@"/"] ||
          ![NSFileManager.defaultManager fileExistsAtPath:home isDirectory:&isDirectory] ||
          !isDirectory) {
        PrintError(@"the current account's home directory is unsafe or unavailable");
        return kExitOperationFailed;
      }

      printf("%s\n", home.fileSystemRepresentation);
      return 0;
    }

    if (argc < 3) {
      PrintError(@"usage: iconforge-native-icon user-home | set <app-path> <icon-path> | test <app-path> | present <app-path> | remove <app-path> | validate <icon-path> | normalize <name> | path-key <path> | link-exclusive <source> <target> | rename-exact <source> <target>");
      return kExitUsage;
    }

    if ([command isEqualToString:@"normalize"]) {
      if (argc != 3) {
        PrintError(@"usage: iconforge-native-icon normalize <name>");
        return kExitUsage;
      }
      NSString *value = [NSString stringWithUTF8String:argv[2]];
      printf("%s\n", NormalizeMatchToken(value).UTF8String);
      return 0;
    }

    if ([command isEqualToString:@"path-key"]) {
      if (argc != 3) {
        PrintError(@"usage: iconforge-native-icon path-key <path>");
        return kExitUsage;
      }
      NSString *value = [NSString stringWithUTF8String:argv[2]];
      printf("%s\n", NormalizePathCollisionKey(value).UTF8String);
      return 0;
    }

    if ([command isEqualToString:@"link-exclusive"]) {
      if (argc != 4) {
        PrintError(@"usage: iconforge-native-icon link-exclusive <source> <target>");
        return kExitUsage;
      }
      NSString *sourcePath = [[NSString stringWithUTF8String:argv[2]] stringByStandardizingPath];
      NSString *targetPath = [[NSString stringWithUTF8String:argv[3]] stringByStandardizingPath];
      if (link(sourcePath.fileSystemRepresentation, targetPath.fileSystemRepresentation) != 0) {
        PrintError([NSString stringWithFormat:@"could not create output exclusively: %s", strerror(errno)]);
        return kExitOperationFailed;
      }
      return 0;
    }

    if ([command isEqualToString:@"rename-exact"]) {
      if (argc != 4) {
        PrintError(@"usage: iconforge-native-icon rename-exact <source> <target>");
        return kExitUsage;
      }
      NSString *sourcePath = [[NSString stringWithUTF8String:argv[2]] stringByStandardizingPath];
      NSString *targetPath = [[NSString stringWithUTF8String:argv[3]] stringByStandardizingPath];
      if (rename(sourcePath.fileSystemRepresentation, targetPath.fileSystemRepresentation) != 0) {
        PrintError([NSString stringWithFormat:@"could not replace exact output path: %s", strerror(errno)]);
        return kExitOperationFailed;
      }
      return 0;
    }

    if ([command isEqualToString:@"validate"]) {
      if (argc != 3) {
        PrintError(@"usage: iconforge-native-icon validate <icon-path>");
        return kExitUsage;
      }
      NSString *iconPath = [[NSString stringWithUTF8String:argv[2]] stringByStandardizingPath];
      return ValidateIcon(iconPath);
    }

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

    if ([command isEqualToString:@"present"]) {
      if (argc != 3) {
        PrintError(@"usage: iconforge-native-icon present <app-path>");
        return kExitUsage;
      }
      return (HasCustomIconFlag(appPath) || HasCustomIconPayload(appPath)) ? 0 : kExitOperationFailed;
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
      int validationStatus = ValidateIcon(iconPath);
      if (validationStatus != 0) {
        return validationStatus;
      }
      NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
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

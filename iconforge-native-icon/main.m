#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <pwd.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <stdlib.h>
#import <sys/xattr.h>

static const int kExitOperationFailed = 1;
static const int kExitUsage = 64;
static const int kExitInput = 66;
static const uint16_t kFinderHasCustomIcon = 0x0400;
static NSMutableArray<NSString *> *diagnosticMessages;

static void PrintError(NSString *message) {
  [diagnosticMessages addObject:message];
  fprintf(stderr, "iconforge-native-icon: %s\n", message.UTF8String);
}

static NSString *DisplayPath(NSString *path) {
  return [[path stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"]
      stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
}

static BOOL CheckNativeWritePrerequisites(NSString *appPath, BOOL printFacts) {
  BOOL ready = YES;
  if (printFacts) {
    PrintError([NSString stringWithFormat:@"Diagnostic: %@; uid=%u euid=%u",
        NSProcessInfo.processInfo.operatingSystemVersionString, getuid(), geteuid()]);
  }
  struct statfs volume;
  if (statfs(appPath.fileSystemRepresentation, &volume) == 0) {
    if (printFacts) {
      PrintError([NSString stringWithFormat:@"Diagnostic: filesystem=%s read-only=%@",
          volume.f_fstypename, (volume.f_flags & MNT_RDONLY) ? @"yes" : @"no"]);
    }
    if (volume.f_flags & MNT_RDONLY) {
      PrintError(@"The app is on a read-only volume. Remedy: use a copy on a writable volume.");
      ready = NO;
    }
  } else {
    PrintError([NSString stringWithFormat:@"Could not inspect the app's volume: %s", strerror(errno)]);
    ready = NO;
  }
  NSArray<NSString *> *paths = @[appPath, [appPath stringByAppendingPathComponent:@"Icon\r"]];
  for (NSUInteger index = 0; index < paths.count; index++) {
    NSString *path = paths[index];
    struct stat info;
    int result = index == 0 ? stat(path.fileSystemRepresentation, &info)
                            : lstat(path.fileSystemRepresentation, &info);
    if (result != 0) {
      int savedError = errno;
      if (index == 1 && savedError == ENOENT) {
        if (printFacts) PrintError(@"Diagnostic: Finder icon payload is absent.");
        continue;
      }
      PrintError([NSString stringWithFormat:@"Could not inspect %@: %s", DisplayPath(path), strerror(savedError)]);
      ready = NO;
      continue;
    }
    if (printFacts) {
      PrintError([NSString stringWithFormat:@"Diagnostic: path=%@ mode=%04o owner=%u group=%u flags=0x%x",
          DisplayPath(path), info.st_mode & 07777, info.st_uid, info.st_gid, info.st_flags]);
    }
    if (info.st_flags & (UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND)) {
      PrintError([NSString stringWithFormat:@"The icon target is locked or append-only: %@ (flags=0x%x). Remedy: use an unlocked writable copy or have the owner resolve the file lock.", DisplayPath(path), info.st_flags]);
      ready = NO;
    }
    if (index == 1 && !S_ISREG(info.st_mode)) {
      PrintError([NSString stringWithFormat:@"Finder icon payload is not a regular file: %@. Remedy: preserve and resolve this unexpected entry before retrying.", DisplayPath(path)]);
      ready = NO;
    }
  }
  if (access(appPath.fileSystemRepresentation, W_OK | X_OK) != 0) {
    int savedError = errno;
    PrintError([NSString stringWithFormat:@"This process cannot write inside %@: %s. Remedy: use a writable copy or authorize only the single-app helper operation.", DisplayPath(appPath), strerror(savedError)]);
    ready = NO;
  }
  return ready;
}

static void PrintAppKitFailure(NSString *operation, NSString *appPath) {
  PrintError([NSString stringWithFormat:@"AppKit failed to %@ the Finder custom icon on %@", operation, DisplayPath(appPath)]);
  BOOL ready = CheckNativeWritePrerequisites(appPath, YES);
  if (ready) {
    PrintError(@"No filesystem blocker was identified by the read-only checks. AppKit did not expose the underlying cause; errno and Resource Manager status are not reliable for this API.");
    PrintError(@"Remedy: retain this diagnostic output and compare the same icon on a disposable writable app copy. Do not assume the failure is an authorization problem.");
  }
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

static uint16_t ReadBE16(const uint8_t *bytes) {
  return ((uint16_t)bytes[0] << 8) | bytes[1];
}

static uint32_t ReadBE32(const uint8_t *bytes) {
  return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
         ((uint32_t)bytes[2] << 8) | bytes[3];
}

static BOOL RangeFits(NSUInteger offset, NSUInteger length, NSUInteger total) {
  return offset <= total && length <= total - offset;
}

static NSData *CustomIconData(NSString *path) {
  NSString *payload = [path stringByAppendingPathComponent:@"Icon\r"];
  struct stat info;
  if (lstat(payload.fileSystemRepresentation, &info) != 0 || !S_ISREG(info.st_mode)) return nil;
  NSString *forkPath = [payload stringByAppendingString:@"/..namedfork/rsrc"];
  NSData *fork = [NSData dataWithContentsOfFile:forkPath];
  if (fork.length < 16) return nil;
  const uint8_t *bytes = fork.bytes;
  NSUInteger dataOffset = ReadBE32(bytes);
  NSUInteger mapOffset = ReadBE32(bytes + 4);
  NSUInteger dataLength = ReadBE32(bytes + 8);
  NSUInteger mapLength = ReadBE32(bytes + 12);
  if (!RangeFits(dataOffset, dataLength, fork.length) ||
      !RangeFits(mapOffset, mapLength, fork.length) || mapLength < 28) return nil;
  NSUInteger typeOffset = ReadBE16(bytes + mapOffset + 24);
  if (!RangeFits(typeOffset, 2, mapLength)) return nil;
  const uint8_t *types = bytes + mapOffset + typeOffset;
  uint16_t countMinusOne = ReadBE16(types);
  if (countMinusOne == UINT16_MAX) return nil;
  NSUInteger typeCount = (NSUInteger)countMinusOne + 1;
  if (!RangeFits(typeOffset + 2, typeCount * 8, mapLength)) return nil;
  for (NSUInteger i = 0; i < typeCount; i++) {
    const uint8_t *entry = types + 2 + i * 8;
    if (memcmp(entry, "icns", 4) != 0) continue;
    uint16_t resourceCountMinusOne = ReadBE16(entry + 4);
    if (resourceCountMinusOne == UINT16_MAX) return nil;
    NSUInteger resourceCount = (NSUInteger)resourceCountMinusOne + 1;
    NSUInteger referenceOffset = typeOffset + ReadBE16(entry + 6);
    if (!RangeFits(referenceOffset, resourceCount * 12, mapLength)) return nil;
    for (NSUInteger j = 0; j < resourceCount; j++) {
      const uint8_t *reference = bytes + mapOffset + referenceOffset + j * 12;
      if ((int16_t)ReadBE16(reference) != -16455) continue;
      NSUInteger offset = ((NSUInteger)reference[5] << 16) |
                          ((NSUInteger)reference[6] << 8) | reference[7];
      if (!RangeFits(offset, 4, dataLength)) return nil;
      NSUInteger length = ReadBE32(bytes + dataOffset + offset);
      if (!RangeFits(offset + 4, length, dataLength) || length < 8) return nil;
      return [fork subdataWithRange:NSMakeRange(dataOffset + offset + 4, length)];
    }
  }
  return nil;
}

static BOOL HasUsableCustomIcon(NSString *path) {
  if (!HasCustomIconFlag(path)) return NO;
  NSData *data = CustomIconData(path);
  if (data.length < 8 || memcmp(data.bytes, "icns", 4) != 0 ||
      ReadBE32((const uint8_t *)data.bytes + 4) != data.length) return NO;
  NSImage *image = [[NSImage alloc] initWithData:data];
  return image != nil && image.valid && image.representations.count > 0;
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

static int LoadValidatedIcon(NSString *iconPath, NSImage **validatedImage) {
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
  if (validatedImage != NULL) *validatedImage = icon;
  return 0;
}

static int ValidateIcon(NSString *iconPath) {
  return LoadValidatedIcon(iconPath, NULL);
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

static int RunCommand(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 2) {
      PrintError(@"usage: iconforge-native-icon user-home | set <app-path> <icon-path> | test <app-path> | present <app-path> | diagnose <app-path> | remove <app-path> | validate <icon-path> | normalize <name> | path-key <path> | link-exclusive <source> <target> | rename-exact <source> <target>");
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
      PrintError(@"usage: iconforge-native-icon user-home | set <app-path> <icon-path> | test <app-path> | present <app-path> | diagnose <app-path> | remove <app-path> | validate <icon-path> | normalize <name> | path-key <path> | link-exclusive <source> <target> | rename-exact <source> <target>");
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

    BOOL appValid = IsAppBundle(appPath);
    if (!appValid) {
      PrintError([NSString stringWithFormat:@"app bundle not found or invalid: %@", appPath]);
      if (![command isEqualToString:@"set"] || argc != 4) return kExitInput;
    }

    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;

    if ([command isEqualToString:@"diagnose"]) {
      if (argc != 3) {
        PrintError(@"usage: iconforge-native-icon diagnose <app-path>");
        return kExitUsage;
      }
      return CheckNativeWritePrerequisites(appPath, YES) ? 0 : kExitOperationFailed;
    }

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
      if (!CheckNativeWritePrerequisites(appPath, NO)) return kExitOperationFailed;
      if (![workspace setIcon:nil forFile:appPath options:0]) {
        PrintAppKitFailure(@"remove", appPath);
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
      NSImage *icon = nil;
      int validationStatus = LoadValidatedIcon(iconPath, &icon);
      if (!appValid) return kExitInput;
      BOOL writable = CheckNativeWritePrerequisites(appPath, NO);
      if (validationStatus != 0) return validationStatus;
      if (!writable) return kExitOperationFailed;
      if (![workspace setIcon:icon forFile:appPath options:0]) {
        PrintAppKitFailure(@"set", appPath);
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

static void SaveFailureReport(int argc, const char *argv[], int status) {
  const char *captured = getenv("ICONFORGE_DIAGNOSTIC_CAPTURE");
  if (captured != NULL && strcmp(captured, "1") == 0) return;
  char reportPath[] = "/tmp/iconforge-native-report.XXXXXX";
  int descriptor = mkstemp(reportPath);
  if (descriptor < 0) {
    fprintf(stderr, "iconforge-native-icon: Could not save a report: %s. All diagnostics are printed above.\n", strerror(errno));
    return;
  }
  if (geteuid() == 0) {
    const char *sudoUID = getenv("SUDO_UID");
    char *end = NULL;
    if (sudoUID != NULL && sudoUID[0] >= '0' && sudoUID[0] <= '9') {
      errno = 0;
      unsigned long value = strtoul(sudoUID, &end, 10);
      if (errno == 0 && end != sudoUID && *end == '\0' && value > 0 && value < UINT32_MAX) {
        if (fchown(descriptor, (uid_t)value, (gid_t)-1) != 0) {
          fprintf(stderr, "iconforge-native-icon: Report ownership could not be assigned to the invoking user: %s\n", strerror(errno));
        }
      }
    }
  }
  FILE *report = fdopen(descriptor, "w");
  if (report == NULL) {
    close(descriptor);
    unlink(reportPath);
    fprintf(stderr, "iconforge-native-icon: Could not open the diagnostic report. All diagnostics are printed above.\n");
    return;
  }
  fprintf(report, "IconForge native helper diagnostic report\nDate: %s\nSystem: %s\nuid=%u euid=%u\n",
      NSDate.date.description.UTF8String, NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String,
      getuid(), geteuid());
  for (int i = 1; i < argc; i++) {
    NSString *argument = [NSString stringWithUTF8String:argv[i]];
    fprintf(report, "Argument %d: %s\n", i, DisplayPath(argument).UTF8String);
  }
  for (NSString *message in diagnosticMessages) fprintf(report, "%s\n", message.UTF8String);
  fprintf(report, "Exit status: %d\n", status);
  BOOL failed = ferror(report) != 0;
  if (fclose(report) != 0) failed = YES;
  fprintf(stderr, "iconforge-native-icon: %s: %s\n",
      failed ? "Diagnostic report may be incomplete" : "Full diagnostic report", reportPath);
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    diagnosticMessages = [NSMutableArray array];
    int status = RunCommand(argc, argv);
    if (status != 0) SaveFailureReport(argc, argv, status);
    return status;
  }
}

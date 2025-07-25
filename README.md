# libXelahot

A library for Xelahot's iOS tweaks. It contains reusable stuff.

---
## ✔️ Compatibility

- Should work at least on iOS 14–18

## ⚙️ How to Install
### Jailbroken device:
Install using my jailbreak repository https://xelahot.github.io/ directly on your device or use the pre-compiled releases on this Github repository.

### Non-jailbroken device:
You must make a custom IPA of the app of you want to use a tweak that depends on libXelahot. I use ESign to make it but you could use anything else like Sideloadly:
1. Get a decrypted version of you IPA (you can use TrollDecrypt, CrackerXI, flexdecrypt, bfdecrypt, etc.)
2. Add the "libXelahot.bundle" folder to the "\*.app" folder of your decrypted IPA
3. Either add the "libXelahot.dylib" file from the releases of of this repository to the "\*.app" folder or "\*.app/Frameworks" folder of your decrypted IPA (it depends on the tool and/or options you use in your custom IPA making tool)
4. Either add the "\*.dylib" file from the tweak that depends on libXelahot to the "\*.app" folder or "\*.app/Frameworks" folder of your decrypted IPA (it depends on the tool and/or options you use in your custom IPA making tool)
5. Either add the "CydiaSubstrate.framework" folder (it actually contains the ElleKit binary. I'll include that folder in the releases of this repository) to the "\*.app" folder or "\*.app/Frameworks" folder of your decrypted IPA (it depends on the tool and/or options you use in your custom IPA making tool)
6. Repack/make your custom IPA
7. Sideload/install that custom IPA using a developer certificate or tools Sideloadly, Sidestore, etc.

## 📦 Compilation Prerequisites
- MacOS - Because you will also need XCode (I use a Sequoia 15.3.1 VM)
- Xcode - Because of the new ABI (I manually installed version 16.3 beta 2)
- Theos (https://theos.dev/docs/installation)

## 🔨 How to Compile
- Make sure your tweak's Makefile links libXelahot like this: "MemEdit_LIBRARIES = Xelahot"  (we use "Xelahot" even though the full file name is libXelahot.dylib)
- Add the "Utils/XelaUtils.h" file from this repository to Theos "$(THEOS)/include/Xelahot/Utils/XelaUtils.h" folder. You must do this every time the library code is edited or else your tweak may give you "use of undeclared identifier" errors
- Add the "libXelahot.dylib" file from the releases of this repository to your Theos "$(THEOS)/lib/iphone/rootless/libXelahot.dylib" folder

### Extra steps specific to rootful jailbreak environments:
- Add the "libXelahot.dylib" file from the releases of this repository to your Theos "$(THEOS)/lib/libXelahot.dylib" folder (I'm not sure about this, it may be "$(THEOS)/lib/iphone/libXelahot.dylib")
- Use the master-rootful-jb branch

## ⌨️ How to Use/Code
Since some methods must be executed from the SpringBoard, the tweak that depends libXelahot should inject into it. The library contains useful functions and can be used with inter-process communication (IPC) by sending/receiving notifications. Basically, you can post a notification from a process (ex: the app), listen to it on the other (ex: the SpringBoard) or the opposite.

- **Send notification (with content):**
  ```objc
  NSMutableDictionary *userInfos = [[NSMutableDictionary alloc] init];
  [userInfos setObject:[[NSObject alloc] init] forKey:@"someKey"];
  [[NSDistributedNotificationCenter defaultCenter] postNotificationName::@"com.xelahot.libxelahot/MemEdit/passObject" object:nil userInfo:userInfos];
  ```

- **Receive notification:**
  ```objc
  [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"com.xelahot.libxelahot/MemEdit/passObject"
      object:nil
      queue:nil
      usingBlock:^(NSNotification *notifContent) {
          receivedNotifToPassObjectCallback(notifContent);
      }
  ];
  ```

- **Read contents of a notification:**
  ```objc
  void receivedNotifToPassObjectCallback(NSNotification *notifContent) {
      NSDictionary *dict = notifContent.userInfo;
      NSObject *someObjectThatWasPassedThroughTheNotif = [dict objectForKey:@"someKey"];
  }
  ```

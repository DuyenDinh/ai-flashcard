# LinguaSnap – Xcode Project Setup Guide

## 1. Create the Xcode Project

1. Open Xcode → **New Project** → **iOS App**
2. Product Name: `LinguaSnap`
3. Bundle Identifier: `com.yourname.linguasnap`
4. Interface: SwiftUI | Language: Swift | Storage: SwiftData
5. Save to this folder (replace the generated files with those in this repo)

---

## 2. Add the Share Extension Target

1. File → **New → Target** → **Share Extension**
2. Product Name: `LinguaSnapShare`
3. Bundle ID will be: `com.yourname.linguasnap.ShareExtension`
4. When prompted, do NOT activate the scheme automatically (keep the main app scheme active for debugging)

---

## 3. Configure App Groups (Critical)

Both targets must share the same data store.

### Main App target:
1. Select the **LinguaSnap** target → **Signing & Capabilities**
2. Click `+` → **App Groups**
3. Add: `group.com.yourname.linguasnap`

### Share Extension target:
1. Select the **LinguaSnapShare** target → **Signing & Capabilities**
2. Click `+` → **App Groups**
3. Add the same group: `group.com.yourname.linguasnap`

---

## 4. Add Source Files to Each Target

### Main App target – add these files:
```
LinguaSnap/App/LinguaSnapApp.swift
LinguaSnap/App/ContentView.swift
LinguaSnap/Models/Flashcard.swift
LinguaSnap/Models/SRSEngine.swift
LinguaSnap/Services/LinguaService.swift
LinguaSnap/Shared/SharedDataManager.swift
LinguaSnap/Screens/HomeView.swift
LinguaSnap/Screens/ReviewView.swift
LinguaSnap/Screens/DeckView.swift
LinguaSnap/Screens/CameraOCRView.swift
LinguaSnap/Screens/SettingsView.swift
```

### Share Extension target – add these files (check "LinguaSnapShare" membership):
```
LinguaSnap/Models/Flashcard.swift          ← must be in BOTH targets
LinguaSnap/Models/SRSEngine.swift          ← must be in BOTH targets
LinguaSnap/Services/LinguaService.swift    ← must be in BOTH targets
LinguaSnap/Shared/SharedDataManager.swift  ← must be in BOTH targets
LinguaSnap/ShareExtension/ShareViewController.swift
LinguaSnap/ShareExtension/ExtensionViewModel.swift
```

> **Note:** Select the file in Project Navigator → File Inspector → Target Membership → check both boxes.

---

## 5. Share Extension – NSExtension Info.plist

Replace the default `NSExtension` dict in `LinguaSnapShare/Info.plist` with:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>NSExtensionActivationRule</key>
        <dict>
            <key>NSExtensionActivationSupportsText</key>
            <true/>
            <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
            <integer>1</integer>
        </dict>
    </dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.share-services</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
</dict>
```

---

## 6. Info.plist Permissions (Main App)

Add these keys to `LinguaSnap/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>LinguaSnap uses the camera to scan Swedish text for vocabulary extraction.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>LinguaSnap reads photos to extract Swedish text for vocabulary extraction.</string>
```

---

## 7. API Key

1. Launch the app → Settings tab
2. Paste your Anthropic API key (starts with `sk-ant-`)
3. Tap **Save Key** — stored securely in iOS Keychain

---

## 8. Run & Test

- **Simulator**: Camera is unavailable; use the paste-text fallback in the Scan tab.
- **Device**: All features work including camera OCR and the Share Extension.
- **Share Extension test**: Open Safari → long-press any Swedish text → Share → LinguaSnap.

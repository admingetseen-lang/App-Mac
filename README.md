# GetSeen Cloud — macOS App

Native SwiftUI Mac-App für **GetSeen Cloud** (https://getseen.cloud).

## Voraussetzungen

- **macOS 13 (Ventura) oder neuer** — wegen MenuBarExtra & SwiftUI Features
- **Xcode 15.0 oder neuer**
- (Optional) Apple Developer Account für Code-Signing & Distribution

## Setup

1. **Projekt öffnen:** Doppelklick auf `GetSeen Cloud.xcodeproj`
2. **Bundle Identifier:** ist bereits auf `GetSeen-Cloud.App-Mac` gesetzt
3. **Signing & Capabilities** in Xcode öffnen:
   - Wähle dein Team (oder "None" für lokales Testen)
   - Falls "None": die App läuft, aber nur lokal — keine Distribution
4. **Run:** `Cmd+R` — App startet

## Architektur

```
GetSeen Cloud/
├── GetSeenCloudApp.swift     ← App Entry Point + Commands + MenuBarExtra
├── Models/Models.swift        ← CloudUser, CloudItem, Notifications
├── Services/
│   ├── APIService.swift      ← API-Calls an getseen.cloud/api.php (Cookie-Auth)
│   ├── AuthManager.swift     ← Login/Logout/Session
│   ├── NotificationManager.swift
│   └── FileStore.swift       ← Datei-Verwaltung
├── Views/
│   ├── RootView.swift
│   ├── LoginView.swift       ← GetSeen-Branding (Lila/Blau)
│   ├── DashboardView.swift   ← Sidebar + File-Browser
│   ├── FileItemViews.swift   ← Grid/List
│   ├── DocsEditorView.swift  ← WKWebView für docs.php
│   ├── FilePreviewSheet.swift ← QuickLook
│   ├── SettingsView.swift
│   └── MenuBarView.swift     ← Menüleisten-Icon
├── Resources/Theme.swift      ← Farb-Theme + Button-Styles
└── Assets.xcassets            ← App-Icon + AccentColor
```

## Features

- ✅ **Login** mit Cookie-Session (wie im Web)
- ✅ **Dashboard** mit Sidebar (Meine Dateien, Favoriten, Geteilt, Tresor, Papierkorb)
- ✅ **Grid + List View** mit GetSeen Premium-Badges (alle Datei-Typen)
- ✅ **Drag & Drop Upload** vom Finder
- ✅ **Download** in ~/Downloads (öffnet Finder)
- ✅ **QuickLook Vorschau** (nativ — PDF, Bilder, Video, Audio, Code, Text)
- ✅ **docs.php Editor** als WKWebView (Cookie-geteilt mit nativer Session)
- ✅ **Ordner erstellen, umbenennen** (mit Extension-Schutz wie im Web)
- ✅ **Favoriten** toggeln
- ✅ **Tresor** mit Passwort-Entsperrung
- ✅ **Papierkorb** mit Wiederherstellen / endgültig löschen
- ✅ **Push-Notifications** für Uploads
- ✅ **Menüleisten-Icon** mit Quick Actions
- ✅ **Settings** (Theme, Notifications, Account)
- ✅ **Auto Dark/Light Mode**

## Cookie-Sharing Web ↔ Native

Die App nutzt `HTTPCookieStorage.shared` mit der `URLSession`. Für WKWebView werden
Cookies via `WKWebsiteDataStore.default().httpCookieStore.setCookie()` synchronisiert,
sodass docs.php direkt mit der eingeloggten Session lädt — kein erneuter Login nötig.

## API-Endpoints (genutzt)

```
GET  api.php?action=list&parent_id=X
GET  api.php?action=vault_list | trash_list
POST api.php?action=login   (email, password)
POST api.php?action=logout
GET  api.php?action=profile_get
POST api.php?action=create_folder (name, parent_id)
POST api.php?action=rename (id, name)
POST api.php?action=delete (id)
POST api.php?action=restore (id)
POST api.php?action=delete_permanently (id)
POST api.php?action=toggle_favorite (id)
POST api.php?action=vault_unlock (password)
POST api.php?action=upload (multipart: file, parent_id, [replace_id])
GET  api.php?action=download&id=X
```

## App-Icon

Auto-generiert in Lila/Blau Gradient mit Cloud-Symbol. Eigenes Icon: PNG
(1024×1024 + alle Sizes) in `Assets.xcassets/AppIcon.appiconset/` ablegen.

---

**© 2026 GetSeen UG (haftungsbeschränkt)**

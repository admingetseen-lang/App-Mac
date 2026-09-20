//
//  DashboardView.swift
//  GetSeen Cloud
//

import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var fileStore = FileStore()

    @State private var selectedSection: SidebarSection = .myFiles
    @State private var viewMode: ViewMode = .grid
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .nameAsc
    @State private var searchText = ""
    @State private var showProfile = false
    /// Docs-Editor-Ziel: als Identifiable-Item, damit der Sheet die URL
    /// garantiert kennt (bei isPresented+String wurde er mit "" aufgebaut).
    @State private var docsTarget: DocsTarget? = nil
    @State private var previewItem: CloudItem?
    @State private var renameItem: CloudItem?
    @State private var renameText = ""
    @State private var renameExt = ""
    @State private var newFolderName = ""
    @State private var showNewFolder = false
    @State private var showFileImporter = false
    @State private var isDragOver = false
    @State private var vaultPassword = ""
    @State private var showVaultUnlock = false
    @State private var folderStack: [CloudItem] = []   // Breadcrumb
    @State private var showAIChat = false
    @State private var selectedItemId: String? = nil
    @State private var selectedItemIds: Set<String> = []
    @State private var dropHoverSection: SidebarSection? = nil
    @State private var draggingIDs: [String] = []
    @State private var dropTargetFolderID: String? = nil
    @State private var springWork: DispatchWorkItem? = nil
    @State private var dropTargetCrumb: String? = nil
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var showEmptyTrashConfirm = false
    @State private var shareLinkText: String? = nil
    @State private var showStorage = false
    @State private var versionItem: CloudItem? = nil
    @State private var showAccount = false
    @State private var infoItem: CloudItem? = nil
    @State private var showNotifications = false
    @State private var exportItem: ExportItem? = nil
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    #endif

    var currentParentId: String? { folderStack.last?.id }

    var body: some View {
        content
        .overlay(alignment: .bottomTrailing) { TransferOverlay() }
        #if os(macOS)
        .frame(minWidth: 1100, minHeight: 700)
        #endif
        .navigationTitle("")
        .onAppear {
            #if os(iOS)
            if hSize == .compact { viewMode = .list }
            #endif
            Task { await reload() }
            Task { await fileStore.loadNotifications() }
        }
        .onChange(of: selectedSection) { _ in
            folderStack = []
            selectedItemId = nil
            Task { await reload() }
        }
        .onChange(of: searchText) { q in
            guard selectedSection == .myFiles else { return }
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if searchText == q { await fileStore.search(q) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewDoc)) { _ in openNewDoc() }
        .onReceive(NotificationCenter.default.publisher(for: .createNewFolder)) { _ in showNewFolder = true }
        .onReceive(NotificationCenter.default.publisher(for: .triggerUpload)) { _ in showFileImporter = true }
        .onReceive(NotificationCenter.default.publisher(for: .openAIChat)) { _ in showAIChat = true }
        .onReceive(NotificationCenter.default.publisher(for: .refreshFiles)) { _ in Task { await reload() } }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleFileImporter(result)
        }
        .sheet(item: $renameItem) { _ in renameSheet }
        .sheet(isPresented: $showNewFolder) { newFolderSheet }
        .sheet(isPresented: $showVaultUnlock) { vaultUnlockSheet }
        .sheet(item: $previewItem) { item in
            FilePreviewSheet(item: item, fileStore: fileStore)
        }
        .sheet(item: $docsTarget) { target in
            DocsEditorWindow(url: target.url, onClose: {
                docsTarget = nil
                Task { await reload() }
            })
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet()
                .environmentObject(auth)
        }
        .sheet(isPresented: $showAIChat) {
            AIChatView()
        }
        .sheet(isPresented: $showStorage) {
            StorageBreakdownView(fileStore: fileStore, onClose: { showStorage = false })
        }
        .sheet(item: $versionItem) { item in
            FileVersionsSheet(item: item, fileStore: fileStore, onDone: { Task { await reload() } })
        }
        .sheet(isPresented: $showAccount) {
            AccountSheet(onClose: { showAccount = false })
        }
        .sheet(item: $infoItem) { item in
            FileInfoSheet(item: item, onClose: { infoItem = nil })
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet(fileStore: fileStore, onClose: { showNotifications = false })
        }
        #if os(iOS)
        .sheet(item: $exportItem) { export in
            ShareSheet(items: [export.url])
        }
        #endif
        .alert("Papierkorb wirklich leeren?", isPresented: $showEmptyTrashConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("Endgültig löschen", role: .destructive) {
                Task { await emptyTrash() }
            }
        } message: {
            Text("Alle Dateien im Papierkorb werden endgültig gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.")
        }
        .alert("Freigabe-Link erstellt", isPresented: Binding(
            get: { shareLinkText != nil },
            set: { if !$0 { shareLinkText = nil } }
        )) {
            Button("Link kopieren") { if let l = shareLinkText { PlatformClipboard.copy(l) } }
            Button("OK", role: .cancel) { }
        } message: {
            Text(shareLinkText ?? "")
        }
    }

    // MARK: - Adaptive Container
    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if hSize == .compact { iPhoneTabView } else { splitView }
        #else
        splitView
        #endif
    }

    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            mainContent
                #if os(macOS)
                .background(KeyboardHandler(
                    onArrow: { direction in moveSelection(direction) },
                    onEnter: { openSelected() },
                    onSpace: { previewSelected() },
                    onEscape: { clearSelection() },
                    onBackspace: { if !folderStack.isEmpty { folderStack.removeLast(); Task { await reload() } } }
                ))
                #endif
        }
    }

    #if os(iOS)
    private var iPhoneTabView: some View {
        TabView(selection: Binding(
            get: { selectedSection },
            set: { newSec in
                if newSec == .vault && !fileStore.vaultUnlocked { showVaultUnlock = true }
                else { selectedSection = newSec }
            }
        )) {
            ForEach(SidebarSection.allCases) { sec in
                NavigationStack {
                    mainContent
                        .navigationTitle(sec.rawValue)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) { accountMenu }
                        }
                }
                .tabItem { Label(sec.rawValue, systemImage: sec.iconName) }
                .tag(sec)
            }
        }
    }

    private var accountMenu: some View {
        Menu {
            Button("Profil") { showProfile = true }
            Button("Account & Sicherheit") { showAccount = true }
            Button("Backup herunterladen…") {
                Task { if let url = await fileStore.backupToShare() { exportItem = ExportItem(url: url) } }
            }
            Divider()
            Button("Abmelden", role: .destructive) { auth.requestLogout() }
        } label: {
            avatarCircle(size: 28)
        }
    }
    #endif

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo (extra Top-Padding für Traffic-Lights + Toolbar-Button)
            HStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                Text("GetSeen Cloud")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 50)
            .padding(.bottom, 14)

            Divider().opacity(0.5)

            // Sections
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SidebarSection.allCases) { sec in
                        sidebarButton(sec)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }

            Spacer()

            // User-Card unten
            if let user = auth.currentUser {
                Divider().opacity(0.5)
                HStack(spacing: 10) {
                    avatarCircle(size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName.isEmpty ? user.email : user.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        // Storage Bar (klickbar -> Aufschlüsselung)
                        Button { showStorage = true } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.10)).frame(height: 4)
                                        Capsule().fill(Theme.gradient)
                                            .frame(width: max(2, geo.size.width * user.storagePercent), height: 4)
                                    }
                                }
                                .frame(height: 4)
                                Text("\(formatBytes(user.storageUsed)) / \(formatBytes(user.storageQuota))")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Speicher-Aufschlüsselung anzeigen")
                    }
                    Spacer()
                    Menu {
                        Button("Profil") { showProfile = true }
                        #if os(macOS)
                        if #available(macOS 14.0, *) {
                            SettingsLink {
                                Text("Einstellungen")
                            }
                        } else {
                            Button("Einstellungen") {
                                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                            }
                        }
                        #endif
                        Button("Account & Sicherheit") { showAccount = true }
                        Button("Backup herunterladen…") {
                            Task {
                                #if os(macOS)
                                await fileStore.downloadBackup()
                                #else
                                if let url = await fileStore.backupToShare() { exportItem = ExportItem(url: url) }
                                #endif
                            }
                        }
                        Divider()
                        Button("Abmelden", role: .destructive) {
                            auth.requestLogout()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.secondary, Color.primary.opacity(0.08))
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .fixedSize()
                }
                .padding(12)
            }
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
        .background(Color.platformControlBackground.opacity(0.5))
    }

    private func sidebarButton(_ sec: SidebarSection) -> some View {
        let btn = SidebarButton(section: sec,
                                isActive: selectedSection == sec,
                                isDropTarget: dropHoverSection == sec) {
            if sec == .vault && !fileStore.vaultUnlocked {
                showVaultUnlock = true
            } else {
                selectedSection = sec
            }
        }
        return Group {
            if sec == .favorites || sec == .vault {
                btn.dropDestination(for: URL.self) { urls, _ in
                    dropHoverSection = nil
                    let ids = urls.flatMap { idsFromDragURL($0) }
                    guard !ids.isEmpty else { return false }
                    sidebarDrop([ids.joined(separator: ",")], section: sec)
                    return true
                } isTargeted: { over in
                    dropHoverSection = over ? sec : (dropHoverSection == sec ? nil : dropHoverSection)
                }
            } else {
                btn
            }
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.5)

            if !folderStack.isEmpty {
                breadcrumbBar
                Divider().opacity(0.5)
            }

            ZStack {
                if fileStore.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedSection == .shared {
                    SharesView(fileStore: fileStore)
                } else if filteredItems.isEmpty {
                    emptyState
                } else {
                    filesGrid
                }

                // Drag overlay bei externem Datei-Upload
                if isDragOver {
                    ZStack {
                        Theme.purple.opacity(0.10)
                        VStack(spacing: 16) {
                            Image(systemName: "icloud.and.arrow.up.fill")
                                .font(.system(size: 80, weight: .light))
                                .foregroundStyle(Theme.gradient)
                            Text("Hier loslassen zum Upload")
                                .font(.system(size: 22, weight: .semibold))
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            // Externer Datei-Upload (Finder -> App) über die MODERNE Drop-API.
            // Wichtig: Die alte .onDrop-Fläche kollidierte mit den modernen
            // .dropDestination-Zielen der Ordner-Kacheln darunter (mal gewann
            // die Kachel, mal die Fläche -> Ordner wurden nicht lila).
            // Nur URL-Payloads (externe Dateien) landen hier; interne
            // String-Drags gehen weiterhin an die Ordner-Kacheln.
            // TEST: übergeordnetes Upload-Drop-Ziel vorübergehend deaktiviert
            // (Verdacht: überschattet das Raster-Drop-Ziel darunter).
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        #if os(iOS)
        if hSize == .compact { compactToolbar } else { regularToolbar }
        #else
        regularToolbar
        #endif
    }

    #if os(iOS)
    private var compactToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Suchen…", text: $searchText).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 9))

            Button { viewMode = (viewMode == .grid ? .list : .grid) } label: {
                Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 16, weight: .medium)).foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }.buttonStyle(.plain)

            Button { showNotifications = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell").font(.system(size: 16)).foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                    if fileStore.unreadCount > 0 {
                        Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: 2, y: 0)
                    }
                }
            }.buttonStyle(.plain)

            Button { showAIChat = true } label: {
                Image(systemName: "sparkles").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.gradient).frame(width: 32, height: 32)
            }.buttonStyle(.plain)

            Menu {
                if selectedSection == .trash {
                    Button { Task { await restoreAllFromTrash() } } label: { Label("Alle wiederherstellen", systemImage: "arrow.uturn.backward") }
                    Button(role: .destructive) { showEmptyTrashConfirm = true } label: { Label("Papierkorb leeren", systemImage: "trash") }
                } else {
                    Button { showFileImporter = true } label: { Label("Upload", systemImage: "icloud.and.arrow.up") }
                    Button { showNewFolder = true } label: { Label("Neuer Ordner", systemImage: "folder.badge.plus") }
                    Button { openNewDoc() } label: { Label("Neues Dokument", systemImage: "doc.badge.plus") }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    .frame(width: 34, height: 34).background(Theme.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
    #endif

    private var regularToolbar: some View {
        HStack(spacing: 12) {
            // Section-Titel
            HStack(spacing: 8) {
                Image(systemName: selectedSection.iconName)
                    .foregroundColor(selectedSection.iconColor)
                Text(selectedSection.rawValue)
                    .font(.system(size: 17, weight: .semibold))
            }

            Spacer()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Suchen…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 260)

            // View Toggle
            Picker("", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                Image(systemName: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)

            // Sortierung
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        Label(order.label,
                              systemImage: sortOrder == order ? "checkmark" : order.icon)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 28)
            }
            .fixedSize()
            .help("Sortieren")

            // Benachrichtigungen
            Button { showNotifications = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 28)
                    if fileStore.unreadCount > 0 {
                        Text("\(min(fileStore.unreadCount, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Benachrichtigungen")

            // AI Chat
            HoverIconButton(
                systemName: "sparkles",
                tooltip: "KI-Assistent öffnen",
                useGradient: true
            ) { showAIChat = true }

            if selectedSection == .trash {
                // Papierkorb-Modus: andere Buttons
                ToolbarButton(
                    title: "Alle wiederherstellen",
                    systemImage: "arrow.uturn.backward",
                    style: .secondary
                ) {
                    Task { await restoreAllFromTrash() }
                }

                ToolbarButton(
                    title: "Papierkorb leeren",
                    systemImage: "trash.fill",
                    style: .destructive
                ) {
                    showEmptyTrashConfirm = true
                }
            } else {
                // Normal-Modus
                ToolbarButton(
                    title: "Ordner",
                    systemImage: "folder.badge.plus",
                    style: .secondary
                ) { showNewFolder = true }

                ToolbarButton(
                    title: "Neues Doc",
                    systemImage: "doc.badge.plus",
                    style: .primary
                ) { openNewDoc() }

                ToolbarButton(
                    title: "Upload",
                    systemImage: "icloud.and.arrow.up",
                    style: .primary
                ) { showFileImporter = true }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Button {
                folderStack = []
                Task { await reload() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "house.fill")
                    Text(selectedSection.rawValue)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(dropTargetCrumb == "__root__" ? Theme.purple.opacity(0.22) : Color.clear))
            }
            .buttonStyle(.plain)
            .foregroundColor(dropTargetCrumb == "__root__" ? Theme.purple : .secondary)
            .dropDestination(for: URL.self) { urls, _ in
                dropTargetCrumb = nil
                let ids = urls.flatMap { idsFromDragURL($0) }
                guard !ids.isEmpty else { return false }
                moveDropped([ids.joined(separator: ",")], toFolder: nil)
                return true
            } isTargeted: { over in
                dropTargetCrumb = over ? "__root__" : (dropTargetCrumb == "__root__" ? nil : dropTargetCrumb)
            }

            ForEach(Array(folderStack.enumerated()), id: \.element.id) { idx, folder in
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Button {
                    folderStack = Array(folderStack.prefix(idx + 1))
                    Task { await reload() }
                } label: {
                    Text(folder.name)
                        .font(.system(size: 12, weight: idx == folderStack.count - 1 ? .semibold : .medium))
                        .foregroundColor(dropTargetCrumb == folder.id ? Theme.purple
                                         : (idx == folderStack.count - 1 ? .primary : .secondary))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(dropTargetCrumb == folder.id ? Theme.purple.opacity(0.22) : Color.clear))
                }
                .buttonStyle(.plain)
                .dropDestination(for: URL.self) { urls, _ in
                    dropTargetCrumb = nil
                    let ids = urls.flatMap { idsFromDragURL($0) }
                    guard !ids.isEmpty else { return false }
                    moveDropped([ids.joined(separator: ",")], toFolder: folder.id)
                    return true
                } isTargeted: { over in
                    dropTargetCrumb = over ? folder.id : (dropTargetCrumb == folder.id ? nil : dropTargetCrumb)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    @State private var rubberBandStart: CGPoint? = nil
    @State private var rubberBandCurrent: CGPoint? = nil

    @ViewBuilder
    private var filesGrid: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                // Auswahl-Fläche (Rubber-Band). Liegt UNTER den Kacheln; Drops auf
                // Ordner treffen die Kacheln, freie Drags starten die Marquee.
                // Rahmen-Auswahl (Marquee). Hintergrundfläche mit Auswahl-Geste.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(minHeight: 600)
                    .gesture(
                        DragGesture(minimumDistance: 6, coordinateSpace: .named("gridSpace"))
                            .onChanged { value in
                                if rubberBandStart == nil {
                                    rubberBandStart = value.startLocation
                                    selectedItemIds = []
                                    selectedItemId = nil
                                }
                                rubberBandCurrent = value.location
                                updateRubberBandSelection()
                            }
                            .onEnded { _ in
                                rubberBandStart = nil
                                rubberBandCurrent = nil
                            }
                    )
                    .onTapGesture {
                        selectedItemIds = []
                        selectedItemId = nil
                    }

                // Items-Layer
                if viewMode == .grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)], spacing: 16) {
                        ForEach(filteredItems) { item in
                            gridCell(for: item)
                        }
                    }
                    .padding(20)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            rowCell(for: item)
                            Divider().opacity(0.3)
                        }
                    }
                    .padding(.vertical, 4)
                }

            }
            .coordinateSpace(name: "gridSpace")
            // Auswahl-Rechteck als OVERLAY (nicht als ZStack-Kind), damit es die
            // Layout-Breite des Grids nicht vergrößert -> kein Verrutschen/Reflow.
            .overlay(alignment: .topLeading) { rubberBandOverlay }
            .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                // Async: verhindert die Layout-Rekursion (State-Änderung während
                // des Layouts), die die Ansicht mitten im Ziehen destabilisierte.
                DispatchQueue.main.async { itemFrames = frames }
            }
            // EIN stabiles Drop-Ziel für das ganze Raster. Ermittelt den Zielordner
            // aus der Cursor-Position (itemFrames) -> zuverlässig, anders als
            // Drop-Ziele auf einzelnen LazyVGrid-Kacheln.
            .contentShape(Rectangle())
            // Internes Verschieben – EIN stabiles Ziel fürs ganze Raster. Der
            // Delegate kennt die Cursor-Position: er hebt den Ordner darunter
            // lila hervor (dropUpdated) und verschiebt beim Ablegen (performDrop).
            .onDrop(of: [UTType.url, UTType.fileURL], delegate: GridFolderDropDelegate(
                folderID: { folderID(at: $0) },
                setTarget: { dropTargetFolderID = $0 },
                setUploadHint: { isDragOver = $0 },
                performMove: { fid, ids in
                    dropTargetFolderID = nil
                    moveDropped([ids.joined(separator: ",")], toFolder: fid)
                },
                performUpload: { urls in
                    isDragOver = false
                    Task {
                        for url in urls { fileStore.upload(url: url, parentId: currentParentId) }
                        await reload()
                        await MainActor.run { isDragOver = false }
                    }
                }
            ))
        }
        .clipped()
    }

    @ViewBuilder
    private var rubberBandOverlay: some View {
        if let start = rubberBandStart, let current = rubberBandCurrent {
            GeometryReader { geo in
                // Auf den sichtbaren Bereich begrenzen -> stoppt am linken UND
                // rechten Fensterrand statt darüber hinauszuwachsen.
                let maxX = geo.size.width
                let sx = min(max(start.x, 0), maxX)
                let cx = min(max(current.x, 0), maxX)
                let sy = max(start.y, 0)
                let cy = max(current.y, 0)
                let x = min(sx, cx)
                let y = min(sy, cy)
                Rectangle()
                    .fill(Theme.purple.opacity(0.15))
                    .overlay(Rectangle().strokeBorder(Theme.purple.opacity(0.7), lineWidth: 1))
                    .frame(width: abs(cx - sx), height: abs(cy - sy))
                    .offset(x: x, y: y)
            }
            .allowsHitTesting(false)
        }
    }

    private func updateRubberBandSelection() {
        guard let start = rubberBandStart, let current = rubberBandCurrent else { return }
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        var newSelection = Set<String>()
        for (id, frame) in itemFrames where rect.intersects(frame) {
            newSelection.insert(id)
        }
        selectedItemIds = newSelection
        selectedItemId = newSelection.first
    }

    /// Gemeinsamer Interaktions-„Rahmen“ um eine Kachel/Zeile: Frame-Messung
    /// für die Rahmen-Auswahl, Klick-Gesten und Kontextmenü. Liegt bewusst
    /// AUSSEN um das Drop-Ziel, damit das Ziel selbst schlank bleibt (wie die
    /// Seitenleisten-Schaltfläche, die immer zuverlässig funktioniert).
    private func cellChrome<V: View>(_ content: V, item: CloudItem) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ItemFramePreferenceKey.self,
                                    value: [item.id: geo.frame(in: .named("gridSpace"))])
                }
            )
            #if os(macOS)
            .simultaneousGesture(TapGesture(count: 2).onEnded { openItem(item) })
            #endif
            #if os(macOS)
            .simultaneousGesture(
                TapGesture(count: 1).modifiers(.command).onEnded {
                    toggleSelect(item.id)
                }
            )
            #endif
            .simultaneousGesture(
                TapGesture(count: 1).onEnded {
                    #if os(iOS)
                    openItem(item)
                    #else
                    selectedItemIds = [item.id]
                    selectedItemId = item.id
                    #endif
                }
            )
            .contextMenu { itemContextMenu(item) }
    }

    @ViewBuilder
    private func gridCell(for item: CloudItem) -> some View {
        let cell = cellChrome(
            FileGridItem(item: item, isSelected: selectedItemIds.contains(item.id), isDropTarget: dropTargetFolderID == item.id,
                         onToggleFavorite: { Task { await fileStore.toggleFavorite(item); await reload() } })
                .contentShape(Rectangle()),
            item: item)

        if item.isFolder && item.deletedAt == nil {
            cell   // Drop wird zentral über gridDropDelegate gehandhabt (LazyVGrid-Kacheln sind unzuverlässig)
        } else {
            cell.draggable(dragURL(for: item)) { dragPreview(for: item) }
        }
    }

    @ViewBuilder
    private func rowCell(for item: CloudItem) -> some View {
        let cell = cellChrome(
            FileRowItem(item: item, isSelected: selectedItemIds.contains(item.id), isDropTarget: dropTargetFolderID == item.id,
                        onToggleFavorite: { Task { await fileStore.toggleFavorite(item); await reload() } })
                .contentShape(Rectangle()),
            item: item)

        if item.isFolder && item.deletedAt == nil {
            cell   // Drop zentral über gridDropDelegate
        } else {
            cell.draggable(dragURL(for: item)) { dragPreview(for: item) }
        }
    }

    private func toggleSelect(_ id: String) {
        if selectedItemIds.contains(id) {
            selectedItemIds.remove(id)
            if selectedItemId == id { selectedItemId = selectedItemIds.first }
        } else {
            selectedItemIds.insert(id)
            selectedItemId = id
        }
    }

    // MARK: - Drag & Drop Provider

    /// Welche Objekte werden gezogen? Ist das angefasste Objekt Teil einer
    /// Mehrfachauswahl, wandern ALLE ausgewählten mit; sonst nur dieses eine.
    private func dragSet(for item: CloudItem) -> [String] {
        if selectedItemIds.contains(item.id) && selectedItemIds.count > 1 {
            return Array(selectedItemIds)
        }
        return [item.id]
    }

    /// Drag-Vorschau mit Zähler-Badge bei Mehrfachauswahl („+N in der Hand").
    @ViewBuilder
    private func dragPreview(for item: CloudItem) -> some View {
        let count = dragSet(for: item).count
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Theme.gradient)
                    .frame(width: 30, height: 30)
                Image(systemName: count > 1 ? "square.stack.3d.up.fill" : item.iconSystemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(count > 1 ? "\(count) Objekte" : item.name)
                .lineLimit(1)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.platformControlBackground)
                .shadow(color: .black.opacity(0.20), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.purple.opacity(0.35), lineWidth: 1)
        )
        .fixedSize()
    }

    /// Nutzlast des Drags: die IDs der zu ziehenden Objekte (kommagetrennt).
    /// Interner Drag-Träger: URL mit eigenem Schema. So sind interner Zug und
    /// Finder-Datei beide URLs -> EIN Ziel kann beides annehmen und sicher
    /// unterscheiden (getseen:// = verschieben, file:// = hochladen).
    private func dragURL(for item: CloudItem) -> URL {
        let ids = dragSet(for: item).joined(separator: ",")
        return URL(string: "getseen://items/\(ids)") ?? URL(string: "getseen://items/")!
    }

    /// IDs aus einer internen Drag-URL; leer, wenn es keine interne URL ist.
    private func idsFromDragURL(_ url: URL) -> [String] {
        guard url.scheme == "getseen" else { return [] }
        return url.lastPathComponent.split(separator: ",").map(String.init)
    }

    /// Zerlegt die von .dropDestination übergebenen Strings in einzelne IDs.
    private func parseDropped(_ items: [String]) -> [String] {
        items.flatMap { $0.split(separator: ",").map(String.init) }
    }

    /// Verschiebt abgelegte Objekte in einen Ordner (oder Wurzel).
    private func moveDropped(_ items: [String], toFolder targetID: String?) {
        dropTargetFolderID = nil
        let ids = parseDropped(items).filter { $0 != targetID }
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            await fileStore.moveItems(ids: ids, targetId: targetID)
            await reload()
        }
    }

    /// Ablegen auf einen Seitenleisten-Eintrag (Favoriten / Tresor).
    private func sidebarDrop(_ items: [String], section: SidebarSection) {
        let ids = parseDropped(items)
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            switch section {
            case .favorites:
                await fileStore.addToFavorites(ids: ids)
            case .vault:
                if fileStore.vaultUnlocked {
                    await fileStore.moveToVault(ids: ids, enabled: true)
                } else {
                    showVaultUnlock = true
                    return
                }
            default:
                return
            }
            await reload()
        }
    }

    private func makeDragProvider(for item: CloudItem) -> NSItemProvider {
        let ids = dragSet(for: item)
        draggingIDs = ids   // zuverlässige In-Process-Übergabe für interne Moves

        // Standard-NSString-Provider: registriert public.plain-text /
        // public.utf8-plain-text so, wie das System (macOS 26+) es zum
        // Erkennen des Drop-Ziels erwartet. Der interne Move nutzt ohnehin
        // draggingIDs; der Text ist nur der Träger, damit onDrop anspringt.
        let payload = "getseen-items:" + ids.joined(separator: ",")
        let provider = NSItemProvider(object: payload as NSString)
        return provider
    }

    /// Verschiebt die gerade gezogenen Objekte in einen Ordner (oder Wurzel).
    private func handleInternalMove(toFolder targetID: String?) {
        let ids = draggingIDs.filter { $0 != targetID }
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            await fileStore.moveItems(ids: ids, targetId: targetID)
            draggingIDs = []
            await reload()
        }
    }

    /// Ablegen auf einen Seitenleisten-Eintrag (Favoriten / Tresor).
    private func handleSidebarDrop(section: SidebarSection) {
        let ids = draggingIDs
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            switch section {
            case .favorites:
                await fileStore.addToFavorites(ids: ids)
            case .vault:
                if fileStore.vaultUnlocked {
                    await fileStore.moveToVault(ids: ids, enabled: true)
                } else {
                    showVaultUnlock = true
                    return
                }
            default:
                return
            }
            draggingIDs = []
            await reload()
        }
    }

    /// Highlight-Binding fürs Ordner-Drop-Ziel + Spring-Loaded Öffnen:
    /// 1 Sek. über einem Ordner verweilen öffnet dessen Ebene.
    /// Drag betritt einen Ordner: lila markieren + Spring-Loading (nach 1s öffnen).
    private func dropEnterFolder(_ id: String) {
        // Nur Highlight – KEIN Auto-Öffnen (das baute die Ansicht mitten im Zug
        // neu auf und tötete danach alle Drop-Ziele). In Ordner: Doppelklick.
        dropTargetFolderID = id
    }

    /// Drag verlässt den Ordner wieder.
    private func dropExitFolder(_ id: String) {
        if dropTargetFolderID == id { dropTargetFolderID = nil }
        springWork?.cancel()
        springWork = nil
    }

    /// Verschiebt via Kontextmenü (die Auswahl, falls das Objekt Teil einer ist).
    private func moveViaMenu(_ item: CloudItem, to targetID: String?) {
        let ids: [String] = (selectedItemIds.contains(item.id) && selectedItemIds.count > 1)
            ? Array(selectedItemIds) : [item.id]
        let moveIDs = ids.filter { $0 != targetID }
        guard !moveIDs.isEmpty else { return }
        Task { @MainActor in
            await fileStore.moveItems(ids: moveIDs, targetId: targetID)
            await reload()
        }
    }

    /// Untermenü „Verschieben nach" mit Hauptordner, Pfad-Ebenen und Unterordnern.
    @ViewBuilder
    private func moveMenu(for item: CloudItem) -> some View {
        Menu("Verschieben nach") {
            if currentParentId != nil {
                Button { moveViaMenu(item, to: nil) } label: {
                    Label(selectedSection.rawValue, systemImage: "house")
                }
            }
            let pathFolders = Array(folderStack.dropLast())
            ForEach(pathFolders) { folder in
                Button { moveViaMenu(item, to: folder.id) } label: {
                    Label(folder.name, systemImage: "folder")
                }
            }
            let subfolders = filteredItems.filter { $0.isFolder && $0.deletedAt == nil && $0.id != item.id }
            if !subfolders.isEmpty {
                if currentParentId != nil || !pathFolders.isEmpty { Divider() }
                ForEach(subfolders) { folder in
                    Button { moveViaMenu(item, to: folder.id) } label: {
                        Label(folder.name, systemImage: "folder.fill")
                    }
                }
            }
        }
    }

    /// Farb-Eintrag im Kontextmenü mit Haken bei der aktuell gewählten Farbe.
    @ViewBuilder
    private func colorMenuButton(_ item: CloudItem, _ title: String, _ value: String) -> some View {
        Button {
            Task { await fileStore.setColor(item, color: value); await reload() }
        } label: {
            if (item.color ?? "") == value {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func itemContextMenu(_ item: CloudItem) -> some View {
        if item.isFolder {
            if item.deletedAt == nil {
                Button("Öffnen") { openItem(item) }
            }
        } else {
            if item.deletedAt == nil {
                if item.isGdoc {
                    Button("Im Editor öffnen") { openInEditor(item) }
                } else {
                    Button("Vorschau") { previewItem = item }
                }
                Button("Herunterladen") {
                    #if os(macOS)
                    fileStore.download(item)
                    #else
                    Task { if let url = await fileStore.downloadToTemp(item) { exportItem = ExportItem(url: url) } }
                    #endif
                }
                if !item.isVault {
                    Button("Teilen…") {
                        Task {
                            if let link = await fileStore.createShare(item) { shareLinkText = link }
                        }
                    }
                }
                Button("Versionen…") { versionItem = item }
                if item.isArchive {
                    Button("Entpacken") {
                        Task { if await fileStore.extractZip(item) { await reload() } }
                    }
                }
            }
        }
        if item.deletedAt == nil {
            Divider()
            Button(item.isFavorite ? "Favorit entfernen" : "Als Favorit") {
                Task { await fileStore.toggleFavorite(item) }
            }
            Button("Umbenennen") { startRename(item) }
            moveMenu(for: item)
            Button(item.isVault ? "Aus Tresor entfernen" : "In Tresor verschieben") {
                if fileStore.vaultUnlocked {
                    Task { await fileStore.moveToVault(item, enabled: !item.isVault); await reload() }
                } else {
                    showVaultUnlock = true
                }
            }
            Button("Informationen") { infoItem = item }
            Menu("Farbe") {
                colorMenuButton(item, "Keine",  "")
                colorMenuButton(item, "Lila",   "purple")
                colorMenuButton(item, "Blau",   "blue")
                colorMenuButton(item, "Grün",   "green")
                colorMenuButton(item, "Orange", "orange")
                colorMenuButton(item, "Rot",    "red")
                colorMenuButton(item, "Grau",   "gray")
            }
        }
        Divider()
        if item.deletedAt != nil {
            Button("Wiederherstellen") { Task { await fileStore.restore(item); await reload() } }
            Button("Endgültig löschen", role: .destructive) { Task { await fileStore.deletePermanently(item); await reload() } }
        } else {
            Button("In Papierkorb", role: .destructive) { Task { await fileStore.delete(item); await reload() } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedSection == .trash ? "trash" : "folder")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundColor(.secondary.opacity(0.5))
            Text(emptyMessage)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            if selectedSection == .myFiles && folderStack.isEmpty {
                Text("Datei hierher ziehen oder oben hochladen")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        switch selectedSection {
        case .myFiles: return folderStack.isEmpty ? "Noch keine Dateien" : "Dieser Ordner ist leer"
        case .favorites: return "Keine Favoriten"
        case .shared: return "Nichts geteilt"
        case .vault: return "Tresor ist leer"
        case .trash: return "Papierkorb ist leer"
        }
    }

    // MARK: - Filtered Items
    private var filteredItems: [CloudItem] {
        let base: [CloudItem]
        if searchText.isEmpty {
            base = fileStore.items
        } else if selectedSection == .myFiles {
            base = fileStore.searchResults
        } else {
            base = fileStore.items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return sortItems(base)
    }

    /// Ordner-ID an einer Cursor-Position (im „gridSpace") oder nil.
    private func folderID(at point: CGPoint) -> String? {
        for item in filteredItems where item.isFolder && item.deletedAt == nil {
            if let f = itemFrames[item.id], f.contains(point) { return item.id }
        }
        return nil
    }

    /// Sortiert: Ordner immer zuerst, dann nach gewählter Reihenfolge.
    private func sortItems(_ items: [CloudItem]) -> [CloudItem] {
        items.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            switch sortOrder {
            case .nameAsc:  return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .nameDesc: return a.name.localizedStandardCompare(b.name) == .orderedDescending
            case .dateAsc:  return a.createdAt < b.createdAt
            case .dateDesc: return a.createdAt > b.createdAt
            case .sizeAsc:  return a.sizeBytes < b.sizeBytes
            case .sizeDesc: return a.sizeBytes > b.sizeBytes
            }
        }
    }

    // MARK: - Actions
    private func reload() async {
        switch selectedSection {
        case .myFiles: await fileStore.loadList(parentId: currentParentId)
        case .favorites: await fileStore.loadFavorites()
        case .shared: await fileStore.loadShared()
        case .vault: await fileStore.loadVault()
        case .trash: await fileStore.loadTrash()
        }
        // Cleanup nach Reload — stale Selection und Rubber-Band-State entfernen
        await MainActor.run {
            rubberBandStart = nil
            rubberBandCurrent = nil
            let validIds = Set(filteredItems.map { $0.id })
            selectedItemIds = selectedItemIds.intersection(validIds)
            if let sel = selectedItemId, !validIds.contains(sel) {
                selectedItemId = selectedItemIds.first
            }
        }
    }

    private func openItem(_ item: CloudItem) {
        if item.isFolder {
            folderStack.append(item)
            selectedItemId = nil
            Task { await reload() }
        } else if item.isGdoc {
            openInEditor(item)
        } else {
            previewItem = item
        }
    }

    // MARK: - Keyboard Navigation
    private func moveSelection(_ direction: ArrowDirection) {
        let items = filteredItems
        guard !items.isEmpty else { return }

        guard let currentId = selectedItemId,
              let currentIdx = items.firstIndex(where: { $0.id == currentId }) else {
            let firstId = items.first?.id
            selectedItemId = firstId
            selectedItemIds = firstId.map { [$0] } ?? []
            return
        }

        let columns = max(1, gridColumnsApprox())
        var newIdx = currentIdx
        switch direction {
        case .left:  newIdx = max(0, currentIdx - 1)
        case .right: newIdx = min(items.count - 1, currentIdx + 1)
        case .up:
            newIdx = viewMode == .grid
                ? max(0, currentIdx - columns)
                : max(0, currentIdx - 1)
        case .down:
            newIdx = viewMode == .grid
                ? min(items.count - 1, currentIdx + columns)
                : min(items.count - 1, currentIdx + 1)
        }
        let newId = items[newIdx].id
        selectedItemId = newId
        selectedItemIds = [newId]
    }

    private func openSelected() {
        guard let id = selectedItemId,
              let item = filteredItems.first(where: { $0.id == id }) else { return }
        openItem(item)
    }

    private func previewSelected() {
        guard let id = selectedItemId,
              let item = filteredItems.first(where: { $0.id == id }),
              !item.isFolder else { return }
        if item.isGdoc { openInEditor(item) } else { previewItem = item }
    }

    private func clearSelection() {
        selectedItemId = nil
        selectedItemIds = []
    }

    // MARK: - Trash Operationen
    private func emptyTrash() async {
        let toDelete = filteredItems  // alles was aktuell im Trash sichtbar ist
        for item in toDelete {
            await fileStore.deletePermanently(item)
        }
        await reload()
        clearSelection()
    }

    private func restoreAllFromTrash() async {
        let toRestore = filteredItems
        for item in toRestore {
            await fileStore.restore(item)
        }
        await reload()
        clearSelection()
    }

    private func gridColumnsApprox() -> Int {
        return 5
    }

    private func openNewDoc() {
        var url = "https://getseen.cloud/docs?new=1"
        if let pid = currentParentId {
            url += "&parent_id=\(pid)"
        }
        docsTarget = DocsTarget(url: url)
    }

    private func openInEditor(_ item: CloudItem) {
        docsTarget = DocsTarget(url: "https://getseen.cloud/docs?id=\(item.id)")
    }

    private func startRename(_ item: CloudItem) {
        var base = item.name
        var ext = ""
        if item.isFile, let dot = item.name.lastIndex(of: ".") {
            base = String(item.name[..<dot])
            ext = String(item.name[dot...])
        }
        renameText = base
        renameExt = ext
        renameItem = item
    }

    // MARK: - Sheets
    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Umbenennen")
                .font(.system(size: 18, weight: .bold))

            HStack(spacing: 0) {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)
                if !renameExt.isEmpty {
                    Text(renameExt)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.leading, 6)
                }
            }
            if !renameExt.isEmpty {
                Text("Die Dateiendung bleibt erhalten")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Spacer()
                SheetButton(
                    title: "Abbrechen",
                    style: .secondary,
                    keyboardShortcut: .cancelAction
                ) { renameItem = nil }
                SheetButton(
                    title: "Umbenennen",
                    style: .primary,
                    keyboardShortcut: .defaultAction,
                    isDisabled: renameText.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    if let item = renameItem {
                        let finalName = renameText.trimmingCharacters(in: .whitespaces) + renameExt
                        Task {
                            await fileStore.rename(item, newName: finalName)
                            renameItem = nil
                            await reload()
                        }
                    }
                }
            }
        }
        .padding(28)
        #if os(macOS)
        .frame(width: 420)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var newFolderSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.gradient.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.gradient)
                }
                Text("Neuer Ordner")
                    .font(.system(size: 18, weight: .bold))
            }
            TextField("Ordnername", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))

            HStack(spacing: 10) {
                Spacer()
                SheetButton(
                    title: "Abbrechen",
                    style: .secondary,
                    keyboardShortcut: .cancelAction
                ) {
                    showNewFolder = false
                    newFolderName = ""
                }
                SheetButton(
                    title: "Erstellen",
                    style: .primary,
                    keyboardShortcut: .defaultAction,
                    isDisabled: newFolderName.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    let name = newFolderName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        await fileStore.createFolder(name: name, parentId: currentParentId)
                        showNewFolder = false
                        newFolderName = ""
                        await reload()
                    }
                }
            }
        }
        .padding(28)
        #if os(macOS)
        .frame(width: 420)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var vaultUnlockSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.pink)
                Text("Tresor entsperren")
                    .font(.system(size: 18, weight: .bold))
            }
            SecureField("Tresor-Passwort", text: $vaultPassword)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Abbrechen") {
                    showVaultUnlock = false
                    vaultPassword = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("Entsperren") {
                    Task {
                        let ok = await fileStore.unlockVault(password: vaultPassword)
                        if ok {
                            showVaultUnlock = false
                            vaultPassword = ""
                            selectedSection = .vault
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PremiumPrimaryButtonStyle())
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 380)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Drag & Drop
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url = url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task {
                for url in urls {
                    fileStore.upload(url: url, parentId: currentParentId)
                }
                await reload()
            }
        }
        return true
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            Task {
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    fileStore.upload(url: url, parentId: currentParentId)
                }
                await reload()
            }
        }
    }

    // MARK: - Helpers
    @ViewBuilder
    private func avatarCircle(size: CGFloat) -> some View {
        if let avatarStr = auth.currentUser?.avatarURL,
           let url = URL(string: avatarStr.hasPrefix("http") ? avatarStr : "https://getseen.cloud/\(avatarStr)") {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Theme.gradient
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            ZStack {
                Theme.gradient
                Text(String(auth.currentUser?.displayName.first ?? auth.currentUser?.email.first ?? "?").uppercased())
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Hover-Wrapper für Buttons (für Lift-Animation + Glow)
struct HoverWrapper<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        content()
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .shadow(color: isHovered ? Theme.purple.opacity(0.40) : Color.clear,
                    radius: isHovered ? 12 : 0, y: isHovered ? 3 : 0)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.14), value: isHovered)
    }
}

// MARK: - Sheet-Button (Erstellen / Abbrechen) mit Hover + großer Größe
struct SheetButton: View {
    let title: String
    let style: ToolbarButtonStyle
    var keyboardShortcut: KeyboardShortcut? = nil
    var isDisabled: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let btn = Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(
                    style == .primary
                    ? .white
                    : (isDisabled ? .secondary : .primary)
                )
                .padding(.horizontal, 22)
                .frame(height: 38)
                .background(
                    ZStack {
                        if style == .primary {
                            Theme.gradient
                                .opacity(isDisabled ? 0.5 : 1.0)
                        } else {
                            Color.primary.opacity(isHovered ? 0.12 : 0.06)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(
                            style == .primary
                            ? Color.white.opacity(0.20)
                            : (isHovered ? Theme.purple.opacity(0.40) : Color.primary.opacity(0.10)),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: style == .primary
                        ? Theme.purple.opacity(isHovered && !isDisabled ? 0.50 : 0.25)
                        : Color.black.opacity(isHovered ? 0.08 : 0.04),
                    radius: isHovered ? 10 : 4,
                    y: isHovered ? 3 : 1
                )
                .scaleEffect(isHovered && !isDisabled ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)

        if let shortcut = keyboardShortcut {
            btn.keyboardShortcut(shortcut)
        } else {
            btn
        }
    }
}

// MARK: - Einheitlicher Toolbar Button mit Hover
enum ToolbarButtonStyle { case primary, secondary, destructive }

struct ToolbarButton: View {
    let title: String
    let systemImage: String
    let style: ToolbarButtonStyle
    let action: () -> Void
    @State private var isHovered = false

    private var fgColor: Color {
        switch style {
        case .primary: return .white
        case .destructive: return .white
        case .secondary: return .primary
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary: return Color.white.opacity(0.20)
        case .destructive: return Color.white.opacity(0.20)
        case .secondary: return isHovered ? Theme.purple.opacity(0.35) : Color.primary.opacity(0.08)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .primary: return Theme.purple.opacity(isHovered ? 0.45 : 0.25)
        case .destructive: return Color.red.opacity(isHovered ? 0.50 : 0.30)
        case .secondary: return Color.black.opacity(isHovered ? 0.08 : 0.04)
        }
    }

    @ViewBuilder
    private var bg: some View {
        switch style {
        case .primary:
            Theme.gradient
        case .destructive:
            LinearGradient(
                colors: [Color.red, Color(red: 0.85, green: 0.20, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            Color.primary.opacity(isHovered ? 0.10 : 0.06)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(fgColor)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: isHovered ? 8 : 4, y: isHovered ? 3 : 1)
            .scaleEffect(isHovered ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Icon-Button mit Hover-Animation für Toolbar
struct HoverIconButton: View {
    let systemName: String
    let tooltip: String
    var useGradient: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    useGradient ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary)
                )
                .frame(width: 36, height: 32)
                .background(
                    isHovered
                    ? Color.primary.opacity(0.12)
                    : Color.primary.opacity(0.06)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isHovered ? Theme.purple.opacity(0.35) : Color.primary.opacity(0.10),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scaleEffect(isHovered ? 1.04 : 1.0)
                .shadow(color: isHovered ? Theme.purple.opacity(0.35) : Color.clear,
                        radius: isHovered ? 8 : 0, y: 2)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }
}

// MARK: - Sidebar Button mit Hover-Animation
struct SidebarButton: View {
    let section: SidebarSection
    let isActive: Bool
    var isDropTarget: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.iconName)
                    .foregroundColor(section.iconColor)
                    .frame(width: 18)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isDropTarget
                ? AnyView(Theme.purple.opacity(0.25))
                : (isActive
                   ? AnyView(section.iconColor.opacity(0.18))
                   : (isHovered ? AnyView(Color.primary.opacity(0.08)) : AnyView(Color.clear)))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isDropTarget ? Theme.purple.opacity(0.7)
                        : (isActive ? section.iconColor.opacity(0.30) : Color.clear),
                        lineWidth: isDropTarget ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovered)
        .animation(.easeOut(duration: 0.10), value: isActive)
    }
}

// MARK: - Item-Frame PreferenceKey
struct ItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Arrow direction für Keyboard-Navigation
enum ArrowDirection {
    case up, down, left, right
}

#if os(macOS)
// MARK: - Globaler NSEvent-Monitor für Pfeiltasten/Enter/Space/Esc/Backspace
// (Ein local monitor bekommt alle keyDown-Events egal welcher View Fokus hat)
struct KeyboardHandler: NSViewRepresentable {
    var onArrow: (ArrowDirection) -> Void
    var onEnter: () -> Void
    var onSpace: () -> Void
    var onEscape: () -> Void
    var onBackspace: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.attach()
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var parent: KeyboardHandler
        private var monitor: Any?

        init(_ parent: KeyboardHandler) {
            self.parent = parent
        }

        func attach() {
            // local monitor — bekommt alle keyDown-Events des Prozesses
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                // Nur reagieren, wenn das Hauptfenster vorn ist und KEIN Sheet offen ist.
                // (Sonst schluckt der Monitor Tasten in Sheets: Umbenennen, Tresor, AI-Chat …)
                guard let keyWin = NSApp.keyWindow,
                      keyWin == NSApp.mainWindow,
                      keyWin.attachedSheet == nil else { return event }

                // Wenn ein TextField fokussiert ist, Event durchlassen (sonst Schreiben kaputt)
                if let resp = keyWin.firstResponder,
                   resp is NSTextView || String(describing: type(of: resp)).contains("Text") {
                    return event
                }

                switch event.keyCode {
                case 123: self.parent.onArrow(.left);  return nil   // ←
                case 124: self.parent.onArrow(.right); return nil   // →
                case 125: self.parent.onArrow(.down);  return nil   // ↓
                case 126: self.parent.onArrow(.up);    return nil   // ↑
                case 36, 76: self.parent.onEnter();    return nil   // ⏎
                case 49:     self.parent.onSpace();    return nil   // Space
                case 53:     self.parent.onEscape();   return nil   // Esc
                case 51:     self.parent.onBackspace();return nil   // Backspace
                default: return event
                }
            }
        }

        func detach() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit { detach() }
    }
}
#endif

// MARK: - Interner Move-Drop-Delegate
// Aktiviert das Drop-Ziel zuverlässig auf macOS 26+ (die isTargeted-Bindung
// sprang dort nicht mehr an) und erzwingt die .copy-Operation, damit
// performDrop garantiert ausgelöst wird.
struct InternalMoveDropDelegate: DropDelegate {
    let canDrop: () -> Bool
    let onEntered: () -> Void
    let onExited: () -> Void
    let onPerform: () -> Void

    func validateDrop(info: DropInfo) -> Bool { canDrop() }
    func dropEntered(info: DropInfo) { onEntered() }
    func dropExited(info: DropInfo) { onExited() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }
    func performDrop(info: DropInfo) -> Bool {
        guard canDrop() else { return false }
        onPerform()
        return true
    }
}


// MARK: - Sortier-Reihenfolge
enum SortOrder: String, CaseIterable {
    case nameAsc, nameDesc, dateAsc, dateDesc, sizeAsc, sizeDesc

    var label: String {
        switch self {
        case .nameAsc:  return "Name A–Z"
        case .nameDesc: return "Name Z–A"
        case .dateAsc:  return "Datum – älteste zuerst"
        case .dateDesc: return "Datum – neueste zuerst"
        case .sizeAsc:  return "Größe – klein zuerst"
        case .sizeDesc: return "Größe – groß zuerst"
        }
    }

    var icon: String {
        switch self {
        case .nameAsc:  return "arrow.up"
        case .nameDesc: return "arrow.down"
        case .dateAsc:  return "calendar"
        case .dateDesc: return "calendar"
        case .sizeAsc:  return "arrow.up"
        case .sizeDesc: return "arrow.down"
        }
    }
}


// MARK: - Zentrales Raster-Drop-Ziel
// Ein einziges, stabiles Drop-Ziel für das ganze Datei-Raster. Bestimmt den
// Zielordner aus der Cursor-Position statt sich auf Drop-Ziele einzelner
// LazyVGrid-Kacheln zu verlassen (die macOS nicht zuverlässig registriert).
struct GridFolderDropDelegate: DropDelegate {
    let folderID: (CGPoint) -> String?
    let setTarget: (String?) -> Void            // Ordner-Highlight (interner Zug)
    let setUploadHint: (Bool) -> Void           // Upload-Overlay (Finder-Datei)
    let performMove: (String, [String]) -> Void // Ordner-ID, verschobene IDs
    let performUpload: ([URL]) -> Void          // externe Datei-URLs

    /// Finder-Dateien sind file:// (fileURL). Der interne Zug ist getseen://
    /// (nur .url, NICHT .fileURL) -> sauber trennbar.
    private func isExternal(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.url, UTType.fileURL])
    }
    func dropEntered(info: DropInfo) { _ = dropUpdated(info: info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isExternal(info) {
            setTarget(nil); setUploadHint(true)
        } else {
            setUploadHint(false); setTarget(folderID(info.location))
        }
        return DropProposal(operation: .copy)
    }
    func dropExited(info: DropInfo) { setTarget(nil); setUploadHint(false) }

    func performDrop(info: DropInfo) -> Bool {
        setTarget(nil); setUploadHint(false)
        // macOS schickt nach dem Drop oft noch ein nachlaufendes dropUpdated,
        // danach aber KEIN dropExited -> Overlay/Highlight würden hängen.
        // Deshalb kurz danach nochmal sicher zurücksetzen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            setTarget(nil); setUploadHint(false)
        }
        let fid = folderID(info.location)
        let providers = info.itemProviders(for: [UTType.url, UTType.fileURL])
        guard !providers.isEmpty else { return false }

        let lock = NSLock()
        var fileURLs: [URL] = []
        var internalIDs: [String] = []
        let group = DispatchGroup()
        for prov in providers {
            group.enter()
            _ = prov.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    lock.lock()
                    if url.scheme == "getseen" {
                        internalIDs += url.lastPathComponent.split(separator: ",").map(String.init)
                    } else if url.isFileURL {
                        fileURLs.append(url)
                    }
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !internalIDs.isEmpty, let fid = fid {
                performMove(fid, internalIDs)
            } else if !fileURLs.isEmpty {
                performUpload(fileURLs)
            }
        }
        return true
    }
}


/// Ziel für den Docs-Editor-Sheet (Identifiable, damit `.sheet(item:)` die URL mitnimmt)
struct DocsTarget: Identifiable, Equatable {
    let url: String
    var id: String { url }
}

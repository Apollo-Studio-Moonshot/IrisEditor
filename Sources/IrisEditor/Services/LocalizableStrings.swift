import Foundation

/// Type-safe wrapper around `NSLocalizedString`.
///
/// Every entry carries a non-empty `comment:` so `genstrings` can emit useful
/// translator context. Strings that interpolate counts use small helpers instead of
/// building English sentences at the call site.
enum L10n {
    // MARK: - Common

    static let properties = NSLocalizedString("Properties", comment: "Properties card header")
    static let documentProperties = NSLocalizedString("Document properties", comment: "Accessibility label for the frontmatter properties card")
    static let zenMode = NSLocalizedString("Zen Mode", comment: "Toggle zen mode")
    static let saved = NSLocalizedString("Saved", comment: "Confirmation after quick capture saves")
    static let capture = NSLocalizedString("Capture", comment: "Quick capture save button")
    static let quickCapture = NSLocalizedString("Quick Capture", comment: "Menu bar quick capture panel title")
    static let newTab = NSLocalizedString("New tab", comment: "Label used when a quick capture has no file name")
    static let noVault = NSLocalizedString("No vault", comment: "Sidebar title when no vault folder is selected")
    static let vault = NSLocalizedString("Vault", comment: "Fallback folder title in the sidebar")
    static let refreshVault = NSLocalizedString("Refresh Vault", comment: "Sidebar refresh button help")
    static let closeSidebar = NSLocalizedString("Close Sidebar (⇧⌘O)", comment: "Sidebar close button help")
    static let chooseVaultFolder = NSLocalizedString("Choose vault folder", comment: "Sidebar vault picker help")
    static let newNote = NSLocalizedString("New Note", comment: "Create note button in the sidebar")
    static let renameNote = NSLocalizedString("Rename Current Note", comment: "Rename current note button help")
    static let deleteNote = NSLocalizedString("Delete Current Note", comment: "Delete current note button help")
    static let noNotesFound = NSLocalizedString("No notes found", comment: "Empty state title in the files pane")
    static let noNotesMessage = NSLocalizedString("Save a note or choose a vault folder to get started.", comment: "Empty state hint when no vault is selected")
    static let emptyVaultMessage = NSLocalizedString("This folder has no Markdown files yet.", comment: "Empty state hint when the vault has no notes")
    static let openInSecondPane = NSLocalizedString("Open in Second Pane", comment: "Context menu item for a note")
    static let showInFinder = NSLocalizedString("Show in Finder", comment: "Context menu item for a note")
    static let noTagsYet = NSLocalizedString("No tags yet", comment: "Empty state title in the tags pane")
    static let addTagsHint = NSLocalizedString("Add #tags or a tags property to a note.", comment: "Empty state hint in the tags pane")
    static let saveToSeeBacklinks = NSLocalizedString("Save to see backlinks", comment: "Empty state title when the document is unsaved")
    static let saveToSeeBacklinksHint = NSLocalizedString("Backlinks are indexed by note name.", comment: "Empty state hint explaining backlink indexing")
    static let noBacklinks = NSLocalizedString("No backlinks", comment: "Empty state title in the backlinks pane")
    static let noLocalGraph = NSLocalizedString("No local graph", comment: "Empty state title in the graph pane")
    static let noLocalGraphHint = NSLocalizedString("Link notes with [[wiki links]] to build a graph.", comment: "Empty state hint in the graph pane")
    static let unsavedChanges = NSLocalizedString("Unsaved changes", comment: "Help text for the dirty tab indicator")
    static let edited = NSLocalizedString("Edited", comment: "Status bar label for unsaved changes")
    static let utf8 = NSLocalizedString("UTF-8", comment: "Status bar encoding label")

    // MARK: - Sidebar

    static let searchNotes = NSLocalizedString("Search notes", comment: "Placeholder in the sidebar search field")
    static let clearNoteSearch = NSLocalizedString("Clear note search", comment: "Accessibility label for clearing the sidebar search field")
    static let noSearchResults = NSLocalizedString("No matching notes", comment: "Empty state title when the sidebar search finds nothing")
    static let columnMenu = NSLocalizedString("Sidebar options", comment: "Accessibility label for the sidebar options menu")
    static let groupByFolder = NSLocalizedString("Group by Folder", comment: "Sidebar files option grouping notes by folder")
    static let showAllNotes = NSLocalizedString("All Notes", comment: "Sidebar files option listing every note flat")
    static let showRecentNotes = NSLocalizedString("Recent Notes", comment: "Sidebar files option listing recently edited notes")
    static let sortBy = NSLocalizedString("Sort By", comment: "Sidebar files submenu choosing the sort order")
    static let sortAscending = NSLocalizedString("Ascending", comment: "Sidebar files sort direction: ascending")
    static let sortDescending = NSLocalizedString("Descending", comment: "Sidebar files sort direction: descending")
    static let collapseAll = NSLocalizedString("Collapse All", comment: "Sidebar files button folding every folder")
    static let expandAll = NSLocalizedString("Expand All", comment: "Sidebar files button unfolding every folder")
    static let recentSection = NSLocalizedString("RECENTLY EDITED", comment: "Sidebar section heading for recently edited notes")
    static let editBelowHeader = NSLocalizedString("Edit in split", comment: "Sidebar action opening a note beside the current one")
    static let starNote = NSLocalizedString("Star Note", comment: "Sidebar action starring the current note")
    static let unstarNote = NSLocalizedString("Unstar Note", comment: "Sidebar action removing the current note's star")
    static let starredNotes = NSLocalizedString("Starred", comment: "Sidebar pane title listing starred notes")
    static let noStarredNotes = NSLocalizedString("No starred notes", comment: "Empty state title in the starred pane")
    static let starNotesHint = NSLocalizedString("Star a note with ⌘⇧S to keep it here.", comment: "Empty state hint in the starred pane")
    static let removeStar = NSLocalizedString("Remove Star", comment: "Menu item removing a note's star")
    static let clearStarred = NSLocalizedString("Remove All Stars", comment: "Menu item clearing every starred note")
    static let missingNote = NSLocalizedString("Note not found", comment: "Warning beside a starred note whose file is gone")
    static let copyWikiLink = NSLocalizedString("Copy Wiki Link", comment: "Note context menu action copying an [[wiki link]]")
    static let moveToTrash = NSLocalizedString("Move to Trash", comment: "Note context menu action deleting the note from disk")
    static let copyTag = NSLocalizedString("Copy Tag", comment: "Tag context menu action copying the tag to the pasteboard")
    static let archiveNote = NSLocalizedString("Archive Note", comment: "Sidebar footer button moving the current note into the vault's .trash folder")
    static let noSearchResultsHint = NSLocalizedString("Nothing in the vault matches the filter. Press ⌫ in the field to clear it.", comment: "Empty state hint when the sidebar filter hides every note")
    static let noSiblings = NSLocalizedString("No other notes here", comment: "Empty state title in the same-folder pane")
    static let siblingNotes = NSLocalizedString("SAME FOLDER", comment: "Sidebar section heading for notes in the same folder")
    static let noFolderNotes = NSLocalizedString("Nothing in this folder", comment: "Empty state title when a folder has no notes")
    static let openGraphWindow = NSLocalizedString("Open Graph View", comment: "Sidebar button opening the graph view tab")
    static let graphWindowHelp = NSLocalizedString("Open Graph View (⇧⌘G)", comment: "Help text for the graph view button")
    static let graphDefaultScope = NSLocalizedString("Graph scope", comment: "Settings picker choosing the graph window's initial scope")
    static let followCurrentNote = NSLocalizedString("Follow Current Note", comment: "Graph window option keeping the graph centred on the open note")
    static let showLabels = NSLocalizedString("Show Labels", comment: "Graph window option showing note titles under nodes")
    static let showTags = NSLocalizedString("Show Tags", comment: "Graph window option showing a note's tags in the inspector")
    static let showOrphans = NSLocalizedString("Show Orphans", comment: "Graph window option including notes without links")
    static let graphDepth = NSLocalizedString("Depth", comment: "Graph window control for how many links to walk")
    static let graphNodeLimit = NSLocalizedString("Node Limit", comment: "Graph window control capping the number of notes")
    static let graphReset = NSLocalizedString("Reset Layout", comment: "Graph window button restoring the automatic layout")
    static let graphFit = NSLocalizedString("Fit to Window", comment: "Graph window button fitting the graph in view")
    static let graphReheat = NSLocalizedString("Redraw", comment: "Graph window button re-running the layout")
    static let graphOpenNote = NSLocalizedString("Open", comment: "Graph inspector button opening the selected note")
    static let graphFilter = NSLocalizedString("Filter notes", comment: "Placeholder in the graph search field")
    static let graphNoMatches = NSLocalizedString("No notes match the filter.", comment: "Graph empty state when a filter hides every note")
    static let graphNoNotes = NSLocalizedString("No notes to graph yet", comment: "Graph empty state when the vault has no links")
    static let graphNoNotesHint = NSLocalizedString("Link notes with [[wiki links]] to draw a graph.", comment: "Graph empty state hint")
    static let selectGraphNode = NSLocalizedString("Select a note to see its links.", comment: "Graph inspector placeholder")
    static let linkedNotesSection = NSLocalizedString("LINKS", comment: "Graph inspector section heading for outgoing links")
    static let backlinksSection = NSLocalizedString("BACKLINKS", comment: "Graph inspector section heading for incoming links")
    static let tagsSection = NSLocalizedString("TAGS", comment: "Graph inspector section heading for tags")
    static let zoomInGraph = NSLocalizedString("Zoom In", comment: "Graph window zoom button")
    static let zoomOutGraph = NSLocalizedString("Zoom Out", comment: "Graph window zoom button")
    static let graphShowsCurrent = NSLocalizedString("Current note", comment: "Graph legend label for the highlighted note")
    static let graphSettingsTitle = NSLocalizedString("Graph", comment: "Graph tab settings panel title")
    static let graphShowSettings = NSLocalizedString("Show Graph Settings", comment: "Graph tab button expanding the settings panel")
    static let graphHideSettings = NSLocalizedString("Hide Graph Settings", comment: "Graph tab button collapsing the settings panel")
    static let graphDisplaySection = NSLocalizedString("DISPLAY", comment: "Graph tab settings section for visual options")
    static let graphForcesSection = NSLocalizedString("FORCES", comment: "Graph tab settings section for physics sliders")
    static let graphGroupsSection = NSLocalizedString("GROUPS", comment: "Graph tab settings section for tag and folder filters")
    static let graphNodeSizeSetting = NSLocalizedString("Node size", comment: "Graph tab slider scaling every node")
    static let graphCenterForceSetting = NSLocalizedString("Center force", comment: "Graph tab slider pulling nodes to the centre")
    static let graphLinkDistanceSetting = NSLocalizedString("Link distance", comment: "Graph tab slider for preferred edge length")
    static let graphLinkForceSetting = NSLocalizedString("Link force", comment: "Graph tab slider for edge attraction")
    static let graphResetForces = NSLocalizedString("Reset", comment: "Graph tab button restoring the default forces")
    static let graphTabTitle = NSLocalizedString("Graph", comment: "Title of the graph workspace tab")
    static let graphTabHelp = NSLocalizedString("Open the graph of your vault", comment: "Help text for the graph tab")
    static let closeGraphTab = NSLocalizedString("Close Graph Tab", comment: "Help text for closing the graph tab")

    // MARK: - Menu bar

    static let newTabMenu = NSLocalizedString("New Tab", comment: "Menu item to create a tab")
    static let newTabHelp = NSLocalizedString("New Tab (⌘T)", comment: "Tab strip new tab button help")
    static let openMenu = NSLocalizedString("Open…", comment: "Menu item to open a document")
    static let closeTabMenu = NSLocalizedString("Close Tab", comment: "Menu item to close the current tab")
    static let reopenClosedTab = NSLocalizedString("Reopen Closed Tab", comment: "Menu item to reopen the last closed tab")
    static let openRecent = NSLocalizedString("Open Recent", comment: "Submenu listing recent files")
    static let noRecentFiles = NSLocalizedString("No Recent Files", comment: "Disabled item when there are no recent files")
    static let clearMenu = NSLocalizedString("Clear Menu", comment: "Menu item clearing recent files")
    static let nextTab = NSLocalizedString("Next Tab", comment: "Menu item to select the next tab")
    static let previousTab = NSLocalizedString("Previous Tab", comment: "Menu item to select the previous tab")
    static let lastTab = NSLocalizedString("Last Tab", comment: "Menu item to select the last tab")
    static let printDocument = NSLocalizedString("Print…", comment: "Menu item to print the document")
    static let navigateMenu = NSLocalizedString("Navigate", comment: "Menu title for navigation commands")
    static let quickSwitcher = NSLocalizedString("Quick Switcher…", comment: "Menu item opening the quick switcher")
    static let commandPalette = NSLocalizedString("Command Palette…", comment: "Menu item opening the command palette")
    static let toggleOutline = NSLocalizedString("Toggle Outline", comment: "Menu item toggling the outline sidebar")
    static let versionHistory = NSLocalizedString("Version History…", comment: "Menu item opening version history")
    static let pasteAsMarkdown = NSLocalizedString("Paste as Markdown", comment: "Menu item converting pasted HTML to Markdown")
    static let saveMenu = NSLocalizedString("Save", comment: "Menu item to save the document")
    static let saveAsMenu = NSLocalizedString("Save As…", comment: "Menu item to save the document under a new name")
    static let exportHTML = NSLocalizedString("Export as HTML…", comment: "Menu item exporting HTML")
    static let pluginsMenu = NSLocalizedString("Plugins", comment: "Menu containing plugin commands and management items")
    static let exportPDF = NSLocalizedString("Export as PDF…", comment: "Menu item exporting PDF")
    static let exportRTF = NSLocalizedString("Export as RTF…", comment: "Menu item exporting RTF")
    static let findReplace = NSLocalizedString("Find & Replace…", comment: "Menu item opening find and replace")
    static let goToLine = NSLocalizedString("Go to Line…", comment: "Menu item opening the go-to-line panel")
    static let zoomIn = NSLocalizedString("Zoom In", comment: "Menu item increasing the editor font size")
    static let zoomOut = NSLocalizedString("Zoom Out", comment: "Menu item decreasing the editor font size")
    static let actualSize = NSLocalizedString("Actual Size", comment: "Menu item resetting the editor font size")
    static let formatMenu = NSLocalizedString("Format", comment: "Menu title for Markdown formatting commands")
    static let bold = NSLocalizedString("Bold", comment: "Menu item applying bold formatting")
    static let italic = NSLocalizedString("Italic", comment: "Menu item applying italic formatting")
    static let inlineCode = NSLocalizedString("Inline Code", comment: "Menu item applying inline code formatting")
    static let strikethrough = NSLocalizedString("Strikethrough", comment: "Menu item applying strikethrough formatting")
    static let heading = NSLocalizedString("Heading", comment: "Menu item applying heading formatting")
    static let bulletedList = NSLocalizedString("Bulleted List", comment: "Menu item applying bulleted list formatting")
    static let blockQuote = NSLocalizedString("Block Quote", comment: "Menu item applying block quote formatting")
    static let insertTable = NSLocalizedString("Insert Table", comment: "Menu item inserting a Markdown table")
    static let togglePreview = NSLocalizedString("Toggle Preview", comment: "Menu item cycling editor and preview modes")
    static let aboutIris = NSLocalizedString("About Iris Editor", comment: "Application menu item showing the About panel")
    static let aiMenu = NSLocalizedString("AI", comment: "Menu title for AI commands")
    static let inlineCompletion = NSLocalizedString("Inline Completion", comment: "Menu item requesting an inline AI completion")
    static let rewriteSelection = NSLocalizedString("Rewrite Selection…", comment: "Menu item rewriting the selected text with AI")
    static let summarizeDocument = NSLocalizedString("Summarize Document", comment: "Menu item summarizing the document with AI")
    static let generateTitleTags = NSLocalizedString("Generate Title & Tags", comment: "Menu item generating frontmatter with AI")
    static let vaultMenu = NSLocalizedString("Vault", comment: "Menu title for vault commands")
    static let newNoteMenu = NSLocalizedString("New Note…", comment: "Menu item creating a note")
    static let searchAllNotes = NSLocalizedString("Search All Notes…", comment: "Menu item opening vault search")
    static let dailyNote = NSLocalizedString("Daily Note", comment: "Menu item opening today's daily note")
    static let sidebarMenu = NSLocalizedString("Sidebar", comment: "Submenu selecting the sidebar pane")
    static let resizeSidebar = NSLocalizedString("Resize Sidebar", comment: "Accessibility label for the sidebar width drag handle")
    static let insertTemplate = NSLocalizedString("Insert Template", comment: "Submenu inserting a vault template")
    static let noTemplates = NSLocalizedString("No templates in /Templates", comment: "Disabled item when the templates folder is empty")
    static let chooseVaultFolderMenu = NSLocalizedString("Choose Vault Folder…", comment: "Menu item choosing the vault root")
    static let openCurrentNoteToSide = NSLocalizedString("Open Current Note to the Side", comment: "Menu item opening the current note in the second pane")
    static let duplicateTab = NSLocalizedString("Duplicate Tab", comment: "Tab context menu item duplicating a tab")
    static let close = NSLocalizedString("Close", comment: "Tab context menu item closing a tab")
    static let revealInFinder = NSLocalizedString("Reveal in Finder", comment: "Tab context menu item revealing the file")
    static let copyPath = NSLocalizedString("Copy Path", comment: "Tab context menu item copying the file path")
    static let notSelected = NSLocalizedString("Not selected", comment: "Accessibility value for an inactive tab")
    static let selected = NSLocalizedString("Selected", comment: "Accessibility value for the active tab")

    // MARK: - Settings tabs

    static let settingsEditorTab = NSLocalizedString("Editor", comment: "Settings tab for font, indentation, and display options")
    static let settingsAppearanceTab = NSLocalizedString("Appearance", comment: "Settings tab for themes and accent color")
    static let settingsWritingTab = NSLocalizedString("Writing", comment: "Settings tab for writing modes and keymap")
    static let settingsAITab = NSLocalizedString("AI", comment: "Settings tab for the writing assistant provider")
    static let settingsKeysTab = NSLocalizedString("Keys", comment: "Settings tab for keyboard shortcuts")
    static let settingsPluginsTab = NSLocalizedString("Plugins", comment: "Settings tab for installed plugins")
    static let settingsAdvancedTab = NSLocalizedString("Advanced", comment: "Settings tab for vault and accessibility options")

    // MARK: - Settings

    static let editorFont = NSLocalizedString("Editor Font", comment: "Settings section title for font options")
    static let family = NSLocalizedString("Family", comment: "Settings label for the editor font family")
    static let size = NSLocalizedString("Size", comment: "Settings label for the editor font size")
    static let display = NSLocalizedString("Display", comment: "Settings section title for display options")
    static let showLineNumbers = NSLocalizedString("Show Line Numbers", comment: "Settings toggle for the line number ruler")
    static let highlightCurrentLine = NSLocalizedString("Highlight Current Line", comment: "Settings toggle for current line highlighting")
    static let wrapLines = NSLocalizedString("Wrap Lines", comment: "Settings toggle for soft wrapping")
    static let appearance = NSLocalizedString("Appearance", comment: "Settings section title for colors")
    static let accent = NSLocalizedString("Accent", comment: "Settings label for the accent color")
    static let previewTheme = NSLocalizedString("Preview Theme", comment: "Settings label for the preview color theme")
    static let appTheme = NSLocalizedString("Theme", comment: "Settings label for the window appearance")
    static let customAccentColor = NSLocalizedString("Custom Accent Color", comment: "Settings label for the custom accent color picker")
    static let highContrastNote = NSLocalizedString("High Contrast pins a dark palette with stronger borders for bright rooms and projectors.", comment: "Explanation of the high contrast appearance option")
    static let editingMode = NSLocalizedString("Editing Mode", comment: "Settings label for the Standard, Vim, or Emacs keymap")
    static let editingModeNote = NSLocalizedString("Vim uses Normal, Insert, Visual, and : command modes. Emacs adds Control and Option navigation, kill, and yank.", comment: "Explanation of the editing mode setting")
    static let writing = NSLocalizedString("Writing", comment: "Settings section title for writing modes")
    static let typewriterScrolling = NSLocalizedString("Typewriter Scrolling", comment: "Settings toggle for typewriter mode")
    static let focusMode = NSLocalizedString("Focus Mode (dim other paragraphs)", comment: "Settings toggle for focus mode")
    static let smartTableNavigation = NSLocalizedString("Smart Table Navigation", comment: "Settings toggle for table Tab navigation and pipe completion")
    static let wikiAutocomplete = NSLocalizedString("Wiki Link Autocomplete", comment: "Settings toggle for wiki link suggestions")
    static let vaultSection = NSLocalizedString("Vault", comment: "Settings section title for vault options")
    static let noFolderSelected = NSLocalizedString("No folder selected", comment: "Settings text when no vault root exists")
    static let choose = NSLocalizedString("Choose…", comment: "Settings button choosing a vault folder")
    static let useCurrentFolder = NSLocalizedString("Use Current Document’s Folder", comment: "Settings button making the document folder the vault")
    static let aiProvider = NSLocalizedString("AI Provider", comment: "Settings section title for the writing assistant backend")
    static let provider = NSLocalizedString("Provider", comment: "Settings label for the AI provider picker")
    static let apiKey = NSLocalizedString("API Key", comment: "Settings label for the AI provider API key")
    static let model = NSLocalizedString("Model", comment: "Settings label for the AI provider model name")
    static let baseURL = NSLocalizedString("Base URL", comment: "Settings label for the AI provider endpoint")
    static let apiKeyKeychainNote = NSLocalizedString("The API key is stored in your macOS Keychain.", comment: "Settings note explaining where the AI provider key is saved")
    static let indentation = NSLocalizedString("Indentation", comment: "Settings section title for indentation")
    static let tabWidth = NSLocalizedString("Tab Width", comment: "Settings label for tab width")
    static let previewSection = NSLocalizedString("Preview", comment: "Settings section title for the font preview")
    static let keybindings = NSLocalizedString("Keybindings", comment: "Settings section title for keyboard shortcuts")
    static let keybindingFieldPlaceholder = NSLocalizedString("command+option+v", comment: "Placeholder showing the expected keybinding format")
    static let resetKeybinding = NSLocalizedString("Reset", comment: "Button resetting one keybinding to its default")
    static let resetAllKeybindings = NSLocalizedString("Reset All Keybindings", comment: "Button resetting every keybinding")
    static let invalidKeybinding = NSLocalizedString("Use a key with a command or control modifier.", comment: "Validation message for an invalid keybinding")
    static let pluginsSection = NSLocalizedString("Installed Plugins", comment: "Settings section title listing plugins")
    static let noPlugins = NSLocalizedString("No plugins installed. Add a folder with plugin.json and main.js to the Plugins folder, or install the sample plugin.", comment: "Empty state for the plugin list")
    static let reloadPlugins = NSLocalizedString("Reload Plugins", comment: "Button rescanning the plugin folder")
    static let openPluginsFolder = NSLocalizedString("Open Plugins Folder", comment: "Button revealing the plugins folder in Finder")
    static let installSamplePlugin = NSLocalizedString("Install Sample Plugin", comment: "Button writing the example plugin")
    static let pluginErrors = NSLocalizedString("Plugin Errors", comment: "Settings section title listing plugin load errors")
    static let pluginDisabled = NSLocalizedString("Disabled", comment: "Label for a disabled plugin")
    static let pluginCommands = NSLocalizedString("commands", comment: "Plugin summary noun for commands")
    static let pluginExporters = NSLocalizedString("exporters", comment: "Plugin summary noun for exporters")
    static let accessibilitySection = NSLocalizedString("Accessibility", comment: "Settings section title for the accessibility audit")
    static let accessibilityAuditSummary = NSLocalizedString("VoiceOver labels and stable identifiers are present across the writing surfaces below.", comment: "Explanation of the accessibility audit list")
    static let sidebarAudit = NSLocalizedString("Sidebar panes and note rows", comment: "Accessibility audit row")
    static let suggestionAudit = NSLocalizedString("Wiki link suggestion bar", comment: "Accessibility audit row")
    static let searchAudit = NSLocalizedString("Vault search and command palette", comment: "Accessibility audit row")
    static let dialogAudit = NSLocalizedString("Version history and quick capture dialogs", comment: "Accessibility audit row")
    static let editorAudit = NSLocalizedString("Editor, status bar, and tab strip", comment: "Accessibility audit row")

    // MARK: - Content toolbar

    static let newButton = NSLocalizedString("New", comment: "Toolbar button creating a tab")
    static let openButton = NSLocalizedString("Open", comment: "Toolbar button opening a document")
    static let saveButton = NSLocalizedString("Save", comment: "Toolbar button saving the document")
    static let quickSwitcherButton = NSLocalizedString("Quick Switcher", comment: "Toolbar button opening the quick switcher")
    static let sidebarButton = NSLocalizedString("Sidebar", comment: "Toolbar button toggling the sidebar")
    static let searchVaultButton = NSLocalizedString("Search Vault", comment: "Toolbar button opening vault search")
    static let zenButton = NSLocalizedString("Zen", comment: "Toolbar button toggling zen mode")
    static let findButton = NSLocalizedString("Find", comment: "Toolbar button opening find and replace")
    static let previewButton = NSLocalizedString("Preview", comment: "Toolbar button cycling preview modes")
    static let commandPaletteButton = NSLocalizedString("Command Palette", comment: "Toolbar button opening the command palette")
    static let settingsButton = NSLocalizedString("Settings", comment: "Toolbar button opening Settings")
    static let closeSecondPane = NSLocalizedString("Close Second Pane", comment: "Button closing the side-by-side preview pane")
    static let writingAssistant = NSLocalizedString("Writing assistant", comment: "Accessibility label for the AI toolbar menu")
    static let toggleVaultSidebar = NSLocalizedString("Toggle vault sidebar", comment: "Accessibility label for the sidebar toolbar button")

    static let openHelp = NSLocalizedString("Open… (⌘O)", comment: "Toolbar help for opening a document")
    static let saveHelp = NSLocalizedString("Save (⌘S)", comment: "Toolbar help for saving")
    static let quickSwitcherHelp = NSLocalizedString("Quick Switcher (⌘P)", comment: "Toolbar help for the quick switcher")
    static let toggleSidebarHelp = NSLocalizedString("Toggle Vault Sidebar (⇧⌘O)", comment: "Toolbar help for the sidebar")
    static let searchAllNotesHelp = NSLocalizedString("Search All Notes (⇧⌘F)", comment: "Toolbar help for vault search")
    static let zenModeHelp = NSLocalizedString("Zen Mode (⌃⌘Z)", comment: "Toolbar help for zen mode")
    static let inlineCompletionHelp = NSLocalizedString("Offer a continuation at the cursor (⌃Space)", comment: "Toolbar help for inline AI completion")
    static let findHelp = NSLocalizedString("Find & Replace (⌘F)", comment: "Toolbar help for find and replace")
    static let goToLineHelp = NSLocalizedString("Go to Line (⌘G)", comment: "Toolbar help for go to line")
    static let commandPaletteHelp = NSLocalizedString("Command Palette (⇧⌘P)", comment: "Toolbar help for the command palette")
    static let settingsHelp = NSLocalizedString("Settings (⌘,)", comment: "Toolbar help for Settings")

    // MARK: - Overlays

    static let wikiSuggestions = NSLocalizedString("Wiki link suggestions", comment: "Accessibility label for the wiki suggestion bar")
    static let vaultSearch = NSLocalizedString("Vault search", comment: "Accessibility label for the vault search overlay")
    static let clearSearch = NSLocalizedString("Clear search", comment: "Accessibility label for the search field clear button")
    static let closeVersionHistory = NSLocalizedString("Close version history", comment: "Accessibility label for the version history close button")
    static let searchAllNotesPlaceholder = NSLocalizedString("Search all notes…", comment: "Placeholder in the vault search field")
    static let searchVaultHint = NSLocalizedString(
        "Search note titles and contents across your vault. Operators: tag:#idea · path:daily · file:meeting · match-case: · -tag:archive",
        comment: "Vault search empty-state hint, including the supported query operators"
    )
    static let searchOperatorsHint = NSLocalizedString(
        "tag: file: path: match-case: -exclusion",
        comment: "Compact reminder of the vault search operators, shown under the search field"
    )
    static let versionHistoryTitle = NSLocalizedString("Version History", comment: "Version history panel title")
    static let versionsHint = NSLocalizedString("Versions are captured each time you save this document.", comment: "Version history empty-state hint")
    static let selectVersionHint = NSLocalizedString("Select a version to preview.", comment: "Version history preview placeholder")
    static let emptySnapshot = NSLocalizedString("(Empty snapshot)", comment: "Placeholder for an empty version snapshot")
    static let restore = NSLocalizedString("Restore", comment: "Version history restore button")
    static let headingOne = NSLocalizedString("Heading 1", comment: "Toolbar help for the H1 format button")

    // MARK: - Interpolated helpers

    static func tab(_ number: Int) -> String {
        String(format: NSLocalizedString("Tab %d", comment: "Menu item selecting a numbered tab"), number)
    }

    static func noMatches(_ query: String) -> String {
        String(format: NSLocalizedString("No matches for “%@”.", comment: "Vault search result message with the query"), query)
    }

    static func results(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 result", comment: "Vault search results count for one")
            : String(format: NSLocalizedString("%d results", comment: "Vault search results count"), count)
    }

    static func lines(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 line", comment: "Status bar line count for one")
            : String(format: NSLocalizedString("%d lines", comment: "Status bar line count"), count)
    }

    static func words(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 word", comment: "Status bar word count for one")
            : String(format: NSLocalizedString("%d words", comment: "Status bar word count"), count)
    }

    static func characters(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 character", comment: "Status bar character count for one")
            : String(format: NSLocalizedString("%d characters", comment: "Status bar character count"), count)
    }

    static func snapshots(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 snapshot stored locally", comment: "Version history footer for one snapshot")
            : String(format: NSLocalizedString("%d snapshots stored locally", comment: "Version history footer"), count)
    }

    static func charactersInSnapshot(_ count: Int) -> String {
        String(format: NSLocalizedString("%d characters", comment: "Version row character count"), count)
    }

    static func files(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 file", comment: "Folder disclosure accessibility value for one file")
            : String(format: NSLocalizedString("%d files", comment: "Folder disclosure accessibility value"), count)
    }

    static func notes(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 note", comment: "Tag row accessibility value for one note")
            : String(format: NSLocalizedString("%d notes", comment: "Tag row accessibility value"), count)
    }

    static func linkedNotes(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 linked note", comment: "Backlinks pane count for one note")
            : String(format: NSLocalizedString("%d linked notes", comment: "Backlinks pane count"), count)
    }

    static func unlinkedMentions(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 unlinked mention", comment: "Unlinked mentions count for one mention")
            : String(format: NSLocalizedString("%d unlinked mentions", comment: "Unlinked mentions pane count"), count)
    }

    static func unlinkedMentionHint(_ title: String) -> String {
        String(format: NSLocalizedString("Mentions of “%@” that are not links yet.", comment: "Unlinked mentions empty-state hint with the document name"), title)
    }

    static var graphScope: String {
        NSLocalizedString("Graph scope", comment: "Graph pane scope picker accessibility label")
    }

    static var localGraph: String {
        NSLocalizedString("Local", comment: "Graph pane local scope option")
    }

    static var vaultGraph: String {
        NSLocalizedString("Vault", comment: "Graph pane whole-vault scope option")
    }

    static var unlinkedMentionsTitle: String {
        NSLocalizedString("Unlinked mentions", comment: "Unlinked mentions section heading")
    }

    static func backlinksHint(_ title: String) -> String {
        String(format: NSLocalizedString("Notes linking to [[%@]] appear here.", comment: "Backlinks empty-state hint with the document name"), title)
    }

    static func cursorPosition(line: Int, column: Int) -> String {
        String(format: NSLocalizedString("Ln %d, Col %d", comment: "Status bar cursor position"), line, column)
    }

    static func closeTab(_ title: String) -> String {
        String(format: NSLocalizedString("Close “%@”", comment: "Tab close button help with the document name"), title)
    }

    static func shortcutLabel(_ title: String) -> String {
        String(format: NSLocalizedString("%@ shortcut", comment: "Accessibility label for a command's current key binding"), title)
    }

    static func newShortcutField(_ title: String) -> String {
        String(format: NSLocalizedString("%@ new shortcut", comment: "Accessibility label for a command's key binding field"), title)
    }

    static func resetShortcut(_ title: String) -> String {
        String(format: NSLocalizedString("Reset %@ to its default shortcut", comment: "Accessibility label for a keybinding reset button"), title)
    }

    static func propertyCount(_ count: Int) -> String {
        String(format: NSLocalizedString("%d properties", comment: "Accessibility value for the properties card count"), count)
    }

    static func filterByTag(_ tag: String) -> String {
        String(format: NSLocalizedString("Filter by tag %@", comment: "Accessibility label for a clickable tag chip"), tag)
    }

    static func tabAccessibilityLabel(_ title: String) -> String {
        String(format: NSLocalizedString("%@ tab", comment: "Accessibility label for a tab with the document name"), title)
    }

    static func starredCount(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 starred", comment: "Starred pane count for one note")
            : String(format: NSLocalizedString("%d starred", comment: "Starred pane count"), count)
    }

    static func searchResultCount(_ count: Int) -> String {
        count == 1
            ? NSLocalizedString("1 note", comment: "Sidebar search result count for one note")
            : String(format: NSLocalizedString("%d notes", comment: "Sidebar search result count"), count)
    }

    static func openNotePath(_ path: String) -> String {
        String(format: NSLocalizedString("Open %@", comment: "Accessibility label for a sidebar note row with its path"), path)
    }

    static func graphStats(nodes: Int, links: Int) -> String {
        String(
            format: NSLocalizedString("%d notes · %d links", comment: "Graph window footer statistics"),
            nodes,
            links
        )
    }

    static let graphTitleMenu = NSLocalizedString("Graph", comment: "Menu title shown while the graph window is key")
    static let toggleInspector = NSLocalizedString("Toggle Inspector", comment: "Graph window command showing or hiding the inspector")
    static let clearFilters = NSLocalizedString("Clear Filters", comment: "Graph window action removing every active filter")
    static let openInMainWindow = NSLocalizedString("Open in Main Window", comment: "Graph inspector action opening the note in the editor")
    static let graphCurrentNote = NSLocalizedString("Current note", comment: "Graph legend label for the highlighted note")
    static let graphNoFilteredLinks = NSLocalizedString("None in view", comment: "Graph inspector placeholder when links exist but are filtered out")

    static func graphFiltered(hidden: Int) -> String {
        String(format: NSLocalizedString("%d hidden by the filter", comment: "Graph window notice about filtered notes"), hidden)
    }
}

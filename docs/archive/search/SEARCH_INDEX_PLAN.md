# FeyaPDF Search Index System — Implementation Plan

## Goal
Implement a proper text search system for the PDF viewer with background indexing, status indicators, and crash-free search.

## Architecture

### 1. SearchIndex class (`lib/features/viewer/providers/search_index.dart`)
Stores extracted page text and provides fast search.

```dart
class SearchIndex {
  final Map<int, String> _pageTexts = {};  // pageNumber -> full text
  bool _isIndexed = false;
  bool _isIndexing = false;
  bool _hasText = false;  // false for image-only PDFs
  
  // Status getters
  bool get isIndexed => _isIndexed;
  bool get isIndexing => _isIndexing;
  bool get hasText => _hasText;
  bool get isEmpty => _pageTexts.isEmpty;
  
  // Build index from document pages
  Future<void> buildIndex(PdfDocument document) async { ... }
  
  // Search through indexed text
  List<SearchResult> search(String query) { ... }
  
  // Clear index
  void clear() { ... }
}
```

### 2. SearchProvider updates (`lib/features/viewer/providers/search_provider.dart`)
Manages search state and integrates with SearchIndex.

```dart
class SearchProvider extends ChangeNotifier {
  final SearchIndex _index = SearchIndex();
  
  // Status
  SearchStatus get status => _index.isIndexed 
    ? SearchStatus.ready 
    : _index.isIndexing 
      ? SearchStatus.indexing 
      : SearchStatus.notIndexed;
  
  // Build index in background
  Future<void> buildIndex(PdfDocument document) async { ... }
  
  // Search through index
  Future<void> search(String query) async { ... }
  
  // Navigate to match
  void goToMatch(int index) { ... }
}
```

### 3. SearchStatus enum
```dart
enum SearchStatus {
  notIndexed,  // Grey icon — no text extracted yet
  indexing,     // Spinning icon — extracting text
  ready,       // Active icon — searchable
  noText,      // Grey icon — image-only PDF
}
```

### 4. Viewer screen integration (`lib/features/viewer/viewer_screen.dart`)
- Add search button to toolbar with status-based icon
- Show search bar when tapped
- Display indexing progress
- Handle search results

### 5. UI Components
- **Search icon**: Shows status (grey/spinning/active)
- **Search bar**: Text input with match count
- **Match navigation**: Previous/Next buttons
- **Indexing indicator**: Progress bar or spinner during indexing

## Implementation Steps

### Step 1: Create SearchIndex class
- Store page text as Map<int, String>
- Implement buildIndex() that loads text from each page
- Implement search() with pure Dart string matching
- Handle image-based PDFs (no text) gracefully

### Step 2: Update SearchProvider
- Integrate SearchIndex
- Add status management
- Implement search through index
- Add match navigation

### Step 3: Update Viewer Screen
- Add search button to toolbar
- Show status-based icon (grey/spinning/active)
- Add search bar widget
- Display match count and navigation

### Step 4: Add Search Bar Widget
- Text input field
- Match count display
- Previous/Next buttons
- Close button

### Step 5: Integrate with Existing Systems
- Reuse highlight provider's page text cache if available
- Ensure indexing doesn't block UI
- Handle document disposal properly

## Key Design Decisions

1. **No PdfTextSearcher** — Use manual text extraction via `page.loadText()` to avoid PDFium crashes
2. **Background indexing** — Extract text asynchronously, don't block UI
3. **Status-based UI** — Clear visual feedback for indexing state
4. **Pure Dart search** — String matching in Dart, no native code
5. **Reuse existing cache** — Leverage highlight provider's page text cache if available

## Files to Create/Modify

### Create:
- `lib/features/viewer/providers/search_index.dart` — Search index class

### Modify:
- `lib/features/viewer/providers/search_provider.dart` — Add indexing and status
- `lib/features/viewer/viewer_screen.dart` — Add search UI
- `lib/features/viewer/widgets/search_bar.dart` — Search bar widget (if needed)

## Testing Checklist
- [ ] Search icon shows correct status for each state
- [ ] Indexing doesn't block UI
- [ ] Search works for text-based PDFs
- [ ] Search shows "no text" for image-based PDFs
- [ ] Match navigation works (next/previous)
- [ ] Search clears when closing search bar
- [ ] No crashes during indexing or search
- [ ] Works with encrypted PDFs
- [ ] Works with large PDFs (100+ pages)

/// Validates a page number input against the total page count.
///
/// Returns the parsed page number if valid (1-based), or null if invalid.
/// Invalid inputs include:
/// - Non-numeric strings
/// - Numbers outside [1, totalPages]
/// - Empty or whitespace-only strings
int? validatePageNumber(String input, int totalPages) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final parsed = int.tryParse(trimmed);
  if (parsed == null) return null;
  if (parsed < 1 || parsed > totalPages) return null;
  return parsed;
}

/// Whether a "first page" / "previous page" button should be enabled.
bool isNotFirstPage(int currentPage) => currentPage > 1;

/// Whether a "last page" / "next page" button should be enabled.
bool isNotLastPage(int currentPage, int totalPages) =>
    currentPage < totalPages;

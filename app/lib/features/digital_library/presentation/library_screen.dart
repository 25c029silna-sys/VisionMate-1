import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/voice/voice_service.dart';
import '../../../widgets/voice_button.dart';
import '../data/embedding_store.dart';
import '../domain/library_service.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late VoiceService voiceService;
  late StorageService storageService;
  late LibraryService libraryService;

  String status = 'Smart digital library ready. Search by voice, browse books, or import PDFs.';
  List<Map<String, dynamic>> searchResults = [];
  List<Map<String, dynamic>> allBooks = [];
  bool isSearching = false;
  bool isLoadingBooks = false;
  bool isImportingPdf = false;
  String selectedFilter = 'all'; // 'all', 'pdf', 'notes', 'search'
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    voiceService = Provider.of<VoiceService>(context, listen: false);
    storageService = Provider.of<StorageService>(context, listen: false);
    libraryService = LibraryService(EmbeddingStore(storageService));

    _initializeLibrary();
  }

  Future<void> _initializeLibrary() async {
    await _seedSampleDocumentsIfEmpty();
    await _loadAvailableBooks();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await voiceService.speak(
        'Digital library ready. Showing $_pdfCount PDF books and ${allBooks.length} total items. Tap Voice Search or browse available books below.',
      );
    });
  }

  Future<void> _loadAvailableBooks() async {
    if (!mounted) return;
    setState(() {
      isLoadingBooks = true;
    });
    try {
      final docs = await libraryService.fetchAvailableDocuments();
      if (mounted) {
        setState(() {
          allBooks = docs;
          isLoadingBooks = false;
        });
      }
    } catch (e) {
      debugPrint('LibraryScreen: Error loading books: $e');
      if (mounted) {
        setState(() {
          isLoadingBooks = false;
        });
      }
    }
  }

  Future<void> _seedSampleDocumentsIfEmpty() async {
    try {
      final docs = await storageService.fetchDocuments();
      if (docs.isEmpty) {
        await libraryService.addAndIndexDocument(
          'VisionMate Navigation Manual',
          'VisionMate uses artificial intelligence to assist blind and visually impaired users with real-time obstacle detection and scene recognition.',
          sourceType: 'user_manual',
        );
        await libraryService.addAndIndexDocument(
          'Emergency SOS Guide',
          'Pressing the SOS button triggers an emergency alert SMS with current GPS latitude and longitude coordinates, and calls your trusted contact.',
          sourceType: 'guide',
        );
        await libraryService.addAndIndexDocument(
          'Braille & OCR Scanner Guide',
          'Point camera at printed pages or tactile Braille characters to scan and hear translated text spoken clearly.',
          sourceType: 'tutorial',
        );
      }
    } catch (e) {
      debugPrint('LibraryScreen: Seeding skipped: $e');
    }
  }

  int get _pdfCount => allBooks.where((b) {
        final st = (b['source_type'] as String? ?? '').toLowerCase();
        final title = (b['title'] as String? ?? '').toLowerCase();
        return st.contains('pdf') || title.endsWith('.pdf');
      }).length;

  int get _noteCount => allBooks.length - _pdfCount;

  List<Map<String, dynamic>> get _filteredBooks {
    if (selectedFilter == 'pdf') {
      return allBooks.where((b) {
        final st = (b['source_type'] as String? ?? '').toLowerCase();
        final title = (b['title'] as String? ?? '').toLowerCase();
        return st.contains('pdf') || title.endsWith('.pdf');
      }).toList();
    } else if (selectedFilter == 'notes') {
      return allBooks.where((b) {
        final st = (b['source_type'] as String? ?? '').toLowerCase();
        final title = (b['title'] as String? ?? '').toLowerCase();
        return !st.contains('pdf') && !title.endsWith('.pdf');
      }).toList();
    } else if (selectedFilter == 'search') {
      return searchResults;
    }
    return allBooks;
  }

  Future<void> _importPdfFile() async {
    if (isImportingPdf) return;
    try {
      setState(() {
        isImportingPdf = true;
        status = 'Opening file picker for PDF books...';
      });
      await voiceService.speak('Select a PDF book from your device storage.');

      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (picked != null && picked.path != null) {
        final filePath = picked.path!;
        final file = File(filePath);
        final fileName = picked.name;

        if (mounted) {
          setState(() {
            status = 'Extracting and indexing "$fileName"...';
          });
        }
        await voiceService.speak('Importing and indexing $fileName into your library.');

        await libraryService.importAndIndexPdf(file);
        await _loadAvailableBooks();

        if (mounted) {
          setState(() {
            selectedFilter = 'pdf';
            status = 'Successfully imported "$fileName" into library.';
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully imported and indexed "$fileName"'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await voiceService.speak('$fileName has been indexed into your library and is ready to read.');
      } else {
        if (mounted) {
          setState(() {
            status = 'PDF import cancelled.';
          });
        }
      }
    } catch (e) {
      debugPrint('LibraryScreen: Error importing PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import PDF: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      await voiceService.speak('Failed to import PDF file.');
    } finally {
      if (mounted) {
        setState(() {
          isImportingPdf = false;
        });
      }
    }
  }

  Future<void> _confirmDeleteBook(Map<String, dynamic> book) async {
    final title = book['title'] as String? ?? 'Untitled Book';
    final docId = book['id'] as int? ?? (book['document_id'] as int? ?? -1);
    if (docId == -1) return;

    await voiceService.speak('Delete $title? Please confirm.');
    if (!mounted) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Delete Book?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "$title" from your digital library?\n\nThis will permanently delete the book, any saved PDF files, and its search index from your device.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Keep Book', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogCtx, true),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      final success = await libraryService.deleteBook(docId, title: title);
      if (success) {
        await _loadAvailableBooks();
        setState(() {
          searchResults.removeWhere((item) => item['document_id'] == docId || item['id'] == docId);
          status = 'Deleted "$title" from library.';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "$title" from library'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        await voiceService.speak('$title has been deleted from your library.');
      } else {
        await voiceService.speak('Could not delete $title.');
      }
    }
  }

  void _openBookReader(Map<String, dynamic> book) {
    final title = book['title'] as String? ?? 'Untitled Document';
    final text = book['text'] as String? ?? 'No text content available.';
    final sourceType = book['source_type'] as String? ?? 'document';
    final isPdf = sourceType.toLowerCase().contains('pdf') || title.toLowerCase().endsWith('.pdf');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: isPdf
                        ? Colors.deepOrange.withAlpha(50)
                        : Colors.purple.withAlpha(50),
                    child: Icon(
                      isPdf ? Icons.picture_as_pdf_rounded : Icons.menu_book_rounded,
                      color: isPdf ? Colors.deepOrangeAccent : Colors.purpleAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isPdf
                                    ? Colors.deepOrange.withAlpha(40)
                                    : Colors.purple.withAlpha(40),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isPdf ? Colors.deepOrangeAccent : Colors.purpleAccent,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                isPdf ? 'PDF BOOK' : sourceType.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  color: isPdf ? Colors.deepOrangeAccent : Colors.purpleAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${text.length} chars • ~${(text.split(RegExp(r'\s+')).length / 150).ceil()} min read',
                              style: const TextStyle(fontSize: 11, color: Colors.white54),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Action Buttons Row (Listen Aloud & Delete)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await voiceService.speak('Reading $title. $text');
                      },
                      icon: const Icon(Icons.volume_up_rounded, size: 20),
                      label: const Text('Read Aloud'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purpleAccent.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _confirmDeleteBook(book);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                    label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              // Text Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddDocumentDialog() async {
    final titleController = TextEditingController();
    final textController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Add Document to Library', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Document Title',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'e.g., Biology Notes Chapter 1',
                hintStyle: TextStyle(color: Colors.white30),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Document Content',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'Paste or type notes or Braille translation text...',
                hintStyle: TextStyle(color: Colors.white30),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              final title = titleController.text.trim();
              final text = textController.text.trim();
              if (title.isNotEmpty && text.isNotEmpty) {
                await libraryService.addAndIndexDocument(title, text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _loadAvailableBooks();
                await voiceService.speak('Document indexed into digital library.');
                if (mounted) {
                  setState(() {
                    status = 'Document "$title" added and indexed into library.';
                  });
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
            child: const Text('Index Document'),
          ),
        ],
      ),
    );
  }

  Future<void> _searchLibrary() async {
    _retryTimer?.cancel();
    if (isSearching) {
      await voiceService.stopListening();
      if (mounted) {
        setState(() {
          isSearching = false;
        });
      }
      return;
    }

    setState(() {
      isSearching = true;
      status = 'Listening for your search query...';
    });

    final rawQuery = await voiceService.listen();

    if (!mounted) return;

    if (rawQuery == null || rawQuery.trim().isEmpty) {
      if (mounted) {
        setState(() {
          isSearching = false;
          status = 'Tap Voice Search button to speak a query.';
        });
      }
      return;
    }

    final query = rawQuery.trim();
    final lower = query.toLowerCase();

    if (lower == 'back' || lower == 'home' || lower == 'exit' || lower == 'close') {
      setState(() {
        isSearching = false;
      });
      await voiceService.speak('Returning to main menu.');
      if (mounted) Navigator.pop(context);
      return;
    }

    if (lower.contains('add document') || lower.contains('add note') || lower == 'add') {
      setState(() {
        isSearching = false;
      });
      await voiceService.speak('Opening add document window.');
      await _showAddDocumentDialog();
      return;
    }

    if (lower.contains('import') || lower.contains('import pdf')) {
      setState(() {
        isSearching = false;
      });
      await _importPdfFile();
      return;
    }

    if (lower.startsWith('delete') || lower.startsWith('remove')) {
      setState(() {
        isSearching = false;
      });
      final targetTitle = lower.replaceFirst(RegExp(r'^(delete|remove)\s+'), '').trim();
      final match = allBooks.cast<Map<String, dynamic>?>().firstWhere(
            (b) => (b?['title'] as String? ?? '').toLowerCase().contains(targetTitle),
            orElse: () => null,
          );
      if (match != null) {
        await _confirmDeleteBook(match);
      } else {
        await voiceService.speak('Could not find any book matching "$targetTitle" to delete.');
      }
      return;
    }

    if (lower.contains('show pdf') || lower.contains('pdfs')) {
      setState(() {
        selectedFilter = 'pdf';
        isSearching = false;
        status = 'Showing all available PDF books ($_pdfCount found).';
      });
      await voiceService.speak('Showing $_pdfCount available PDF books.');
      return;
    }

    if (lower.contains('all books') || lower.contains('show all') || lower.contains('list books')) {
      setState(() {
        selectedFilter = 'all';
        isSearching = false;
        status = 'Showing all ${allBooks.length} available library books.';
      });
      await voiceService.speak('Showing all ${allBooks.length} available library books.');
      return;
    }

    if (lower.contains('help') || lower.contains('guide')) {
      setState(() {
        isSearching = false;
      });
      await voiceService.speak(
        'Available commands: speak any topic to search, say Import PDF to add a book, say Delete followed by the book title to remove it, or say Show PDFs to view all PDF files.',
      );
      return;
    }

    setState(() {
      status = 'Performing vector search for: "$query"';
    });

    final results = await libraryService.searchBySpokenQuery(query, topK: 5);

    if (!mounted) return;

    setState(() {
      searchResults = results;
      selectedFilter = 'search';
      isSearching = false;
      status = 'Search complete for "$query". Found ${results.length} relevant matches.';
    });

    if (results.isNotEmpty) {
      final topResult = results.first;
      final title = topResult['title'] ?? 'Matching Document';
      final text = topResult['text'] ?? '';
      await voiceService.speak('Found match: $title. $text');
    } else {
      await voiceService.speak('No matching documents found in your library for $query.');
    }
  }

  Widget _buildFilterChip(String filterKey, String label, IconData icon, {Color? activeColor}) {
    final isSelected = selectedFilter == filterKey;
    final color = activeColor ?? Colors.purpleAccent;

    return InkWell(
      onTap: () {
        setState(() {
          selectedFilter = filterKey;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(50) : const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.white24,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? color : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookCard(Map<String, dynamic> book) {
    final title = book['title'] as String? ?? 'Untitled Book';
    final text = book['text'] as String? ?? '';
    final sourceType = (book['source_type'] as String? ?? 'note').toLowerCase();
    final createdAt = book['created_at'] as String? ?? '';
    final score = book['score'] as double?;

    final isPdf = sourceType.contains('pdf') || title.toLowerCase().endsWith('.pdf');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFF161B22),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isPdf ? Colors.deepOrange.withAlpha(90) : Colors.purple.withAlpha(90),
          width: 1.1,
        ),
      ),
      child: InkWell(
        onTap: () => _openBookReader(book),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isPdf ? Colors.deepOrange.withAlpha(40) : Colors.purple.withAlpha(40),
                    child: Icon(
                      isPdf ? Icons.picture_as_pdf_rounded : Icons.menu_book_rounded,
                      color: isPdf ? Colors.deepOrangeAccent : Colors.purpleAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isPdf ? Colors.deepOrange.withAlpha(40) : Colors.purple.withAlpha(40),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isPdf ? 'PDF BOOK' : sourceType.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isPdf ? Colors.deepOrangeAccent : Colors.purpleAccent,
                                ),
                              ),
                            ),
                            if (createdAt.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                createdAt.split('T').first,
                                style: const TextStyle(fontSize: 11, color: Colors.white38),
                              ),
                            ],
                            if (score != null) ...[
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withAlpha(50),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${(score * 100).toStringAsFixed(0)}% match',
                                  style: const TextStyle(
                                    color: Colors.purpleAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Read Aloud button
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, color: Colors.cyanAccent, size: 21),
                    tooltip: 'Read Aloud with Voice',
                    onPressed: () async {
                      await voiceService.speak('Reading $title. $text');
                    },
                  ),
                  // Delete button
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 21),
                    tooltip: 'Delete Book',
                    onPressed: () => _confirmDeleteBook(book),
                  ),
                ],
              ),
              if (text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayedBooks = _filteredBooks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Library'),
        actions: [
          IconButton(
            icon: isImportingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.file_upload_outlined, color: Colors.deepOrangeAccent),
            tooltip: 'Import PDF Book',
            onPressed: isImportingPdf ? null : _importPdfFile,
          ),
          IconButton(
            icon: const Icon(Icons.note_add_rounded, color: Colors.purpleAccent),
            tooltip: 'Add Note / Document',
            onPressed: _showAddDocumentDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh Books',
            onPressed: _loadAvailableBooks,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status & Vector Search Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.purpleAccent.withAlpha(70)),
              ),
              child: Row(
                children: [
                  Icon(
                    isSearching ? Icons.search_rounded : Icons.menu_book_rounded,
                    color: Colors.purpleAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SEMANTIC VECTOR SEARCH & PDF BOOKS',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.purpleAccent,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          status,
                          style: const TextStyle(fontSize: 12.5, color: Colors.white),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Search Trigger Button
            VoiceButton(
              label: 'Voice Search Library',
              subtitle: 'Tap to speak: search books, "Import PDF", or "Delete <title>"',
              activeSubtitle: 'Listening... speak query or "Delete <title>"',
              isListening: isSearching,
              onPressed: _searchLibrary,
              primaryColor: const Color(0xFF1E293B),
              activeColor: Colors.purple.shade700,
            ),
            const SizedBox(height: 10),

            // Action Quick Buttons Row
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: isImportingPdf ? null : _importPdfFile,
                      icon: isImportingPdf
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded, size: 17),
                      label: Text(isImportingPdf ? 'Importing...' : 'Import PDF Book'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrangeAccent.shade400,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _showAddDocumentDialog,
                      icon: const Icon(Icons.note_add_rounded, size: 17, color: Colors.purpleAccent),
                      label: const Text('Add Note', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.purpleAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Filter Chips Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'All Books (${allBooks.length})', Icons.auto_stories_rounded),
                  const SizedBox(width: 8),
                  _buildFilterChip('pdf', 'PDF Books ($_pdfCount)', Icons.picture_as_pdf_rounded, activeColor: Colors.deepOrangeAccent),
                  const SizedBox(width: 8),
                  _buildFilterChip('notes', 'Notes & Guides ($_noteCount)', Icons.note_rounded, activeColor: Colors.purpleAccent),
                  if (searchResults.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _buildFilterChip('search', 'Search Matches (${searchResults.length})', Icons.saved_search_rounded, activeColor: Colors.cyanAccent),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Header for Available Documents List
            Row(
              children: [
                Text(
                  selectedFilter == 'search'
                      ? 'SEARCH MATCHES (${searchResults.length})'
                      : selectedFilter == 'pdf'
                          ? 'AVAILABLE PDF BOOKS ($_pdfCount)'
                          : selectedFilter == 'notes'
                              ? 'NOTES & GUIDES ($_noteCount)'
                              : 'LIBRARY BOOKS & PDFS (${allBooks.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white54,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                if (selectedFilter != 'all')
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedFilter = 'all';
                      });
                    },
                    child: const Text(
                      'View All',
                      style: TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Available Books List
            Expanded(
              child: isLoadingBooks
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.purpleAccent),
                    )
                  : displayedBooks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                selectedFilter == 'pdf'
                                    ? Icons.picture_as_pdf_outlined
                                    : Icons.library_books_outlined,
                                size: 48,
                                color: Colors.grey.shade700,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                selectedFilter == 'pdf'
                                    ? 'No PDF books in library yet.\nTap "Import PDF Book" or scan Braille pages to export PDFs.'
                                    : selectedFilter == 'search'
                                        ? 'No matching results found.\nTry a different search query.'
                                        : 'No books in library.\nImport a PDF or add notes to get started.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 14),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: isImportingPdf ? null : _importPdfFile,
                                icon: const Icon(Icons.file_upload_outlined, size: 18),
                                label: const Text('Import PDF File'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepOrangeAccent.shade400,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadAvailableBooks,
                          color: Colors.purpleAccent,
                          child: ListView.builder(
                            itemCount: displayedBooks.length,
                            itemBuilder: (context, index) {
                              return _buildBookCard(displayedBooks[index]);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/voice/voice_service.dart';
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

  String status = 'Smart digital library ready. Search by voice or add notes.';
  List<Map<String, dynamic>> searchResults = [];
  bool isSearching = false;

  @override
  void initState() {
    super.initState();
    voiceService = Provider.of<VoiceService>(context, listen: false);
    storageService = Provider.of<StorageService>(context, listen: false);
    libraryService = LibraryService(EmbeddingStore(storageService));

    _seedSampleDocumentsIfEmpty();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await voiceService.speak('Smart digital library activated. Speak your search query to search Braille documents and notes.');
    });
  }

  Future<void> _seedSampleDocumentsIfEmpty() async {
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
        'Braille & OCR Scanner',
        'Point camera at printed pages or tactile Braille characters to scan and hear translated text spoken clearly.',
        sourceType: 'tutorial',
      );
    }
  }

  Future<void> _showAddDocumentDialog() async {
    final titleController = TextEditingController();
    final textController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Add Document to Library', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Document Title',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Document Text / Content',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              final title = titleController.text.trim();
              final text = textController.text.trim();
              if (title.isNotEmpty && text.isNotEmpty) {
                await libraryService.addAndIndexDocument(title, text);
                if (mounted) Navigator.pop(context);
                await voiceService.speak('Document indexed into digital library.');
                setState(() {
                  status = 'Document "$title" added and indexed into vector store.';
                });
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
    if (isSearching) return;
    setState(() {
      isSearching = true;
      status = 'Listening for your search query...';
    });

    await voiceService.speak('Listening for your digital library search query.');
    final query = await voiceService.listen();

    if (query == null || query.trim().isEmpty) {
      setState(() {
        isSearching = false;
        status = 'No query detected. Tap Search button to try again.';
      });
      await voiceService.speak('No search query detected.');
      return;
    }

    setState(() {
      status = 'Performing vector search for: "$query"';
    });

    final results = await libraryService.searchBySpokenQuery(query, topK: 5);

    setState(() {
      searchResults = results;
      isSearching = false;
      status = 'Search complete for "$query". Found ${results.length} relevant matches.';
    });

    if (results.isNotEmpty) {
      final topResult = results.first;
      final title = topResult['title'] ?? 'Matching Document';
      final text = topResult['text'] ?? '';
      await voiceService.speak('Found match: $title. $text');
    } else {
      await voiceService.speak('No matching documents found in your library.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.note_add_rounded, color: Colors.purpleAccent),
            tooltip: 'Add Note / Document',
            onPressed: _showAddDocumentDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purpleAccent.withAlpha((0.3 * 255).round())),
              ),
              child: Row(
                children: [
                  Icon(
                    isSearching ? Icons.search_rounded : Icons.menu_book_rounded,
                    color: Colors.purpleAccent,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SEMANTIC VECTOR SEARCH',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.purpleAccent,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status,
                          style: const TextStyle(fontSize: 14, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search Trigger Button
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: isSearching ? null : _searchLibrary,
                icon: Icon(
                  isSearching ? Icons.mic_rounded : Icons.mic_none_rounded,
                  size: 28,
                ),
                label: Text(
                  isSearching ? 'Listening...' : 'Voice Search Library',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Add Document Action Button
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _showAddDocumentDialog,
                icon: const Icon(Icons.note_add_rounded, color: Colors.purpleAccent),
                label: const Text('Add Note / Document', style: TextStyle(color: Colors.white, fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.purpleAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Results Section
            const Text(
              'RELEVANT MATCHES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white54,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: searchResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.library_books_outlined, size: 48, color: Colors.grey.shade700),
                          const SizedBox(height: 12),
                          const Text(
                            'No search results yet.\nRecognize Braille pages to export PDFs or tap Voice Search.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: searchResults.length,
                      itemBuilder: (context, index) {
                        final item = searchResults[index];
                        final score = (item['score'] as double? ?? 0.0);
                        final title = item['title'] ?? 'Document';
                        final text = item['text'] ?? '';
                        final sourceType = item['source_type'] ?? 'note';

                        final isBraillePdf = sourceType == 'braille_pdf' || sourceType == 'pdf_import';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: const Color(0xFF161B22),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: score > 0.4 ? Colors.purpleAccent : Colors.grey.shade800,
                              width: score > 0.4 ? 1.5 : 1,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isBraillePdf
                                  ? Colors.deepOrange.withAlpha((0.2 * 255).round())
                                  : Colors.purple.withAlpha((0.2 * 255).round()),
                              child: Icon(
                                isBraillePdf ? Icons.picture_as_pdf_rounded : Icons.article_rounded,
                                color: isBraillePdf ? Colors.deepOrangeAccent : Colors.purpleAccent,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              title,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            subtitle: Text(
                              text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.purple.withAlpha((0.3 * 255).round()),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${(score * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: Colors.purpleAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            onTap: () async {
                              await voiceService.speak('Reading document: $title. $text');
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


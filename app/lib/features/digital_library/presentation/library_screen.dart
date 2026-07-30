import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/voice/voice_service.dart';
import '../../../core/storage/storage_service.dart';
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

  String status = 'Smart digital library ready. Tap mic or say search.';
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
      await voiceService.speak('Smart digital library activated. Say search or tap to begin vector search.');
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
            tooltip: 'Add Document',
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
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search Action Button
            ElevatedButton.icon(
              onPressed: _searchLibrary,
              icon: Icon(isSearching ? Icons.hourglass_top_rounded : Icons.mic_rounded),
              label: Text(isSearching ? 'Searching...' : 'Voice Search Library'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),

            // Results Section Title
            Row(
              children: [
                const Text(
                  'MATCHING DOCUMENTS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white38,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showAddDocumentDialog,
                  icon: const Icon(Icons.add, size: 14, color: Colors.purpleAccent),
                  label: const Text('Add Document', style: TextStyle(fontSize: 12, color: Colors.purpleAccent)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Results List
            Expanded(
              child: searchResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.search_off_rounded, size: 48, color: Colors.white24),
                          SizedBox(height: 12),
                          Text(
                            'No search results yet.\nTap "Voice Search Library" or add a document.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: searchResults.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = searchResults[index];
                        final score = (item['score'] as double? ?? 0.0);
                        final percentage = (score * 100).toStringAsFixed(1);

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF21262D),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item['title'] as String? ?? 'Document',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purpleAccent,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.purpleAccent.withAlpha((0.2 * 255).round()),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Match: $percentage%',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.purpleAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item['text'] as String? ?? '',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
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


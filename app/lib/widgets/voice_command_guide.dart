import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/voice/voice_service.dart';
import '../core/voice/voice_guide_service.dart';

class VoiceCommandGuideModal extends StatelessWidget {
  const VoiceCommandGuideModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const VoiceCommandGuideModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final voiceService = Provider.of<VoiceService>(context, listen: false);
    final categories = [
      {
        'title': 'Emergency SOS',
        'icon': Icons.warning_amber_rounded,
        'color': Colors.redAccent,
        'route': '/emergency',
        'keywords': ['emergency', 'sos', 'panic', 'help', 'danger', 'distress'],
        'description': 'Triggers emergency alert with GPS location and calls trusted contact',
      },
      {
        'title': 'Braille Recognition',
        'icon': Icons.grid_on_rounded,
        'color': Colors.amberAccent,
        'route': '/braille',
        'keywords': ['braille', 'brail', 'tactile'],
        'description': 'Scans and decodes Braille characters',
      },
      {
        'title': 'OCR Text Reader',
        'icon': Icons.document_scanner_rounded,
        'color': Colors.lightBlueAccent,
        'route': '/ocr',
        'keywords': ['ocr', 'read text', 'read document', 'read page', 'scan text', 'text reader', 'read', 'scan', 'capture'],
        'description': 'Reads aloud printed text, pages, & signs',
      },
      {
        'title': 'Scene & Obstacles',
        'icon': Icons.remove_red_eye_rounded,
        'color': Colors.tealAccent,
        'route': '/scene',
        'keywords': ['scene', 'surroundings', 'navigate', 'navigation', 'obstacle', 'environment', 'describe'],
        'description': 'Describes surroundings and detects obstacles',
      },
      {
        'title': 'Digital Library',
        'icon': Icons.menu_book_rounded,
        'color': Colors.purpleAccent,
        'route': '/library',
        'keywords': ['library', 'semantic search', 'document search', 'search', 'find document'],
        'description': 'Semantic search across saved documents',
      },
    ];

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Colors.white24, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              children: [
                const Icon(Icons.record_voice_over, color: Colors.blueAccent, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Supported Voice Commands',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Spoken list of all available voice triggers.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    VoiceGuideService(voiceService).readGuideAloud();
                  },
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: const Text('Read Aloud', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 24),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final item = categories[index];
                final Color color = item['color'] as Color;
                final List<String> keywords = item['keywords'] as List<String>;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withAlpha((0.3 * 255).round())),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(item['icon'] as IconData, color: color, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            item['title'] as String,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            item['route'] as String,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white38,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item['description'] as String,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Spoken Triggers:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white38,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: keywords.map((kw) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withAlpha((0.15 * 255).round()),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: color.withAlpha((0.4 * 255).round()),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '"$kw"',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withAlpha((0.9 * 255).round()),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

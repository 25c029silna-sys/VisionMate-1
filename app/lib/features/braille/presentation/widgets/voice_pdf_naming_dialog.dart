import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/voice/voice_service.dart';
import '../../domain/braille_service.dart';

/// Accessible voice-guided modal bottom sheet that prompts the user to name their
/// recognized Braille PDF document via voice command, with visual and manual fallbacks.
class VoicePdfNamingDialog extends StatefulWidget {
  final VoiceService voiceService;
  final String? initialName;

  const VoicePdfNamingDialog({
    super.key,
    required this.voiceService,
    this.initialName,
  });

  /// Presents the voice naming dialog and returns the chosen document name,
  /// or null if the user cancelled.
  static Future<String?> show(
    BuildContext context, {
    required VoiceService voiceService,
    String? initialName,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoicePdfNamingDialog(
        voiceService: voiceService,
        initialName: initialName,
      ),
    );
  }

  @override
  State<VoicePdfNamingDialog> createState() => _VoicePdfNamingDialogState();
}

class _VoicePdfNamingDialogState extends State<VoicePdfNamingDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _nameController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool _isListening = false;
  bool _hasAutoPrompted = false;
  String _statusMessage = 'Listening for document name...';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final defaultTitle = 'Braille Document ($dateStr $timeStr)';

    _nameController =
        TextEditingController(text: widget.initialName ?? defaultTitle);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasAutoPrompted && mounted) {
        _hasAutoPrompted = true;
        _startListeningForName();
      }
    });
  }

  Future<void> _startListeningForName() async {
    if (_isListening) return;

    if (mounted) {
      setState(() {
        _isListening = true;
        _statusMessage = 'Listening... Please speak the document name.';
      });
      _pulseController.repeat(reverse: true);
    }

    try {
      await widget.voiceService.speak(
        'Please speak the name for your PDF document, or say cancel.',
      );

      if (!mounted) return;

      final spoken = await widget.voiceService.listen();

      if (!mounted) return;

      _pulseController.stop();
      _pulseController.reset();

      setState(() {
        _isListening = false;
      });

      if (spoken == null || spoken.trim().isEmpty) {
        setState(() {
          _statusMessage = 'No name heard. Tap the microphone to try again or tap Save.';
        });
        await widget.voiceService.speak(
          'No name heard. Say your document name, tap Use Default, or tap Cancel.',
        );
        return;
      }

      final lower = spoken.toLowerCase().trim();

      // Check for voice cancellation
      if (lower.contains('cancel') || lower == 'stop' || lower == 'back') {
        await widget.voiceService.speak('PDF export cancelled.');
        if (mounted) Navigator.of(context).pop(null);
        return;
      }

      // Check for default name command
      if (lower.contains('default') || lower == 'skip') {
        final currentText = _nameController.text.trim();
        await widget.voiceService.speak('Using default name. Saving.');
        if (mounted) Navigator.of(context).pop(currentText);
        return;
      }

      final cleaned = BrailleService.cleanPdfName(spoken);
      if (cleaned.isNotEmpty) {
        _nameController.text = cleaned;
        setState(() {
          _statusMessage = 'Document name: "$cleaned"';
        });

        await widget.voiceService.speak('Document name set to $cleaned. Saving.');
        if (mounted) {
          Navigator.of(context).pop(cleaned);
        }
      } else {
        setState(() {
          _statusMessage = 'Could not parse document name. Please tap microphone and try again.';
        });
        await widget.voiceService.speak('Could not recognize a valid name. Please try speaking again.');
      }
    } catch (e) {
      debugPrint('VoicePdfNamingDialog error: $e');
      if (mounted) {
        _pulseController.stop();
        _pulseController.reset();
        setState(() {
          _isListening = false;
          _statusMessage = 'Voice recognition error. Please type or tap Save.';
        });
      }
    }
  }

  void _onConfirm() {
    final chosen = _nameController.text.trim();
    final clean = BrailleService.cleanPdfName(chosen);
    Navigator.of(context).pop(clean.isNotEmpty ? clean : chosen);
  }

  void _onUseDefault() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    Navigator.of(context).pop('Braille Document ($dateStr $timeStr)');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161E2E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white24, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(160),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Center drag pill
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Dialog Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepOrangeAccent.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Colors.deepOrangeAccent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Save Braille PDF',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Speak or type the document name',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white60),
                  tooltip: 'Cancel',
                  onPressed: () {
                    widget.voiceService.speak('PDF export cancelled.');
                    Navigator.of(context).pop(null);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Voice Status & Microphone Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _isListening
                    ? const Color(0xFF0D3B2E)
                    : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isListening
                      ? const Color(0xFF00E676)
                      : Colors.white12,
                  width: _isListening ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  ScaleTransition(
                    scale: _isListening
                        ? _pulseAnimation
                        : const AlwaysStoppedAnimation(1.0),
                    child: InkWell(
                      onTap: _isListening ? null : _startListeningForName,
                      borderRadius: BorderRadius.circular(28),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isListening
                              ? const Color(0xFF00E676)
                              : Colors.amber.shade700,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isListening ? 'Listening...' : 'Voice Command',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _isListening
                                ? const Color(0xFF00E676)
                                : Colors.amberAccent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _statusMessage,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Document Name Editable Field
            TextField(
              controller: _nameController,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                labelText: 'Document Name',
                labelStyle: const TextStyle(color: Colors.white70),
                hintText: 'e.g. Biology Notes',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.edit_note, color: Colors.amberAccent),
                suffixIcon: _nameController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54, size: 20),
                        tooltip: 'Clear Name',
                        onPressed: () {
                          setState(() {
                            _nameController.clear();
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00E676), width: 2),
                ),
              ),
              onChanged: (_) {
                setState(() {});
              },
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _onUseDefault,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.white30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Use Default',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _nameController.text.trim().isEmpty ? null : _onConfirm,
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text(
                      'Save PDF',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrangeAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

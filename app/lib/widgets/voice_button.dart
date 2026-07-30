import 'package:flutter/material.dart';

class VoiceButton extends StatelessWidget {
  final String label;
  final bool isListening;
  final VoidCallback onPressed;

  const VoiceButton({
    super.key,
    this.label = 'TAP TO SPEAK',
    this.isListening = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isListening ? 'Voice Assistant is listening' : 'Activate Voice Command Button',
      hint: 'Double tap to activate voice recognition',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isListening
                    ? [const Color(0xFF2563EB), const Color(0xFF1D4ED8)]
                    : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isListening ? const Color(0xFF60A5FA) : const Color(0xFF334155),
                width: isListening ? 3 : 2,
              ),
              boxShadow: isListening
                  ? [
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withAlpha((0.5 * 255).round()),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withAlpha((0.3 * 255).round()),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isListening ? Colors.white : const Color(0xFF2563EB),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: isListening
                            ? Colors.white.withAlpha((0.6 * 255).round())
                            : const Color(0xFF2563EB).withAlpha((0.4 * 255).round()),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Icon(
                    isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: isListening ? const Color(0xFF1D4ED8) : Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isListening ? 'LISTENING NOW...' : label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isListening ? 'Speak your command clearly' : 'Tap once for instant voice action',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isListening ? const Color(0xFF93C5FD) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VoiceButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final String? activeSubtitle;
  final bool isListening;
  final VoidCallback onPressed;
  final double? height;
  final Color? primaryColor;
  final Color? activeColor;

  const VoiceButton({
    super.key,
    this.label = 'TAP TO SPEAK',
    this.subtitle,
    this.activeSubtitle,
    this.isListening = false,
    required this.onPressed,
    this.height,
    this.primaryColor,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final subText = isListening
        ? (activeSubtitle ?? 'Listening... Speak your command clearly')
        : (subtitle ?? 'Tap anywhere on this button to speak');

    final effectiveActiveColor = activeColor ?? const Color(0xFF2563EB);
    final effectivePrimaryColor = primaryColor ?? const Color(0xFF1E293B);

    return Semantics(
      button: true,
      label: isListening ? 'Voice Assistant is listening' : 'Activate Voice Command Button: $label',
      hint: 'Double tap to activate voice recognition and speak commands',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            try {
              HapticFeedback.selectionClick();
            } catch (_) {}
            onPressed();
          },
          borderRadius: BorderRadius.circular(28),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            constraints: BoxConstraints(minHeight: height ?? 80),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isListening
                    ? [effectiveActiveColor, const Color(0xFF1D4ED8)]
                    : [effectivePrimaryColor, const Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isListening ? const Color(0xFF93C5FD) : const Color(0xFF475569),
                width: isListening ? 3.5 : 2.5,
              ),
              boxShadow: isListening
                  ? [
                      BoxShadow(
                        color: effectiveActiveColor.withAlpha((0.6 * 255).round()),
                        blurRadius: 28,
                        spreadRadius: 6,
                      ),
                      BoxShadow(
                        color: Colors.white.withAlpha((0.2 * 255).round()),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withAlpha((0.45 * 255).round()),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: isListening ? Colors.white : effectiveActiveColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: isListening
                            ? Colors.white.withAlpha((0.8 * 255).round())
                            : effectiveActiveColor.withAlpha((0.5 * 255).round()),
                        blurRadius: 16,
                        spreadRadius: isListening ? 4 : 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: isListening ? const Color(0xFF1D4ED8) : Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isListening ? 'LISTENING NOW...' : label,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isListening ? const Color(0xFFBFDBFE) : const Color(0xFFCBD5E1),
                          height: 1.2,
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


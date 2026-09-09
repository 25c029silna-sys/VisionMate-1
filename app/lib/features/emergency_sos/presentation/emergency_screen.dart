import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/voice/voice_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../../widgets/voice_button.dart';
import '../domain/emergency_service.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  late VoiceService voiceService;
  late StorageService storageService;
  final EmergencyService emergencyService = EmergencyService();

  String status = 'Emergency SOS ready. Tap button or trigger via voice.';
  String contactName = '';
  String contactPhone = '';
  bool isLoadingContact = true;
  bool isListening = false;
  bool isCountingDown = false;
  int countdownSeconds = 3;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    voiceService = Provider.of<VoiceService>(context, listen: false);
    storageService = Provider.of<StorageService>(context, listen: false);
    _loadTrustedContact();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await voiceService.speak('Emergency SOS activated. Say SOS or tap the button to call for help.');
      if (mounted) {
        await _handleVoiceCommand();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTrustedContact() async {
    final contact = await storageService.getTrustedContact();
    setState(() {
      contactName = contact['name'] ?? '';
      contactPhone = contact['phone'] ?? '';
      isLoadingContact = false;
    });
  }

  Future<void> _handleVoiceCommand() async {
    if (isCountingDown) {
      await _cancelSos();
      return;
    }

    if (isListening) {
      await voiceService.stopListening();
      if (mounted) {
        setState(() {
          isListening = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        isListening = true;
      });
    }

    final command = await voiceService.listen();

    if (!mounted) return;
    setState(() {
      isListening = false;
    });

    if (command == null || command.trim().isEmpty) return;

    final lower = command.toLowerCase().trim();
    if (lower.contains('sos') || lower.contains('help') || lower.contains('emergency') || lower.contains('call') || lower.contains('trigger')) {
      await _triggerSos();
    } else if (lower.contains('contact') || lower.contains('add contact') || lower.contains('edit contact')) {
      await _showAddContactDialog();
    } else if (lower.contains('back') || lower.contains('home') || lower.contains('exit') || lower.contains('cancel') || lower.contains('close')) {
      await voiceService.speak('Returning to main menu.');
      if (mounted) Navigator.pop(context);
    } else if (lower.contains('help') || lower.contains('guide')) {
      await voiceService.speak('Available commands: say SOS to trigger emergency alert, Contact to edit trusted contact, or Back to return home.');
    } else {
      await voiceService.speak('Command not recognized. Say SOS, Contact, or Back.');
    }
  }

  Future<void> _showAddContactDialog() async {
    final nameController = TextEditingController(text: contactName);
    final phoneController = TextEditingController(text: contactPhone);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Configure Trusted Contact', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Contact Name',
                labelStyle: TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: '+1234567890',
                hintStyle: TextStyle(color: Colors.white30),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              await storageService.saveTrustedContact(name: name, phone: phone);
              setState(() {
                contactName = name;
                contactPhone = phone;
              });
              if (mounted) Navigator.pop(context);
              await voiceService.speak('Trusted contact updated.');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Save Contact'),
          ),
        ],
      ),
    );
  }

  /// Cancels an active emergency SOS countdown.
  Future<void> _cancelSos() async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    await voiceService.stopListening();

    if (mounted) {
      setState(() {
        isCountingDown = false;
        countdownSeconds = 3;
        status = 'Emergency SOS request cancelled by user.';
      });
    }

    await voiceService.speak('Emergency SOS cancelled. No alert was sent.');
  }

  Future<void> _triggerSos() async {
    if (isCountingDown) return;

    if (contactPhone.isEmpty) {
      await voiceService.speak('No trusted contact configured. Please add a trusted contact first.');
      await _showAddContactDialog();
      if (contactPhone.isEmpty) return;
    }

    // Enter 3-second cancellation countdown state
    setState(() {
      isCountingDown = true;
      countdownSeconds = 3;
      status = 'EMERGENCY SOS ACTIVATED. Say "CANCEL" within 3 seconds to cancel.';
    });

    // Announce 3-second cancellation window
    await voiceService.speak(
      'Emergency SOS activated. Say CANCEL within 3 seconds to cancel.',
      awaitCompletion: false,
    );

    // Start 1-second periodic timer for visual and state countdown
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (countdownSeconds > 1) {
        setState(() {
          countdownSeconds--;
          status = 'EMERGENCY SOS: $countdownSeconds seconds remaining to cancel (Say "CANCEL").';
        });
      } else {
        timer.cancel();
        _countdownTimer = null;
        if (isCountingDown) {
          _executeSosDispatch();
        }
      }
    });

    // Concurrently listen for voice cancellation ('cancel', 'stop', 'abort', 'wait', 'no')
    final wasCancelled = await voiceService.listenForCancellation(duration: const Duration(seconds: 3));
    if (wasCancelled && isCountingDown) {
      await _cancelSos();
    }
  }

  Future<void> _executeSosDispatch() async {
    if (!mounted || !isCountingDown) return;

    setState(() {
      isCountingDown = false;
      status = '3 seconds elapsed. Dispatching emergency alert to $contactName...';
    });

    await voiceService.speak('Dispatching emergency alert. Fetching GPS coordinates.');

    try {
      final location = await emergencyService.fetchLocation();
      final message = emergencyService.composeMessage(location);

      // 1. Send SMS alert
      await emergencyService.sendSos(contactPhone, message);
      if (mounted) {
        setState(() {
          status = 'SOS SMS sent to $contactName ($contactPhone) with coordinates ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}. Calling contact now...';
        });
      }
      await voiceService.speak('Emergency SMS sent. Placing call to $contactName.');

      // 2. Call trusted contact
      await emergencyService.makePhoneCall(contactPhone);
    } catch (error) {
      final errorMsg = 'SOS alert error: $error';
      if (mounted) {
        setState(() {
          status = errorMsg;
        });
      }
      await voiceService.speak('Emergency alert encountered an issue. Placing phone call directly.');
      try {
        await emergencyService.makePhoneCall(contactPhone);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency SOS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
            tooltip: 'Configure Trusted Contact',
            onPressed: isCountingDown ? null : _showAddContactDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Trusted Contact Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withAlpha((0.4 * 255).round())),
              ),
              child: Row(
                children: [
                  const Icon(Icons.contact_phone_rounded, color: Colors.redAccent, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TRUSTED EMERGENCY CONTACT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          contactPhone.isNotEmpty ? '$contactName ($contactPhone)' : 'No Contact Configured',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: isCountingDown ? null : _showAddContactDialog,
                    child: Text(contactPhone.isNotEmpty ? 'Edit' : 'Add', style: const TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Status message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCountingDown ? const Color(0xFF3B1219) : const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(12),
                border: isCountingDown ? Border.all(color: Colors.redAccent, width: 2) : null,
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: isCountingDown ? Colors.white : Colors.white70,
                  fontSize: 15,
                  fontWeight: isCountingDown ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(),

            // If counting down: show prominent 3-second Cancellation Banner & Cancel Button
            if (isCountingDown) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E080E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.redAccent, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withAlpha((0.4 * 255).round()),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$countdownSeconds',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CANCELLATION WINDOW',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.redAccent,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Say "CANCEL" or tap below',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton.icon(
                        onPressed: _cancelSos,
                        icon: const Icon(Icons.cancel_rounded, size: 30, color: Colors.white),
                        label: const Text(
                          'CANCEL SOS NOW',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ] else ...[
              // Voice Command Button
              VoiceButton(
                label: 'VOICE SOS COMMAND',
                subtitle: 'Tap to speak: "SOS", "Contact", or "Back"',
                activeSubtitle: 'Listening... say "SOS" for immediate help',
                isListening: isListening,
                onPressed: _handleVoiceCommand,
                primaryColor: const Color(0xFF1E293B),
                activeColor: Colors.red.shade700,
              ),
              const SizedBox(height: 16),

              // Big SOS Trigger Button
              SizedBox(
                height: 100,
                child: ElevatedButton.icon(
                  onPressed: _triggerSos,
                  icon: const Icon(Icons.warning_amber_rounded, size: 38, color: Colors.white),
                  label: const Text(
                    'TRIGGER EMERGENCY SOS\n(SMS + Call with 3s Cancel)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, height: 1.2),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}


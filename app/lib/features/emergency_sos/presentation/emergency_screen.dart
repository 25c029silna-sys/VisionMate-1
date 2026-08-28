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

  Future<void> _loadTrustedContact() async {
    final contact = await storageService.getTrustedContact();
    setState(() {
      contactName = contact['name'] ?? '';
      contactPhone = contact['phone'] ?? '';
      isLoadingContact = false;
    });
  }

  Future<void> _handleVoiceCommand() async {
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


  Future<void> _triggerSos() async {
    if (contactPhone.isEmpty) {
      await voiceService.speak('No trusted contact configured. Please add a trusted contact first.');
      await _showAddContactDialog();
      if (contactPhone.isEmpty) return;
    }

    await voiceService.speak('Triggering emergency alert. Fetching GPS coordinates.');
    try {
      final location = await emergencyService.fetchLocation();
      final message = emergencyService.composeMessage(location);

      // 1. Send SMS alert
      await emergencyService.sendSos(contactPhone, message);
      setState(() {
        status = 'SOS SMS sent to $contactName ($contactPhone) with coordinates ${location.latitude}, ${location.longitude}. Calling contact now...';
      });
      await voiceService.speak('Emergency SMS sent. Placing call to $contactName.');

      // 2. Call trusted contact
      await emergencyService.makePhoneCall(contactPhone);
    } catch (error) {
      final errorMsg = 'SOS alert error: $error';
      setState(() {
        status = errorMsg;
      });
      await voiceService.speak('Emergency alert encountered an issue. Please dial manually.');
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
            onPressed: _showAddContactDialog,
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
                    onPressed: _showAddContactDialog,
                    child: Text(contactPhone.isNotEmpty ? 'Edit' : 'Add', style: const TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Status message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(),

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
              height: 110,
              child: ElevatedButton.icon(
                onPressed: _triggerSos,
                icon: const Icon(Icons.warning_amber_rounded, size: 42, color: Colors.white),
                label: const Text(
                  'TRIGGER EMERGENCY SOS\n(SMS + Call)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.2),
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
        ),
      ),
    );
  }
}


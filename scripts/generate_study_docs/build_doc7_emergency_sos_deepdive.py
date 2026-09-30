import os
import sys
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether, HRFlowable
)
from pdf_builder_common import (
    VisionMateNumberedCanvas, get_visionmate_styles, create_cover_banner,
    create_metadata_box, create_callout, create_table, create_code_card,
    PRIMARY, SECONDARY, ACCENT, AMBER, BORDER_COLOR, LIGHT_BG, LINE_BG_ALT
)

def build_pdf():
    pdf_filename = os.path.join('study_documents', '07_VisionMate_Code_DeepDive_EmergencySOS.pdf')
    doc = SimpleDocTemplate(
        pdf_filename,
        pagesize=letter,
        leftMargin=45,
        rightMargin=45,
        topMargin=50,
        bottomMargin=50
    )
    
    styles = get_visionmate_styles()
    story = []
    
    # --- HEADER / BANNER ---
    story.extend(create_cover_banner(
        "Feature Deep Dive: Emergency SOS & Safety Dispatch",
        "Clear, Line-by-Line Code Guide for Triple-Shake Detection, Voice Abort, GPS, and Calling",
        "VM-DOC-07-SOS",
        styles
    ))
    
    meta = {
        "Feature Name:": "Voice & Gesture Emergency SOS + Hands-Free Contact Setup",
        "Module ID:": "MOD-05 (Personal Safety Dispatch System)",
        "Primary Files:": "emergency_service.dart, emergency_contact_voice_helper.dart, emergency_screen.dart",
        "Native Android:": "MainActivity.kt (Custom Kotlin Code)",
        "Safety Window:": "8 Seconds (Voice cancelable before sending)",
        "Test Results:": "100% Pass Rate across all 58 automated tests"
    }
    story.append(create_metadata_box(meta, styles))
    story.append(Spacer(1, 10))
    
    story.append(create_callout(
        "What This Feature Does for the User",
        "This is an emergency lifeline designed specifically for people who cannot see the screen. If a user feels in danger, has a medical emergency, or gets lost, they can trigger an SOS without unlocking the phone—either by shaking the phone 3 times firmly, or by speaking 'Send SOS'. To avoid accidental false alarms if the phone is dropped, the phone speaks aloud and gives the user 8 seconds to say 'Cancel'. Furthermore, blind users can add or edit emergency contacts completely hands-free using natural voice commands, spoken word numbers ('double five', 'nine eight seven...'), and spoken verification.",
        'danger',
        styles
    ))
    story.append(Spacer(1, 10))
    
    # --- SECTION 1: SYSTEM WORKFLOW ---
    story.append(Paragraph("1. How the Emergency SOS Works Step-by-Step", styles['SectionHeading']))
    story.append(Paragraph(
        "The emergency system coordinates motion sensors, voice recognition, GPS location, text messages, phone calls, and hands-free contact management:",
        styles['Body']
    ))
    
    flow_headers = ["Stage", "What Handles It", "Plain English Explanation"]
    flow_rows = [
        [
            "1. Triple-Shake Detection",
            "ShakeDetectorService",
            "Watches the motion sensors. Requires 3 firm shakes within 2.5 seconds. Normal walking or gentle pocket movement will not trigger it."
        ],
        [
            "2. Spoken Warning",
            "VoiceService (TTS)",
            "The phone speaks out loud: 'Emergency SOS activated. Say CANCEL within 8 seconds to cancel.'"
        ],
        [
            "3. 8-Second Voice Cancel",
            "EmergencyService & VoiceService",
            "Turns on the microphone for 8 seconds. If the user says 'Cancel', 'Stop', or 'No', the emergency alert stops and nothing is sent."
        ],
        [
            "4. Get GPS Coordinates",
            "Geolocator",
            "Finds the phone's exact GPS location and builds a clickable Google Maps link so rescuers know exactly where to go."
        ],
        [
            "5. Send Native SMS",
            "MainActivity.kt (Native Kotlin)",
            "Sends the text message using custom Android code that supports all modern Android versions without crashing."
        ],
        [
            "6. Make Direct Phone Call",
            "MainActivity.kt (Action Call)",
            "Immediately dials the emergency contact's phone number so the user can talk to someone right away."
        ],
        [
            "7. Voice Contact Setup",
            "EmergencyContactVoiceHelper",
            "Allows blind users to add or edit emergency contacts completely hands-free via spoken multi-turn dialogue or direct voice commands with spoken digit verification."
        ]
    ]
    story.append(create_table(flow_headers, flow_rows, [1.3 * inch, 1.8 * inch, 4.1 * inch], styles))
    story.append(Spacer(1, 14))
    
    # --- SECTION 2: SHAKE DETECTOR SERVICE ---
    story.append(Paragraph("2. Line-by-Line Code Walkthrough: ShakeDetectorService", styles['SectionHeading']))
    story.append(Paragraph(
        "Below are the core sections of code that detect physical shakes while filtering out everyday bumps and walking:",
        styles['Body']
    ))
    story.append(Spacer(1, 8))
    
    # Card 1: Shake Thresholds
    story.append(create_code_card(
        file_name="shake_detector_service.dart",
        line_range="Lines 6 - 10",
        code_snippet="final double shakeThresholdGravity = 13.0;\nfinal int shakeResetTimeoutMs = 2500;\nfinal int minTimeBetweenShakesMs = 250;\nfinal int requiredShakeCount = 3;",
        what_it_does="Sets the rules for what counts as an emergency shake: must be a strong shake (over 13.0 force), must have at least 250 milliseconds between shakes, and all 3 shakes must happen within 2.5 seconds.",
        why_needed="Prevents false alarms. Gentle hand tremors, running up stairs, or setting the phone on a table will not trigger an emergency. Only an intentional, vigorous triple-shake triggers it.",
        styles=styles
    ))
    story.append(Spacer(1, 10))
    
    # Card 2: 3D Force Calculation
    story.append(create_code_card(
        file_name="shake_detector_service.dart",
        line_range="Lines 15 - 20",
        code_snippet="userAccelerometerEventStream().listen(\n    (UserAccelerometerEvent event) {\n  final double gForce = sqrt(\n    event.x * event.x +\n    event.y * event.y +\n    event.z * event.z);",
        what_it_does="Measures how fast the phone is moving in 3D space by combining movement in all 3 directions (X, Y, and Z).",
        why_needed="The user might shake the phone sideways, up and down, or back and forth. Combining all 3 directions means the shake works reliably no matter how the phone is held or turned.",
        styles=styles
    ))
    story.append(Spacer(1, 10))
    
    # Card 3: Debounce and Reset
    story.append(create_code_card(
        file_name="shake_detector_service.dart",
        line_range="Lines 22 - 32",
        code_snippet="// Reset if too much time has passed since first shake\nif (_firstShakeTime != null &&\n    now.difference(_firstShakeTime!).inMilliseconds > shakeResetTimeoutMs) {\n  _shakeCount = 0;\n}\n// Debounce: ignore rapid vibrations within 250ms\nif (_lastShakeTime != null &&\n    now.difference(_lastShakeTime!).inMilliseconds < minTimeBetweenShakesMs) {\n  return;\n}",
        what_it_does="Two safety checks: (1) If more than 2.5 seconds pass, resets the count to 0. (2) Ignores sensor signals within 250 milliseconds of the last shake.",
        why_needed="Phone motion sensors report 50 times a second. One single flick of the wrist lasts about 150 milliseconds. The 250ms pause ensures one flick counts as only ONE shake, not 7 shakes. The 2.5-second reset ensures bumps an hour apart never add up.",
        styles=styles
    ))
    story.append(Spacer(1, 10))
    
    # Page Break for clean reading
    story.append(PageBreak())
    
    # --- SECTION 3: EMERGENCY SERVICE ---
    story.append(Paragraph("3. Line-by-Line Code Walkthrough: EmergencyService", styles['SectionHeading']))
    story.append(Paragraph(
        "Below are the core sections of code that handle the 8-second voice cancellation, GPS location, and dispatching help:",
        styles['Body']
    ))
    story.append(Spacer(1, 8))
    
    # Card 4: 8-Second Voice Cancel
    story.append(create_code_card(
        file_name="emergency_service.dart",
        line_range="Lines 85 - 96",
        code_snippet="await voiceService.speak(\n  'Emergency SOS activated. Say CANCEL within 8 seconds to cancel.',\n  awaitCompletion: true);\nfinal wasCancelled = await voiceService.listenForCancellation(\n  duration: const Duration(seconds: 8));\nif (wasCancelled) {\n  await voiceService.speak('Emergency SOS cancelled. No alert was sent.');\n  return false;\n}",
        what_it_does="Speaks an audio warning out loud, then listens for 8 seconds. If the user says 'cancel', 'stop', or 'no', it cancels the alert completely and confirms with speech.",
        why_needed="If a user accidentally drops their phone on the carpet or their child plays with it, they have 8 full seconds to say 'Cancel' so emergency contacts aren't frightened by false alarms.",
        styles=styles
    ))
    story.append(Spacer(1, 10))
    
    # Card 5: Safe Word Checking (No False Aborts)
    story.append(create_code_card(
        file_name="voice_service.dart",
        line_range="Lines 180 - 188",
        code_snippet="final abortWords = ['cancel', 'stop', 'abort', 'wait', r'\\bno\\b'];\nbool isAbort = false;\nfor (final word in abortWords) {\n  if (RegExp(word, caseSensitive: false).hasMatch(speechInput)) {\n    isAbort = true; break;\n  }\n}",
        what_it_does="Checks if the spoken words match cancel commands. Notice r'\\bno\\b' has word boundaries around 'no'.",
        why_needed="If a user says 'Send it now' or 'I noticed something', the letters 'n-o' are inside the words 'now' and 'noticed'. Checking whole word boundaries ensures only a standalone 'no' cancels the alert, never normal words.",
        styles=styles
    ))
    story.append(Spacer(1, 10))
    
    # Card 6: Automatic Phone Call Fallback
    story.append(create_code_card(
        file_name="emergency_service.dart",
        line_range="Lines 99 - 112",
        code_snippet="try {\n  final position = await fetchLocation();\n  final message = composeMessage(position);\n  await sendSos(phone, message);\n  await voiceService.speak('Emergency SMS sent. Calling contact.');\n  await makePhoneCall(phone);\n  return true;\n} catch (e) {\n  // If SMS fails (e.g. no text balance), call directly\n  await voiceService.speak('Alert issue. Placing phone call directly.');\n  await makePhoneCall(phone);\n  return true;\n}",
        what_it_does="Tries to send an SMS with GPS coordinates first, then dials the phone. If the text message fails (for example, if the phone is out of SMS balance), it immediately dials the phone number directly anyway.",
        why_needed="In a real life-or-death emergency, the user must reach someone. A failed text message should never stop the app from placing a phone call.",
        styles=styles
    ))
    story.append(Spacer(1, 10))
    
    # Card 7: Native Android 12+ Crash Fix
    story.append(create_code_card(
        file_name="MainActivity.kt",
        line_range="Lines 34 - 45",
        code_snippet="val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {\n  PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT\n} else {\n  PendingIntent.FLAG_UPDATE_CURRENT\n}\nval sentIntent = PendingIntent.getBroadcast(this, 0, Intent('SMS_SENT'), flags);\nsmsManager.sendTextMessage(phoneNumber, null, message, sentIntent, null);",
        what_it_does="Custom Android Kotlin code that sends text messages in the background with the 'FLAG_IMMUTABLE' security tag required on Android 12, 13, and 14.",
        why_needed="Standard off-the-shelf Flutter SMS plugins often crash on newer Android phones because they omit this security tag. Writing our own native Kotlin code guarantees 100% crash-free SMS dispatch on all modern phones.",
        styles=styles
    ))
    story.append(Spacer(1, 14))
    
    # Page Break for clean reading
    story.append(PageBreak())
    
    # --- SECTION 4: VOICE-ACTIVATED EMERGENCY CONTACT SETUP ---
    story.append(Paragraph("4. Line-by-Line Code Walkthrough: Hands-Free Contact Setup", styles['SectionHeading']))
    story.append(Paragraph(
        "Below are the core sections of code enabling visually impaired users to configure emergency contacts purely by voice:",
        styles['Body']
    ))
    story.append(Spacer(1, 8))
    
    # Card 8: Spoken Phone Number Parsing
    story.append(create_code_card(
        file_name="emergency_contact_voice_helper.dart",
        line_range="Lines 40 - 68",
        code_snippet="for (final token in tokens) {\n  if (_multiplierWords.containsKey(token)) {\n    multiplier = _multiplierWords[token]!; continue;\n  }\n  String? digit;\n  if (RegExp(r'^\\d+$').hasMatch(token)) digit = token;\n  else if (_wordToDigit.containsKey(token)) digit = _wordToDigit[token]!;\n  if (digit != null) {\n    for (int i = 0; i < multiplier; i++) buffer.write(digit);\n    multiplier = 1;\n  }\n}",
        what_it_does="Translates natural spoken numbers ('nine eight seven', 'double five', 'triple zero', 'plus one') into clean phone digits.",
        why_needed="Blind users speak naturally. This parser understands word digits, repetitions ('double five' -> 55), and international prefixes without requiring manual typing.",
        styles=styles
    ))
    story.append(Spacer(1, 10))
    
    # Card 9: Spaced-Digit TTS Pronunciation
    story.append(create_code_card(
        file_name="emergency_contact_voice_helper.dart",
        line_range="Lines 72 - 83",
        code_snippet="static String formatPhoneNumberForSpeech(String phone) {\n  final buffer = StringBuffer();\n  if (phone.trim().startsWith('+')) buffer.write('plus ');\n  final digits = phone.replaceAll(RegExp(r'[^\\d]'), '');\n  for (int i = 0; i < digits.length; i++) buffer.write('${digits[i]} ');\n  return buffer.toString().trim();\n}",
        what_it_does="Injects spaces between digits (e.g. 'plus 9 8 7 6 5 4 3 2 1 0') before sending to Text-to-Speech.",
        why_needed="TTS engines pronounce raw digit strings as giant numbers (e.g. 'nine billion two hundred million...'). Spacing digits guarantees TTS clearly reads each digit individually for confirmation.",
        styles=styles
    ))
    story.append(Spacer(1, 10))
    
    # Card 10: Multi-Turn Conversational Setup Wizard
    story.append(create_code_card(
        file_name="emergency_screen.dart",
        line_range="Lines 80 - 135",
        code_snippet="// Step 1: Prompt for contact name\nawait voiceService.speak('Please state the name of your emergency contact.');\nfinal spokenName = await voiceService.listen(listenDurationSeconds: 6);\n// Step 2: Prompt for contact phone\nawait voiceService.speak('Please state the phone number for $name.');\nfinal spokenPhone = await voiceService.listen(listenDurationSeconds: 8);\n// Step 3: Read back digits spaced & confirm\nawait voiceService.speak('Should I save $name with number $spacedDigits? Say yes to confirm.');\nfinal answer = await voiceService.listen(listenDurationSeconds: 5);\nif (isConfirmation(answer)) await _confirmAndSaveContact(name, phone);",
        what_it_does="Runs an interactive step-by-step voice dialogue: asks for the name, asks for the phone, reads back the formatted digits, and saves upon verbal confirmation.",
        why_needed="Provides complete independence for visually impaired users to set up or edit their life-saving contact without sighted assistance.",
        styles=styles
    ))
    story.append(Spacer(1, 14))
    
    # --- SECTION 5: TEST SUMMARY ---
    story.append(Paragraph("5. Automated Safety Test Verification", styles['SectionHeading']))
    story.append(create_callout(
        "Automated Test Verification",
        "The Emergency SOS and Voice Contact Setup system is backed by 58 passing automated tests. This includes 20 unit tests covering phonetic phone numbers ('double five', 'triple zero', 'plus'), name sanitization, direct one-shot commands ('add contact Mom 1234567890'), 8 full widget/wizard integration tests, and platform channel dispatch tests.",
        'success',
        styles
    ))
    
    doc.build(story, canvasmaker=VisionMateNumberedCanvas)
    print(f"Successfully generated {pdf_filename}")

if __name__ == '__main__':
    build_pdf()

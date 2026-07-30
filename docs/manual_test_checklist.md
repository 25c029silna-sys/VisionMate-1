# VisionMate Manual Test Checklist

This checklist documents manual testing protocols for features requiring hardware devices, native Android permissions, or physical sensor triggers.

---

## 1. Emergency SOS SMS Delivery Verification (Android 13+)

### Test Environment Requirements
- Physical Android smartphone running **Android 13 (API Level 33)** or higher.
- Active SIM card with valid SMS messaging capability.
- Valid emergency contact phone number configured.

### Prerequisites
1. Install the debug APK: `flutter build apk --debug`.
2. Launch VisionMate on the target device.
3. Grant **Location** (`ACCESS_FINE_LOCATION`) and **SMS** (`SEND_SMS`) permissions when prompted by `PermissionService`.

### Step-by-Step Test Procedure
1. Navigate to the **Emergency SOS** module (via voice command *"emergency"* or tap).
2. Confirm initial spoken message: *"Emergency SOS activated. Shake your device or press the button to send help."*
3. **Trigger Scenario A (Button Tap)**: Tap **Send Emergency SOS**.
   - Verify location is fetched within **3 seconds**.
   - Verify SMS is dispatched to the contact.
   - Verify SMS recipient receives: `"Emergency alert: I need help. My location is <lat>, <long>."` within **10 seconds**.
   - Confirm spoken voice feedback: *"Emergency message sent. Help is on the way."*
4. **Trigger Scenario B (Shake Detection)**: Shake the physical device firmly.
   - Verify accelerometer trigger fires and initiates emergency flow.
   - Confirm SMS receipt by emergency contact.
5. **Fallback Scenario (No Signal / Permission Revoked)**:
   - Temporarily enable Airplane Mode or revoke SMS permission in Settings.
   - Tap **Send Emergency SOS**.
   - Confirm application does **not crash**.
   - Confirmspoken TTS alert: *"Emergency SMS alert could not be sent. Please seek help immediately or dial emergency services manually."*

---

## 2. On-Device TFLite Model Fallback Check

### Test Procedure
1. Launch VisionMate when `.tflite` model files are absent or uninitialized.
2. Trigger **Braille Recognition** via voice command *"read braille"*.
   - Confirm screen displays and speaks: *"This feature isn't available yet — the recognition model hasn't been installed."*
3. Trigger **Scene Navigation** via voice command *"describe surroundings"*.
   - Confirm screen displays and speaks: *"This feature isn't available yet — the recognition model hasn't been installed."*
4. Confirm navigation control immediately returns to the voice home menu without hanging or crashing.

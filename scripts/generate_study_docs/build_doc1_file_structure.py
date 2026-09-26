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
    create_metadata_box, create_callout, create_table, PRIMARY, SECONDARY,
    ACCENT, AMBER, BORDER_COLOR, LIGHT_BG, LINE_BG_ALT
)

def build_pdf():
    pdf_filename = os.path.join('study_documents', '01_VisionMate_File_Structure_Study.pdf')
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
        "Complete File Structure & Architectural Topology Study",
        "Comprehensive Directory Hierarchy, Module Boundaries, Code Responsibilities, and Technical Assets",
        "VM-DOC-01-FS",
        styles
    ))
    
    # Metadata Block
    meta = {
        "Project Name:": "VisionMate (Assistive Platform)",
        "Repository:": "VisionMate-1",
        "Operating System:": "Android 10+ (Cross-Platform Flutter/Dart)",
        "Primary Languages:": "Dart 3.x, Kotlin 1.9, Python 3.11+",
        "Architecture Pattern:": "Clean Architecture (Data, Domain, Presentation)",
        "Braille Operational Status:": "Printed Braille (Active) | Embossed (Future Enhancement)"
    }
    story.append(create_metadata_box(meta, styles))
    story.append(Spacer(1, 10))
    
    # Callout
    story.append(create_callout(
        "Architectural Principle & Future Enhancement Notice",
        "VisionMate follows an offline-first modular Clean Architecture. Foundational services reside in 'core/', distinct user capabilities reside in 'features/', and deep learning research/training pipelines are isolated in 'ml/' and 'embossed_braille_recognition/'.<br/><br/>"
        "<b>Important Operational Note:</b> The recognition of <i>physical embossed Braille text</i> (tactile depressions on paper) is <b>currently not operational</b> and is formally designated as a <b>Future Enhancement</b>. The active, production-ready Braille subsystem is the <b>Printed Braille Recognition Engine</b> (operating on 2D printed, flat, digital, and packaging Braille with 100% verified accuracy).",
        'warning',
        styles
    ))
    story.append(Spacer(1, 10))
    
    # --- SECTION 1: HIGH-LEVEL ARCHITECTURAL TOPOLOGY ---
    story.append(Paragraph("1. High-Level Repository Topology", styles['SectionHeading']))
    story.append(Paragraph(
        "The VisionMate repository is structured into six distinct operational subsystems designed to separate on-device production code from training workflows, synthetic dataset generators, and verification suites.",
        styles['Body']
    ))
    
    topo_headers = ["Subsystem / Directory", "Primary Technology", "Lines / Size", "Operational Role & Scope"]
    topo_rows = [
        ["app/lib/core/", "Dart / Flutter", "787 Lines (9 files)", "Cross-cutting foundational services: camera, audio, sensors, SQLite, permissions, and TFLite FlatBuffer loading."],
        ["app/lib/features/", "Dart / Flutter", "5,540 Lines (18 files)", "Domain-driven feature modules: Printed Braille Recognition (Active), Digital Library, OCR Reader, Scene Navigation, Emergency SOS."],
        ["app/android/", "Kotlin / Gradle", "3,400 Bytes (Native)", "Native Android platform channel, SmsManager with FLAG_IMMUTABLE, Direct phone dialer, AndroidManifest runtime permissions."],
        ["app/assets/", "TFLite / Text Maps", "34.7 MB (5 files)", "Quantized on-device neural network weights (yolov8n, detect, yolov8_braille prototype) and label index maps."],
        ["app/test/", "Dart Test Framework", "3,800+ Lines (20 files)", "Comprehensive test suites including unit tests, widget tests, and the 40-test automated accuracy suite."],
        ["embossed_braille_recognition/", "Python / PyTorch / OpenCV", "85+ Files / 25 MB", "[FUTURE ENHANCEMENT R&D]: Experimental research lab for physical embossed Braille (Angelina reader, DSBI dataset, Keras CNN). Currently non-operational in mobile release."],
        ["ml/", "Python / Ultralytics", "20+ Files", "Machine learning workspace: YOLOv8 obstacle training, ONNX/TFLite export pipelines, and MiniLM sentence embedding export."],
        ["reports/", "Markdown Reports", "7 Detailed Reports", "Comprehensive verification reports from live system accuracy and precision benchmarking across all modules."],
        ["docs/", "Technical Specs", "5 Documents", "Pre-implementation audit, API contract specifications, requirements specifications, and hardware test checklists."],
        ["scripts/", "Python / PowerShell", "4 Utility Scripts", "Automated environment bootstrap, synthetic dataset generators, and demo harnesses."]
    ]
    story.append(create_table(topo_headers, topo_rows, [1.4 * inch, 1.3 * inch, 1.1 * inch, 3.4 * inch], styles))
    story.append(Spacer(1, 12))
    
    # --- SECTION 2: MOBILE APPLICATION (app/lib/core) ---
    story.append(Paragraph("2. Foundational Core Infrastructure (app/lib/core/)", styles['SectionHeading']))
    story.append(Paragraph(
        "The core layer provides reusable singleton and provider-managed services required by multiple features. None of these files contain domain-specific UI logic.",
        styles['Body']
    ))
    
    core_headers = ["File Path", "Size / Lines", "Key Classes / Functions", "Architectural Responsibility"]
    core_rows = [
        ["core/camera/camera_service.dart", "72 lines", "CameraService, initializeCamera(), captureImage(), toggleTorch()", "Manages the hardware CameraController lifecycle, torch/flashlight control, resolution presets, and high-res picture taking."],
        ["core/pdf/pdf_service.dart", "130 lines", "PdfService, extractTextFromPdf(), extractImagesFromPdf(), generatePdfFromText()", "Integrates Syncfusion Flutter PDF for native text layer parsing, page rasterization for OCR, and A4 PDF synthesis."],
        ["core/permissions/permission_service.dart", "81 lines", "PermissionService, requestCameraPermission(), requestSmsPermission()", "Handles runtime permission requests across Android API versions, including fine location, camera, mic, and telephony."],
        ["core/sensors/shake_detector_service.dart", "77 lines", "ShakeDetectorService, startListening(), stopListening()", "Listens to userAccelerometerEvents, computes 3D Euclidean magnitude, and filters triple-shake gestures with debouncing."],
        ["core/storage/storage_service.dart", "95 lines", "StorageService, saveDocument(), fetchDocuments(), saveSetting()", "Manages local SQLite database (visionmate.db) lifecycle, table migrations, document indices, and key-value user preferences."],
        ["core/tflite/tflite_helper.dart", "56 lines", "TfliteHelper, loadModel(), validateTfliteHeader()", "Safely loads .tflite assets into memory, validates the 'TFL3' FlatBuffer magic bytes, and prevents native engine crashes."],
        ["core/voice/voice_service.dart", "293 lines", "VoiceService, speak(), listen(), listenForCancellation()", "Bidirectional voice engine: speech-to-text with auto-restart, text-to-speech with rate control, haptic feedback, and audio collision locks."],
        ["core/voice/command_router.dart", "124 lines", "CommandRouter, routeForCommand(), _normalize()", "Deterministic voice intent router. Normalizes noisy conversational speech and evaluates a priority keyword arbitration hierarchy."],
        ["core/voice/voice_guide_service.dart", "54 lines", "VoiceGuideService, speakGuide()", "Accessible spoken guidance service that announces available voice commands and navigation syntax to the visually impaired user."]
    ]
    story.append(create_table(core_headers, core_rows, [1.5 * inch, 0.9 * inch, 1.8 * inch, 3.0 * inch], styles))
    story.append(Spacer(1, 12))
    
    # --- SECTION 3: FEATURE MODULES (app/lib/features/) ---
    story.append(Paragraph("3. Domain Feature Modules (app/lib/features/)", styles['SectionHeading']))
    story.append(Paragraph(
        "Each functional module in VisionMate is cleanly segregated into its own feature directory containing 'data/', 'domain/', and 'presentation/' subpackages.",
        styles['Body']
    ))
    
    feat_headers = ["Module & Subdirectory", "Key Source Files", "Role in System Architecture"]
    feat_rows = [
        [
            "Braille Recognition\n(features/braille/)\n\n[PRINTED: ACTIVE]\n[EMBOSSED: FUTURE]",
            "domain/printed_braille_detector.dart (914 lines)\ndomain/page_border_detector.dart (908 lines)\ndomain/braille_service.dart (915 lines)\ndomain/braille_text_refiner.dart (77 lines)\npresentation/braille_screen.dart (582 lines)\nwidgets/voice_pdf_naming_dialog.dart (447 lines)\n[Future R&D: yolo_braille_decoder.dart]",
            "Active Production Subsystem: Pure-Dart Printed Braille Recognition (cards, packaging, books, signage). Features 4-way auto-orientation with linguistic scoring, Otsu document border cropping, Grade 1 decoding, number run normalization (#a->1), Grade 2 contraction expansion, and voice-named PDF export.\n\nFuture Enhancement Note: Recognition of physical tactile embossed Braille text is currently not working and is preserved as a future research milestone."
        ],
        [
            "Smart Digital Library\n(features/digital_library/)",
            "domain/library_service.dart (191 lines)\ndomain/minilm_embedder.dart (33 lines)\ndata/embedding_store.dart (25 lines)\npresentation/library_screen.dart (1063 lines)",
            "Offline semantic document archive: Converts documents and spoken queries into 384-dimensional dense vectors using WordPiece hashing and L2 normalization. Computes cosine similarity across stored records in SQLite. Includes native PDF ingestion with automatic OCR fallback for scanned pages and physical PDF disk cleanup."
        ],
        [
            "OCR Reader\n(features/ocr_reader/)",
            "domain/ocr_service.dart (114 lines)\ndata/ocr_data_source.dart (49 lines)\npresentation/ocr_screen.dart (381 lines)",
            "Printed document reader: Extracts text blocks via Google ML Kit on-device. Employs a 2-pass spatial geometric sorting algorithm with 20px horizontal line-band grouping to eliminate jumbled reading order. Integrates sentence-by-sentence TTS navigation, torch control, and network-isolated Wikipedia context expansion."
        ],
        [
            "Scene & Obstacle Navigation\n(features/scene_navigation/)",
            "domain/scene_service.dart (567 lines)\npresentation/scene_screen.dart (435 lines)\ndata/scene_data.dart (6 lines)",
            "Real-time computer vision guide: Ingests camera frames into YOLOv8 with aspect-ratio preserving letterboxing (300x300). Calculates metric distance using pinhole camera optical geometry and real-world reference heights. Categorizes obstacles into Left/Center/Right corridors, issues steering advice, and throttles alerts to a 3s cooldown."
        ],
        [
            "Emergency SOS Dispatch\n(features/emergency_sos/)",
            "domain/emergency_service.dart (119 lines)\npresentation/emergency_screen.dart (566 lines)\ndata/emergency_data.dart (6 lines)",
            "Safety dispatch engine: Activated globally by triple-shake gesture or voice command. Initiates an 8-second spoken cancellation window with regex-safe command parsing. Fetches GPS coordinates, formats Google Maps location links, and dispatches native SMS with retry loops and automatic direct voice calling."
        ]
    ]
    story.append(create_table(feat_headers, feat_rows, [1.4 * inch, 2.3 * inch, 3.5 * inch], styles))
    story.append(Spacer(1, 12))
    
    # Page Break for clean reading
    story.append(PageBreak())
    
    # --- SECTION 4: NATIVE ANDROID LAYER ---
    story.append(Paragraph("4. Native Android Platform Integration (app/android/)", styles['SectionHeading']))
    story.append(Paragraph(
        "VisionMate relies on native Kotlin platform channels to execute hardware-level operations that are either restricted or poorly supported by standard Flutter plugins.",
        styles['Body']
    ))
    
    android_headers = ["File / Resource", "Technology", "Configuration & Purpose"]
    android_rows = [
        [
            "MainActivity.kt",
            "Kotlin 1.9 / Android Telephony",
            "Implements MethodChannel('com.visionmate.app/sms'). Invokes Android's SmsManager to dispatch SMS background payloads. Configures PendingIntent with FLAG_IMMUTABLE (or FLAG_UPDATE_CURRENT) to comply strictly with Android 12+ API 31 security requirements. Also handles direct telephony dialing via Intent.ACTION_CALL with graceful fallback to ACTION_DIAL."
        ],
        [
            "AndroidManifest.xml",
            "Android XML Permissions",
            "Declares critical system permissions: android.permission.CAMERA, android.permission.RECORD_AUDIO, android.permission.ACCESS_FINE_LOCATION, android.permission.ACCESS_COARSE_LOCATION, android.permission.SEND_SMS, android.permission.CALL_PHONE, and android.permission.VIBRATE. Configures camera autofocus hardware features."
        ],
        [
            "build.gradle.kts (App)",
            "Gradle Kotlin DSL",
            "Sets compileSdk = 34, minSdk = 21, and targetSdk = 34. Configures NDK ABI splits, ProGuard rules, and enables core library desugaring for backward-compatible Java 8+ APIs."
        ]
    ]
    story.append(create_table(android_headers, android_rows, [1.5 * inch, 1.5 * inch, 4.2 * inch], styles))
    story.append(Spacer(1, 12))
    
    # --- SECTION 5: MACHINE LEARNING & RESEARCH LABS ---
    story.append(Paragraph("5. Machine Learning, Assets & Future Enhancements", styles['SectionHeading']))
    story.append(Paragraph(
        "The project contains production on-device models ('app/assets/') alongside research prototypes in 'embossed_braille_recognition/' and 'ml/':",
        styles['Body']
    ))
    
    ml_headers = ["Directory / Asset", "Format / Model", "Operational Status", "Function & Workflow Role"]
    ml_rows = [
        ["app/assets/models/yolov8n.tflite", "TFLite (Int8/Float16)", "PRODUCTION READY", "Ultralytics YOLOv8 Nano model for real-time indoor obstacle detection, furniture recognition, and doorway identification."],
        ["app/assets/models/detect.tflite", "TFLite (SSD MobileNet)", "PRODUCTION READY", "Secondary fallback object detection model providing bounded box outputs for mobile devices with constrained compute."],
        ["app/assets/labels/yolo_labels.txt", "Text", "PRODUCTION READY", "80-class COCO label index mapping obstacle categories."],
        ["app/assets/models/yolov8_braille.tflite", "TFLite (Float16, 26.3 MB)", "FUTURE ENHANCEMENT", "[Prototype]: Experimental deep learning model trained on physical embossed paper pages. Currently non-operational due to lighting/shadow dipole sensitivities."],
        ["app/assets/labels/braille_labels.txt", "Text (192 Bytes)", "REFERENCE ASSET", "64-class mapping associating Braille 6-bit binary indices to alphanumeric characters."],
        ["embossed_braille_recognition/pipelines/angelina_reader/", "PyTorch / Python", "FUTURE ENHANCEMENT", "Reference upstream research engine for optical Braille recognition based on RetinaNet and adaptive grid segmentation."],
        ["embossed_braille_recognition/training/braille_cnn/", "Keras / TensorFlow", "FUTURE ENHANCEMENT", "Experimental training scripts and Google Colab notebooks for 28x28 grayscale Braille cell classification."],
        ["embossed_braille_recognition/testing/experiments/", "Python / OpenCV", "RESEARCH LAB", "Experimental scripts exploring morphological circle discrimination, shadow-dipole filtering, and lattice fitting."]
    ]
    story.append(create_table(ml_headers, ml_rows, [1.8 * inch, 1.2 * inch, 1.3 * inch, 2.9 * inch], styles))
    story.append(Spacer(1, 12))
    
    # --- SECTION 6: TEST SUITE ARCHITECTURE ---
    story.append(Paragraph("6. Automated Verification & Testing Suite (app/test/)", styles['SectionHeading']))
    story.append(Paragraph(
        "VisionMate includes an enterprise-grade automated test harness verifying mathematical correctness, zero-crash fault tolerance, and 100% test pass rates across active modules.",
        styles['Body']
    ))
    
    test_headers = ["Test Suite / Path", "Tests", "Pass Rate", "Verification Scope"]
    test_rows = [
        ["test/accuracy_system_suite/braille_accuracy_system_test.dart", "10 Tests", "100.0%", "Verifies active Printed Braille engine: 64-symbol dictionary mapping, orientation transforms, seam deduplication, and zero CER/WER on printed sequences."],
        ["test/accuracy_system_suite/digital_library_accuracy_system_test.dart", "6 Tests", "100.0%", "Verifies 384d vector L2 normalization (norm=1.000), cosine ranking, multi-domain separation margin (>0.40), and scanned PDF OCR fallback."],
        ["test/accuracy_system_suite/ocr_reader_accuracy_system_test.dart", "7 Tests", "100.0%", "Validates 2-pass spatial reading order sorting, 20px line-band grouping, paragraph assembly, and non-blocking Wikipedia timeouts."],
        ["test/accuracy_system_suite/scene_navigation_accuracy_system_test.dart", "6 Tests", "100.0%", "Validates optical pinhole distance calculations (error < 0.05m), NMS IoU thresholding (0.45), and 3-second audio throttle window."],
        ["test/accuracy_system_suite/emergency_sos_accuracy_system_test.dart", "6 Tests", "100.0%", "Verifies voice cancellation regex specificity (prevents false aborts on 'now', 'know'), GPS payload format, and fall-through calling."],
        ["test/accuracy_system_suite/voice_commands_accuracy_system_test.dart", "5 Tests", "100.0%", "Evaluates a 35-utterance noisy conversational corpus, verifying priority arbitration across all 7 destination routes."]
    ]
    story.append(create_table(test_headers, test_rows, [2.2 * inch, 0.7 * inch, 0.8 * inch, 3.5 * inch], styles))
    story.append(Spacer(1, 15))
    
    # Closing summary
    story.append(create_callout(
        "Summary: Production Readiness & Roadmap",
        "The active production features of VisionMate (Printed Braille Recognition, Smart Digital Library, Real-Time OCR, Scene Navigation, Emergency SOS, and Voice Hub) are fully operational and verified with 100% test pass rates. The recognition of physical embossed Braille text is formally scheduled as a Future Enhancement requiring specialized oblique illumination or external tactile sensors.",
        'success',
        styles
    ))
    
    doc.build(story, canvasmaker=VisionMateNumberedCanvas)
    print(f"Successfully generated {pdf_filename}")

if __name__ == '__main__':
    build_pdf()

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ui/theme/app_theme.dart';
import '../../services/state_manager.dart';
import '../../ui/widgets/app_clickable.dart';
import '../../core/llm/ollama_client.dart';
import 'settings_service.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isRefreshingOllama = false;

  Future<void> _showModelSelectionDialog() async {
    final settings = ref.read(settingsServiceProvider);
    final models = await settings.getAvailableModels();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgDarkLighter,
        title: const Text('Select Whisper Model'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: models.length,
            itemBuilder: (context, index) {
              final modelPath = models[index];
              final fileName = p.basename(modelPath);
              final isSelected = settings.whisperModelPath == modelPath;

              return ListTile(
                title: Text(
                  fileName,
                  style: TextStyle(
                    color: isSelected ? AppTheme.orangeMain : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  modelPath,
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
                onTap: () {
                  settings.whisperModelPath = modelPath;
                  Navigator.pop(context);
                },
                trailing: isSelected
                    ? const Icon(Icons.check, color: AppTheme.orangeMain)
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshOllamaModels() async {
    setState(() => _isRefreshingOllama = true);
    try {
      final client = ref.read(ollamaClientProvider);
      final models = await client.getModels();
      final settings = ref.read(settingsServiceProvider);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.bgDarkLighter,
          title: const Text('Select Ollama Model'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: models.length,
              itemBuilder: (context, index) {
                final modelName = models[index];
                final isSelected = settings.ollamaModel == modelName;

                return ListTile(
                  title: Text(
                    modelName,
                    style: TextStyle(
                      color: isSelected ? AppTheme.orangeMain : Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    settings.ollamaModel = modelName;
                    Navigator.pop(context);
                  },
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppTheme.orangeMain)
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch Ollama models: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshingOllama = false);
    }
  }

  Future<void> _showPullOllamaModelDialog() async {
    final controller = TextEditingController();
    int pullProgress = -1;
    String? error;
    bool isPulling = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgDarkLighter,
          title: const Text('Pull Ollama Model'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isPulling)
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'e.g. llama3, mistral, llama2:7b',
                    errorText: error,
                  ),
                  style: const TextStyle(color: Colors.white),
                )
              else ...[
                Text('Pulling ${controller.text}...',
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: pullProgress == -1 ? null : pullProgress / 100,
                  color: AppTheme.orangeMain,
                  backgroundColor: Colors.white10,
                ),
                const SizedBox(height: 8),
                Text(pullProgress == -1 ? 'Initializing...' : '$pullProgress%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            if (!isPulling) ...[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final modelName = controller.text.trim();
                  if (modelName.isEmpty) return;

                  setDialogState(() {
                    isPulling = true;
                    error = null;
                  });

                  try {
                    final client = ref.read(ollamaClientProvider);
                    await client.pullModel(
                      model: modelName,
                      onProgress: (progress) {
                        setDialogState(() {
                          pullProgress = progress;
                        });
                      },
                    );
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    setDialogState(() {
                      isPulling = false;
                      error = e.toString();
                    });
                  }
                },
                child: const Text('Pull'),
              ),
            ],
          ],
        ),
      ),
    );
  }
  Future<void> _showPTTKeyDialog() async {
    final settings = ref.read(settingsServiceProvider);
    final hotkeyService = ref.read(voiceSyncManagerProvider).hotkeyService;
    bool isListening = false;
    String currentKey = settings.pttKey;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgDarkLighter,
          title: const Text('Set Push-to-Talk Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Assign a hotkey to trigger recording.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              AppClickable(
                onTap: isListening
                    ? null
                    : () async {
                        setDialogState(() => isListening = true);
                        final newKey = await hotkeyService.getNextPressedKey();
                        if (mounted) {
                          setDialogState(() {
                            isListening = false;
                            if (newKey != null) currentKey = newKey;
                          });
                        }
                      },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: isListening
                        ? AppTheme.orangeMain.withOpacity(0.1)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isListening ? AppTheme.orangeMain : Colors.white12,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        isListening ? Icons.keyboard_rounded : Icons.touch_app_rounded,
                        size: 48,
                        color: isListening ? AppTheme.orangeMain : Colors.white24,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isListening ? 'Listening...' : currentKey,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isListening ? AppTheme.orangeMain : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!isListening)
                const Text(
                  'Click the box and press a key',
                  style: TextStyle(fontSize: 10, color: Colors.white38),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isListening
                  ? null
                  : () {
                      settings.pttKey = currentKey;
                      Navigator.pop(context);
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _showLanguageDialog() async {
    final settings = ref.read(settingsServiceProvider);
    final languages = {
      'en': {'name': 'English', 'flag': '🇺🇸'},
      'es': {'name': 'Spanish', 'flag': '🇪🇸'},
      'fr': {'name': 'French', 'flag': '🇫🇷'},
      'de': {'name': 'German', 'flag': '🇩🇪'},
      'it': {'name': 'Italian', 'flag': '🇮🇹'},
      'pt': {'name': 'Portuguese', 'flag': '🇵🇹'},
      'nl': {'name': 'Dutch', 'flag': '🇳🇱'},
      'ru': {'name': 'Russian', 'flag': '🇷🇺'},
      'zh': {'name': 'Chinese', 'flag': '🇨🇳'},
      'ja': {'name': 'Japanese', 'flag': '🇯🇵'},
      'ko': {'name': 'Korean', 'flag': '🇰🇷'},
      'auto': {'name': 'Auto Detect', 'flag': '🌍'},
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgDarkLighter,
        title: const Text('Select Language'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: languages.length,
            itemBuilder: (context, index) {
              final code = languages.keys.elementAt(index);
              final lang = languages[code]!;
              final isSelected = settings.language == code;

              return ListTile(
                leading: Text(lang['flag']!, style: const TextStyle(fontSize: 20)),
                title: Text(
                  lang['name']!,
                  style: TextStyle(
                    color: isSelected ? AppTheme.orangeMain : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  settings.language = code;
                  Navigator.pop(context);
                },
                trailing: isSelected
                    ? const Icon(Icons.check, color: AppTheme.orangeMain)
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsServiceProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Container(
        color: AppTheme.bgLight,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSection(
                        context,
                        'Audio Configuration',
                        Icons.graphic_eq_rounded,
                        [
                          _buildAudioDeviceCard(context),
                          _buildVadSettingsCard(context, settings),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSection(
                        context,
                        'Transcription',
                        Icons.transcribe_rounded,
                        [
                          _buildWhisperModelCard(context, settings),
                          _buildLanguageCard(context, settings),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSection(
                        context,
                        'AI Enhancement',
                        Icons.auto_awesome_rounded,
                        [
                          _buildOllamaCard(context, settings),
                          _buildCleanupCard(context, settings),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSection(
                        context,
                        'Input Methods',
                        Icons.keyboard_rounded,
                        [
                          _buildPTTCard(context, settings),
                          _buildTextInjectionCard(context, settings),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.skyBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.settings_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                'Configure your experience',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textGray,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.skyBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: AppTheme.skyBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children.map((child) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: child,
            )),
      ],
    );
  }

  Widget _buildAudioDeviceCard(BuildContext context) {
    return AppClickable(
      onTap: () {
        // TODO: Implement audio device selection
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: Colors.green,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Microphone',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textDark,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        Text(
                          'Default input device',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textGray,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Active',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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

  Widget _buildVadSettingsCard(BuildContext context, SettingsService settings) {
    double vadThreshold = settings.vadThreshold;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.skyBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: AppTheme.skyBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Voice Activity Detection',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sensitivity',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textGray,
                        ),
                  ),
                  Text(
                    '${(vadThreshold * 100).toInt()}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.skyBlue,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                  activeTrackColor: AppTheme.skyBlue,
                  inactiveTrackColor: Colors.black.withOpacity(0.05),
                  thumbColor: AppTheme.skyBlue,
                  overlayColor: AppTheme.skyBlue.withOpacity(0.1),
                ),
                child: Slider(
                  value: vadThreshold,
                  onChanged: (value) {
                    settings.vadThreshold = value;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWhisperModelCard(BuildContext context, SettingsService settings) {
    return AppClickable(
      onTap: _showModelSelectionDialog,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.skyBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.psychology_rounded,
                    color: AppTheme.skyBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Whisper Model',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.skyBlue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.skyBlue.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.skyBlue,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.basename(settings.whisperModelPath),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textDark,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'High Performance • Fast & Accurate',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textGray,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageCard(BuildContext context, SettingsService settings) {
    final languages = {
      'en': {'name': 'English (US)', 'flag': '🇺🇸'},
      'es': {'name': 'Spanish', 'flag': '🇪🇸'},
      'fr': {'name': 'French', 'flag': '🇫🇷'},
      'de': {'name': 'German', 'flag': '🇩🇪'},
      'it': {'name': 'Italian', 'flag': '🇮🇹'},
      'pt': {'name': 'Portuguese', 'flag': '🇵🇹'},
      'nl': {'name': 'Dutch', 'flag': '🇳🇱'},
      'ru': {'name': 'Russian', 'flag': '🇷🇺'},
      'zh': {'name': 'Chinese', 'flag': '🇨🇳'},
      'ja': {'name': 'Japanese', 'flag': '🇯🇵'},
      'ko': {'name': 'Korean', 'flag': '🇰🇷'},
      'auto': {'name': 'Auto Detect', 'flag': '🌍'},
    };

    final currentLang = languages[settings.language] ?? languages['en']!;

    return GestureDetector(
      onTap: _showLanguageDialog,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.translate_rounded,
                    color: Colors.purple,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Language',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.02),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.black.withOpacity(0.05),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        currentLang['flag']!,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        currentLang['name']!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textDark,
                            ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textGray.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOllamaCard(BuildContext context, SettingsService settings) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.skyBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppTheme.skyBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Ollama AI',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Connected',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.skyBlue.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '🤖',
                        style: TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              settings.ollamaModel,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textDark,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              'Current model',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textGray,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AppClickable(
                onTap: _showPullOllamaModelDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.skyBlue.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: AppTheme.skyBlue,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AppClickable(
                onTap: _isRefreshingOllama ? null : _refreshOllamaModels,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.skyBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isRefreshingOllama
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCleanupCard(BuildContext context, SettingsService settings) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.cleaning_services_rounded,
                      color: Colors.cyan,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Auto-cleanup transcriptions',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: settings.autoCleanup,
              onChanged: (value) {
                settings.autoCleanup = value;
              },
              activeColor: AppTheme.skyBlue,
            ),
          ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPTTCard(BuildContext context, SettingsService settings) {
    return AppClickable(
      onTap: _showPTTKeyDialog,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.push_pin_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Push-to-Talk',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.02),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.black.withOpacity(0.05),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '⌨️',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        settings.pttKey,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textDark,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  Text(
                    'Press to record',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textGray,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextInjectionCard(BuildContext context, SettingsService settings) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.input_rounded,
                  color: Colors.blueGrey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Text Injection',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInjectionMethod(
                  context,
                  settings,
                  'dotool',
                  'Direct input',
                  settings.injectionMethod == 'dotool',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInjectionMethod(
                  context,
                  settings,
                  'Clipboard',
                  'Fallback method',
                  settings.injectionMethod == 'Clipboard',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInjectionMethod(
    BuildContext context,
    SettingsService settings,
    String name,
    String description,
    bool isActive,
  ) {
    return AppClickable(
      onTap: () {
        settings.injectionMethod = name;
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.skyBlue.withOpacity(0.1) : Colors.black.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppTheme.skyBlue
                : Colors.black.withOpacity(0.05),
            width: isActive ? 1 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isActive ? '✓' : '•',
                  style: TextStyle(
                    color: isActive ? AppTheme.skyBlue : AppTheme.textGray,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isActive ? AppTheme.skyBlue : AppTheme.textDark,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textGray,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

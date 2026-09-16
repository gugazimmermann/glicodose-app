import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/services/brazil_time.dart';
import 'package:diabetes_app/services/iob_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/widgets/disclaimer_banner.dart';
import 'package:diabetes_app/widgets/section_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.services,
    this.embedded = false,
  });

  final AppServices services;
  final bool embedded;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _glucoseController = TextEditingController();
  final _foodController = TextEditingController();
  final _carbsController = TextEditingController();
  final _appliedController = TextEditingController();
  final _picker = ImagePicker();
  final _iobService = const IobService();
  final _speech = SpeechToText();

  Uint8List? _photoBytes;
  String? _photoName;
  InsulinRecommendation? _recommendation;
  IobSnapshot _iob = IobSnapshot.empty;
  bool _useAi = true;
  bool _calculating = false;
  bool _saving = false;
  bool _loadingIob = true;
  bool _speechReady = false;
  bool _listening = false;
  String _speechBase = '';
  String? _error;
  String? _pendingImagePath;
  String? _pendingEntryId;

  @override
  void initState() {
    super.initState();
    _refreshIob();
  }

  @override
  void dispose() {
    if (_listening) {
      _speech.stop();
    }
    _glucoseController.dispose();
    _foodController.dispose();
    _carbsController.dispose();
    _appliedController.dispose();
    super.dispose();
  }

  Future<bool> _ensureSpeechReady() async {
    if (_speechReady) return true;
    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        final listening = status == SpeechToText.listeningStatus;
        if (_listening != listening) {
          setState(() => _listening = listening);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _error = 'Não foi possível ouvir. Tente novamente.';
        });
      },
    );
    if (!mounted) return false;
    setState(() => _speechReady = available);
    if (!available) {
      setState(() => _error = 'Reconhecimento de voz indisponível neste aparelho.');
    }
    return available;
  }

  Future<String?> _resolveSpeechLocale() async {
    final locales = await _speech.locales();
    for (final preferred in ['pt_BR', 'pt_PT', 'pt']) {
      for (final locale in locales) {
        final normalized = locale.localeId.replaceAll('-', '_');
        if (locale.localeId == preferred || normalized == preferred) {
          return locale.localeId;
        }
      }
    }
    for (final locale in locales) {
      final id = locale.localeId.toLowerCase();
      if (id.startsWith('pt')) return locale.localeId;
    }
    return null;
  }

  void _applySpeechWords(String words) {
    final spoken = words.trim();
    if (spoken.isEmpty) return;
    final base = _speechBase.trim();
    final text = base.isEmpty ? spoken : '$base $spoken';
    _foodController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _recommendation = null);
  }

  Future<void> _toggleFoodSpeech() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    setState(() => _error = null);
    final ready = await _ensureSpeechReady();
    if (!ready || !mounted) return;

    _speechBase = _foodController.text;
    final localeId = await _resolveSpeechLocale();
    if (!mounted) return;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) => _applySpeechWords(result.recognizedWords),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        partialResults: true,
        localeId: localeId,
      ),
    );
  }

  Widget _foodMicButton() {
    return IconButton(
      tooltip: _listening ? 'Parar' : 'Falar',
      onPressed: _toggleFoodSpeech,
      icon: Icon(
        _listening ? Icons.mic : Icons.mic_none_outlined,
        color: _listening ? AppColors.accent : AppColors.muted,
      ),
    );
  }

  Future<void> _refreshIob() async {
    setState(() => _loadingIob = true);
    try {
      const duration = 4.0;
      final since =
          DateTime.now().subtract(Duration(hours: duration.ceil() + 1));
      final entries = await widget.services.entries.listEntriesSince(since);
      final snap = _iobService.computeIob(
        recentEntries: entries,
        durationHours: duration,
        now: DateTime.now(),
      );
      if (mounted) setState(() => _iob = snap);
    } catch (_) {
      if (mounted) setState(() => _iob = IobSnapshot.empty);
    } finally {
      if (mounted) setState(() => _loadingIob = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photoBytes = bytes;
      _photoName = file.name;
      _recommendation = null;
    });
  }

  Future<void> _calculate() async {
    if (!_formKey.currentState!.validate()) return;

    final foodText = _foodController.text.trim();
    if (_useAi && foodText.isEmpty && _photoBytes == null) {
      setState(() {
        _error = 'Informe o alimento em texto e/ou anexe uma foto.';
      });
      return;
    }

    if (!_useAi) {
      final carbs = double.tryParse(
        _carbsController.text.trim().replaceAll(',', '.'),
      );
      if (carbs == null || carbs < 0) {
        setState(() => _error = 'Informe os carboidratos em gramas.');
        return;
      }
    }

    setState(() {
      _calculating = true;
      _error = null;
      _recommendation = null;
    });

    try {
      await _refreshIob();
      final entryId = const Uuid().v4();
      _pendingEntryId = entryId;
      _pendingImagePath = null;
      String? imageUrl;

      if (_photoBytes != null) {
        final path = await widget.services.entries.uploadFoodPhoto(
          entryId: entryId,
          bytes: _photoBytes!,
        );
        imageUrl = await widget.services.entries.createSignedUrl(path);
        _pendingImagePath = path;
      }

      final glucose = int.parse(_glucoseController.text.trim());
      late final InsulinRecommendation result;

      if (_useAi) {
        final brNow = BrazilTime.now();
        result = await widget.services.insulin.recommendWithAi(
          glucoseMgdl: glucose,
          localTime: BrazilTime.formatHm(brNow),
          timezone: BrazilTime.locationName,
          iobU: _iob.iobU,
          foodText: foodText.isEmpty ? null : foodText,
          foodImageUrl: imageUrl,
        );
      } else {
        final profile = await widget.services.profile.fetchCurrent();
        if (profile == null || !profile.isComplete) {
          throw Exception('Perfil incompleto. Atualize sua prescrição.');
        }
        final carbs = double.parse(
          _carbsController.text.trim().replaceAll(',', '.'),
        );
        result = widget.services.insulin.calculateManual(
          glucoseMgdl: glucose,
          carboidratosG: carbs,
          profile: profile,
          iobU: _iob.iobU,
        );
      }

      setState(() {
        _recommendation = result;
        _appliedController.text = formatWhole(result.insulinaRecomendadaU);
        if (!_useAi) {
          _carbsController.text = formatWhole(result.carboidratosG);
        }
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  Future<void> _save() async {
    if (_recommendation == null) {
      setState(() => _error = 'Calcule a insulina antes de salvar.');
      return;
    }
    final applied = double.tryParse(
      _appliedController.text.trim().replaceAll(',', '.'),
    );
    if (applied == null) {
      setState(() => _error = 'Informe a insulina aplicada.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.services.entries.saveEntry(
        entryId: _pendingEntryId,
        glucoseMgdl: int.parse(_glucoseController.text.trim()),
        recordedAt: DateTime.now(),
        foodText: _foodController.text.trim().isEmpty
            ? null
            : _foodController.text.trim(),
        foodImagePath: _pendingImagePath,
        recommendedInsulin: _recommendation!.insulinaRecomendadaU,
        appliedInsulin: applied,
        gptRawResponse: _recommendation!.raw,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro salvo')),
      );
      setState(() {
        _glucoseController.clear();
        _foodController.clear();
        _carbsController.clear();
        _appliedController.clear();
        _photoBytes = null;
        _photoName = null;
        _recommendation = null;
        _pendingImagePath = null;
        _pendingEntryId = null;
      });
      await _refreshIob();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          const DisclaimerBanner(),
          const SizedBox(height: 12),
          if (!_loadingIob && _iob.iobU > 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC80)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Você ainda tem ~${formatWhole(_iob.iobU)} U ativas. '
                      'A recomendação já desconta isso.',
                      style: const TextStyle(
                        color: Color(0xFFBF360C),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!_loadingIob && _iob.iobU > 0) const SizedBox(height: 12),
          SectionCard(
            title: 'Glicose atual',
            icon: Icons.water_drop,
            iconColor: AppColors.accent,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _glucoseController,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          height: 1.1,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          hintText: '105',
                          hintStyle: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB0BEC5),
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          errorStyle: TextStyle(height: 0.8),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe a glicose';
                          }
                          final n = int.tryParse(value.trim());
                          if (n == null || n <= 0) return 'Valor inválido';
                          return null;
                        },
                        onChanged: (_) =>
                            setState(() => _recommendation = null),
                      ),
                      const Text(
                        'mg/dL',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Alimentação',
            icon: Icons.restaurant_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Estimar com IA'),
                      icon: Icon(Icons.auto_awesome, size: 16),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Carbs manuais'),
                      icon: Icon(Icons.calculate_outlined, size: 16),
                    ),
                  ],
                  selected: {_useAi},
                  onSelectionChanged: (values) {
                    setState(() {
                      _useAi = values.first;
                      _recommendation = null;
                      _error = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (_useAi) ...[
                  TextFormField(
                    controller: _foodController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _listening
                          ? 'Ouvindo...'
                          : 'Ex: 2 pães franceses com queijo',
                      alignLabelWithHint: true,
                      suffixIcon: _foodMicButton(),
                    ),
                    onChanged: (_) => setState(() => _recommendation = null),
                  ),
                  if (_listening)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Ouvindo… toque no microfone para parar',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Câmera'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galeria'),
                        ),
                      ),
                    ],
                  ),
                  if (_photoBytes != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          Image.memory(
                            _photoBytes!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setState(() {
                                    _photoBytes = null;
                                    _photoName = null;
                                    _recommendation = null;
                                  });
                                },
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_photoName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _photoName!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                  ],
                ] else ...[
                  const Text(
                    'Informe os carboidratos. A dose usa sua fórmula '
                    '(correção + comida − IOB), sem chamar a IA.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _foodController,
                    decoration: InputDecoration(
                      labelText: 'Descrição (opcional)',
                      hintText: _listening ? 'Ouvindo...' : 'Ex: almoço',
                      suffixIcon: _foodMicButton(),
                    ),
                    onChanged: (_) => setState(() => _recommendation = null),
                  ),
                  if (_listening)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Ouvindo… toque no microfone para parar',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _carbsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Carboidratos (g)',
                      prefixIcon: Icon(Icons.grain),
                    ),
                    onChanged: (_) => setState(() => _recommendation = null),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _calculating ? null : _calculate,
            icon: _calculating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(_useAi ? Icons.auto_awesome : Icons.calculate_outlined),
            label: Text(
              _calculating
                  ? 'Calculando...'
                  : (_useAi
                      ? 'Estimar carbs e calcular'
                      : 'Calcular com fórmula'),
            ),
          ),
          if (_recommendation != null) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Insulina recomendada',
              icon: Icons.medication_outlined,
              iconColor: AppColors.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatWhole(
                              _recommendation!.insulinaRecomendadaU,
                            ),
                            style: const TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              height: 1,
                            ),
                          ),
                          const TextSpan(
                            text: ' U',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      _recommendation!.source == 'manual'
                          ? 'Cálculo local (fórmula)'
                          : 'Carbs TACO (IA) + fórmula',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_recommendation!.metaDisplay != null) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        _recommendation!.horarioBr != null
                            ? '${_recommendation!.metaDisplay!} · ${_recommendation!.horarioBr} (Brasília)'
                            : _recommendation!.metaDisplay!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _MetricChip(
                        label: 'Carbs',
                        value: '${formatWhole(_recommendation!.carboidratosG)} g',
                      ),
                      const SizedBox(width: 8),
                      _MetricChip(
                        label: 'Correção',
                        value: '${formatWhole(_recommendation!.correcaoU)} U',
                      ),
                      const SizedBox(width: 8),
                      _MetricChip(
                        label: 'Comida',
                        value: '${formatWhole(_recommendation!.bolusComidaU)} U',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _MetricChip(
                        label: 'IOB',
                        value: '${formatWhole(_recommendation!.iobU)} U',
                      ),
                    ],
                  ),
                  if (_recommendation!.observacao != null &&
                      _recommendation!.observacao!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _recommendation!.observacao!,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _appliedController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Insulina aplicada (U)',
                      helperText: 'Ajuste para mais ou menos se necessário',
                      prefixIcon: Icon(Icons.edit_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Salvar registro'),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.accent, fontSize: 13),
            ),
          ],
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Nova dose')),
      body: body,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

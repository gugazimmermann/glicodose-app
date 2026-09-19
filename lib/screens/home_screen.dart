import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/screens/dose_result_screen.dart';
import 'package:diabetes_app/services/brazil_time.dart';
import 'package:diabetes_app/services/iob_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/decimal_input.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/disclaimer_banner.dart';
import 'package:diabetes_app/widgets/section_card.dart';
import 'package:diabetes_app/widgets/support_cta_banner.dart';

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
  final _picker = ImagePicker();
  final _iobService = const IobService();

  Uint8List? _photoBytes;
  String? _photoName;
  IobSnapshot _iob = IobSnapshot.empty;
  bool _useAi = true;
  bool _calculating = false;
  bool _loadingIob = true;
  bool _listening = false;
  bool _transcribing = false;
  bool _iobFailed = false;
  bool _isSupporter = false;
  String? _error;
  String? _glucoseWarning;

  @override
  void initState() {
    super.initState();
    _refreshIob();
  }

  @override
  void dispose() {
    if (_listening) {
      widget.services.speech.cancelRecording();
    }
    _glucoseController.dispose();
    _foodController.dispose();
    _carbsController.dispose();
    super.dispose();
  }

  void _reportSpeechIssue(String message) {
    if (!mounted) return;
    setState(() {
      _listening = false;
      _transcribing = false;
      _error = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _applySpeechWords(String words) {
    if (!mounted) return;
    final spoken = words.trim();
    if (spoken.isEmpty) return;
    final base = _foodController.text.trim();
    final text = base.isEmpty ? spoken : '$base $spoken';
    _foodController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {});
  }

  Future<void> _toggleFoodSpeech() async {
    if (_transcribing) return;

    if (_listening) {
      setState(() {
        _listening = false;
        _transcribing = true;
        _error = null;
      });
      try {
        final text = await widget.services.speech.stopAndTranscribe();
        if (!mounted) return;
        _applySpeechWords(text);
        setState(() => _transcribing = false);
      } catch (e) {
        _reportSpeechIssue(userFacingError(e));
      }
      return;
    }

    setState(() => _error = null);
    try {
      await widget.services.speech.startRecording();
      if (!mounted) return;
      setState(() => _listening = true);
    } catch (e) {
      _reportSpeechIssue(userFacingError(e));
    }
  }

  Widget _foodMicButton() {
    final active = _listening || _transcribing;
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: _transcribing
            ? 'Transcrevendo…'
            : _listening
                ? 'Parar'
                : 'Falar',
        onPressed: _transcribing ? null : _toggleFoodSpeech,
        icon: _transcribing
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                active ? Icons.mic : Icons.mic_none_outlined,
                color: active ? AppColors.accent : AppColors.muted,
              ),
      ),
    );
  }

  Future<void> _refreshIob() async {
    setState(() {
      _loadingIob = true;
      _iobFailed = false;
    });
    try {
      final profile = await widget.services.profile.fetchCurrent();
      final duration = profile?.insulinDurationHours ?? 4.0;
      final since =
          DateTime.now().subtract(Duration(hours: duration.ceil() + 1));
      final entries = await widget.services.entries.listEntriesSince(since);
      final snap = _iobService.computeIob(
        recentEntries: entries,
        durationHours: duration,
        now: DateTime.now(),
      );
      if (mounted) {
        setState(() {
          _iob = snap;
          _iobFailed = false;
          _isSupporter = profile?.isSupporter ?? false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _iob = IobSnapshot.empty;
          _iobFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingIob = false);
    }
  }

  void _updateGlucoseWarning(String? raw) {
    final n = int.tryParse(raw?.trim() ?? '');
    String? warning;
    if (n != null) {
      if (n > 0 && n < 70) {
        warning = 'Glicose baixa (< 70). Considere tratar hipoglicemia antes do bolus.';
      } else if (n > 300) {
        warning = 'Glicose muito alta (> 300). Confira a leitura e siga sua orientação médica.';
      }
    }
    if (warning != _glucoseWarning) {
      setState(() => _glucoseWarning = warning);
    }
  }

  Future<bool> _confirmExtremeGlucoseIfNeeded(int glucose) async {
    if (glucose >= 70 && glucose <= 300) return true;
    final message = glucose < 70
        ? 'Glicose $glucose mg/dL está baixa. Deseja calcular mesmo assim?'
        : 'Glicose $glucose mg/dL está muito alta. Deseja calcular mesmo assim?';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar glicose'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    return ok == true;
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
    });
  }

  void _clearForm() {
    _glucoseController.clear();
    _foodController.clear();
    _carbsController.clear();
    _photoBytes = null;
    _photoName = null;
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
      final carbs = parseDecimal(_carbsController.text);
      if (carbs == null || carbs < 0) {
        setState(() => _error = 'Informe os carboidratos em gramas.');
        return;
      }
    }

    final glucose = int.parse(_glucoseController.text.trim());
    if (!await _confirmExtremeGlucoseIfNeeded(glucose)) return;
    if (!mounted) return;

    setState(() {
      _calculating = true;
      _error = null;
    });

    try {
      await _refreshIob();
      final entryId = const Uuid().v4();
      String? imagePath;

      if (_photoBytes != null) {
        imagePath = await widget.services.entries.uploadFoodPhoto(
          entryId: entryId,
          bytes: _photoBytes!,
        );
      }

      late final InsulinRecommendation result;

      if (_useAi) {
        final brNow = BrazilTime.now();
        final imageUrl = imagePath == null
            ? null
            : await widget.services.entries.createSignedUrl(imagePath);
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
        final carbs = parseDecimal(_carbsController.text)!;
        result = widget.services.insulin.calculateManual(
          glucoseMgdl: glucose,
          carboidratosG: carbs,
          profile: profile,
          iobU: _iob.iobU,
        );
      }

      // Persist recommendation only — applied stays null until user confirms.
      final entry = await widget.services.entries.saveEntry(
        entryId: entryId,
        glucoseMgdl: glucose,
        recordedAt: DateTime.now(),
        foodText: foodText.isEmpty ? null : foodText,
        foodImagePath: imagePath,
        recommendedInsulin: result.insulinaRecomendadaU,
        appliedInsulin: null,
        gptRawResponse: result.raw,
      );
      widget.services.notifyEntriesChanged();

      if (!mounted) return;

      final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DoseResultScreen(
            services: widget.services,
            entry: entry,
            recommendation: result,
          ),
        ),
      );

      if (!mounted) return;
      if (done == true) {
        setState(_clearForm);
        await _refreshIob();
      }
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          if (!_loadingIob && _iob.iobU > 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC80)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning),
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
          if (_iobFailed) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCDD2)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: AppColors.error),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Não foi possível calcular o IOB. '
                      'A dose pode ficar superestimada.',
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const DisclaimerBanner(),
          const SizedBox(height: 12),
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
                      Semantics(
                        label: 'Glicose em miligramas por decilitro',
                        textField: true,
                        child: TextFormField(
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
                            hintText: 'ex.: 120',
                            hintStyle: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: AppColors.hint,
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
                          onChanged: _updateGlucoseWarning,
                        ),
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
                if (_glucoseWarning != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _glucoseWarning!,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                      icon: Icon(Icons.auto_awesome, size: 18),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Carbs manuais'),
                      icon: Icon(Icons.edit_note_outlined, size: 18),
                    ),
                  ],
                  selected: {_useAi},
                  onSelectionChanged: (values) {
                    setState(() {
                      _useAi = values.first;
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
                      hintText: (_listening || _transcribing)
                          ? (_transcribing ? 'Transcrevendo…' : 'Ouvindo...')
                          : 'Ex: 2 pães franceses com queijo',
                      alignLabelWithHint: true,
                      suffixIcon: _foodMicButton(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_listening || _transcribing)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _transcribing
                            ? 'Transcrevendo o áudio…'
                            : 'Ouvindo… toque no microfone para parar',
                        style: const TextStyle(
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
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _photoBytes = null;
                                    _photoName = null;
                                  });
                                },
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
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
                      hintText: (_listening || _transcribing)
                          ? (_transcribing ? 'Transcrevendo…' : 'Ouvindo...')
                          : 'Ex: almoço',
                      suffixIcon: _foodMicButton(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_listening || _transcribing)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _transcribing
                            ? 'Transcrevendo o áudio…'
                            : 'Ouvindo… toque no microfone para parar',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _carbsController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [decimalInputFormatter],
                    decoration: const InputDecoration(
                      labelText: 'Carboidratos (g)',
                      prefixIcon: Icon(Icons.grain),
                    ),
                    onChanged: (_) => setState(() {}),
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
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          if (!_isSupporter) ...[
            const SizedBox(height: 16),
            SupportCtaBanner(
              visible: !_isSupporter,
              onTap: () => widget.services.selectedTabIndex.value = 2,
            ),
          ],
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Dose')),
      body: body,
    );
  }
}

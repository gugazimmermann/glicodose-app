import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/screens/dose_result_screen.dart';
import 'package:diabetes_app/screens/health_import_screen.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/dose_factor.dart';
import 'package:diabetes_app/services/health_platform_service.dart';
import 'package:diabetes_app/services/iob_live_controller.dart';
import 'package:diabetes_app/services/libre_alert_service.dart';
import 'package:diabetes_app/services/status_home_widget_service.dart';
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

  Uint8List? _photoBytes;
  String? _photoName;
  bool _useAi = true;
  bool _calculating = false;
  bool _listening = false;
  bool _transcribing = false;
  bool _isSupporter = false;
  String? _error;
  String? _glucoseWarning;
  bool _glucoseManuallyEdited = false;
  String? _autoFilledGlucose;
  /// When glucose was filled from Health Connect / Apple Health.
  PlatformGlucoseReading? _healthImport;
  bool _libreConnected = false;
  bool _libreSyncing = false;
  LibreGlucoseReading? _libreReading;
  StreamSubscription<LibreGlucoseReading?>? _libreSub;
  DoseSituation _situation = DoseSituation.none;
  Entry? _unconfirmed;
  bool _basalLoggedToday = false;

  IobLiveController get _iobLive => widget.services.iobLive;

  @override
  void initState() {
    super.initState();
    _iobLive.snapshot.addListener(_onIobChanged);
    _iobLive.loading.addListener(_onIobChanged);
    _iobLive.failed.addListener(_onIobChanged);
    unawaited(_loadSupporterFlag());
    unawaited(_checkUnconfirmed());
    unawaited(_checkBasalToday());
    if (_iobLive.snapshot.value.iobU == 0 && !_iobLive.loading.value) {
      unawaited(_iobLive.refreshFromNetwork());
    }
    unawaited(_initLibre());
  }

  Future<void> _checkUnconfirmed() async {
    try {
      final entry = await widget.services.entries.latestUnconfirmed();
      if (mounted) setState(() => _unconfirmed = entry);
    } catch (_) {}
  }

  Future<void> _checkBasalToday() async {
    try {
      final dose = await widget.services.basal.latestToday();
      if (mounted) setState(() => _basalLoggedToday = dose != null);
    } catch (_) {}
  }

  @override
  void dispose() {
    _iobLive.snapshot.removeListener(_onIobChanged);
    _iobLive.loading.removeListener(_onIobChanged);
    _iobLive.failed.removeListener(_onIobChanged);
    _libreSub?.cancel();
    if (_listening) {
      widget.services.speech.cancelRecording();
    }
    _glucoseController.dispose();
    _foodController.dispose();
    _carbsController.dispose();
    super.dispose();
  }

  void _onIobChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSupporterFlag() async {
    try {
      final profile = await widget.services.profile.fetchCurrent();
      if (mounted) {
        setState(() => _isSupporter = profile?.isSupporter ?? false);
      }
    } catch (_) {}
  }

  Future<void> _initLibre() async {
    try {
      final status = await widget.services.libre.status();
      if (!mounted) return;
      setState(() => _libreConnected = status.connected);
      if (!status.connected) {
        unawaited(
          StatusHomeWidgetService.publish(
            libreConnected: false,
            clearGlucose: true,
            iobU: asWholeDose(_iobLive.snapshot.value.iobU),
          ),
        );
        return;
      }

      if (status.latest != null) {
        _applyLibreReading(status.latest!);
      } else {
        unawaited(
          StatusHomeWidgetService.publish(
            libreConnected: true,
            iobU: asWholeDose(_iobLive.snapshot.value.iobU),
          ),
        );
      }

      _libreSub?.cancel();
      _libreSub = widget.services.libre.watchLatestGlucose().listen((reading) {
        if (!mounted || reading == null) return;
        _applyLibreReading(reading);
      });

      await _syncLibre(silent: true);
    } catch (_) {
      // Libre is optional; Dose still works with manual glucose.
    }
  }

  void _applyLibreReading(
    LibreGlucoseReading reading, {
    bool force = false,
  }) {
    final text = reading.glucoseMgdl.toString();
    final current = _glucoseController.text.trim();
    final stillAuto =
        current.isEmpty || current == (_autoFilledGlucose ?? '');
    final canFill = force || !_glucoseManuallyEdited || stillAuto;

    setState(() {
      _libreReading = reading;
      _libreConnected = true;
      if (canFill) {
        _glucoseController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        _autoFilledGlucose = text;
        _glucoseManuallyEdited = false;
        _healthImport = null;
      }
    });
    if (canFill) {
      _updateGlucoseWarning(text);
    }
    unawaited(() async {
      await StatusHomeWidgetService.publish(
        libreConnected: true,
        reading: reading,
        iobU: asWholeDose(_iobLive.snapshot.value.iobU),
      );
      await _iobLive.ensureWidgetRefreshRunning();
    }());
  }

  Future<void> _syncLibre({bool silent = false, bool forceFill = false}) async {
    if (_libreSyncing) return;
    setState(() => _libreSyncing = true);
    try {
      final reading = await widget.services.libre.syncNow();
      if (!mounted) return;
      _applyLibreReading(reading, force: forceFill);
      try {
        await LibreAlertService.recordSyncSuccess();
        await LibreAlertService.evaluate(reading, libreConnected: true);
      } catch (_) {}
    } catch (e) {
      try {
        await LibreAlertService.recordSyncFailure();
      } catch (_) {}
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _libreSyncing = false);
    }
  }

  void _onGlucoseChanged(String value) {
    final trimmed = value.trim();
    _glucoseManuallyEdited =
        trimmed.isNotEmpty && trimmed != (_autoFilledGlucose ?? '');
    _updateGlucoseWarning(value);
  }

  Future<void> _openLinkarSensor() async {
    final reading = await Navigator.of(context).push<PlatformGlucoseReading>(
      MaterialPageRoute<PlatformGlucoseReading>(
        builder: (_) => HealthImportScreen(services: widget.services),
      ),
    );
    if (!mounted) return;
    await _initLibre();
    if (reading != null) {
      _applyHealthReading(reading);
    }
  }

  void _applyHealthReading(PlatformGlucoseReading reading) {
    final text = reading.glucoseMgdl.toString();
    setState(() {
      _glucoseController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _autoFilledGlucose = text;
      _glucoseManuallyEdited = false;
      _healthImport = reading;
      _error = null;
    });
    _updateGlucoseWarning(text);
  }

  Future<void> _importFromHealth() async {
    final health = widget.services.healthPlatform;
    if (!health.isSupportedPlatform) {
      setState(
        () => _error =
            'Health Connect / Apple Health não disponível neste dispositivo.',
      );
      return;
    }
    setState(() => _error = null);
    try {
      final avail = await health.availability();
      if (avail == HealthPlatformAvailability.needsInstall) {
        await health.openInstallPage();
        return;
      }
      final ok = await health.requestAuthorization();
      if (!ok) {
        if (!mounted) return;
        setState(
          () => _error =
              'Autorize a leitura de glicose em ${health.platformLabel}.',
        );
        return;
      }
      final reading = await health.latestGlucose();
      if (!mounted) return;
      if (reading == null) {
        setState(
          () => _error =
              'Nenhuma glicose recente em ${health.platformLabel}.',
        );
        return;
      }
      _applyHealthReading(reading);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Glicose ${reading.glucoseMgdl} mg/dL de ${reading.sourceName}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    }
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

  Widget _foodMicButton(BuildContext context) {
    final colors = AppColors.of(context);
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
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                active ? Icons.mic : Icons.mic_none_outlined,
                color: active ? AppColors.accent : colors.muted,
              ),
      ),
    );
  }

  void _updateGlucoseWarning(String? raw) {
    final n = int.tryParse(raw?.trim() ?? '');
    String? warning;
    if (n != null) {
      if (n > 0 && n < 70) {
        warning =
            'Glicose baixa (< 70). Considere tratar hipoglicemia antes do bolus.';
      } else if (n > 300) {
        warning =
            'Glicose muito alta (> 300). Confira a leitura e siga sua orientação médica.';
      }
    }
    final trend = _libreReading?.trend;
    if (trend != null && trend <= 2 && n != null && n < 120) {
      final trendMsg =
          'Tendência Libre ${_libreReading!.trendLabel}: glicose em queda — risco de hipo se bolus agora.';
      warning = warning == null ? trendMsg : '$warning\n$trendMsg';
    }
    if (warning != _glucoseWarning) {
      setState(() => _glucoseWarning = warning);
    }
  }

  Future<bool> _confirmExtremeGlucoseIfNeeded(int glucose) async {
    final trend = _libreReading?.trend;
    final fallingFast = trend != null && trend <= 2 && glucose < 120;
    if (glucose >= 70 && glucose <= 300 && !fallingFast) return true;
    final message = glucose < 70
        ? 'Glicose $glucose mg/dL está baixa. Deseja calcular mesmo assim?'
        : fallingFast
            ? 'Glicose $glucose mg/dL com tendência ${_libreReading!.trendLabel}. '
                'Bolus agora aumenta risco de hipoglicemia. Continuar?'
            : 'Glicose $glucose mg/dL está muito alta. Deseja calcular mesmo assim?';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fallingFast ? 'Tendência em queda' : 'Confirmar glicose'),
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
    _foodController.clear();
    _carbsController.clear();
    _photoBytes = null;
    _photoName = null;
    _error = null;
    _glucoseWarning = null;
    _glucoseManuallyEdited = false;
    _autoFilledGlucose = null;
    _healthImport = null;

    final reading = _libreReading;
    if (reading != null) {
      final text = reading.glucoseMgdl.toString();
      _glucoseController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _autoFilledGlucose = text;
      if (reading.glucoseMgdl > 0 && reading.glucoseMgdl < 70) {
        _glucoseWarning =
            'Glicose baixa (< 70). Considere tratar hipoglicemia antes do bolus.';
      } else if (reading.glucoseMgdl > 300) {
        _glucoseWarning =
            'Glicose muito alta (> 300). Confira a leitura e siga sua orientação médica.';
      }
    } else {
      _glucoseController.clear();
    }
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
      await _iobLive.refreshFromNetwork();
      final iobU = _iobLive.snapshot.value.iobU;
      final entryId = const Uuid().v4();
      String? imagePath;

      if (_photoBytes != null) {
        imagePath = await widget.services.entries.uploadFoodPhoto(
          entryId: entryId,
          bytes: _photoBytes!,
        );
      }

      late InsulinRecommendation result;

      if (_useAi) {
        final zonedNow = AppTime.now();
        final imageUrl = imagePath == null
            ? null
            : await widget.services.entries.createSignedUrl(imagePath);
        result = await widget.services.insulin.recommendWithAi(
          glucoseMgdl: glucose,
          localTime: AppTime.formatHm(zonedNow),
          timezone: AppTime.locationName,
          iobU: iobU,
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
          iobU: iobU,
        );
      }

      final profileForFactor =
          await widget.services.profile.fetchCurrent();
      if (profileForFactor != null) {
        result = const DoseFactor().applyToRecommendation(
          result,
          _situation,
          doseStep: profileForFactor.doseStep,
        );
      }

      // Persist recommendation only — applied stays null until user confirms.
      final health = _healthImport;
      final fromHealth = health != null &&
          !_glucoseManuallyEdited &&
          _glucoseController.text.trim() == health.glucoseMgdl.toString();
      final fromLibre = !fromHealth &&
          _libreConnected &&
          !_glucoseManuallyEdited &&
          _autoFilledGlucose != null &&
          _glucoseController.text.trim() == _autoFilledGlucose;
      final glucoseSource = fromHealth
          ? 'health'
          : fromLibre
              ? 'libre'
              : 'manual';
      final recordedAt =
          fromHealth ? health.recordedAt : DateTime.now();

      final entry = await widget.services.entries.saveEntry(
        entryId: entryId,
        glucoseMgdl: glucose,
        recordedAt: recordedAt,
        foodText: foodText.isEmpty ? null : foodText,
        foodImagePath: imagePath,
        recommendedInsulin: result.insulinaRecomendadaU,
        appliedInsulin: null,
        gptRawResponse: result.raw,
        glucoseSource: glucoseSource,
        healthGlucoseUuid: fromHealth ? health.externalId : null,
      );

      // Best-effort write-back of manual/Libre glucose (not Health echo).
      if (glucoseSource != 'health') {
        unawaited(() async {
          try {
            final profile =
                await widget.services.profile.fetchCurrent(applyTheme: false);
            if (profile?.healthSyncEnabled != true) return;
            await widget.services.healthPlatform.writeGlucose(
              glucoseMgdl: glucose,
              recordedAt: recordedAt,
              clientRecordId: entry.id,
            );
          } catch (_) {}
        }());
      }

      if (!mounted) return;

      await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(
          builder: (_) => DoseResultScreen(
            services: widget.services,
            entry: entry,
            recommendation: result,
          ),
        ),
      );

      if (!mounted) return;
      widget.services.notifyEntriesChanged();
      setState(() {
        _clearForm();
        _situation = DoseSituation.none;
      });
      await _iobLive.refreshFromNetwork();
      await _checkUnconfirmed();
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  Future<void> _openBasalSheet() async {
    Profile? profile;
    try {
      profile = await widget.services.profile.fetchCurrent(applyTheme: false);
    } catch (_) {}
    if (!mounted) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _BasalLogSheet(
        services: widget.services,
        profile: profile,
      ),
    );
    if (saved == true && mounted) {
      widget.services.notifyEntriesChanged();
      await _checkBasalToday();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Basal registrada')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final body = Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          if (!_isSupporter) ...[
            SupportCtaBanner(
              visible: !_isSupporter,
              onTap: () => widget.services.selectedTabIndex.value = 2,
            ),
            SizedBox(height: 12),
          ],
          if (_unconfirmed != null) ...[
            Material(
              color: colors.primarySoft,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final e = _unconfirmed!;
                  final rec = InsulinRecommendation.fromEntry(e);
                  await Navigator.of(context, rootNavigator: true).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => DoseResultScreen(
                        services: widget.services,
                        entry: e,
                        recommendation: rec,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  await _checkUnconfirmed();
                  await _iobLive.refreshFromNetwork();
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions,
                          color: AppColors.primaryDark),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Dose pendente de confirmação '
                          '(${_unconfirmed!.glucoseMgdl} mg/dL). '
                          'Toque para confirmar e atualizar o IOB.',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: AppColors.primaryDark),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 12),
          ],
          if (!_iobLive.loading.value && _iobLive.snapshot.value.iobU > 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.warningSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC80)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Você ainda tem ~${formatWhole(_iobLive.snapshot.value.iobU)} U ativas. '
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
          if (!_iobLive.loading.value && _iobLive.snapshot.value.iobU > 0)
            SizedBox(height: 12),
          if (_iobLive.failed.value) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCDD2)),
              ),
              child: Row(
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
            SizedBox(height: 12),
          ],
          const DisclaimerBanner(),
          SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openBasalSheet,
            icon: Icon(
              _basalLoggedToday
                  ? Icons.check_circle_outline
                  : Icons.nights_stay_outlined,
            ),
            label: Text(
              _basalLoggedToday
                  ? 'Basal registrada hoje · Registrar outra'
                  : 'Registrar basal',
            ),
          ),
          SizedBox(height: 12),
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
                    color: colors.primarySoft,
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
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                            height: 1.1,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            hintText: 'ex.: 120',
                            hintStyle: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: colors.hint,
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
                          onChanged: _onGlucoseChanged,
                        ),
                      ),
                      Text(
                        'mg/dL',
                        style: TextStyle(
                          color: colors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_libreConnected) ...[
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          () {
                            final r = _libreReading;
                            if (r == null) return 'LibreLinkUp conectado';
                            final parts = <String>[
                              'Libre',
                              if (r.trendLabel.isNotEmpty) r.trendLabel,
                              if (r.ageLabel.isNotEmpty) r.ageLabel,
                            ];
                            return parts.join(' ');
                          }(),
                          style: TextStyle(
                            color: colors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _openLinkarSensor,
                        child: const Text('Gerenciar'),
                      ),
                      IconButton(
                        tooltip: 'Atualizar do Libre',
                        onPressed: _libreSyncing
                            ? null
                            : () => unawaited(
                                  _syncLibre(silent: false, forceFill: true),
                                ),
                        icon: _libreSyncing
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync, size: 20),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openLinkarSensor,
                          icon: const Icon(Icons.sensors, size: 18),
                          label: const Text('Linkar Sensor'),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _importFromHealth,
                          icon: const Icon(Icons.monitor_heart_outlined,
                              size: 18),
                          label: Text(
                            widget.services.healthPlatform.isSupportedPlatform
                                ? 'Health'
                                : 'Health',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_glucoseWarning != null) ...[
                  SizedBox(height: 10),
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
          SizedBox(height: 12),
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
                SizedBox(height: 12),
                Text(
                  'Situação (ajuste opcional)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
                SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: DoseSituation.values.map((s) {
                    final selected = _situation == s;
                    return ChoiceChip(
                      label: Text(s.label),
                      selected: selected,
                      onSelected: (_) => setState(() => _situation = s),
                      selectedColor: colors.primarySoft,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: selected
                            ? AppColors.primaryDark
                            : colors.ink,
                      ),
                    );
                  }).toList(),
                ),
                if (_situation != DoseSituation.none) ...[
                  SizedBox(height: 4),
                  Text(
                    _situation.hint,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.muted,
                      height: 1.3,
                    ),
                  ),
                ],
                SizedBox(height: 12),
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
                      suffixIcon: _foodMicButton(context),
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
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Câmera'),
                        ),
                      ),
                      SizedBox(width: 8),
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
                    SizedBox(height: 12),
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
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.muted,
                          ),
                        ),
                      ),
                  ],
                ] else ...[
                  Text(
                    'Informe os carboidratos. A dose usa sua fórmula '
                    '(correção + comida − IOB), sem chamar a IA.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.muted,
                      height: 1.35,
                    ),
                  ),
                  SizedBox(height: 12),
                  TextFormField(
                    controller: _foodController,
                    decoration: InputDecoration(
                      labelText: 'Descrição (opcional)',
                      hintText: (_listening || _transcribing)
                          ? (_transcribing ? 'Transcrevendo…' : 'Ouvindo...')
                          : 'Ex: almoço',
                      suffixIcon: _foodMicButton(context),
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
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  SizedBox(height: 12),
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
          SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _calculating ? null : _calculate,
            icon: _calculating
                ? SizedBox(
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
            SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
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

class _BasalLogSheet extends StatefulWidget {
  const _BasalLogSheet({
    required this.services,
    this.profile,
  });

  final AppServices services;
  final Profile? profile;

  @override
  State<_BasalLogSheet> createState() => _BasalLogSheetState();
}

class _BasalLogSheetState extends State<_BasalLogSheet> {
  late final TextEditingController _unitsController;
  late final TextEditingController _nameController;
  late DateTime _recordedAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    final dose = p?.basalDoseU;
    _unitsController = TextEditingController(
      text: dose == null ? '' : formatWhole(dose),
    );
    _nameController = TextEditingController(text: p?.basalInsulinName ?? '');
    _recordedAt = AppTime.now();
  }

  @override
  void dispose() {
    _unitsController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final initial = TimeOfDay.fromDateTime(_recordedAt);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _recordedAt = DateTime(
        _recordedAt.year,
        _recordedAt.month,
        _recordedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _save() async {
    final units = parseDecimal(_unitsController.text);
    if (units == null || units <= 0) {
      setState(() => _error = 'Informe a dose em unidades');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final name = _nameController.text.trim();
      await widget.services.basal.saveDose(
        units: units,
        recordedAt: _recordedAt,
        insulinName: name.isEmpty ? null : name,
      );
      try {
        final profile =
            await widget.services.profile.fetchCurrent(applyTheme: false);
        if (profile?.healthSyncEnabled == true) {
          await widget.services.healthPlatform.writeInsulin(
            units: units,
            recordedAt: _recordedAt,
            basal: true,
          );
        }
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final hm =
        '${_recordedAt.hour.toString().padLeft(2, '0')}:${_recordedAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Registrar basal',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Não altera o IOB da insulina rápida.',
            style: TextStyle(fontSize: 13, color: colors.muted, height: 1.35),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Insulina',
              hintText: 'Ex: Lantus, Tresiba',
              prefixIcon: Icon(Icons.vaccines_outlined),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _unitsController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [decimalInputFormatter],
            decoration: const InputDecoration(
              labelText: 'Unidades (U)',
              prefixIcon: Icon(Icons.straighten),
            ),
          ),
          SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Horário'),
            subtitle: Text(hm),
            trailing: TextButton(
              onPressed: _pickTime,
              child: const Text('Alterar'),
            ),
          ),
          if (_error != null) ...[
            SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          SizedBox(height: 12),
          FilledButton(
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
                : const Text('Salvar basal'),
          ),
        ],
      ),
    );
  }
}

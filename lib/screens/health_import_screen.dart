import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/health_platform_service.dart';
import 'package:diabetes_app/services/libre_alert_service.dart';
import 'package:diabetes_app/services/status_home_widget_service.dart';
import 'package:diabetes_app/services/widget_health_sync.dart';
import 'package:diabetes_app/services/widget_libre_sync.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/section_card.dart';

const _libreRegions = <String, String>{
  'global': 'Global',
  'eu': 'Europa (EU) — comum no Brasil',
  'eu2': 'Europa 2 (EU2)',
  'us': 'Estados Unidos (US)',
  'de': 'Alemanha (DE)',
  'fr': 'França (FR)',
  'ap': 'Ásia / Pacífico (AP)',
  'au': 'Austrália (AU)',
  'ca': 'Canadá (CA)',
  'jp': 'Japão (JP)',
  'ae': 'Emirados (AE)',
};

/// LibreLinkUp connect + Health Connect / Apple Health blood glucose import.
class HealthImportScreen extends StatefulWidget {
  const HealthImportScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<HealthImportScreen> createState() => _HealthImportScreenState();
}

class _HealthImportScreenState extends State<HealthImportScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  LibreConnectionStatus _status = LibreConnectionStatus.disconnected;
  String _region = 'global';
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;
  String? _error;

  Profile? _profile;
  bool _alertsEnabled = false;
  final _hypoController = TextEditingController(text: '70');
  final _hyperController = TextEditingController(text: '180');
  final _staleController = TextEditingController(text: '20');
  bool _alertsSaving = false;

  HealthPlatformAvailability _healthAvail =
      HealthPlatformAvailability.unsupported;
  PlatformGlucoseReading? _healthReading;
  bool _healthBusy = false;
  String? _healthError;
  bool _healthSyncEnabled = false;
  bool _healthSyncBusy = false;

  HealthPlatformService get _health => widget.services.healthPlatform;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadHealth();
    _loadAlertPrefs();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _hypoController.dispose();
    _hyperController.dispose();
    _staleController.dispose();
    super.dispose();
  }

  Future<void> _loadAlertPrefs() async {
    try {
      final profile = await widget.services.profile.fetchCurrent(applyTheme: false);
      if (!mounted) return;
      if (profile != null) {
        setState(() {
          _profile = profile;
          _alertsEnabled = profile.libreAlertsEnabled;
          _healthSyncEnabled = profile.healthSyncEnabled;
          _hypoController.text = '${profile.libreAlertHypoMgdl}';
          _hyperController.text = '${profile.libreAlertHyperMgdl}';
          _staleController.text = '${profile.libreAlertStaleMinutes}';
        });
      }
    } catch (_) {
      // Prefs mirror still usable offline.
    }
  }

  Future<void> _persistAlerts({bool? enabled}) async {
    final hypo = int.tryParse(_hypoController.text.trim()) ?? 70;
    final hyper = int.tryParse(_hyperController.text.trim()) ?? 180;
    final stale = int.tryParse(_staleController.text.trim()) ?? 20;
    final nextEnabled = enabled ?? _alertsEnabled;

    if (nextEnabled) {
      final ok = await LibreAlertService.requestPermissions();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permissão de notificação necessária para alertas de glicose.',
            ),
          ),
        );
      }
      if (nextEnabled) {
        unawaited(widget.services.pushTokens.register());
      }
    }

    setState(() {
      _alertsEnabled = nextEnabled;
      _alertsSaving = true;
    });

    try {
      final current = _profile ??
          await widget.services.profile.fetchCurrent(applyTheme: false);
      if (current == null) {
        await LibreAlertService.applyFromProfile(
          Profile(
            id: widget.services.auth.currentUser?.id ?? '',
            libreAlertsEnabled: nextEnabled,
            libreAlertHypoMgdl: hypo.clamp(40, 120),
            libreAlertHyperMgdl: hyper.clamp(120, 400),
            libreAlertStaleMinutes: stale.clamp(5, 120),
          ),
        );
        return;
      }
      final updated = current.copyWith(
        libreAlertsEnabled: nextEnabled,
        libreAlertHypoMgdl: hypo.clamp(40, 120),
        libreAlertHyperMgdl: hyper.clamp(120, 400),
        libreAlertStaleMinutes: stale.clamp(5, 120),
      );
      final saved = await widget.services.profile.upsert(updated);
      if (!mounted) return;
      setState(() => _profile = saved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _alertsSaving = false);
    }
  }

  Future<void> _loadHealth() async {
    if (!_health.isSupportedPlatform) {
      if (mounted) {
        setState(() => _healthAvail = HealthPlatformAvailability.unsupported);
      }
      return;
    }
    try {
      final avail = await _health.availability();
      PlatformGlucoseReading? reading;
      if (avail == HealthPlatformAvailability.ready) {
        final auth = await _health.hasAuthorization();
        if (auth == true) {
          reading = await _health.latestGlucose();
        }
      }
      if (!mounted) return;
      setState(() {
        _healthAvail = avail;
        _healthReading = reading;
        _healthError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _healthError = userFacingError(e));
    }
  }

  Future<void> _authorizeAndFetchHealth() async {
    setState(() {
      _healthBusy = true;
      _healthError = null;
    });
    try {
      final avail = await _health.availability();
      if (avail == HealthPlatformAvailability.needsInstall) {
        await _health.openInstallPage();
        if (!mounted) return;
        setState(() => _healthAvail = avail);
        return;
      }
      final ok = await _health.requestAuthorization();
      if (!ok) {
        if (!mounted) return;
        setState(
          () => _healthError =
              'Permissão negada. Autorize a leitura de glicose em '
              '${_health.platformLabel}.',
        );
        return;
      }
      final reading = await _health.latestGlucose();
      if (!mounted) return;
      setState(() {
        _healthAvail = HealthPlatformAvailability.ready;
        _healthReading = reading;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reading == null
                ? 'Conectado. Nenhuma glicose recente em ${_health.platformLabel}.'
                : 'Última glicose: ${reading.glucoseMgdl} mg/dL',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _healthError = userFacingError(e));
    } finally {
      if (mounted) setState(() => _healthBusy = false);
    }
  }

  Future<void> _refreshHealthReading() async {
    setState(() {
      _healthBusy = true;
      _healthError = null;
    });
    try {
      final reading = await _health.latestGlucose();
      if (!mounted) return;
      setState(() => _healthReading = reading);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reading == null
                ? 'Nenhuma glicose nos últimos 7 dias'
                : 'Atualizado: ${reading.glucoseMgdl} mg/dL',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _healthError = userFacingError(e));
    } finally {
      if (mounted) setState(() => _healthBusy = false);
    }
  }

  Future<void> _setHealthSync(bool enabled) async {
    setState(() {
      _healthSyncBusy = true;
      _healthError = null;
    });
    try {
      if (enabled) {
        final avail = await _health.availability();
        if (avail == HealthPlatformAvailability.needsInstall) {
          await _health.openInstallPage();
          if (!mounted) return;
          setState(() => _healthSyncBusy = false);
          return;
        }
        final ok = await _health.requestAuthorization();
        if (!ok) {
          if (!mounted) return;
          setState(() {
            _healthError =
                'Autorize leitura/escrita de glicose em ${_health.platformLabel}.';
            _healthSyncBusy = false;
          });
          return;
        }
        await _health.requestBackgroundAuthorization();
      }

      final current = _profile ??
          await widget.services.profile.fetchCurrent(applyTheme: false);
      if (current == null) {
        throw Exception('Perfil não encontrado');
      }
      final saved = await widget.services.profile.upsert(
        current.copyWith(healthSyncEnabled: enabled),
      );
      await WidgetHealthSync.setEnabled(enabled);
      if (enabled) {
        final history = await _health.glucoseHistory(
          lookback: const Duration(days: 14),
        );
        final n =
            await widget.services.glicemias.upsertHealthReadings(history);
        await widget.services.iobLive.ensureWidgetRefreshRunning();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              n == 0
                  ? 'Sync ativo. Nenhuma amostra nova para importar.'
                  : 'Sync ativo. $n amostras importadas.',
            ),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _profile = saved;
        _healthSyncEnabled = enabled;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _healthError = userFacingError(e));
    } finally {
      if (mounted) setState(() => _healthSyncBusy = false);
    }
  }

  Future<void> _backfillHealth() async {
    setState(() {
      _healthBusy = true;
      _healthError = null;
    });
    try {
      final ok = await _health.requestAuthorization();
      if (!ok) {
        if (!mounted) return;
        setState(
          () => _healthError =
              'Autorize a leitura de glicose em ${_health.platformLabel}.',
        );
        return;
      }
      final history = await _health.glucoseHistory(
        lookback: const Duration(days: 30),
      );
      final n = await widget.services.glicemias.upsertHealthReadings(history);
      final latest = history.isEmpty ? null : history.first;
      if (!mounted) return;
      setState(() {
        _healthReading = latest;
        _healthAvail = HealthPlatformAvailability.ready;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'Nenhuma glicose encontrada no período.'
                : '$n amostras importadas para o histórico.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _healthError = userFacingError(e));
    } finally {
      if (mounted) setState(() => _healthBusy = false);
    }
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.services.libre.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        if (status.region != null &&
            _libreRegions.containsKey(status.region)) {
          _region = status.region!;
        }
        if (status.email != null) {
          _emailController.text = status.email!;
        }
      });
      await _publishWidgetFromStatus(status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.services.libre.connect(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        region: _region,
      );
      _passwordController.clear();
      await _loadStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LibreLinkUp conectado')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desconectar LibreLinkUp?'),
        content: const Text(
          'A sincronização automática de glicose será interrompida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.services.libre.disconnect();
      if (!mounted) return;
      setState(() {
        _status = LibreConnectionStatus.disconnected;
        _passwordController.clear();
      });
      await StatusHomeWidgetService.publish(
        libreConnected: false,
        clearGlucose: true,
        iobU: asWholeDose(widget.services.iobLive.snapshot.value.iobU),
        clearError: true,
      );
      await widget.services.iobLive.ensureWidgetRefreshRunning();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LibreLinkUp desconectado')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ok = await WidgetLibreSync.refresh(showSyncing: true);
      await widget.services.iobLive.ensureWidgetRefreshRunning();
      await _loadStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Glicemia atualizada' : 'Falha ao sincronizar Libre',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publishWidgetFromStatus(LibreConnectionStatus status) async {
    final iobU = asWholeDose(widget.services.iobLive.snapshot.value.iobU);
    if (!status.connected) {
      await StatusHomeWidgetService.publish(
        libreConnected: false,
        clearGlucose: true,
        iobU: iobU,
      );
      await widget.services.iobLive.ensureWidgetRefreshRunning();
      return;
    }
    await StatusHomeWidgetService.publish(
      libreConnected: true,
      reading: status.latest,
      iobU: iobU,
      clearError: true,
    );
    await widget.services.iobLive.ensureWidgetRefreshRunning();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Linkar Sensor')),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                SectionCard(
                  title: 'LibreLinkUp',
                  icon: Icons.sensors,
                  iconColor: AppColors.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _status.connected
                            ? 'Conta seguidor conectada. A glicose atual '
                                'aparece automaticamente na tela Dose.'
                            : 'Use a conta de seguidor do LibreLinkUp '
                                '(não a conta principal do sensor). '
                                'E-mail e senha não ficam salvos — só o token.',
                        style: const TextStyle(height: 1.4),
                      ),
                      if (_status.connected) ...[
                        SizedBox(height: 12),
                        _StatusLine(
                          label: 'E-mail',
                          value: _status.email ?? '—',
                        ),
                        _StatusLine(
                          label: 'Região',
                          value: _status.region?.toUpperCase() ?? '—',
                        ),
                        if (_status.latest != null)
                          _StatusLine(
                            label: 'Última glicose',
                            value:
                                '${_status.latest!.glucoseMgdl} mg/dL '
                                '${_status.latest!.trendLabel} '
                                '(${_status.latest!.ageLabel})',
                          ),
                        if (_status.lastSyncAt != null)
                          _StatusLine(
                            label: 'Última sync',
                            value: _formatLocal(_status.lastSyncAt!),
                          ),
                        if (_status.lastError != null &&
                            _status.lastError!.isNotEmpty) ...[
                          SizedBox(height: 8),
                          Text(
                            _status.lastError!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                        SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _saving ? null : _syncNow,
                          icon: const Icon(Icons.sync),
                          label: Text(
                            _saving ? 'Sincronizando…' : 'Atualizar agora',
                          ),
                        ),
                        SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _disconnect,
                          icon: const Icon(Icons.link_off),
                          label: const Text('Desconectar'),
                        ),
                      ] else ...[
                        SizedBox(height: 14),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'E-mail LibreLinkUp',
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Informe o e-mail';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 10),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscure,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Senha',
                                  suffixIcon: IconButton(
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Informe a senha';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                key: ValueKey(_region),
                                initialValue: _region,
                                decoration: const InputDecoration(
                                  labelText: 'Região da API',
                                ),
                                items: _libreRegions.entries
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(
                                          e.value,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _saving
                                    ? null
                                    : (v) {
                                        if (v != null) {
                                          setState(() => _region = v);
                                        }
                                      },
                              ),
                              SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: _saving ? null : _connect,
                                icon: const Icon(Icons.link),
                                label: Text(
                                  _saving ? 'Conectando…' : 'Conectar',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 12),
                SectionCard(
                  title: 'Alertas de glicose',
                  icon: Icons.notifications_active_outlined,
                  iconColor: AppColors.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        !kIsWeb &&
                                defaultTargetPlatform == TargetPlatform.iOS
                            ? 'Receba avisos de hipo/hiper e sensor parado. '
                                'No iOS, com o app fechado os alertas chegam '
                                'por push (requer permissão e Firebase).'
                            : 'Receba avisos de hipo/hiper e sensor parado. '
                                'No Android o serviço em segundo plano avalia '
                                'a cada minuto; push cobre quando o app está morto.',
                        style: const TextStyle(height: 1.4),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ativar alertas Libre'),
                        value: _alertsEnabled,
                        onChanged: _alertsSaving
                            ? null
                            : (v) => _persistAlerts(enabled: v),
                      ),
                      if (_alertsEnabled) ...[
                        SizedBox(height: 4),
                        TextField(
                          controller: _hypoController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Hipo abaixo de (mg/dL)',
                            helperText: 'Padrão 70',
                          ),
                          onEditingComplete: () => _persistAlerts(),
                        ),
                        SizedBox(height: 10),
                        TextField(
                          controller: _hyperController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Hiper acima de (mg/dL)',
                            helperText: 'Padrão 180',
                          ),
                          onEditingComplete: () => _persistAlerts(),
                        ),
                        SizedBox(height: 10),
                        TextField(
                          controller: _staleController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Sem dados há (minutos)',
                            helperText: 'Alerta de sensor parado — padrão 20',
                          ),
                          onEditingComplete: () => _persistAlerts(),
                        ),
                        SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed:
                                _alertsSaving ? null : () => _persistAlerts(),
                            child: Text(
                              _alertsSaving ? 'Salvando…' : 'Salvar limiares',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 12),
                SectionCard(
                  title: _health.platformLabel,
                  icon: Icons.monitor_heart_outlined,
                  iconColor: AppColors.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _healthAvail == HealthPlatformAvailability.unsupported
                            ? 'Disponível apenas em Android (Health Connect) '
                                'e iOS (Apple Health).'
                            : 'Importe glicose do ${_health.platformLabel} '
                                'para a Dose e o histórico. Ao confirmar doses, '
                                'o app pode gravar glicose e carbs'
                                '${_health.supportsInsulinWrite ? ' e insulina' : ''}'
                                ' de volta.',
                        style: const TextStyle(height: 1.4),
                      ),
                      if (_healthAvail !=
                          HealthPlatformAvailability.unsupported) ...[
                        SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Sincronizar em segundo plano'),
                          subtitle: Text(
                            _health.supportsInsulinWrite
                                ? 'Importa glicose e grava bolus/basal no Apple Health.'
                                : 'Importa glicose e grava carbs/glicose no Health Connect (insulina só no iOS).',
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                          value: _healthSyncEnabled,
                          onChanged: _healthSyncBusy
                              ? null
                              : (v) => _setHealthSync(v),
                        ),
                      ],
                      if (_healthAvail ==
                          HealthPlatformAvailability.needsInstall) ...[
                        SizedBox(height: 10),
                        Text(
                          'Instale o app Health Connect na Play Store para continuar.',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (_healthReading != null) ...[
                        SizedBox(height: 12),
                        _StatusLine(
                          label: 'Última',
                          value:
                              '${_healthReading!.glucoseMgdl} mg/dL · '
                              '${_formatLocal(_healthReading!.recordedAt)}',
                        ),
                        _StatusLine(
                          label: 'Fonte',
                          value: _healthReading!.sourceName,
                        ),
                      ],
                      if (_healthError != null) ...[
                        SizedBox(height: 10),
                        Text(
                          _healthError!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                      SizedBox(height: 12),
                      if (_healthAvail ==
                          HealthPlatformAvailability.unsupported)
                        Text(
                          'Use LibreLinkUp ou digite a glicose manualmente.',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.muted,
                          ),
                        )
                      else ...[
                        FilledButton.icon(
                          onPressed: _healthBusy
                              ? null
                              : _authorizeAndFetchHealth,
                          icon: _healthBusy
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _healthAvail ==
                                          HealthPlatformAvailability.needsInstall
                                      ? Icons.download_outlined
                                      : Icons.health_and_safety_outlined,
                                ),
                          label: Text(
                            _healthAvail ==
                                    HealthPlatformAvailability.needsInstall
                                ? 'Instalar Health Connect'
                                : 'Autorizar e buscar glicose',
                          ),
                        ),
                        if (_healthAvail == HealthPlatformAvailability.ready) ...[
                          SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed:
                                _healthBusy ? null : _refreshHealthReading,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Atualizar leitura'),
                          ),
                          SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _healthBusy ? null : _backfillHealth,
                            icon: const Icon(Icons.history),
                            label: const Text('Importar histórico (30 dias)'),
                          ),
                          if (_healthReading != null) ...[
                            SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  Navigator.of(context).pop(_healthReading),
                              icon: const Icon(Icons.medication_liquid),
                              label: const Text('Usar na Dose'),
                            ),
                          ],
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String _formatLocal(DateTime dt) {
    final local = dt.toLocal();
    final d =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    final t =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: colors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

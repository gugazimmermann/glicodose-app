import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/services/status_home_widget_service.dart';
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

/// LibreLinkUp connect + placeholders for Health Connect / Apple Health (R4).
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

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
      await widget.services.libre.syncNow();
      await _loadStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Glicemia atualizada')),
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
      return;
    }
    await StatusHomeWidgetService.publish(
      libreConnected: true,
      reading: status.latest,
      iobU: iobU,
      clearError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Linkar Sensor')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                        const SizedBox(height: 12),
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
                          const SizedBox(height: 8),
                          Text(
                            _status.lastError!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _saving ? null : _syncNow,
                          icon: const Icon(Icons.sync),
                          label: Text(
                            _saving ? 'Sincronizando…' : 'Atualizar agora',
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _disconnect,
                          icon: const Icon(Icons.link_off),
                          label: const Text('Desconectar'),
                        ),
                      ] else ...[
                        const SizedBox(height: 14),
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
                              const SizedBox(height: 10),
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
                              const SizedBox(height: 10),
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
                              const SizedBox(height: 14),
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
                        const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Outras fontes (em breve)',
                  icon: Icons.monitor_heart_outlined,
                  iconColor: AppColors.muted,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Também planejamos importar glicemias de:',
                        style: TextStyle(height: 1.4),
                      ),
                      SizedBox(height: 12),
                      _Bullet('Health Connect (Android)'),
                      _Bullet('Apple Health / HealthKit (iOS)'),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.muted,
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

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

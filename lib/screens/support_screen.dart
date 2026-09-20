import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/support_section.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({
    super.key,
    required this.services,
    this.embedded = false,
  });

  final AppServices services;
  final bool embedded;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  bool _loading = true;
  String? _error;
  String? _supporterProductId;
  String _supporterStatus = 'none';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.services.profile.fetchCurrent();
      if (profile != null) {
        _supporterProductId = profile.supporterProductId;
        _supporterStatus = profile.supporterStatus;
      }
    } catch (e) {
      _error = userFacingError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SupportSection(
                support: widget.services.support,
                profileProductId: _supporterProductId,
                profileStatus: _supporterStatus,
              ),
            ],
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Apoiar')),
      body: body,
    );
  }
}

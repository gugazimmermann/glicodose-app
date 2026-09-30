import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/content/clinical_disclaimer.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/widgets/app_logo.dart';
import 'package:diabetes_app/widgets/section_card.dart';

class DisclaimerScreen extends StatefulWidget {
  const DisclaimerScreen({
    super.key,
    required this.services,
    required this.onAccepted,
  });

  final AppServices services;
  final VoidCallback onAccepted;

  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  bool _accepted = false;
  bool _saving = false;
  String? _error;

  Future<void> _continue() async {
    if (!_accepted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.services.profile.acceptDisclaimer();
      widget.onAccepted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const AppBarLogoTitle(title: 'Aviso importante'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(child: AppLogo(size: 80)),
            SizedBox(height: 20),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ClinicalDisclaimer.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                  SizedBox(height: 12),
                  for (final point in ClinicalDisclaimer.points) ...[
                    Text(
                      point,
                      style: TextStyle(
                        color: colors.muted,
                        height: 1.45,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            SizedBox(height: 16),
            CheckboxListTile(
              value: _accepted,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _accepted = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                ClinicalDisclaimer.acceptLabel,
                style: TextStyle(fontSize: 14, height: 1.35),
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.accent),
              ),
            ],
            SizedBox(height: 16),
            FilledButton(
              onPressed: (_accepted && !_saving) ? _continue : null,
              child: _saving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Concordo e continuar'),
            ),
          ],
        ),
      ),
    );
  }
}

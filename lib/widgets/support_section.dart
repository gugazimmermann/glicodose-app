import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:diabetes_app/config/revenuecat_config.dart';
import 'package:diabetes_app/config/support_products.dart';
import 'package:diabetes_app/services/support_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/section_card.dart';

/// Optional recurring support (IAP). Hidden on web / when RC keys are missing.
class SupportSection extends StatefulWidget {
  const SupportSection({
    super.key,
    required this.support,
    this.profileProductId,
    this.profileStatus,
  });

  final SupportService support;
  final String? profileProductId;
  final String? profileStatus;

  @override
  State<SupportSection> createState() => _SupportSectionState();
}

class _SupportSectionState extends State<SupportSection> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<SupportPlanOption> _plans = const [];
  CustomerInfo? _customerInfo;

  bool get _isSupporter {
    final info = _customerInfo;
    if (info != null && widget.support.hasActiveSupporter(info)) return true;
    final status = widget.profileStatus;
    return status == 'active' || status == 'grace' || status == 'canceled';
  }

  String? get _activeProductId {
    final fromRc = _customerInfo == null
        ? null
        : widget.support.activeProductId(_customerInfo!);
    return fromRc ?? widget.profileProductId;
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!RevenueCatConfig.isConfigured || !widget.support.isAvailable) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final plans = await widget.support.loadPlans();
      final info = await widget.support.getCustomerInfo();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _customerInfo = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(e);
        _loading = false;
      });
    }
  }

  Future<void> _purchase(SupportPlanOption plan) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await widget.support.purchase(plan.package);
      if (!mounted) return;
      setState(() => _customerInfo = info);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obrigado por apoiar o GlicoDose!'),
        ),
      );
    } catch (e) {
      final msg = SupportService.purchaseErrorMessage(e);
      if (msg != null && mounted) {
        setState(() => _error = msg);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await widget.support.restore();
      if (!mounted) return;
      setState(() => _customerInfo = info);
      final ok = widget.support.hasActiveSupporter(info);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Compras restauradas. Obrigado pelo apoio!'
                : 'Nenhuma assinatura de apoio encontrada nesta conta da loja.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !RevenueCatConfig.isSupportedPlatform) {
      return const SizedBox.shrink();
    }
    if (!RevenueCatConfig.isConfigured) {
      if (kDebugMode) {
        return SectionCard(
          title: 'Apoiar o GlicoDose',
          icon: Icons.favorite_outline,
          iconColor: AppColors.accent,
          child: const Text(
            'Defina REVENUECAT_IOS_API_KEY / REVENUECAT_ANDROID_API_KEY '
            'no .env para testar IAP. Veja docs/iap-store-setup.md.',
            style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return SectionCard(
      title: 'Apoiar o GlicoDose',
      icon: Icons.favorite_outline,
      iconColor: AppColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'O app é gratuito. Se quiser, você pode apoiar com uma '
            'assinatura mensal opcional — isso ajuda a manter a '
            'infraestrutura e a IA. Renovação automática; cancele a '
            'qualquer momento na loja.',
            style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
          ),
          if (_isSupporter) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC5D0DB)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Você é apoiador',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        Text(
                          _activeProductId == null
                              ? 'Obrigado por manter o projeto.'
                              : 'Plano: ${SupportProducts.displayLabel(_activeProductId!)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_plans.isEmpty)
            const Text(
              'Planos indisponíveis no momento. Confira a configuração '
              'nas lojas / RevenueCat ou tente mais tarde.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _plans.map((plan) {
                final selected = _activeProductId == plan.productId;
                return ChoiceChip(
                  label: Text(
                    selected
                        ? '${plan.priceLabel} · ativo'
                        : plan.priceLabel,
                  ),
                  selected: selected,
                  onSelected: _busy || selected
                      ? null
                      : (_) => _purchase(plan),
                );
              }).toList(),
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _restore,
                  child: const Text('Restaurar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => widget.support.openManageSubscriptions(
                            productId: _activeProductId,
                          ),
                  child: const Text('Gerenciar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

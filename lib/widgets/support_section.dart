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
    final colors = AppColors.of(context);
    if (kIsWeb || !RevenueCatConfig.isSupportedPlatform) {
      return const SizedBox.shrink();
    }
    if (!RevenueCatConfig.isConfigured) {
      if (kDebugMode) {
        return SectionCard(
          title: 'Apoiar o GlicoDose',
          icon: Icons.favorite_outline,
          iconColor: AppColors.accent,
          child: Text(
            'Defina REVENUECAT_IOS_API_KEY / REVENUECAT_ANDROID_API_KEY '
            'no .env para testar IAP. Veja docs/iap-store-setup.md.',
            style: TextStyle(fontSize: 13, color: colors.muted, height: 1.4),
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
          Text(
            'A calculadora de dose continua gratuita. O apoio libera:',
            style: TextStyle(fontSize: 13, color: colors.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          const _BenefitRow(
            icon: Icons.sensors,
            label: 'LibreLinkUp em tempo real',
          ),
          const _BenefitRow(
            icon: Icons.widgets_outlined,
            label: 'Widget da tela inicial',
          ),
          const _BenefitRow(
            icon: Icons.monitor_heart_outlined,
            label: 'Apple Health e Health Connect',
          ),
          const SizedBox(height: 10),
          Text(
            'Essas funções usam servidor. Renovação automática; '
            'cancele quando quiser na loja.',
            style: TextStyle(fontSize: 13, color: colors.muted, height: 1.4),
          ),
          if (_isSupporter) ...[
            SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outline),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: AppColors.primaryDark,
                  ),
                  SizedBox(width: 10),
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
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 14),
          if (_loading)
            Padding(
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
            Text(
              'Planos indisponíveis no momento. Confira a configuração '
              'nas lojas / RevenueCat ou tente mais tarde.',
              style: TextStyle(fontSize: 13, color: colors.muted),
            )
          else
            _PlanPicker(
              plans: _plans,
              activeProductId: _activeProductId,
              busy: _busy,
              onPurchase: _purchase,
            ),
          if (_error != null) ...[
            SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _restore,
                  child: const Text('Restaurar'),
                ),
              ),
              SizedBox(width: 8),
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

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanPicker extends StatelessWidget {
  const _PlanPicker({
    required this.plans,
    required this.activeProductId,
    required this.busy,
    required this.onPurchase,
  });

  final List<SupportPlanOption> plans;
  final String? activeProductId;
  final bool busy;
  final ValueChanged<SupportPlanOption> onPurchase;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    SupportPlanOption? recommended;
    SupportPlanOption? firstMonthly;
    for (final plan in plans) {
      if (plan.isRecommended) recommended = plan;
      if (!plan.isAnnual && firstMonthly == null) firstMonthly = plan;
    }
    recommended ??= firstMonthly;
    final annual = plans.where((plan) => plan.isAnnual);
    final others = plans.where(
      (plan) => plan != recommended && !plan.isAnnual,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recommended != null) ...[
          Text(
            'Mais escolhido',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 6),
          _PlanButton(
            plan: recommended,
            filled: true,
            selected: activeProductId == recommended.productId,
            busy: busy,
            onPurchase: onPurchase,
          ),
        ],
        for (final plan in annual) ...[
          const SizedBox(height: 8),
          _PlanButton(
            plan: plan,
            filled: false,
            selected: activeProductId == plan.productId,
            busy: busy,
            onPurchase: onPurchase,
            caption: 'Plano anual',
          ),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Outros valores',
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
          Wrap(
            spacing: 4,
            children: [
              for (final plan in others)
                TextButton(
                  onPressed: busy || activeProductId == plan.productId
                      ? null
                      : () => onPurchase(plan),
                  child: Text(_priceLabel(plan, activeProductId)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PlanButton extends StatelessWidget {
  const _PlanButton({
    required this.plan,
    required this.filled,
    required this.selected,
    required this.busy,
    required this.onPurchase,
    this.caption,
  });

  final SupportPlanOption plan;
  final bool filled;
  final bool selected;
  final bool busy;
  final ValueChanged<SupportPlanOption> onPurchase;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final label = _priceLabel(plan, selected ? plan.productId : null);
    final child = Column(
      children: [
        Text(label),
        if (caption != null)
          Text(
            caption!,
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
      ],
    );
    final onPressed = busy || selected ? null : () => onPurchase(plan);
    if (filled) {
      return FilledButton(onPressed: onPressed, child: child);
    }
    return OutlinedButton(onPressed: onPressed, child: child);
  }
}

String _priceLabel(SupportPlanOption plan, String? activeProductId) {
  final active = activeProductId == plan.productId;
  if (active) return '${plan.priceLabel} · ativo';
  final intro = plan.introLabel;
  if (intro != null) return '$intro, depois ${plan.priceLabel}';
  return plan.priceLabel;
}

import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/screens/pet_home_screen.dart';
import 'package:diabetes_app/services/pet_gamification.dart';
import 'package:diabetes_app/services/pet_progress_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/widgets/pet_mascot.dart';

/// Fuel bar and mascot on the dose tab. Hidden when the mode is off.
class PetFuelCard extends StatefulWidget {
  const PetFuelCard({super.key, required this.services});

  final AppServices services;

  @override
  State<PetFuelCard> createState() => _PetFuelCardState();
}

class _PetFuelCardState extends State<PetFuelCard> {
  PetSnapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.services.entriesRevision.addListener(_reload);
    widget.services.profileRevision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.services.entriesRevision.removeListener(_reload);
    widget.services.profileRevision.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final profile = await widget.services.profile.fetchCurrent(
        applyTheme: false,
      );
      if (!mounted) return;
      if (profile == null ||
          profile.gamificationMode == GamificationMode.off) {
        setState(() {
          _snapshot = null;
          _loading = false;
        });
        return;
      }
      final snapshot = await widget.services.pets.refresh(profile);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _snapshot == null) return const SizedBox.shrink();
    final snapshot = _snapshot!;
    final colors = AppColors.of(context);
    final computation = snapshot.computation;
    final playful = snapshot.mode == GamificationMode.pet;
    final hours = computation.hoursInRangeToday;
    final hourLabel = hours < 10
        ? hours.toStringAsFixed(1)
        : hours.round().toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.cardBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => PetHomeScreen(services: widget.services),
              ),
            );
            if (mounted) await _reload();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
            child: Row(
              children: [
                PetMascot(
                  mood: computation.mood,
                  accessoryId: computation.equippedAccessoryId,
                  size: 72,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playful ? 'Combustível de hoje' : 'Hoje no alvo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0,
                            end: (computation.dropsToday /
                                    PetComputation.barDrops)
                                .clamp(0, 1)
                                .toDouble(),
                          ),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) {
                            return LinearProgressIndicator(
                              value: value,
                              minHeight: 10,
                              backgroundColor: colors.primarySoft,
                              color: AppColors.primary,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        playful
                            ? '${computation.dropsToday} gotas · $hourLabel h no alvo'
                            : '$hourLabel h no alvo',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: colors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.hint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

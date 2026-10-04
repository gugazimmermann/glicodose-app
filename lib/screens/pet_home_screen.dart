import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/pet_gamification.dart';
import 'package:diabetes_app/services/pet_progress_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/pet_mascot.dart';
import 'package:diabetes_app/widgets/section_card.dart';

class PetHomeScreen extends StatefulWidget {
  const PetHomeScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<PetHomeScreen> createState() => _PetHomeScreenState();
}

class _PetHomeScreenState extends State<PetHomeScreen> {
  Profile? _profile;
  PetSnapshot? _snapshot;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.services.profile.fetchCurrent(
        applyTheme: false,
      );
      if (profile == null ||
          profile.gamificationMode == GamificationMode.off) {
        if (!mounted) return;
        setState(() {
          _profile = profile;
          _loading = false;
        });
        return;
      }
      final snapshot = await widget.services.pets.refresh(profile);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(error);
        _loading = false;
      });
    }
  }

  Future<void> _equip(String? id) async {
    final profile = _profile;
    if (profile == null) return;
    try {
      await widget.services.pets.equip(profile, id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = userFacingError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final profile = _profile;
    final snapshot = _snapshot;
    final mode = profile?.gamificationMode ?? GamificationMode.off;
    final playful = mode == GamificationMode.pet;
    return Scaffold(
      appBar: AppBar(
        title: Text(playful ? 'Casa do pet' : 'Conquistas'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                if (snapshot != null) ...[
                  _Hero(snapshot: snapshot, playful: playful),
                  const SizedBox(height: 16),
                  _NextGoalCard(
                    goal: PetGamification.nextGoal(snapshot.computation, mode),
                    playful: playful,
                  ),
                  const SizedBox(height: 16),
                  _Accessories(
                    computation: snapshot.computation,
                    playful: playful,
                    onEquip: _equip,
                  ),
                  const SizedBox(height: 16),
                  _Achievements(
                    mode: mode,
                    computation: snapshot.computation,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                if (snapshot != null && !snapshot.synced) ...[
                  const SizedBox(height: 12),
                  Text(
                    'O pet aparece aqui, mas ainda não sincronizou com os outros aparelhos.',
                    style: TextStyle(fontSize: 12, color: colors.muted),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.snapshot, required this.playful});

  final PetSnapshot snapshot;
  final bool playful;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final computation = snapshot.computation;
    final hours = computation.hoursInRangeToday;
    final hourLabel =
        hours < 10 ? hours.toStringAsFixed(1) : hours.round().toString();
    final streak = computation.streakPaused
        ? playful
            ? 'Pausa — a sequência de ${computation.careStreakDays} dias segue guardada'
            : 'Sequência em pausa: ${computation.careStreakDays} dias'
        : playful
            ? '${computation.careStreakDays} dias cuidando'
            : 'Dias de cuidado: ${computation.careStreakDays}';
    final next = PetGamification.nextAccessory(computation.lifetimeDrops);
    final lifetimeLine = next == null
        ? (playful
            ? '${computation.lifetimeDrops} gotas na vida · guarda-roupa completo'
            : '${computation.lifetimeDrops} gotas · acessórios liberados')
        : (playful
            ? '${computation.lifetimeDrops} gotas na vida · faltam ${next.dropsRequired - computation.lifetimeDrops} pro ${next.name}'
            : '${computation.lifetimeDrops} gotas · faltam ${next.dropsRequired - computation.lifetimeDrops} para ${next.quietName}');
    return SectionCard(
      title: playful ? 'Seu pet' : 'Hoje',
      icon: Icons.pets,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: PetMascot(
                mood: computation.mood,
                accessoryId: computation.equippedAccessoryId,
                size: 160,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            playful ? computation.playfulLine : computation.quietLine,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.35, color: colors.ink),
          ),
          if (computation.suggestion != null) ...[
            const SizedBox(height: 6),
            Text(
              computation.suggestion!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colors.muted),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            playful
                ? '1 gota ≈ 1 h na faixa · barra cheia em 12'
                : '1 ponto ≈ 1 h na faixa · meta do dia: 12',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.3, color: colors.muted),
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(
              begin: 0,
              end: (computation.dropsToday / PetComputation.barDrops)
                  .clamp(0, 1)
                  .toDouble(),
            ),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 12,
                  backgroundColor: colors.primarySoft,
                  color: AppColors.primary,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            playful
                ? '${computation.dropsToday} gotas hoje · $hourLabel h no alvo'
                : '$hourLabel h no alvo hoje',
            style: TextStyle(fontWeight: FontWeight.w700, color: colors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            lifetimeLine,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
          const SizedBox(height: 4),
          Text(streak, style: TextStyle(fontSize: 12, color: colors.muted)),
        ],
      ),
    );
  }
}

class _NextGoalCard extends StatelessWidget {
  const _NextGoalCard({required this.goal, required this.playful});

  final PetNextGoal? goal;
  final bool playful;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final title = goal?.title ??
        (playful ? 'Tudo em dia por aqui' : 'Sem meta pendente');
    final hint = goal?.hint ??
        (playful
            ? 'O pet está feliz com o que você já conquistou.'
            : 'Nenhuma meta em andamento no momento.');
    return SectionCard(
      title: playful ? 'Próxima meta' : 'Próximo passo',
      icon: Icons.flag_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(fontSize: 13, height: 1.35, color: colors.muted),
          ),
          if (goal?.progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: goal!.progress!.clamp(0, 1),
                minHeight: 10,
                backgroundColor: colors.primarySoft,
                color: AppColors.primary,
              ),
            ),
            if (goal?.progressLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                goal!.progressLabel!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Accessories extends StatelessWidget {
  const _Accessories({
    required this.computation,
    required this.playful,
    required this.onEquip,
  });

  final PetComputation computation;
  final bool playful;
  final ValueChanged<String?> onEquip;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SectionCard(
      title: playful ? 'Guarda-roupa' : 'Acessórios',
      icon: Icons.checkroom_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in PetGamification.accessories)
            if (computation.lifetimeDrops >= item.dropsRequired)
              ChoiceChip(
                label: Text(playful ? item.name : item.quietName),
                selected: computation.equippedAccessoryId == item.id,
                onSelected: (_) => onEquip(item.id),
              )
            else
              Chip(
                label: Text(
                  playful
                      ? '${item.name} · faltam ${item.dropsRequired - computation.lifetimeDrops} gotas'
                      : '${item.quietName} · faltam ${item.dropsRequired - computation.lifetimeDrops}',
                ),
                backgroundColor: colors.surface,
              ),
        ],
      ),
    );
  }
}

class _Achievements extends StatelessWidget {
  const _Achievements({required this.mode, required this.computation});

  final GamificationMode mode;
  final PetComputation computation;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final playful = mode == GamificationMode.pet;
    final owned = computation.unlocked.map((item) => item.id).toSet();
    final newly = computation.newlyUnlocked;
    final categories = PetAchievementCategory.values;
    return SectionCard(
      title: 'Conquistas',
      icon: Icons.emoji_events_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (newly.isNotEmpty) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Text(
                  newly.length == 1
                      ? (playful
                          ? 'Nova conquista: ${newly.first.titleFor(mode)}'
                          : 'Nova: ${newly.first.titleFor(mode)}')
                      : (playful
                          ? '${newly.length} conquistas novas desbloqueadas'
                          : '${newly.length} novas conquistas'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final category in categories) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                PetGamification.categoryLabel(category, playful),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: colors.muted,
                ),
              ),
            ),
            for (final item in _sortedForCategory(category, owned))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  owned.contains(item.id)
                      ? Icons.verified
                      : Icons.radio_button_unchecked,
                  color: owned.contains(item.id)
                      ? AppColors.success
                      : colors.hint,
                ),
                title: Text(item.titleFor(mode)),
                subtitle: Text(item.hint),
              ),
          ],
        ],
      ),
    );
  }

  List<PetAchievement> _sortedForCategory(
    PetAchievementCategory category,
    Set<String> owned,
  ) {
    final items = [
      for (final item in PetGamification.achievements)
        if (item.category == category) item,
    ];
    items.sort((a, b) {
      final aOwned = owned.contains(a.id);
      final bOwned = owned.contains(b.id);
      if (aOwned == bOwned) return 0;
      return aOwned ? -1 : 1;
    });
    return items;
  }
}

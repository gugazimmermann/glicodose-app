import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  List<FamilyPet> _family = const [];
  int _followers = 0;
  bool _loading = true;
  String? _error;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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
      List<FamilyPet> family = const [];
      var followers = 0;
      try {
        family = await widget.services.pets.listFamily();
        followers = await widget.services.pets.followerCount();
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = userFacingError(error));
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _snapshot = snapshot;
        _family = family;
        _followers = followers;
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

  Future<void> _follow() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'O código tem 6 caracteres.');
      return;
    }
    try {
      await widget.services.pets.follow(code);
      _codeController.clear();
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = userFacingError(error));
    }
  }

  Future<void> _unfollow(FamilyPet pet) async {
    try {
      await widget.services.pets.unfollow(pet.ownerId);
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
    final playful = profile?.gamificationMode == GamificationMode.pet;
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
                  _Accessories(
                    computation: snapshot.computation,
                    playful: playful,
                    onEquip: _equip,
                  ),
                  const SizedBox(height: 16),
                  _Achievements(
                    mode: profile!.gamificationMode,
                    unlocked: snapshot.computation.unlocked,
                  ),
                  const SizedBox(height: 16),
                ],
                _FamilySection(
                  shareCode: profile?.shareCode,
                  followers: _followers,
                  family: _family,
                  playful: playful,
                  codeController: _codeController,
                  onFollow: _follow,
                  onUnfollow: _unfollow,
                ),
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
        ? 'Sequência em pausa: ${computation.careStreakDays} dias'
        : 'Dias de cuidado: ${computation.careStreakDays}';
    return SectionCard(
      title: playful ? 'Seu pet' : 'Hoje',
      icon: Icons.pets,
      child: Column(
        children: [
          PetMascot(
            mood: computation.mood,
            accessoryId: computation.equippedAccessoryId,
            size: 160,
          ),
          const SizedBox(height: 8),
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
          Text(streak, style: TextStyle(fontSize: 12, color: colors.muted)),
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
                      ? '${item.name} · ${item.dropsRequired} gotas'
                      : '${item.quietName} · ${item.dropsRequired}',
                ),
                backgroundColor: colors.surface,
              ),
        ],
      ),
    );
  }
}

class _Achievements extends StatelessWidget {
  const _Achievements({required this.mode, required this.unlocked});

  final GamificationMode mode;
  final List<PetAchievement> unlocked;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final owned = unlocked.map((item) => item.id).toSet();
    return SectionCard(
      title: 'Conquistas',
      icon: Icons.emoji_events_outlined,
      child: Column(
        children: [
          for (final item in PetGamification.achievements)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                owned.contains(item.id)
                    ? Icons.verified
                    : Icons.radio_button_unchecked,
                color: owned.contains(item.id)
                    ? AppColors.success
                    : colors.hint,
              ),
              title: Text(item.titleFor(mode)),
              subtitle: Text(item.detail),
            ),
        ],
      ),
    );
  }
}

class _FamilySection extends StatelessWidget {
  const _FamilySection({
    required this.shareCode,
    required this.followers,
    required this.family,
    required this.playful,
    required this.codeController,
    required this.onFollow,
    required this.onUnfollow,
  });

  final String? shareCode;
  final int followers;
  final List<FamilyPet> family;
  final bool playful;
  final TextEditingController codeController;
  final VoidCallback onFollow;
  final ValueChanged<FamilyPet> onUnfollow;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SectionCard(
      title: playful ? 'Família' : 'Quem acompanha',
      icon: Icons.group_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Quem tiver o código vê o pet, as gotas e as conquistas. Não vê glicose nem doses.',
            style: TextStyle(fontSize: 13, height: 1.35, color: colors.muted),
          ),
          if (shareCode != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  shareCode!,
                  style: TextStyle(
                    fontSize: 20,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar código',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: shareCode!));
                  },
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ],
            ),
            Text(
              followers == 1
                  ? '1 pessoa acompanha o pet.'
                  : '$followers pessoas acompanham o pet.',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Código de outro pet',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onFollow,
            child: const Text('Acompanhar'),
          ),
          for (final pet in family) ...[
            const SizedBox(height: 12),
            _FamilyPetTile(
              pet: pet,
              playful: playful,
              onUnfollow: () => onUnfollow(pet),
            ),
          ],
        ],
      ),
    );
  }
}

class _FamilyPetTile extends StatelessWidget {
  const _FamilyPetTile({
    required this.pet,
    required this.playful,
    required this.onUnfollow,
  });

  final FamilyPet pet;
  final bool playful;
  final VoidCallback onUnfollow;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final name = (pet.displayName ?? '').trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PetMascot(
          mood: pet.mood,
          accessoryId: pet.equippedAccessoryId,
          size: 64,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Pet da família' : name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                playful ? pet.playfulLine : pet.quietLine,
                style: TextStyle(fontSize: 13, color: colors.ink, height: 1.3),
              ),
              Text(
                playful
                    ? '${pet.dropsToday} gotas hoje'
                    : '${pet.hoursInRangeToday.toStringAsFixed(1)} h no alvo hoje',
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Deixar de acompanhar',
          onPressed: onUnfollow,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

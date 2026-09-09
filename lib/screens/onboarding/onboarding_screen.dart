import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_background.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/language_picker.dart';
import '../../l10n/l10n_state.dart';
import '../../l10n/languages.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  late final TextEditingController _nameController;
  int _page = 0;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<SettingsService>().displayName,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_page < 2) {
      FocusScope.of(context).unfocus();
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() => _nameError = context.read<L10nState>().t('nameRequired'));
      return;
    }
    await context.read<AuthService>().completeOnboarding(displayName: name);
  }

  Future<void> _chooseLanguage() async {
    final l10n = context.read<L10nState>();
    final code = await showLanguagePicker(context, selectedCode: l10n.code);
    if (code == null || !mounted) return;
    l10n.setLanguage(code);
    await context.read<SettingsService>().setLanguageCode(code);
  }

  void _back() {
    if (_page == 0) return;
    FocusScope.of(context).unfocus();
    _pageController.previousPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10nState>();
    final auth = context.watch<AuthService>();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
                child: Row(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _page == 0
                          ? const BrandMark(
                              key: ValueKey('brand'),
                              size: 38,
                              showWordmark: true,
                            )
                          : IconButton.filledTonal(
                              key: const ValueKey('back'),
                              tooltip: l10n.t('back'),
                              onPressed: _back,
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                    ),
                    const Spacer(),
                    Text(
                      '${_page + 1} / 3',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (value) => setState(() => _page = value),
                  children: [
                    _WelcomePage(l10n: l10n),
                    _LanguagePage(l10n: l10n, onChoose: _chooseLanguage),
                    _ProfilePage(
                      l10n: l10n,
                      controller: _nameController,
                      errorText: _nameError,
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        }
                      },
                    ),
                  ],
                ),
              ),
              AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.fromLTRB(
                  22,
                  10,
                  22,
                  math.max(18.0, MediaQuery.viewInsetsOf(context).bottom + 12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        3,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: index == _page ? 24 : 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: index == _page
                                ? AppColors.primary
                                : AppColors.divider,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: auth.isBusy ? null : _continue,
                        child: auth.isBusy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _page == 2
                                        ? l10n.t('joinCommunity')
                                        : l10n.t('continue'),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 20,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.l10n});

  final L10nState l10n;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _WorldOrb()),
          const SizedBox(height: 34),
          Text(
            l10n.t('welcomeEyebrow'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.cyan,
              letterSpacing: 1.7,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.t('welcomeTitle'),
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.t('welcomeBody'),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FeaturePill(
                icon: Icons.translate_rounded,
                label: l10n.t('featureTranslate'),
              ),
              _FeaturePill(
                icon: Icons.people_alt_rounded,
                label: l10n.t('featurePeople'),
              ),
              _FeaturePill(
                icon: Icons.verified_user_rounded,
                label: l10n.t('featureSafe'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorldOrb extends StatefulWidget {
  const _WorldOrb();

  @override
  State<_WorldOrb> createState() => _WorldOrbState();
}

class _WorldOrbState extends State<_WorldOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      height: 230,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 206,
            height: 206,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.26),
                  blurRadius: 70,
                  spreadRadius: 10,
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.rotate(
              angle: _controller.value * math.pi * 2,
              child: child,
            ),
            child: Container(
              width: 218,
              height: 218,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: -5),
                  decoration: const BoxDecoration(
                    color: AppColors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          const BrandMark(size: 168),
          const Positioned(
            top: 24,
            right: 20,
            child: _FloatingFlag(label: 'あ', color: AppColors.coral),
          ),
          const Positioned(
            bottom: 24,
            left: 8,
            child: _FloatingFlag(label: 'سلام', color: AppColors.cyan),
          ),
          const Positioned(
            bottom: 4,
            right: 20,
            child: _FloatingFlag(label: 'Hola', color: AppColors.amber),
          ),
        ],
      ),
    );
  }
}

class _FloatingFlag extends StatelessWidget {
  const _FloatingFlag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primaryBright, size: 16),
          const SizedBox(width: 7),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _LanguagePage extends StatelessWidget {
  const _LanguagePage({required this.l10n, required this.onChoose});

  final L10nState l10n;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final selected = languageByCode(l10n.code);
    const quickCodes = ['tg', 'ru', 'uz', 'en', 'fa', 'ar'];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.language_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            l10n.t('languageTitle'),
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 14),
          Text(
            l10n.t('languageBody'),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 30),
          Card(
            child: InkWell(
              onTap: onChoose,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        selected.code.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primaryBright,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected.nativeName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            selected.name,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.unfold_more_rounded,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: quickCodes
                .map((code) {
                  final language = languageByCode(code);
                  final selected = code == l10n.code;
                  return ChoiceChip(
                    label: Text(language.nativeName),
                    selected: selected,
                    onSelected: (_) async {
                      l10n.setLanguage(code);
                      await context.read<SettingsService>().setLanguageCode(
                        code,
                      );
                    },
                    selectedColor: AppColors.primary.withValues(alpha: 0.24),
                    backgroundColor: AppColors.surface,
                    side: BorderSide(
                      color: selected ? AppColors.primary : AppColors.divider,
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? AppColors.primaryBright
                          : AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.l10n,
    required this.controller,
    required this.errorText,
    required this.onChanged,
  });

  final L10nState l10n;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
            ),
            child: const Icon(
              Icons.waving_hand_rounded,
              color: AppColors.cyan,
              size: 30,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            l10n.t('profileTitle'),
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 14),
          Text(
            l10n.t('profileBody'),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 30),
          Text(
            l10n.t('yourName'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            autofocus: false,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            maxLength: 32,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: l10n.t('nameHint'),
              errorText: errorText,
              prefixIcon: const Icon(Icons.person_outline_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.shield_outlined,
                color: AppColors.success,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.t('termsNote'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

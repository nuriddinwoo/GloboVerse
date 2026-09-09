import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/language_picker.dart';
import '../../l10n/l10n_state.dart';
import '../../l10n/languages.dart';
import '../../services/auth_service.dart';
import '../../services/billing_service.dart';
import '../../services/online_service.dart';
import '../../services/session_service.dart';
import '../../services/settings_service.dart';
import 'billing_sheet.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _changeLanguage(BuildContext context) async {
    final l10n = context.read<L10nState>();
    final code = await showLanguagePicker(context, selectedCode: l10n.code);
    if (code == null || !context.mounted) return;
    l10n.setLanguage(code);
    await context.read<SettingsService>().setLanguageCode(code);
  }

  Future<void> _editName(BuildContext context) async {
    final settings = context.read<SettingsService>();
    final controller = TextEditingController(text: settings.displayName);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.read<L10nState>().t('yourName')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: context.read<L10nState>().t('nameHint'),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.read<L10nState>().t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 2) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: Text(context.read<L10nState>().t('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && context.mounted) await settings.setDisplayName(value);
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final l10n = context.read<L10nState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout_rounded, color: AppColors.coral),
        title: Text(l10n.t('signOutTitle')),
        content: Text(l10n.t('signOutBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: Text(l10n.t('signOut')),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<SessionService>().pause();
      await context.read<AuthService>().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10nState>();
    final settings = context.watch<SettingsService>();
    final session = context.watch<SessionService>();
    final billing = context.watch<BillingService>();
    final online = context.watch<OnlineService>();
    final isOnline = online.isInitialized && online.isConnected;
    final language = languageByCode(l10n.code);
    final name = settings.displayName.isEmpty
        ? l10n.t('guest')
        : settings.displayName;

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 116),
            children: [
              Text(
                l10n.t('profile'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 22),
              _ProfileHeader(
                name: name,
                isConnectionKnown: online.isInitialized,
                isOnline: isOnline,
                editTooltip: l10n.t('editProfile'),
                onlineLabel: l10n.t(
                  !online.isInitialized
                      ? 'presenceUnavailable'
                      : isOnline
                      ? 'online'
                      : 'offline',
                ),
                onEdit: () => _editName(context),
              ),
              const SizedBox(height: 18),
              _PlanCard(
                session: session,
                onTap: () => showBillingSheet(context),
              ),
              const SizedBox(height: 28),
              _SectionLabel(label: l10n.t('preferences')),
              const SizedBox(height: 10),
              _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.language_rounded,
                    color: AppColors.cyan,
                    title: l10n.t('appLanguage'),
                    subtitle: language.label,
                    onTap: () => _changeLanguage(context),
                  ),
                  const Divider(height: 1, indent: 66),
                  SwitchListTile(
                    value: settings.notificationsEnabled,
                    onChanged: settings.setNotificationsEnabled,
                    secondary: const _TileIcon(
                      icon: Icons.notifications_none_rounded,
                      color: AppColors.amber,
                    ),
                    title: Text(l10n.t('notifications')),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionLabel(label: l10n.t('account')),
              const SizedBox(height: 10),
              _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.workspace_premium_outlined,
                    color: AppColors.primaryBright,
                    title: l10n.t('plan'),
                    subtitle: session.isVip
                        ? l10n.t('vipPlan')
                        : l10n.t('freePlan'),
                    onTap: () => showBillingSheet(context),
                  ),
                  const Divider(height: 1, indent: 66),
                  _SettingsTile(
                    icon: Icons.restore_rounded,
                    color: AppColors.success,
                    title: billing.status == BillingStatus.loading
                        ? l10n.t('restoring')
                        : l10n.t('restorePurchases'),
                    onTap: billing.isBusy ? null : billing.restorePurchases,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.coral,
                  side: BorderSide(
                    color: AppColors.coral.withValues(alpha: 0.32),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: Text(l10n.t('signOut')),
              ),
              const SizedBox(height: 22),
              Text(
                'GloboVerse · 1.0.0',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.isConnectionKnown,
    required this.isOnline,
    required this.editTooltip,
    required this.onlineLabel,
    required this.onEdit,
  });

  final String name;
  final bool isConnectionKnown;
  final bool isOnline;
  final String editTooltip;
  final String onlineLabel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 66,
              height: 66,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.24),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Text(
                initialsFor(name),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: !isConnectionKnown
                              ? AppColors.textMuted
                              : isOnline
                              ? AppColors.success
                              : AppColors.coral,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          onlineLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: editTooltip,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.session, required this.onTap});

  final SessionService session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    return Material(
      color: AppColors.primary.withValues(alpha: 0.11),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(23),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(23),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 47,
                height: 47,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  session.isVip
                      ? Icons.workspace_premium_rounded
                      : Icons.timer_rounded,
                  color: session.isVip
                      ? AppColors.amber
                      : AppColors.primaryBright,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.isVip ? l10n.t('vipPlan') : l10n.t('freePlan'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      session.isVip
                          ? l10n.t('vipUnlimited')
                          : '${formatDuration(session.remaining)} · ${l10n.t('minutesLeft')}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textMuted,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 5),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: _TileIcon(icon: icon, color: color),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
      trailing: onTap == null
          ? null
          : const Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppColors.textMuted,
              size: 15,
            ),
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}

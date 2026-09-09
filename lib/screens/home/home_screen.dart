import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/status_notice.dart';
import '../../l10n/l10n_state.dart';
import '../../l10n/languages.dart';
import '../../services/online_service.dart';
import '../../services/session_service.dart';
import '../../services/settings_service.dart';
import '../profile/billing_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onConnect,
    required this.onTranslate,
  });

  final VoidCallback onConnect;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10nState>();
    final settings = context.watch<SettingsService>();
    final online = context.watch<OnlineService>();
    final session = context.watch<SessionService>();
    final displayName = settings.displayName.isEmpty
        ? l10n.t('guest')
        : settings.displayName;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.primaryBright,
        backgroundColor: AppColors.surfaceHigh,
        onRefresh: online.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 110),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Header(
                          name: displayName,
                          isOnline: online.isConnected,
                          onlineCount: online.onlineCount,
                          isPreviewCatalog: online.isPreviewCatalog,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          l10n.t('hello', {'name': displayName}),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          l10n.t('worldWaiting'),
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 18),
                        if (online.hasRemoteDiscovery &&
                            (!online.isInitialized || online.isRefreshing)) ...[
                          Semantics(
                            label: l10n.t('refreshingDiscovery'),
                            child: const LinearProgressIndicator(minHeight: 3),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (online.isPreviewCatalog) ...[
                          StatusNotice(
                            title: l10n.t('discoveryPreviewTitle'),
                            message: l10n.t('discoveryPreviewBody'),
                            icon: Icons.science_outlined,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (!online.isConnected) ...[
                          StatusNotice(
                            title: l10n.t('offline').toUpperCase(),
                            message: l10n.t('discoveryOfflineBody'),
                            icon: Icons.wifi_off_rounded,
                            color: AppColors.coral,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (online.isConnected &&
                            online.discoveryError != null) ...[
                          StatusNotice(
                            title: l10n.t('discoveryRefreshFailedTitle'),
                            message: l10n.t('discoveryRefreshFailedBody'),
                            icon: Icons.cloud_off_rounded,
                            color: AppColors.coral,
                          ),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 10),
                        _SessionCard(
                          session: session,
                          onAddTime: () => showBillingSheet(context),
                          onConnect: onConnect,
                        ),
                        const SizedBox(height: 30),
                        SectionHeader(
                          title: l10n.t('trendingRooms'),
                          action: TextButton(
                            onPressed: onConnect,
                            child: Text(l10n.t('seeAll')),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (online.rooms.isEmpty)
                          StatusNotice(
                            title: l10n.t('trendingRooms'),
                            message: l10n.t('noLiveRooms'),
                            icon: Icons.forum_outlined,
                            color: AppColors.textMuted,
                          )
                        else
                          SizedBox(
                            height: 184,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: online.rooms.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) => _RoomCard(
                                room: online.rooms[index],
                                isPreview: online.isPreviewCatalog,
                                isConnected: online.isConnected,
                                onTap: onConnect,
                              ),
                            ),
                          ),
                        const SizedBox(height: 30),
                        SectionHeader(
                          title: l10n.t('peopleAroundWorld'),
                          subtitle: online.isPreviewCatalog
                              ? l10n.t('sampleProfiles', {
                                  'count': online.members.length,
                                })
                              : !online.isConnected
                              ? l10n.t('presenceUnavailable')
                              : '${online.onlineCount} ${l10n.t('onlineNow')}',
                        ),
                        const SizedBox(height: 16),
                        if (online.members.isEmpty)
                          StatusNotice(
                            title: l10n.t('peopleAroundWorld'),
                            message: l10n.t('noLiveMembers'),
                            icon: Icons.person_search_rounded,
                            color: AppColors.textMuted,
                          )
                        else
                          _MembersStrip(
                            members: online.members,
                            showPresence:
                                !online.isPreviewCatalog && online.isConnected,
                          ),
                        const SizedBox(height: 28),
                        _TranslateBanner(onTap: onTranslate),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.isOnline,
    required this.onlineCount,
    required this.isPreviewCatalog,
  });

  final String name;
  final bool isOnline;
  final int onlineCount;
  final bool isPreviewCatalog;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    return Row(
      children: [
        const BrandMark(size: 39, showWordmark: true),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: (isOnline ? AppColors.success : AppColors.coral).withValues(
              alpha: 0.1,
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: (isOnline ? AppColors.success : AppColors.coral)
                  .withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isOnline ? AppColors.success : AppColors.coral,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                isPreviewCatalog
                    ? l10n.t('previewCatalogShort')
                    : isOnline
                    ? _compactCount(onlineCount)
                    : '—',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.primary.withValues(alpha: 0.2),
          child: Text(
            initialsFor(name),
            style: const TextStyle(
              color: AppColors.primaryBright,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  static String _compactCount(int value) {
    return value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : '$value';
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onAddTime,
    required this.onConnect,
  });

  final SessionService session;
  final VoidCallback onAddTime;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF262052), Color(0xFF161E42)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.34)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  session.isVip
                      ? Icons.workspace_premium_rounded
                      : Icons.timer_outlined,
                  color: session.isVip ? AppColors.amber : AppColors.cyan,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('yourTime'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.isVip
                          ? l10n.t('vipUnlimited')
                          : formatDuration(session.remaining),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: session.isVip
                                ? AppColors.amber
                                : AppColors.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ),
              ),
              if (!session.isVip)
                TextButton.icon(
                  onPressed: onAddTime,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: Text(l10n.t('addTime')),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (!session.isVip) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (session.remaining.inSeconds / 3600).clamp(0.02, 1),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('minutesLeft'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 17),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: session.canStart ? onConnect : onAddTime,
              icon: const Icon(Icons.travel_explore_rounded),
              label: Text(l10n.t('startConnecting')),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.isPreview,
    required this.isConnected,
    required this.onTap,
  });

  final CommunityRoom room;
  final bool isPreview;
  final bool isConnected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    final accent = Color(room.accentColor);
    return SizedBox(
      width: 238,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(23),
          side: const BorderSide(color: AppColors.divider),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(23),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        room.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    const Spacer(),
                    for (final code in room.languageCodes.take(3))
                      Container(
                        width: 25,
                        height: 25,
                        margin: const EdgeInsets.only(left: 3),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Text(
                          code.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  room.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 10),
                Text(
                  isPreview
                      ? l10n.t('previewCatalogShort')
                      : !isConnected
                      ? l10n.t('presenceUnavailable')
                      : l10n.t('members', {'count': room.memberCount}),
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MembersStrip extends StatelessWidget {
  const _MembersStrip({required this.members, required this.showPresence});

  final List<WorldMember> members;
  final bool showPresence;

  static const _colors = [
    AppColors.primary,
    AppColors.coral,
    AppColors.cyan,
    AppColors.amber,
    AppColors.success,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: members.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final member = members[index];
          final color = _colors[member.avatarSeed % _colors.length];
          return SizedBox(
            width: 66,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: color.withValues(alpha: 0.18),
                      child: Text(
                        initialsFor(member.name),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (showPresence)
                      Positioned(
                        right: 0,
                        bottom: 1,
                        child: Tooltip(
                          message: l10n.t(
                            member.isOnline ? 'online' : 'offline',
                          ),
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: member.isOnline
                                  ? AppColors.success
                                  : AppColors.textMuted,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.background,
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TranslateBanner extends StatelessWidget {
  const _TranslateBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    return Material(
      color: AppColors.cyan.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.22)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              const Icon(
                Icons.translate_rounded,
                color: AppColors.cyan,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('translationTitle'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.t('translationBody'),
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.cyan),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/status_notice.dart';
import '../../l10n/l10n_state.dart';
import '../../l10n/languages.dart';
import '../../services/conversation_service.dart';
import '../../services/online_service.dart';
import '../../services/session_service.dart';
import '../profile/billing_sheet.dart';
import 'live_session_sheet.dart';

class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key});

  Future<void> _startSession(
    BuildContext context, {
    CommunityRoom? room,
    WorldMember? member,
  }) async {
    final l10n = context.read<L10nState>();
    final online = context.read<OnlineService>();
    final session = context.read<SessionService>();
    final conversation = context.read<ConversationService>();

    // Preview entries are presentation-only. A configured chat backend may
    // receive a generic match request, but never a built-in room/member ID.
    if (online.isPreviewCatalog) {
      room = null;
      member = null;
    }

    if (conversation.isStarting || conversation.isActive) return;
    if (!online.isConnected && !conversation.isPreviewMode) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.t('offline'))));
      return;
    }
    if (!session.start()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.t('notEnoughTime'))));
      await showBillingSheet(context);
      return;
    }

    final sourceLanguage = l10n.code;
    final targetLanguage =
        member?.languageCode ??
        room?.languageCodes.firstWhere(
          (code) => code != sourceLanguage,
          orElse: () => sourceLanguage == 'en' ? 'tg' : 'en',
        ) ??
        (sourceLanguage == 'en' ? 'tg' : 'en');
    final progress = OverlayEntry(
      builder: (_) => _ConnectingOverlay(label: l10n.t('connectingNow')),
    );
    Overlay.of(context, rootOverlay: true).insert(progress);
    late final bool started;
    try {
      started = await conversation.start(
        room: room,
        member: member,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        fallbackPeerName: l10n.t('sessionActive'),
      );
    } finally {
      progress.remove();
    }
    if (!context.mounted) {
      await conversation.end();
      session.pause();
      return;
    }
    if (!started) {
      session.pause();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.t('connectionFailed'))));
      return;
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        useSafeArea: true,
        builder: (_) => const FractionallySizedBox(
          heightFactor: 0.94,
          child: LiveSessionSheet(),
        ),
      );
    } finally {
      await conversation.end();
      session.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10nState>();
    final online = context.watch<OnlineService>();

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: RefreshIndicator(
            color: AppColors.primaryBright,
            backgroundColor: AppColors.surfaceHigh,
            onRefresh: online.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 112),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.t('discoverTitle'),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  l10n.t('discoverBody'),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _OnlineBadge(online: online),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (online.hasRemoteDiscovery &&
                          (!online.isInitialized ||
                              online.showsRefreshProgress)) ...[
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
                      const SizedBox(height: 6),
                      _RandomConnectCard(
                        onlineCount: online.onlineCount,
                        sampleCount: online.members.length,
                        isPreview: online.isPreviewCatalog,
                        isConnected: online.isConnected,
                        onTap: () => _startSession(context),
                      ),
                      const SizedBox(height: 30),
                      Text(
                        l10n.t('trendingRooms'),
                        style: Theme.of(context).textTheme.titleLarge,
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
                        for (final room in online.rooms) ...[
                          _RoomListCard(
                            room: room,
                            isPreview: online.isPreviewCatalog,
                            isConnected: online.isConnected,
                            onTap: online.isConnected || online.isPreviewCatalog
                                ? () => _startSession(context, room: room)
                                : null,
                          ),
                          const SizedBox(height: 11),
                        ],
                      const SizedBox(height: 20),
                      Text(
                        l10n.t('peopleAroundWorld'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 14),
                      if (online.members.isEmpty)
                        StatusNotice(
                          title: l10n.t('peopleAroundWorld'),
                          message: l10n.t('noLiveMembers'),
                          icon: Icons.person_search_rounded,
                          color: AppColors.textMuted,
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 240,
                                mainAxisExtent: 176,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: online.members.length,
                          itemBuilder: (context, index) {
                            final member = online.members[index];
                            return _MemberCard(
                              member: member,
                              isPreview: online.isPreviewCatalog,
                              isConnected: online.isConnected,
                              onTap:
                                  online.isPreviewCatalog ||
                                      (online.isConnected && member.isOnline)
                                  ? () => _startSession(context, member: member)
                                  : null,
                            );
                          },
                        ),
                    ],
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

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge({required this.online});

  final OnlineService online;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    final color = online.isConnected ? AppColors.success : AppColors.coral;
    return Tooltip(
      message: online.isConnected ? l10n.t('online') : l10n.t('offline'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(
              online.isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: color,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              online.isPreviewCatalog
                  ? l10n.t('previewCatalogShort')
                  : online.isConnected
                  ? '${online.onlineCount}'
                  : l10n.t('offline'),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RandomConnectCard extends StatelessWidget {
  const _RandomConnectCard({
    required this.onlineCount,
    required this.sampleCount,
    required this.isPreview,
    required this.isConnected,
    required this.onTap,
  });

  final int onlineCount;
  final int sampleCount;
  final bool isPreview;
  final bool isConnected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.24),
            blurRadius: 32,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -32,
            top: -46,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 20,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isPreview
                      ? l10n.t('sampleProfiles', {'count': sampleCount})
                      : !isConnected
                      ? l10n.t('offline')
                      : '$onlineCount ${l10n.t('onlineNow')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                l10n.t('worldWaiting'),
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 7),
              Text(
                l10n.t('sessionBody'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF4436B7),
                ),
                icon: const Icon(Icons.shuffle_rounded),
                label: Text(l10n.t('startConnecting')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoomListCard extends StatelessWidget {
  const _RoomListCard({
    required this.room,
    required this.isPreview,
    required this.isConnected,
    required this.onTap,
  });

  final CommunityRoom room;
  final bool isPreview;
  final bool isConnected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    final accent = Color(room.accentColor);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(room.emoji, style: const TextStyle(fontSize: 25)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      room.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(
                          isPreview
                              ? Icons.science_outlined
                              : !isConnected
                              ? Icons.cloud_off_outlined
                              : Icons.people_alt_rounded,
                          color: accent,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isPreview
                              ? l10n.t('previewCatalogShort')
                              : !isConnected
                              ? l10n.t('presenceUnavailable')
                              : l10n.t('members', {'count': room.memberCount}),
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: onTap,
                child: Text(l10n.t(isPreview ? 'connect' : 'join')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.isPreview,
    required this.isConnected,
    required this.onTap,
  });

  final WorldMember member;
  final bool isPreview;
  final bool isConnected;
  final VoidCallback? onTap;

  static const colors = [
    AppColors.primary,
    AppColors.coral,
    AppColors.cyan,
    AppColors.amber,
    AppColors.success,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    final color = colors[member.avatarSeed % colors.length];
    final language = languageByCode(member.languageCode);
    final presenceColor = isPreview
        ? AppColors.amber
        : !isConnected
        ? AppColors.textMuted
        : member.isOnline
        ? AppColors.success
        : AppColors.textMuted;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: color.withValues(alpha: 0.18),
                        child: Text(
                          initialsFor(member.name),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!isPreview && isConnected)
                        Positioned(
                          right: 1,
                          bottom: 1,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: member.isOnline
                                  ? AppColors.success
                                  : AppColors.textMuted,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.surface,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (member.isVip)
                    const Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.amber,
                      size: 19,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                '${member.city}, ${member.country}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        language.nativeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primaryBright,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      isPreview
                          ? l10n.t('previewCatalogShort')
                          : !isConnected
                          ? l10n.t('presenceUnavailable')
                          : l10n.t(member.isOnline ? 'online' : 'offline'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: presenceColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectingOverlay extends StatelessWidget {
  const _ConnectingOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Color(0x990A0B14)),
        Center(
          child: Semantics(
            liveRegion: true,
            label: label,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 13),
                    Flexible(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

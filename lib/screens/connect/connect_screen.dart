import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/l10n_state.dart';
import '../../l10n/languages.dart';
import '../../services/online_service.dart';
import '../../services/session_service.dart';
import '../profile/billing_sheet.dart';

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

    if (!online.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('offline'))),
      );
      return;
    }
    if (!session.start()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('notEnoughTime'))),
      );
      await showBillingSheet(context);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: LiveSessionSheet(room: room, member: member),
      ),
    );
    session.pause();
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
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
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
                                style: Theme.of(context).textTheme.headlineMedium,
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
                    const SizedBox(height: 24),
                    _RandomConnectCard(
                      onlineCount: online.onlineCount,
                      onTap: () => _startSession(context),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      l10n.t('trendingRooms'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 14),
                    for (final room in online.rooms) ...[
                      _RoomListCard(
                        room: room,
                        onTap: () => _startSession(context, room: room),
                      ),
                      const SizedBox(height: 11),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      l10n.t('peopleAroundWorld'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
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
                          onTap: () => _startSession(context, member: member),
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
              online.isConnected ? '${online.onlineCount}' : l10n.t('offline'),
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _RandomConnectCard extends StatelessWidget {
  const _RandomConnectCard({required this.onlineCount, required this.onTap});

  final int onlineCount;
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 20),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$onlineCount ${l10n.t('onlineNow')}',
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
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
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
  const _RoomListCard({required this.room, required this.onTap});

  final CommunityRoom room;
  final VoidCallback onTap;

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
                    Text(room.title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      room.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(Icons.people_alt_rounded, color: accent, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          l10n.t('members', {'count': room.memberCount}),
                          style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: onTap,
                child: Text(l10n.t('join')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.onTap});

  final WorldMember member;
  final VoidCallback onTap;

  static const colors = [
    AppColors.primary,
    AppColors.coral,
    AppColors.cyan,
    AppColors.amber,
    AppColors.success,
  ];

  @override
  Widget build(BuildContext context) {
    final color = colors[member.avatarSeed % colors.length];
    final language = languageByCode(member.languageCode);
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
                          style: TextStyle(color: color, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Positioned(
                        right: 1,
                        bottom: 1,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.surface, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (member.isVip)
                    const Icon(Icons.workspace_premium_rounded, color: AppColors.amber, size: 19),
                ],
              ),
              const Spacer(),
              Text(member.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                '${member.city}, ${member.country}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            ],
          ),
        ),
      ),
    );
  }
}

class LiveSessionSheet extends StatefulWidget {
  const LiveSessionSheet({super.key, this.room, this.member});

  final CommunityRoom? room;
  final WorldMember? member;

  @override
  State<LiveSessionSheet> createState() => _LiveSessionSheetState();
}

class _LiveSessionSheetState extends State<LiveSessionSheet> {
  bool _muted = false;
  bool _translationEnabled = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10nState>();
    final session = context.watch<SessionService>();
    final title = widget.member?.name ?? widget.room?.title ?? l10n.t('sessionActive');
    final subtitle = widget.member == null
        ? l10n.t('sessionBody')
        : '${widget.member!.city}, ${widget.member!.country}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.t('live'),
                      style: const TextStyle(
                        color: AppColors.coral,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                session.isVip ? '∞' : formatDuration(session.remaining),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          const Spacer(),
          _ConversationVisual(member: widget.member),
          const SizedBox(height: 30),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 7),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
          ),
          const Spacer(),
          if (_translationEnabled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: AppColors.cyan, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.t('featureTranslate'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const Icon(Icons.graphic_eq_rounded, color: AppColors.cyan),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CallControl(
                icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                active: _muted,
                onTap: () => setState(() => _muted = !_muted),
              ),
              _CallControl(
                icon: Icons.translate_rounded,
                active: _translationEnabled,
                activeColor: AppColors.cyan,
                onTap: () => setState(
                  () => _translationEnabled = !_translationEnabled,
                ),
              ),
              _CallControl(
                icon: Icons.flag_outlined,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.t('featureSafe'))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
              icon: const Icon(Icons.call_end_rounded),
              label: Text(l10n.t('endSession')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationVisual extends StatelessWidget {
  const _ConversationVisual({this.member});

  final WorldMember? member;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var index = 0; index < 3; index++)
            Transform.rotate(
              angle: index * math.pi / 3,
              child: Container(
                width: 180 - index * 24,
                height: 180 - index * 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.18 + index * 0.06),
                  ),
                ),
              ),
            ),
          Container(
            width: 106,
            height: 106,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 38,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              member == null ? '🌍' : initialsFor(member!.name),
              style: TextStyle(
                color: Colors.white,
                fontSize: member == null ? 45 : 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Positioned(top: 10, right: 12, child: _MessageBubble(text: 'Hello!')),
          const Positioned(bottom: 5, left: 2, child: _MessageBubble(text: 'Салом!')),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 11)),
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.activeColor = AppColors.coral,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      color: active ? activeColor : AppColors.text,
      style: IconButton.styleFrom(
        fixedSize: const Size(54, 54),
        backgroundColor: active
            ? activeColor.withValues(alpha: 0.14)
            : AppColors.surfaceHigh,
        side: BorderSide(
          color: active ? activeColor.withValues(alpha: 0.3) : AppColors.divider,
        ),
      ),
    );
  }
}

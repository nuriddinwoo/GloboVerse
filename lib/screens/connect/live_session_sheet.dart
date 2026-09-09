import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/l10n_state.dart';
import '../../l10n/languages.dart';
import '../../models/conversation_message.dart';
import '../../services/conversation_service.dart';
import '../../services/session_service.dart';

class LiveSessionSheet extends StatefulWidget {
  const LiveSessionSheet({super.key});

  @override
  State<LiveSessionSheet> createState() => _LiveSessionSheetState();
}

class _LiveSessionSheetState extends State<LiveSessionSheet> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _translationEnabled = true;
  bool _closingForTime = false;
  int _lastMessageCount = 0;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestion]) async {
    final text = (suggestion ?? _messageController.text).trim();
    if (text.isEmpty) return;
    _messageController.clear();
    setState(() {});
    await context.read<ConversationService>().send(text);
  }

  Future<void> _report() async {
    final l10n = context.read<L10nState>();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.shield_outlined, color: AppColors.coral),
        title: Text(l10n.t('reportTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.t('reportBody')),
            const SizedBox(height: 12),
            _ReportReason(
              label: l10n.t('reportHarassment'),
              value: 'harassment',
            ),
            _ReportReason(label: l10n.t('reportSpam'), value: 'spam'),
            _ReportReason(
              label: l10n.t('reportUnsafe'),
              value: 'unsafe_content',
            ),
            _ReportReason(label: l10n.t('reportOther'), value: 'other'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.t('cancel')),
          ),
        ],
      ),
    );
    if (reason == null) return;
    if (!mounted) return;

    final conversation = context.read<ConversationService>();
    final wasPreview = conversation.isPreviewMode;
    final reported = await conversation.reportCurrent(reason);
    if (!mounted) return;
    var messageKey = 'reportFailed';
    if (reported) {
      messageKey = wasPreview ? 'previewReportNoted' : 'reportSubmitted';
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.t(messageKey))));
    if (reported) Navigator.pop(context);
  }

  void _closeForExpiredSession() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route == null) return;
    navigator.popUntil((candidate) => candidate == route);
    if (route.isActive) navigator.pop();
  }

  void _scheduleScroll(int messageCount) {
    if (_lastMessageCount == messageCount) return;
    _lastMessageCount = messageCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10nState>();
    final session = context.watch<SessionService>();
    final conversation = context.watch<ConversationService>();
    final source = languageByCode(conversation.sourceLanguage);
    final target = languageByCode(conversation.targetLanguage);
    _scheduleScroll(conversation.messages.length);

    if (!session.canStart && !_closingForTime) {
      _closingForTime = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _closeForExpiredSession();
      });
    }

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(18, 6, 18, 16 + keyboardInset),
      child: Column(
        children: [
          _ConversationHeader(
            title: conversation.peerName,
            time: session.isVip ? '∞' : formatDuration(session.remaining),
            onClose: () => Navigator.pop(context),
          ),
          if (keyboardInset == 0) ...[
            const SizedBox(height: 12),
            _PeerSummary(
              name: conversation.peerName,
              sourceLanguage: source.nativeName,
              targetLanguage: target.nativeName,
            ),
            if (conversation.isPreviewMode) ...[
              const SizedBox(height: 10),
              _PreviewBanner(
                title: l10n.t('previewMode'),
                body: l10n.t('previewModeBody'),
              ),
            ],
            const SizedBox(height: 10),
          ] else
            const SizedBox(height: 4),
          Expanded(
            child: conversation.messages.isEmpty
                ? _EmptyConversation(
                    suggestions: _suggestionsFor(l10n.code),
                    onSuggestion: _send,
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: conversation.messages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final message = conversation.messages[index];
                      return _ChatMessageBubble(
                        message: message,
                        showTranslation: _translationEnabled,
                        onRetry: () => conversation.retry(message.id),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: _translationEnabled
                    ? l10n.t('hideTranslations')
                    : l10n.t('showTranslations'),
                onPressed: () =>
                    setState(() => _translationEnabled = !_translationEnabled),
                style: IconButton.styleFrom(
                  backgroundColor: _translationEnabled
                      ? AppColors.cyan.withValues(alpha: 0.14)
                      : AppColors.surfaceHigh,
                  side: BorderSide(
                    color: _translationEnabled
                        ? AppColors.cyan.withValues(alpha: 0.3)
                        : AppColors.divider,
                  ),
                ),
                color: _translationEnabled
                    ? AppColors.cyan
                    : AppColors.textMuted,
                icon: const Icon(Icons.translate_rounded),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l10n.t('report'),
                onPressed: conversation.isReporting ? null : _report,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceHigh,
                  side: const BorderSide(color: AppColors.divider),
                ),
                color: AppColors.textMuted,
                icon: const Icon(Icons.flag_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MessageComposer(
                  controller: _messageController,
                  enabled: conversation.isActive && !conversation.isSending,
                  onChanged: () => setState(() {}),
                  onSend: _send,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.title,
    required this.time,
    required this.onClose,
  });

  final String title;
  final String time;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Text(
          time,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: l10n.t('endSession'),
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

class _PeerSummary extends StatelessWidget {
  const _PeerSummary({
    required this.name,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  final String name;
  final String sourceLanguage;
  final String targetLanguage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: AppColors.heroGradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              initialsFor(name),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  '$sourceLanguage  ↔  $targetLanguage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.cyan,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.verified_user_outlined,
            color: AppColors.success,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.smart_toy_outlined,
            color: AppColors.amber,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.amber,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({
    required this.suggestions,
    required this.onSuggestion,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.forum_outlined,
                color: AppColors.primaryBright,
                size: 30,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              l10n.t('noMessages'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                l10n.t('trySaying'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 13),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 7,
                runSpacing: 7,
                children: suggestions
                    .map(
                      (suggestion) => ActionChip(
                        onPressed: () => onSuggestion(suggestion),
                        avatar: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 15,
                        ),
                        label: Text(suggestion),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({
    required this.message,
    required this.showTranslation,
    required this.onRetry,
  });

  final ConversationMessage message;
  final bool showTranslation;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    final mine = message.isMine;
    final failed = mine && message.deliveryState == MessageDeliveryState.failed;
    final sending =
        mine && message.deliveryState == MessageDeliveryState.sending;
    return Semantics(
      label: mine ? l10n.t('sendMessage') : l10n.t('translatedMessage'),
      child: Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: 0.84,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: mine
                  ? AppColors.primary.withValues(alpha: 0.24)
                  : AppColors.surfaceHigh,
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(19),
                topEnd: const Radius.circular(19),
                bottomStart: Radius.circular(mine ? 19 : 5),
                bottomEnd: Radius.circular(mine ? 5 : 19),
              ),
              border: Border.all(
                color: failed
                    ? AppColors.coral
                    : mine
                    ? AppColors.primary.withValues(alpha: 0.34)
                    : AppColors.divider,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(fontSize: 15),
                  ),
                  if (showTranslation && message.hasTranslation) ...[
                    const SizedBox(height: 9),
                    Divider(
                      height: 1,
                      color: (mine ? AppColors.primaryBright : AppColors.cyan)
                          .withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.translate_rounded,
                          color: AppColors.cyan,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            message.translatedText!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.text, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (sending) ...[
                    const SizedBox(height: 7),
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.7),
                    ),
                  ],
                  if (failed) ...[
                    const SizedBox(height: 7),
                    InkWell(
                      onTap: onRetry,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.refresh_rounded,
                            color: AppColors.coral,
                            size: 15,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              l10n.t('messageFailed'),
                              style: const TextStyle(
                                color: AppColors.coral,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    final canSend = enabled && controller.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 600,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                hintText: l10n.t('messageHint'),
                counterText: '',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(13, 11, 6, 11),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(5),
            child: IconButton.filled(
              tooltip: l10n.t('sendMessage'),
              onPressed: canSend ? onSend : null,
              icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportReason extends StatelessWidget {
  const _ReportReason({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: () => Navigator.pop(context, value),
      leading: const Icon(Icons.radio_button_unchecked_rounded, size: 20),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

List<String> _suggestionsFor(String code) {
  switch (code) {
    case 'tg':
      return const ['Салом', 'Шумо чӣ хелед?', 'Аз шиносоӣ шодам'];
    case 'ru':
      return const ['Привет', 'Как дела?', 'Приятно познакомиться'];
    case 'uz':
      return const ['Salom', 'Qalaysiz?', 'Tanishganimdan xursandman'];
    case 'es':
      return const ['Hola', '¿Cómo estás?', 'Mucho gusto'];
    case 'fr':
      return const ['Bonjour', 'Comment allez-vous ?', 'Enchanté'];
    case 'de':
      return const [
        'Hallo',
        'Wie geht es dir?',
        'Freut mich, dich kennenzulernen',
      ];
    case 'ar':
      return const ['مرحباً', 'كيف حالك؟', 'سعيد بلقائك'];
    case 'fa':
      return const ['سلام', 'حال شما چطور است؟', 'از آشنایی با شما خوشحالم'];
    case 'ja':
      return const ['こんにちは', 'お元気ですか？', 'はじめまして'];
    case 'zh':
      return const ['你好', '你好吗？', '很高兴认识你'];
    case 'en':
      return const ['Hello', 'How are you?', 'Nice to meet you'];
    default:
      return const [];
  }
}

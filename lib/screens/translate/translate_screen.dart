import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/language_picker.dart';
import '../../l10n/l10n_state.dart';
import '../../l10n/languages.dart';
import '../../services/translation_service.dart';

class TranslateScreen extends StatefulWidget {
  const TranslateScreen({super.key});

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  final _inputController = TextEditingController();
  String _sourceCode = 'auto';
  late String _targetCode;
  TranslationResult? _result;

  @override
  void initState() {
    super.initState();
    final selected = context.read<L10nState>().code;
    _targetCode = selected == 'en' ? 'tg' : selected;
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    final code = await showLanguagePicker(
      context,
      selectedCode: _sourceCode,
      includeAutoDetect: true,
    );
    if (code != null && mounted) setState(() => _sourceCode = code);
  }

  Future<void> _pickTarget() async {
    final code = await showLanguagePicker(context, selectedCode: _targetCode);
    if (code != null && mounted) setState(() => _targetCode = code);
  }

  void _swap() {
    if (_sourceCode == 'auto') {
      setState(() => _sourceCode = _targetCode);
      return;
    }
    setState(() {
      final previousSource = _sourceCode;
      _sourceCode = _targetCode;
      _targetCode = previousSource;
      if (_result != null) {
        final oldInput = _inputController.text;
        _inputController.text = _result!.text;
        _result = TranslationResult(
          text: oldInput,
          sourceLanguage: _targetCode,
          isOfflinePreview: _result!.isOfflinePreview,
        );
      }
    });
  }

  Future<void> _translate() async {
    FocusScope.of(context).unfocus();
    final result = await context.read<TranslationService>().translate(
          text: _inputController.text,
          sourceLanguage: _sourceCode,
          targetLanguage: _targetCode,
        );
    if (mounted && result != null) setState(() => _result = result);
  }

  Future<void> _copyResult() async {
    if (_result == null) return;
    await Clipboard.setData(ClipboardData(text: _result!.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<L10nState>().t('copied'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10nState>();
    final translation = context.watch<TranslationService>();
    final targetLanguage = languageByCode(_targetCode);

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 116),
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.translate_rounded, color: AppColors.cyan),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      l10n.t('translate'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (translation.hasRemoteProvider
                              ? AppColors.success
                              : AppColors.amber)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      translation.hasRemoteProvider ? l10n.t('online') : l10n.t('offlinePreview'),
                      style: TextStyle(
                        color: translation.hasRemoteProvider
                            ? AppColors.success
                            : AppColors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Text(l10n.t('translationTitle'), style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 10),
              Text(
                l10n.t('translationBody'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textMuted,
                    ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: _LanguageButton(
                      eyebrow: l10n.t('from'),
                      label: _sourceCode == 'auto'
                          ? l10n.t('autoDetect')
                          : languageByCode(_sourceCode).nativeName,
                      code: _sourceCode == 'auto' ? 'AI' : _sourceCode.toUpperCase(),
                      onTap: _pickSource,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: IconButton.filledTonal(
                      tooltip: '${l10n.t('from')} / ${l10n.t('to')}',
                      onPressed: _swap,
                      icon: const Icon(Icons.swap_horiz_rounded),
                    ),
                  ),
                  Expanded(
                    child: _LanguageButton(
                      eyebrow: l10n.t('to'),
                      label: targetLanguage.nativeName,
                      code: targetLanguage.code.toUpperCase(),
                      onTap: _pickTarget,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _inputController,
                      minLines: 6,
                      maxLines: 10,
                      maxLength: 1500,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: l10n.t('enterText'),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        counterText: '',
                        contentPadding: const EdgeInsets.all(19),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Row(
                        children: [
                          Text(
                            '${_inputController.text.characters.length} / 1500',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11),
                          ),
                          const Spacer(),
                          if (_inputController.text.isNotEmpty)
                            IconButton(
                              tooltip: l10n.t('cancel'),
                              onPressed: () => setState(() {
                                _inputController.clear();
                                _result = null;
                              }),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          FilledButton.icon(
                            onPressed: _inputController.text.trim().isEmpty ||
                                    translation.isTranslating
                                ? null
                                : _translate,
                            icon: translation.isTranslating
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.auto_awesome_rounded, size: 19),
                            label: Text(l10n.t('translateAction')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: _result == null
                    ? _EmptyResult(text: l10n.t('translatedText'))
                    : _ResultCard(
                        key: ValueKey(_result!.text),
                        result: _result!,
                        language: targetLanguage,
                        onCopy: _copyResult,
                      ),
              ),
              if (translation.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.t('translationUnavailable'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.coral),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.eyebrow,
    required this.label,
    required this.code,
    required this.onTap,
  });

  final String eyebrow;
  final String label;
  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 33,
                height: 33,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    color: AppColors.primaryBright,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('empty'),
      height: 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.subtitles_outlined, color: AppColors.textMuted, size: 28),
          const SizedBox(height: 10),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    super.key,
    required this.result,
    required this.language,
    required this.onCopy,
  });

  final TranslationResult result;
  final AppLanguage language;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2140), Color(0xFF171A31)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                language.label,
                style: const TextStyle(
                  color: AppColors.primaryBright,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (result.isOfflinePreview)
                const Icon(Icons.offline_bolt_outlined, color: AppColors.amber, size: 18),
            ],
          ),
          const SizedBox(height: 16),
          Directionality(
            textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: SelectableText(
              result.text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: 19,
                    height: 1.55,
                  ),
            ),
          ),
          const SizedBox(height: 17),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(l10n.t('copy')),
            ),
          ),
        ],
      ),
    );
  }
}

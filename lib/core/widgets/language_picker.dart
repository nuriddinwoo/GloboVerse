import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n_state.dart';
import '../../l10n/languages.dart';
import '../theme/app_theme.dart';

Future<String?> showLanguagePicker(
  BuildContext context, {
  required String selectedCode,
  bool includeAutoDetect = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.88,
      child: LanguagePickerSheet(
        selectedCode: selectedCode,
        includeAutoDetect: includeAutoDetect,
      ),
    ),
  );
}

class LanguagePickerSheet extends StatefulWidget {
  const LanguagePickerSheet({
    super.key,
    required this.selectedCode,
    this.includeAutoDetect = false,
  });

  final String selectedCode;
  final bool includeAutoDetect;

  @override
  State<LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<LanguagePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10nState>();
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? appLanguages
        : appLanguages
            .where(
              (language) =>
                  language.code.contains(query) ||
                  language.name.toLowerCase().contains(query) ||
                  language.nativeName.toLowerCase().contains(query),
            )
            .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: TextField(
            controller: _searchController,
            autofocus: false,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: l10n.t('searchLanguages'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.t('cancel'),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty && !widget.includeAutoDetect
              ? Center(
                  child: Text(
                    l10n.t('noResults'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: filtered.length +
                      (widget.includeAutoDetect && query.isEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (widget.includeAutoDetect && query.isEmpty && index == 0) {
                      return _LanguageTile(
                        code: 'AI',
                        label: l10n.t('autoDetect'),
                        selected: widget.selectedCode == 'auto',
                        icon: Icons.auto_awesome_rounded,
                        onTap: () => Navigator.pop(context, 'auto'),
                      );
                    }
                    final offset = widget.includeAutoDetect && query.isEmpty ? 1 : 0;
                    final language = filtered[index - offset];
                    return _LanguageTile(
                      code: language.code.toUpperCase(),
                      label: language.label,
                      selected: widget.selectedCode == language.code,
                      onTap: () => Navigator.pop(context, language.code),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: icon == null
            ? Text(
                code,
                style: TextStyle(
                  color: selected ? AppColors.primaryBright : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              )
            : Icon(icon, color: AppColors.primaryBright, size: 20),
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
          : null,
    );
  }
}

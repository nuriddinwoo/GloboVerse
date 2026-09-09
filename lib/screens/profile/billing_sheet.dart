import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/l10n_state.dart';
import '../../services/billing_service.dart';
import '../../services/entitlement_reconciliation_service.dart';

Future<void> showBillingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const BillingSheet(),
  );
}

class BillingSheet extends StatelessWidget {
  const BillingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10nState>();
    final billing = context.watch<BillingService>();
    final entitlementSync = context.watch<EntitlementReconciliationService?>();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          6,
          22,
          22 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: const Icon(
                  Icons.public_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.t('choosePlan'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 7),
              Text(
                l10n.t('choosePlanBody'),
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 22),
              for (final offer in billing.offers) ...[
                _OfferCard(
                  offer: offer,
                  featured: offer.kind == OfferKind.subscription,
                  enabled: billing.canPurchaseOffer(offer),
                  onTap: () => billing.purchase(offer),
                ),
                const SizedBox(height: 12),
              ],
              if (billing.isHourPassCapacityReached) ...[
                _StatusMessage(
                  icon: Icons.timer_off_outlined,
                  color: AppColors.amber,
                  text: l10n.t('hourPassCapacityReached'),
                ),
              ],
              if (billing.isBusy) ...[
                const SizedBox(height: 4),
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                Text(
                  billing.status == BillingStatus.purchasing
                      ? l10n.t('purchasePending')
                      : billing.status == BillingStatus.verifying
                      ? l10n.t('purchaseVerifying')
                      : billing.isRestoring
                      ? l10n.t('restoring')
                      : l10n.t('loadingProducts'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (billing.status == BillingStatus.success) ...[
                _StatusMessage(
                  icon: Icons.verified_rounded,
                  color: AppColors.success,
                  text: l10n.t('purchaseSuccess'),
                ),
              ],
              if (billing.status == BillingStatus.verificationRequired) ...[
                _StatusMessage(
                  icon: Icons.gpp_maybe_outlined,
                  color: AppColors.amber,
                  text: l10n.t('purchaseVerificationRequired'),
                ),
              ],
              if (billing.status == BillingStatus.verificationPending) ...[
                _StatusMessage(
                  icon: Icons.hourglass_top_rounded,
                  color: AppColors.amber,
                  text: l10n.t('purchaseVerificationPending'),
                ),
              ],
              if (billing.status == BillingStatus.verificationFailed) ...[
                _StatusMessage(
                  icon: Icons.gpp_bad_outlined,
                  color: AppColors.coral,
                  text: l10n.t('purchaseVerificationFailed'),
                ),
              ],
              if (billing.status == BillingStatus.verificationError) ...[
                _StatusMessage(
                  icon: Icons.cloud_off_outlined,
                  color: AppColors.amber,
                  text: l10n.t('purchaseVerificationError'),
                ),
              ],
              if (billing.status == BillingStatus.error &&
                  billing.error != null) ...[
                _StatusMessage(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.coral,
                  text: billing.error!,
                ),
              ],
              if (billing.status == BillingStatus.productsUnavailable) ...[
                _StatusMessage(
                  icon: Icons.inventory_2_outlined,
                  color: AppColors.amber,
                  text: l10n.t('storeProductsUnavailable'),
                ),
              ],
              if (billing.status == BillingStatus.unavailable) ...[
                _StatusMessage(
                  icon: Icons.storefront_outlined,
                  color: AppColors.amber,
                  text: l10n.t('storeUnavailable'),
                ),
              ],
              if (entitlementSync != null &&
                  entitlementSync.status == EntitlementSyncStatus.syncing &&
                  !billing.isBusy) ...[
                _StatusMessage(
                  icon: Icons.sync_rounded,
                  color: AppColors.cyan,
                  text: l10n.t('entitlementRefreshing'),
                ),
              ],
              if (entitlementSync != null &&
                  entitlementSync.status == EntitlementSyncStatus.error) ...[
                _StatusMessage(
                  icon: Icons.cloud_off_outlined,
                  color: AppColors.amber,
                  text: l10n.t('entitlementRefreshFailed'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: entitlementSync.refresh,
                    child: Text(l10n.t('retryEntitlements')),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: billing.canRestore
                      ? billing.restorePurchases
                      : null,
                  child: Text(l10n.t('restorePurchases')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.featured,
    required this.enabled,
    required this.onTap,
  });

  final BillingOffer offer;
  final bool featured;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<L10nState>();
    return Opacity(
      opacity: enabled ? 1 : 0.66,
      child: Material(
        color: featured
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: featured ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: featured
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    featured
                        ? Icons.workspace_premium_rounded
                        : Icons.timer_rounded,
                    color: featured ? AppColors.primaryBright : AppColors.amber,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (featured)
                        Text(
                          l10n.t('bestValue'),
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      Text(
                        l10n.t(offer.titleKey),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.t(offer.descriptionKey),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  offer.price,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: featured ? AppColors.primaryBright : AppColors.text,
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

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

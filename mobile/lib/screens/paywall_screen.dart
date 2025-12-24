import 'dart:io' show Platform, exit;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subscription_service.dart';
import '../services/localization_service.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  @override
  void initState() {
    super.initState();
    // 画面表示時にローディング状態をリセット
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(subscriptionProvider.notifier).resetLoadingState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);
    final l10n = ref.watch(l10nProvider);
    final language = ref.watch(languageProvider);

    // If already subscribed, redirect to scan
    if (subscription.isSubscribed && !subscription.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/scan');
      });
      return const Scaffold(
        backgroundColor: Color(0xFF1a1a2e),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFe94560))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Close button & Language Switcher at top
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close button (X)
                  GestureDetector(
                    onTap: () => _showCloseConfirmDialog(context, l10n),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16213e),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24, width: 2),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 24,
                      ),
                    ),
                  ),
                  _buildLanguageSwitcher(ref, language),
                ],
              ),
              const SizedBox(height: 8),
              // App Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFe94560),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.phone_iphone,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              // Title
              Text(
                l10n.appName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.appTagline,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              // Features
              _buildFeatureItem(Icons.keyboard, l10n.featureKeyboard, l10n.featureKeyboardDesc),
              _buildFeatureItem(Icons.mouse, l10n.featureMouse, l10n.featureMouseDesc),
              _buildFeatureItem(Icons.screen_share, l10n.featureScreenShare, l10n.featureScreenShareDesc),
              _buildFeatureItem(Icons.public, l10n.featureRemoteAccess, l10n.featureRemoteAccessDesc),
              const SizedBox(height: 24),
              // Subscription Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF16213e),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFe94560),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      l10n.monthlyPlan,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subscription.product?.price ?? '\$2.99/month',
                      style: const TextStyle(
                        color: Color(0xFFe94560),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.freeTrial,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Trial Terms (Required by Google/Apple)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        l10n.trialTermsWithPrice(
                          subscription.product?.price ?? '\$2.99',
                          isIOS: Platform.isIOS,
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Subscribe Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: subscription.isLoading
                            ? null
                            : () => _subscribe(context, ref),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFe94560),
                          disabledBackgroundColor: const Color(0xFFe94560).withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: subscription.isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                l10n.startFreeTrial,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Restore Purchases & Manage Subscription
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: subscription.isLoading
                        ? null
                        : () => _restorePurchases(context, ref, l10n),
                    child: Text(
                      l10n.restorePurchases,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Text('|', style: TextStyle(color: Colors.white38)),
                  TextButton(
                    onPressed: () => _openSubscriptionManagement(),
                    child: Text(
                      l10n.manageSubscription,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              // Error Message
              if (subscription.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    subscription.errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              // Legal Links
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _showTerms(context, l10n),
                    child: Text(
                      l10n.termsOfUse,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                  const Text('|', style: TextStyle(color: Colors.white38)),
                  TextButton(
                    onPressed: () => _showPrivacy(context, l10n),
                    child: Text(
                      l10n.privacyPolicy,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
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

  Widget _buildLanguageSwitcher(WidgetRef ref, AppLanguage language) {
    return GestureDetector(
      onTap: () {
        ref.read(languageProvider.notifier).toggleLanguage();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF16213e),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              language == AppLanguage.ja ? '🇯🇵' : '🇺🇸',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 6),
            Text(
              language == AppLanguage.ja ? '日本語' : 'English',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.swap_horiz, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF16213e),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFFe94560), size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _subscribe(BuildContext context, WidgetRef ref) async {
    final success = await ref.read(subscriptionProvider.notifier).purchase();
    if (success && context.mounted) {
      // Purchase initiated, result will come through stream
    }
  }

  Future<void> _restorePurchases(BuildContext context, WidgetRef ref, L10n l10n) async {
    await ref.read(subscriptionProvider.notifier).restorePurchases();

    if (context.mounted) {
      final state = ref.read(subscriptionProvider);
      if (state.isSubscribed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.subscriptionRestored)),
        );
        context.go('/scan');
      } else if (state.errorMessage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.noActiveSubscription)),
        );
      }
    }
  }

  Future<void> _showTerms(BuildContext context, L10n l10n) async {
    final url = Uri.parse('https://b19.co.jp/remotetouch/terms.html');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openSubscriptionManagement() async {
    final urlString = Platform.isIOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showPrivacy(BuildContext context, L10n l10n) async {
    final url = Uri.parse('https://b19.co.jp/remotetouch/privacy.html');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showCloseConfirmDialog(BuildContext context, L10n l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: Text(l10n.closePaywallTitle, style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.closePaywallMessage,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // アプリを終了
              if (Platform.isIOS) {
                exit(0);
              } else {
                SystemNavigator.pop();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}

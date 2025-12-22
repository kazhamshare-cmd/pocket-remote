import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Platform-specific subscription IDs
const String kMonthlySubscriptionIdIOS = 'b19.ikushima.pocketremote.monthly';
const String kMonthlySubscriptionIdAndroid = 'remotetouch_monthly';
String get kMonthlySubscriptionId => Platform.isIOS ? kMonthlySubscriptionIdIOS : kMonthlySubscriptionIdAndroid;
const String kPrefSubscriptionActive = 'subscription_active';
const String kPrefSubscriptionExpiry = 'subscription_expiry';

class SubscriptionState {
  final bool isAvailable;
  final bool isSubscribed;
  final bool isLoading;
  final ProductDetails? product;
  final String? errorMessage;

  const SubscriptionState({
    this.isAvailable = false,
    this.isSubscribed = false,
    this.isLoading = true,
    this.product,
    this.errorMessage,
  });

  SubscriptionState copyWith({
    bool? isAvailable,
    bool? isSubscribed,
    bool? isLoading,
    ProductDetails? product,
    String? errorMessage,
  }) {
    return SubscriptionState(
      isAvailable: isAvailable ?? this.isAvailable,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      isLoading: isLoading ?? this.isLoading,
      product: product ?? this.product,
      errorMessage: errorMessage,
    );
  }
}

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  SubscriptionNotifier() : super(const SubscriptionState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    // Check if store is available
    final available = await _inAppPurchase.isAvailable();
    if (!available) {
      state = state.copyWith(
        isAvailable: false,
        isLoading: false,
        errorMessage: 'Store not available / ストアに接続できません',
      );
      return;
    }

    // Listen to purchase updates
    _subscription = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (error) {
        print('[Subscription] Purchase stream error: $error');
      },
    );

    // Load products
    await _loadProducts();

    // Check existing subscription status
    await _checkSubscriptionStatus();

    state = state.copyWith(isAvailable: true, isLoading: false);
  }

  Future<void> _loadProducts() async {
    final productId = kMonthlySubscriptionId;
    print('[Subscription] Platform.isIOS: ${Platform.isIOS}');
    print('[Subscription] Using product ID: $productId');
    final response = await _inAppPurchase.queryProductDetails({productId});

    if (response.notFoundIDs.isNotEmpty) {
      print('[Subscription] Products not found: ${response.notFoundIDs}');
    }

    if (response.productDetails.isNotEmpty) {
      state = state.copyWith(product: response.productDetails.first);
      print('[Subscription] Product loaded: ${response.productDetails.first.title}');
    } else {
      print('[Subscription] No products found');
    }
  }

  Future<void> _checkSubscriptionStatus() async {
    // First check local cache
    final prefs = await SharedPreferences.getInstance();
    final isActive = prefs.getBool(kPrefSubscriptionActive) ?? false;

    if (isActive) {
      state = state.copyWith(isSubscribed: true);
    }

    // Then verify with store (restore purchases)
    try {
      await _inAppPurchase.restorePurchases();
    } catch (e) {
      print('[Subscription] Restore purchases error: $e');
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchase in purchaseDetailsList) {
      print('[Subscription] Purchase update: ${purchase.productID} - ${purchase.status}');

      if (purchase.status == PurchaseStatus.pending) {
        // Show loading indicator
        state = state.copyWith(isLoading: true);
      } else {
        if (purchase.status == PurchaseStatus.error) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: purchase.error?.message ?? 'Purchase failed / 購入に失敗しました',
          );
        } else if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          // Verify and grant subscription
          await _verifyAndGrantSubscription(purchase);
        } else if (purchase.status == PurchaseStatus.canceled) {
          state = state.copyWith(isLoading: false);
        }

        // Complete the purchase
        if (purchase.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchase);
        }
      }
    }
  }

  Future<void> _verifyAndGrantSubscription(PurchaseDetails purchase) async {
    // In production, verify receipt with your server
    // For now, we trust the local verification

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefSubscriptionActive, true);

    state = state.copyWith(
      isSubscribed: true,
      isLoading: false,
      errorMessage: null,
    );

    print('[Subscription] Subscription granted for ${purchase.productID}');
  }

  Future<bool> purchase() async {
    if (state.product == null) {
      state = state.copyWith(errorMessage: 'Product not found / 商品が見つかりません');
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final purchaseParam = PurchaseParam(productDetails: state.product!);
      final success = await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);

      if (!success) {
        state = state.copyWith(isLoading: false, errorMessage: 'Could not start purchase / 購入を開始できませんでした');
        return false;
      }

      // Add timeout to reset loading state if purchase dialog is dismissed
      Future.delayed(const Duration(seconds: 30), () {
        if (state.isLoading) {
          state = state.copyWith(isLoading: false);
        }
      });

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Purchase error / 購入エラー: $e');
      return false;
    }
  }

  Future<void> restorePurchases() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      await _inAppPurchase.restorePurchases();
      // Result will come through the purchase stream
      // Add timeout to reset loading state if no response
      Future.delayed(const Duration(seconds: 5), () {
        if (state.isLoading) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: 'No purchase history / 購入履歴はありません',
          );
        }
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Restore failed / 復元に失敗しました: $e',
      );
    }
  }

  // ローディング状態をリセット（画面遷移時に呼び出す）
  void resetLoadingState() {
    if (state.isLoading) {
      state = state.copyWith(isLoading: false, errorMessage: null);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  return SubscriptionNotifier();
});

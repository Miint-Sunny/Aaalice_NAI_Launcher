import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/utils/app_logger.dart';
import '../../data/datasources/remote/nai_user_info_api_service.dart';
import '../../data/models/user/user_subscription.dart';
import 'account_manager_provider.dart';
import 'auth_provider.dart';

part 'subscription_provider.g.dart';

/// Whether [error] means the server could not be reached at all (no HTTP
/// answer), as opposed to an answer with an error status.
bool isSubscriptionNetworkFailure(Object error) {
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.badCertificate => true,
      DioExceptionType.unknown =>
        error.error is SocketException ||
            error.error is HandshakeException ||
            error.error is HttpException ||
            error.error is TimeoutException,
      // An answer that failed to parse, a cancel, an error status.
      _ => false,
    };
  }
  return error is SocketException ||
      error is HandshakeException ||
      error is HttpException ||
      error is TimeoutException;
}

/// Something is about to stop because the cached balance looks too low or is
/// missing (the Agent's price checks before a generation or an image tool),
/// or the Agent is about to quote or send a price that counts Opus-free
/// images on a quota nearly used up ([opusFreePriceMayBeStale]). Nothing
/// refreshes the balance by itself, so ask now: a stale value must never
/// stop the user, nor price a paid generation as free. A request already out
/// answers instead of a second one. Where the balance notifier never started
/// (isolated tests, tools), nothing is asked.
Future<void> refreshBalanceBeforeBlocking(Ref ref) async {
  if (!ref.exists(subscriptionNotifierProvider)) return;
  await ref.read(subscriptionNotifierProvider.notifier).recheckBalance();
}

/// Whether [price], the price of a request on a given cached account, counts
/// Opus-free images on a quota that is nearly used up: both pools under 5 %
/// and not run out yet. The server may already have run the quota out
/// (`usage.isNegative`) and bill those images; nothing refreshes the cached
/// quota by itself, so such a price may be too low, a paid generation shown
/// as free.
bool opusFreePriceMayBeStale(
  UserSubscription? subscription,
  int Function(UserSubscription? subscription) price,
) {
  final usage = subscription?.usage;
  if (subscription == null ||
      !subscription.isOpus ||
      usage == null ||
      usage.isNegative ||
      !usage.isLow) {
    return false;
  }
  final runOut = subscription.copyWith(usage: usage.copyWith(isNegative: true));
  return price(runOut) != price(subscription);
}

/// 订阅状态 Notifier
///
/// 管理用户订阅信息和 Anlas 余额
///
/// The balance (`GET /user/subscription`) is asked only: at start-up and on
/// a login or an account switch, once (not again when the token validation
/// already brought it); when the user clicks it ([refreshBalance]); right
/// before a low cached balance would stop something
/// ([refreshBalanceBeforeBlocking]); and right before a price that counts
/// Opus-free images on a quota nearly used up is confirmed or quoted
/// ([recheckBeforeOpusFreePrice]). No timer, nothing after a generation or
/// another billed action, nothing when the window comes back (user decision,
/// 2026-10-31). A failed request keeps the last balance and is not retried by
/// itself.
///
/// Anlas 统计不看余额：每个计费请求按自己的价记一笔（`AnlasRequestLedger`），
/// 余额变少不记，点余额也就不会把同一笔再记一遍（用户 2026-10-31 定）。
@riverpod
class SubscriptionNotifier extends _$SubscriptionNotifier {
  AuthState? _previousAuthState;
  SubscriptionState? _lastKnownState;
  bool _hasInitiallyLoaded = false;
  Future<void>? _inflightFetch;
  Future<bool>? _inflightBalanceRefresh;
  bool _balanceRefreshQueued = false;

  static const Duration _initialFetchTimeout = Duration(seconds: 6);

  @override
  SubscriptionState build() {
    ref.keepAlive();

    // Watch authentication state changes
    final authState = ref.watch(authNotifierProvider);
    // A login or a switch in progress (AuthNotifier checks the new token) is
    // not a logout. What comes after it is compared with the session before
    // it: another account resets, the same one put back after a failure
    // keeps the balance it had, a clicked one included.
    if (authState.isLoading) {
      return _lastKnownState ?? const SubscriptionState.initial();
    }
    final previousAuthState = _previousAuthState;
    final loggedIn =
        authState.isAuthenticated &&
        previousAuthState != null &&
        !previousAuthState.isAuthenticated;
    final switchedAccount =
        authState.isAuthenticated &&
        previousAuthState?.isAuthenticated == true &&
        authState.accountId != previousAuthState?.accountId;
    final loggedOut =
        !authState.isAuthenticated &&
        previousAuthState?.isAuthenticated == true;

    if (switchedAccount || loggedOut) {
      // 旧请求无法取消，但会被 session 校验丢弃。切换账号时解除去重，
      // 让新账号无需等待旧请求结束即可立即拉取自己的余额。
      if (switchedAccount) _inflightFetch = null;
      _lastKnownState = null;
      _hasInitiallyLoaded = false;
    }

    final hydratedState = _hydrateFromAuthState(authState);

    // React to authentication state changes
    if (loggedIn || switchedAccount) {
      // Login succeeded - use the subscription info already fetched during
      // token validation; ask only when it brought none.
      if (hydratedState == null) {
        Future.microtask(() => unawaited(fetchSubscription()));
      }
    } else if (previousAuthState == null &&
        authState.isAuthenticated &&
        !_hasInitiallyLoaded) {
      // First build and already authenticated - fetch subscription
      // 使用 _hasInitiallyLoaded 标记避免重复加载（预热阶段可能已加载）
      if (hydratedState == null) {
        Future.microtask(() => unawaited(fetchSubscription()));
      }
    }

    // Store current auth state for next comparison
    _previousAuthState = authState;

    if (hydratedState != null) {
      _lastKnownState = hydratedState;
      return hydratedState;
    }
    return _lastKnownState ?? const SubscriptionState.initial();
  }

  /// An unchanged answer is not news. SubscriptionState is a freezed value,
  /// so a refresh that brings the same balance (a second click, the check
  /// before a block) does not rebuild the screens watching it (up to nine).
  @override
  bool updateShouldNotify(SubscriptionState previous, SubscriptionState next) =>
      previous != next;

  void _updateState(SubscriptionState nextState) {
    _lastKnownState = nextState;
    state = nextState;
  }

  SubscriptionState? _hydrateFromAuthState(AuthState authState) {
    if (!authState.isAuthenticated ||
        authState.subscriptionInfo == null ||
        _hasInitiallyLoaded) {
      return null;
    }

    try {
      final subscription = UserSubscription.fromJson(
        authState.subscriptionInfo!,
      );
      // Token validation just fetched this from the same endpoint: it is the
      // start-up (or login) answer, nothing asks again for it.
      _hasInitiallyLoaded = true;

      final accountId = authState.accountId;
      if (accountId != null) {
        unawaited(
          ref
              .read(accountManagerNotifierProvider.notifier)
              .updateSubscriptionExpiry(accountId, subscription.expiresAt),
        );
      }

      return SubscriptionState.loaded(subscription);
    } catch (e) {
      AppLogger.w(
        'Failed to hydrate subscription from auth state: $e',
        'Subscription',
      );
      return null;
    }
  }

  /// 获取订阅信息
  Future<void> fetchSubscription() async {
    if (_inflightFetch != null) {
      return _inflightFetch;
    }

    final fetchFuture = _doFetchSubscription();
    _inflightFetch = fetchFuture;
    try {
      await fetchFuture;
    } finally {
      if (identical(_inflightFetch, fetchFuture)) {
        _inflightFetch = null;
      }
    }
  }

  Future<void> _doFetchSubscription() async {
    final authSession = ref.read(authNotifierProvider);
    if (!authSession.isAuthenticated) return;

    // 避免重复加载
    if (state.isLoading) return;

    // 如果已经加载过且不是错误状态，跳过（使用缓存）
    if (_hasInitiallyLoaded && !state.isError) {
      AppLogger.i('Subscription already loaded, skipping', 'Subscription');
      return;
    }

    // 首次拉取保持 initial，避免 UI 进入阻塞式 loading 体验
    if (_hasInitiallyLoaded) {
      _updateState(const SubscriptionState.loading());
    }

    try {
      final apiService = ref.read(naiUserInfoApiServiceProvider);
      final data = await apiService.getUserSubscription(
        receiveTimeout: _initialFetchTimeout,
      );
      if (!_isCurrentAuthSession(authSession)) return;

      final subscription = UserSubscription.fromJson(data);
      _updateState(SubscriptionState.loaded(subscription));
      _hasInitiallyLoaded = true;

      final accountId = authSession.accountId;
      if (accountId != null) {
        unawaited(
          ref
              .read(accountManagerNotifierProvider.notifier)
              .updateSubscriptionExpiry(accountId, subscription.expiresAt),
        );
      }

      AppLogger.i(
        'Subscription loaded: ${subscription.tierName}, '
            'Anlas: ${subscription.anlasBalance}',
        'Subscription',
      );
    } catch (e) {
      if (!_isCurrentAuthSession(authSession)) return;
      AppLogger.e('Failed to fetch subscription: $e', 'Subscription');

      // 首次加载失败时不进入 error 态，避免 UI 因网络抖动出现卡顿感
      if (_hasInitiallyLoaded) {
        _updateState(SubscriptionState.error(e.toString()));
      } else {
        _updateState(const SubscriptionState.initial());
      }

      // 检查是否是网络连接错误，如果是则不标记为已加载，允许后续重试
      final errorStr = e.toString().toLowerCase();
      final isNetworkError =
          isSubscriptionNetworkFailure(e) ||
          errorStr.contains('timeout') ||
          errorStr.contains('connection') ||
          errorStr.contains('network') ||
          errorStr.contains('socket') ||
          errorStr.contains('failed host lookup');

      if (!isNetworkError) {
        // 非网络错误（如认证失败），标记为已尝试加载
        _hasInitiallyLoaded = true;
      } else {
        // 网络错误，不标记为已加载：不自动重试，点余额、重新登录或换号时再查
        AppLogger.w('Network error detected, allowing retry', 'Subscription');
      }
    }
  }

  /// 重置加载状态（用于强制刷新）
  void resetLoadState() {
    _hasInitiallyLoaded = false;
  }

  /// 立即刷新余额（用户点余额芯片、额度胶囊时）。
  ///
  /// 刷新进行中收到的新请求不会被丢弃：当前请求结束后再拉取一次；连点几下
  /// 也只多这一次。
  Future<bool> refreshBalance() {
    if (!ref.read(authNotifierProvider).isAuthenticated) {
      return Future.value(false);
    }

    final inflightRefresh = _inflightBalanceRefresh;
    if (inflightRefresh != null) {
      _balanceRefreshQueued = true;
      return inflightRefresh;
    }

    late final Future<bool> trackedRefresh;
    trackedRefresh = _drainBalanceRefreshQueue().whenComplete(() {
      if (identical(_inflightBalanceRefresh, trackedRefresh)) {
        _inflightBalanceRefresh = null;
      }
    });
    _inflightBalanceRefresh = trackedRefresh;
    return trackedRefresh;
  }

  /// The cached balance is about to stop something
  /// ([refreshBalanceBeforeBlocking]): ask once now, or wait for a request
  /// already out, whose answer is just as fresh.
  Future<bool> recheckBalance() => _inflightBalanceRefresh ?? refreshBalance();

  /// Before a price is confirmed (the generate, retry and explore buttons):
  /// when it counts Opus-free images on a quota nearly used up
  /// ([opusFreePriceMayBeStale]), ask once, or join a request already out,
  /// so the price the user confirms is the one the server bills. Null, and
  /// nothing asked, otherwise.
  Future<bool>? recheckBeforeOpusFreePrice(
    int Function(UserSubscription? subscription) price,
  ) => opusFreePriceMayBeStale(state.subscription, price)
      ? recheckBalance()
      : null;

  Future<bool> _drainBalanceRefreshQueue() async {
    var latestRefreshSucceeded = false;
    do {
      _balanceRefreshQueued = false;
      latestRefreshSucceeded = await _refreshBalanceOnce();
    } while (_balanceRefreshQueued);
    return latestRefreshSucceeded;
  }

  Future<bool> _refreshBalanceOnce() async {
    // 保持当前状态，静默刷新
    final authSession = ref.read(authNotifierProvider);
    if (!authSession.isAuthenticated) return false;

    try {
      final apiService = ref.read(naiUserInfoApiServiceProvider);
      final data = await apiService.getUserSubscription(
        receiveTimeout: _initialFetchTimeout,
      );
      if (!_isCurrentAuthSession(authSession)) return false;

      final subscription = UserSubscription.fromJson(data);
      _updateState(SubscriptionState.loaded(subscription));
      // A click after a failed start-up fetch loads it as well: a later login
      // state update must not put the validation's older balance back.
      _hasInitiallyLoaded = true;

      final accountId = authSession.accountId;
      if (accountId != null) {
        unawaited(
          ref
              .read(accountManagerNotifierProvider.notifier)
              .updateSubscriptionExpiry(accountId, subscription.expiresAt),
        );
      }

      return true;
    } catch (e) {
      AppLogger.w('Failed to refresh balance: $e', 'Subscription');
      // 刷新失败不更新状态，保持上次数据
      return false;
    }
  }

  bool _isCurrentAuthSession(AuthState expected) {
    final current = ref.read(authNotifierProvider);
    if (!current.isAuthenticated) return false;
    if (identical(current, expected)) return true;

    final expectedAccountId = expected.accountId;
    return expectedAccountId != null && current.accountId == expectedAccountId;
  }
}

/// 便捷的余额 Provider
@riverpod
int? anlasBalance(Ref ref) {
  final subscriptionState = ref.watch(subscriptionNotifierProvider);
  return subscriptionState.balance;
}

/// 便捷的 Opus 状态 Provider
@riverpod
bool isOpusSubscription(Ref ref) {
  final subscriptionState = ref.watch(subscriptionNotifierProvider);
  return subscriptionState.isOpus;
}

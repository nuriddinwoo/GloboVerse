import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'entitlement_models.dart';
import 'settings_service.dart';

abstract class EntitlementSnapshotSource {
  bool get isConfigured;

  Future<AuthoritativeEntitlementSnapshot> fetch();

  void close() {}
}

class EntitlementReconciliationException implements Exception {
  const EntitlementReconciliationException(this.message);

  final String message;

  @override
  String toString() => 'EntitlementReconciliationException: $message';
}

class HttpEntitlementSnapshotSource extends EntitlementSnapshotSource {
  HttpEntitlementSnapshotSource({
    http.Client? client,
    String? endpoint,
    String? apiToken,
    this.requestTimeout = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : assert(requestTimeout > Duration.zero),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _endpoint = (endpoint ?? _configuredEndpoint).trim().replaceFirst(
         RegExp(r'/+$'),
         '',
       ),
       _apiToken = (apiToken ?? _configuredApiToken).trim(),
       _now = now ?? DateTime.now;

  static const _configuredEndpoint = String.fromEnvironment(
    'GLOBOVERSE_BILLING_API_URL',
  );
  static const _configuredApiToken = String.fromEnvironment(
    'GLOBOVERSE_API_TOKEN',
  );
  static const _maximumResponseBytes = 64 * 1024;

  final http.Client _client;
  final bool _ownsClient;
  final String _endpoint;
  final String _apiToken;
  final DateTime Function() _now;
  final Duration requestTimeout;

  @override
  bool get isConfigured => _validatedBaseUri != null && _hasValidToken;

  @override
  Future<AuthoritativeEntitlementSnapshot> fetch() async {
    if (!isConfigured) {
      throw const EntitlementReconciliationException(
        'Authenticated entitlement reconciliation is not configured.',
      );
    }

    final abort = Completer<void>();
    final request =
        http.AbortableRequest(
            'GET',
            _uri('/billing/entitlements'),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll({
            'Accept': 'application/json',
            'Authorization': 'Bearer $_apiToken',
            'Cache-Control': 'no-store',
          });

    try {
      return await _sendAndParse(request).timeout(
        requestTimeout,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException(
            'Entitlement reconciliation timed out.',
            requestTimeout,
          );
        },
      );
    } on EntitlementReconciliationException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on FormatException catch (error) {
      throw EntitlementReconciliationException(error.message.toString());
    } on http.ClientException {
      rethrow;
    } catch (_) {
      throw const EntitlementReconciliationException(
        'Entitlement reconciliation failed.',
      );
    }
  }

  Future<AuthoritativeEntitlementSnapshot> _sendAndParse(
    http.AbortableRequest request,
  ) async {
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _cancelResponse(response);
      throw EntitlementReconciliationException(
        'Entitlement server returned ${response.statusCode}.',
      );
    }
    if (response.contentLength != null &&
        response.contentLength! > _maximumResponseBytes) {
      await _cancelResponse(response);
      throw const EntitlementReconciliationException(
        'Entitlement response is too large.',
      );
    }

    final body = BytesBuilder(copy: false);
    var byteCount = 0;
    await for (final chunk in response.stream) {
      byteCount += chunk.length;
      if (byteCount > _maximumResponseBytes) {
        throw const EntitlementReconciliationException(
          'Entitlement response is too large.',
        );
      }
      body.add(chunk);
    }

    final decoded = jsonDecode(utf8.decode(body.takeBytes()));
    if (decoded is! Map ||
        decoded.length != 2 ||
        decoded['status'] != 'ok' ||
        !decoded.containsKey('snapshot')) {
      throw const EntitlementReconciliationException(
        'Entitlement response is invalid.',
      );
    }
    return _parseSnapshot(decoded['snapshot']);
  }

  AuthoritativeEntitlementSnapshot _parseSnapshot(Object? value) {
    if (value is! Map ||
        value.length != 3 ||
        !value.containsKey('revision') ||
        !value.containsKey('generatedAt') ||
        !value.containsKey('vipUntil')) {
      throw const EntitlementReconciliationException(
        'Entitlement snapshot is invalid.',
      );
    }
    final revision = value['revision'];
    final generatedAt = _parseUtcTimestamp(value['generatedAt']);
    final vipValue = value['vipUntil'];
    final vipUntil = vipValue == null ? null : _parseUtcTimestamp(vipValue);
    if (revision is! int ||
        revision <= 0 ||
        revision > maximumEntitlementRevision ||
        generatedAt == null ||
        (vipValue != null && vipUntil == null)) {
      throw const EntitlementReconciliationException(
        'Entitlement snapshot is invalid.',
      );
    }

    final now = _now().toUtc();
    if (generatedAt.isBefore(now.subtract(const Duration(hours: 1))) ||
        generatedAt.isAfter(now.add(const Duration(minutes: 5))) ||
        (vipUntil != null &&
            (!vipUntil.isAfter(now) ||
                !vipUntil.isAfter(generatedAt) ||
                vipUntil.isAfter(
                  generatedAt.add(maximumVerifiedVipHorizon),
                )))) {
      throw const EntitlementReconciliationException(
        'Entitlement snapshot timestamps are invalid.',
      );
    }
    return AuthoritativeEntitlementSnapshot(
      revision: revision,
      generatedAt: generatedAt,
      vipUntil: vipUntil,
    );
  }

  DateTime? _parseUtcTimestamp(Object? value) {
    if (value is! String || value.length > 64) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{3})?Z$',
    ).firstMatch(value);
    if (match == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        !parsed.isUtc ||
        parsed.year != int.parse(match.group(1)!) ||
        parsed.month != int.parse(match.group(2)!) ||
        parsed.day != int.parse(match.group(3)!) ||
        parsed.hour != int.parse(match.group(4)!) ||
        parsed.minute != int.parse(match.group(5)!) ||
        parsed.second != int.parse(match.group(6)!)) {
      return null;
    }
    return parsed;
  }

  bool get _hasValidToken =>
      _apiToken.isNotEmpty &&
      _apiToken.length <= 4096 &&
      !RegExp(r'[\u0000-\u001F\u007F]').hasMatch(_apiToken);

  Uri? get _validatedBaseUri {
    final base = Uri.tryParse(_endpoint);
    if (base == null ||
        base.scheme != 'https' ||
        !base.hasAuthority ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      return null;
    }
    return base;
  }

  Uri _uri(String path) {
    final base = _validatedBaseUri;
    if (base == null) {
      throw const EntitlementReconciliationException(
        'Entitlement endpoint is invalid.',
      );
    }
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$prefix$path');
  }

  Future<void> _cancelResponse(http.StreamedResponse response) async {
    final subscription = response.stream.listen((_) {});
    await subscription.cancel();
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}

enum EntitlementSyncStatus { idle, syncing, synced, unavailable, error }

class EntitlementReconciliationService extends ChangeNotifier
    with WidgetsBindingObserver {
  EntitlementReconciliationService(
    this._settings, {
    EntitlementSnapshotSource? source,
    this.refreshInterval = const Duration(minutes: 15),
  }) : assert(refreshInterval > Duration.zero),
       _source = source ?? HttpEntitlementSnapshotSource(),
       _ownsSource = source == null;

  final SettingsService _settings;
  final EntitlementSnapshotSource _source;
  final bool _ownsSource;
  final Duration refreshInterval;

  EntitlementSyncStatus _status = EntitlementSyncStatus.idle;
  Object? _lastError;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _started = false;
  bool _disposed = false;
  VoidCallback? onEntitlementsChanged;

  EntitlementSyncStatus get status => _status;
  Object? get lastError => _lastError;
  bool get isConfigured => _source.isConfigured;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _schedule();
    await refresh();
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final current = _inFlight;
    if (current != null) return current;
    if (!_source.isConfigured) {
      _status = EntitlementSyncStatus.unavailable;
      _lastError = null;
      _notify();
      return Future<void>.value();
    }

    final operation = _refreshOnce();
    _inFlight = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
  }

  Future<void> _refreshOnce() async {
    _status = EntitlementSyncStatus.syncing;
    _lastError = null;
    _notify();
    try {
      final snapshot = await _source.fetch();
      if (_disposed) return;
      await _settings.reconcileEntitlements(snapshot);
      if (_disposed) return;
      try {
        onEntitlementsChanged?.call();
      } catch (_) {
        // The snapshot is already durable; a view observer cannot roll it back.
      }
      _status = EntitlementSyncStatus.synced;
    } catch (error) {
      _lastError = error;
      _status = EntitlementSyncStatus.error;
    }
    _notify();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(refreshInterval, (_) {
      unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedule();
      unawaited(refresh());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    onEntitlementsChanged = null;
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    if (_ownsSource) _source.close();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CommunityRoom {
  const CommunityRoom({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.memberCount,
    required this.languageCodes,
    required this.accentColor,
  });

  final String id;
  final String title;
  final String subtitle;
  final String emoji;
  final int memberCount;
  final List<String> languageCodes;
  final int accentColor;
}

class WorldMember {
  const WorldMember({
    required this.id,
    required this.name,
    required this.city,
    required this.country,
    required this.languageCode,
    required this.avatarSeed,
    this.isVip = false,
    this.isOnline = false,
  });

  final String id;
  final String name;
  final String city;
  final String country;
  final String languageCode;
  final int avatarSeed;
  final bool isVip;
  final bool isOnline;
}

class OnlineService extends ChangeNotifier {
  OnlineService({
    Connectivity? connectivity,
    http.Client? client,
    String? endpoint,
    String? apiToken,
  }) : _connectivity = connectivity ?? Connectivity(),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _endpoint = (endpoint ?? _configuredEndpoint).trim().replaceFirst(
         RegExp(r'/+$'),
         '',
       ),
       _apiToken = (apiToken ?? _configuredApiToken).trim();

  static const _configuredEndpoint = String.fromEnvironment(
    'GLOBOVERSE_DISCOVERY_API_URL',
  );
  static const _configuredApiToken = String.fromEnvironment(
    'GLOBOVERSE_API_TOKEN',
  );
  static const _requestTimeout = Duration(seconds: 15);
  static const _maximumResponseBytes = 1024 * 1024;
  static const _maximumRooms = 50;
  static const _maximumMembers = 100;
  static const _maximumOnlineCount = 10000000;
  static const _maximumAvatarSeed = 1000000000;

  final Connectivity _connectivity;
  final http.Client _client;
  final bool _ownsClient;
  final String _endpoint;
  final String _apiToken;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  List<CommunityRoom> _rooms = _previewRooms;
  List<WorldMember> _members = _previewMembers;
  int _onlineCount = 0;
  bool _isConnected = true;
  bool _isInitialized = false;
  bool _isRefreshing = false;
  bool _isPreviewCatalog = true;
  bool _isDisposed = false;
  int _refreshGeneration = 0;
  String? _discoveryError;
  DateTime? _lastRefreshedAt;

  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;
  bool get isRefreshing => _isRefreshing;
  bool get isPreviewCatalog => _isPreviewCatalog;
  bool get hasRemoteDiscovery => _endpoint.isNotEmpty;
  String? get discoveryError => _discoveryError;
  DateTime? get lastRefreshedAt => _lastRefreshedAt;
  int get onlineCount => _isConnected ? _onlineCount : 0;
  List<CommunityRoom> get rooms => List.unmodifiable(_rooms);
  List<WorldMember> get members => List.unmodifiable(_members);

  Future<void> connect() async {
    if (_isDisposed) return;
    _subscription ??= _connectivity.onConnectivityChanged.listen(
      _handleConnectivityResults,
    );
    try {
      final results = await _connectivity.checkConnectivity();
      if (_isDisposed) return;
      _setConnectivity(results, refreshRemote: false);
    } catch (_) {
      if (_isDisposed) return;
      _isConnected = false;
    }
    _isInitialized = true;
    _notify();

    if (_isConnected && hasRemoteDiscovery) {
      await refreshDiscovery();
    }
  }

  Future<void> refresh() async {
    if (_isDisposed) return;
    if (!_isInitialized) {
      await connect();
      return;
    }
    if (hasRemoteDiscovery) await refreshDiscovery();
  }

  Future<bool> refreshDiscovery() async {
    if (!hasRemoteDiscovery) return true;
    if (!_isConnected || _isRefreshing || _isDisposed) return false;

    final generation = ++_refreshGeneration;
    _isRefreshing = true;
    _discoveryError = null;
    _notify();

    try {
      final payload = await _fetchDiscovery().timeout(_requestTimeout);
      final onlineCount = _parseOnlineCount(payload['onlineCount']);
      final rooms = _parseRooms(payload['rooms']);
      final members = _parseMembers(payload['members']);
      if (!_ownsRefresh(generation)) return false;

      _onlineCount = onlineCount;
      _rooms = List.unmodifiable(rooms);
      _members = List.unmodifiable(members);
      _isPreviewCatalog = false;
      _lastRefreshedAt = DateTime.now();
      _discoveryError = null;
      return true;
    } catch (error) {
      if (_ownsRefresh(generation)) {
        _discoveryError = _friendlyError(error);
      }
      return false;
    } finally {
      if (_ownsRefresh(generation)) {
        _isRefreshing = false;
        _notify();
      }
    }
  }

  void _handleConnectivityResults(List<ConnectivityResult> results) {
    _setConnectivity(results);
  }

  void _setConnectivity(
    List<ConnectivityResult> results, {
    bool refreshRemote = true,
  }) {
    if (_isDisposed) return;
    final next =
        results.isNotEmpty &&
        results.any((result) => result != ConnectivityResult.none);
    if (next == _isConnected && _isInitialized) return;
    _isConnected = next;
    _notify();
    if (next && refreshRemote && hasRemoteDiscovery) {
      unawaited(refreshDiscovery());
    }
  }

  int _parseOnlineCount(Object? value) {
    if (value is! int || value < 0 || value > _maximumOnlineCount) {
      throw const FormatException('Discovery online count is invalid.');
    }
    return value;
  }

  List<CommunityRoom> _parseRooms(Object? value) {
    if (value is! List) {
      throw const FormatException('Discovery rooms are missing.');
    }
    final rooms = <CommunityRoom>[];
    final ids = <String>{};
    for (final entry in value) {
      if (rooms.length >= _maximumRooms) break;
      final room = _parseRoom(entry);
      if (room != null && ids.add(room.id)) rooms.add(room);
    }
    if (value.isNotEmpty && rooms.isEmpty) {
      throw const FormatException('Discovery contains no valid rooms.');
    }
    return rooms;
  }

  CommunityRoom? _parseRoom(Object? value) {
    if (value is! Map) return null;
    final id = _parseId(value['id']);
    final title = _cleanString(value['title'], maximumLength: 120);
    final subtitle = _cleanString(value['subtitle'], maximumLength: 240);
    final emoji = _cleanString(value['emoji'], maximumLength: 16);
    final memberCount = value['memberCount'];
    final languageCodes = _parseLanguageCodes(value['languageCodes']);
    final accentColor = _parseColor(value['accentColor']);
    if (id == null ||
        title == null ||
        subtitle == null ||
        emoji == null ||
        memberCount is! int ||
        memberCount < 0 ||
        memberCount > _maximumOnlineCount ||
        languageCodes == null ||
        accentColor == null) {
      return null;
    }
    return CommunityRoom(
      id: id,
      title: title,
      subtitle: subtitle,
      emoji: emoji,
      memberCount: memberCount,
      languageCodes: List.unmodifiable(languageCodes),
      accentColor: accentColor,
    );
  }

  List<WorldMember> _parseMembers(Object? value) {
    if (value is! List) {
      throw const FormatException('Discovery members are missing.');
    }
    final members = <WorldMember>[];
    final ids = <String>{};
    for (final entry in value) {
      if (members.length >= _maximumMembers) break;
      final member = _parseMember(entry);
      if (member != null && ids.add(member.id)) members.add(member);
    }
    if (value.isNotEmpty && members.isEmpty) {
      throw const FormatException('Discovery contains no valid members.');
    }
    return members;
  }

  WorldMember? _parseMember(Object? value) {
    if (value is! Map) return null;
    final id = _parseId(value['id']);
    final name = _cleanString(value['name'], maximumLength: 100);
    final city = _cleanString(value['city'], maximumLength: 120);
    final country = _cleanString(value['country'], maximumLength: 120);
    final languageCode = _parseLanguageCode(value['languageCode']);
    if (id == null ||
        name == null ||
        city == null ||
        country == null ||
        languageCode == null) {
      return null;
    }
    final avatarValue = value['avatarSeed'];
    var avatarSeed = _stableSeed(id);
    if (avatarValue is int && avatarValue >= 0) {
      avatarSeed = avatarValue > _maximumAvatarSeed
          ? _maximumAvatarSeed
          : avatarValue;
    }
    final isVipValue = value['isVip'];
    final isOnlineValue = value['isOnline'];
    if (isOnlineValue is! bool) return null;
    return WorldMember(
      id: id,
      name: name,
      city: city,
      country: country,
      languageCode: languageCode,
      avatarSeed: avatarSeed,
      isVip: isVipValue is bool && isVipValue,
      isOnline: isOnlineValue,
    );
  }

  List<String>? _parseLanguageCodes(Object? value) {
    if (value is! List || value.isEmpty) return null;
    final codes = <String>[];
    for (final entry in value) {
      final code = _parseLanguageCode(entry);
      if (code == null) return null;
      if (!codes.contains(code)) codes.add(code);
      if (codes.length >= 10) break;
    }
    return codes.isEmpty ? null : codes;
  }

  String? _parseLanguageCode(Object? value) {
    if (value is! String) return null;
    final code = value.trim().toLowerCase().replaceAll('_', '-');
    return RegExp(r'^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$').hasMatch(code)
        ? code
        : null;
  }

  int? _parseColor(Object? value) {
    if (value is int) {
      if (value < 0 || value > 0xFFFFFFFF) return null;
      return value <= 0xFFFFFF ? 0xFF000000 | value : value;
    }
    if (value is! String) return null;
    var hex = value.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    return int.tryParse(hex, radix: 16);
  }

  String? _parseId(Object? value) {
    final id = _cleanString(value, maximumLength: 100);
    if (id == null ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$').hasMatch(id)) {
      return null;
    }
    return id;
  }

  String? _cleanString(Object? value, {required int maximumLength}) {
    if (value is! String) return null;
    final clean = value.trim();
    if (clean.isEmpty ||
        clean.length > maximumLength ||
        RegExp(r'[\u0000-\u001F\u007F]').hasMatch(clean) ||
        RegExp(r'[\u202A-\u202E\u2066-\u2069]').hasMatch(clean)) {
      return null;
    }
    return clean;
  }

  int _stableSeed(String value) {
    var seed = 0;
    for (final codeUnit in value.codeUnits) {
      seed = (seed * 31 + codeUnit) & 0x7FFFFFFF;
    }
    return seed;
  }

  Uri _uri(String path) {
    final base = Uri.tryParse(_endpoint);
    if (base == null ||
        !base.hasScheme ||
        !base.hasAuthority ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.scheme != 'https' && base.scheme != 'http')) {
      throw const FormatException('Discovery API URL is invalid.');
    }
    return Uri.parse('$_endpoint$path');
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (_apiToken.isNotEmpty) 'Authorization': 'Bearer $_apiToken',
  };

  Future<Map<String, dynamic>> _fetchDiscovery() async {
    final request = http.Request('GET', _uri('/discovery'))
      ..followRedirects = false
      ..headers.addAll(_headers);
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final subscription = response.stream.listen((_) {});
      await subscription.cancel();
      throw http.ClientException(
        'Discovery server returned ${response.statusCode}.',
        request.url,
      );
    }
    if (response.contentLength != null &&
        response.contentLength! > _maximumResponseBytes) {
      final subscription = response.stream.listen((_) {});
      await subscription.cancel();
      throw const FormatException('Discovery response is too large.');
    }

    final body = BytesBuilder(copy: false);
    var byteCount = 0;
    await for (final chunk in response.stream) {
      byteCount += chunk.length;
      if (byteCount > _maximumResponseBytes) {
        throw const FormatException('Discovery response is too large.');
      }
      body.add(chunk);
    }
    final decoded = jsonDecode(utf8.decode(body.takeBytes()));
    if (decoded is! Map) {
      throw const FormatException('Invalid discovery response.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  bool _ownsRefresh(int generation) {
    return !_isDisposed && generation == _refreshGeneration;
  }

  String _friendlyError(Object error) {
    if (error is TimeoutException) return 'Discovery request timed out.';
    if (error is FormatException) return error.message.toString();
    if (error is http.ClientException) return error.message;
    return 'Discovery request failed.';
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _refreshGeneration += 1;
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    if (_ownsClient) _client.close();
    super.dispose();
  }
}

const _previewRooms = <CommunityRoom>[
  CommunityRoom(
    id: 'coffee-world',
    title: 'Coffee around the world',
    subtitle: 'Sample room · Everyone welcome',
    emoji: '☕',
    memberCount: 0,
    languageCodes: ['en', 'es', 'fr'],
    accentColor: 0xFFFFA45B,
  ),
  CommunityRoom(
    id: 'central-asia',
    title: 'Central Asia lounge',
    subtitle: 'Sample room · Culture and travel',
    emoji: '🏔️',
    memberCount: 0,
    languageCodes: ['tg', 'uz', 'ru'],
    accentColor: 0xFF5CC8FF,
  ),
  CommunityRoom(
    id: 'language-swap',
    title: 'Language exchange',
    subtitle: 'Sample room · Practice kindly',
    emoji: '💬',
    memberCount: 0,
    languageCodes: ['en', 'de', 'ja'],
    accentColor: 0xFFA68BFF,
  ),
  CommunityRoom(
    id: 'night-owls',
    title: 'Night owls',
    subtitle: 'Sample room · Slow chats',
    emoji: '🌙',
    memberCount: 0,
    languageCodes: ['en', 'ar', 'hi'],
    accentColor: 0xFF6F7DFF,
  ),
];

const _previewMembers = <WorldMember>[
  WorldMember(
    id: 'amina-dushanbe',
    name: 'Amina',
    city: 'Dushanbe',
    country: 'Tajikistan',
    languageCode: 'tg',
    avatarSeed: 0,
    isVip: true,
  ),
  WorldMember(
    id: 'sofia-barcelona',
    name: 'Sofia',
    city: 'Barcelona',
    country: 'Spain',
    languageCode: 'es',
    avatarSeed: 1,
  ),
  WorldMember(
    id: 'haruto-kyoto',
    name: 'Haruto',
    city: 'Kyoto',
    country: 'Japan',
    languageCode: 'ja',
    avatarSeed: 2,
  ),
  WorldMember(
    id: 'malik-casablanca',
    name: 'Malik',
    city: 'Casablanca',
    country: 'Morocco',
    languageCode: 'ar',
    avatarSeed: 3,
  ),
  WorldMember(
    id: 'zarina-samarkand',
    name: 'Zarina',
    city: 'Samarkand',
    country: 'Uzbekistan',
    languageCode: 'uz',
    avatarSeed: 4,
  ),
];

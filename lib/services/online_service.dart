import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

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
    required this.name,
    required this.city,
    required this.country,
    required this.languageCode,
    required this.avatarSeed,
    this.isVip = false,
  });

  final String name;
  final String city;
  final String country;
  final String languageCode;
  final int avatarSeed;
  final bool isVip;
}

class OnlineService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isConnected = true;
  bool _isInitialized = false;

  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;
  int get onlineCount => _isConnected ? 1284 : 0;

  List<CommunityRoom> get rooms => const [
    CommunityRoom(
      id: 'coffee-world',
      title: 'Coffee around the world',
      subtitle: 'Easy conversation · Everyone welcome',
      emoji: '☕',
      memberCount: 248,
      languageCodes: ['en', 'es', 'fr'],
      accentColor: 0xFFFFA45B,
    ),
    CommunityRoom(
      id: 'central-asia',
      title: 'Central Asia lounge',
      subtitle: 'Culture, travel & new friends',
      emoji: '🏔️',
      memberCount: 186,
      languageCodes: ['tg', 'uz', 'ru'],
      accentColor: 0xFF5CC8FF,
    ),
    CommunityRoom(
      id: 'language-swap',
      title: 'Language exchange',
      subtitle: 'Practice kindly · All levels',
      emoji: '💬',
      memberCount: 421,
      languageCodes: ['en', 'de', 'ja'],
      accentColor: 0xFFA68BFF,
    ),
    CommunityRoom(
      id: 'night-owls',
      title: 'Night owls',
      subtitle: 'Slow chats from every timezone',
      emoji: '🌙',
      memberCount: 97,
      languageCodes: ['en', 'ar', 'hi'],
      accentColor: 0xFF6F7DFF,
    ),
  ];

  List<WorldMember> get members => const [
    WorldMember(
      name: 'Amina',
      city: 'Dushanbe',
      country: 'Tajikistan',
      languageCode: 'tg',
      avatarSeed: 0,
      isVip: true,
    ),
    WorldMember(
      name: 'Sofia',
      city: 'Barcelona',
      country: 'Spain',
      languageCode: 'es',
      avatarSeed: 1,
    ),
    WorldMember(
      name: 'Haruto',
      city: 'Kyoto',
      country: 'Japan',
      languageCode: 'ja',
      avatarSeed: 2,
    ),
    WorldMember(
      name: 'Malik',
      city: 'Casablanca',
      country: 'Morocco',
      languageCode: 'ar',
      avatarSeed: 3,
    ),
    WorldMember(
      name: 'Zarina',
      city: 'Samarkand',
      country: 'Uzbekistan',
      languageCode: 'uz',
      avatarSeed: 4,
    ),
  ];

  Future<void> connect() async {
    _subscription ??= _connectivity.onConnectivityChanged.listen(_updateStatus);
    try {
      _updateStatus(await _connectivity.checkConnectivity());
    } catch (_) {
      _isConnected = false;
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> refresh() => connect();

  void _updateStatus(List<ConnectivityResult> results) {
    final next =
        results.isNotEmpty &&
        results.any((result) => result != ConnectivityResult.none);
    if (next == _isConnected && _isInitialized) return;
    _isConnected = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

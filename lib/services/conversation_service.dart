import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../models/conversation_message.dart';
import 'online_service.dart';
import 'translation_service.dart';

enum ConversationStatus { idle, connecting, active, ended, error }

class ConversationService extends ChangeNotifier with WidgetsBindingObserver {
  ConversationService(
    this._translation,
    this._online, {
    http.Client? client,
    String? endpoint,
    String? apiToken,
    this.previewConnectDelay = const Duration(milliseconds: 420),
    this.previewReplyDelay = const Duration(milliseconds: 620),
    this.pollInterval = const Duration(seconds: 4),
    this.maximumPollInterval = const Duration(seconds: 30),
    this.automaticPolling = true,
  }) : assert(pollInterval > Duration.zero),
       assert(maximumPollInterval >= pollInterval),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _endpoint = (endpoint ?? _configuredEndpoint).trim().replaceFirst(
         RegExp(r'/+$'),
         '',
       ),
       _apiToken = (apiToken ?? _configuredApiToken).trim() {
    _online.addListener(_handleConnectivityChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  static const _configuredEndpoint = String.fromEnvironment(
    'GLOBOVERSE_CHAT_API_URL',
  );
  static const _configuredApiToken = String.fromEnvironment(
    'GLOBOVERSE_API_TOKEN',
  );
  static const _requestTimeout = Duration(seconds: 20);
  static const _endTimeout = Duration(seconds: 8);
  static const _maximumMessageLength = 600;
  static const _maximumServerTextLength = 4000;
  static const _maximumIdentifierLength = 200;
  static const _maximumResponseBytes = 1024 * 1024;
  static const _maximumMessagesPerResponse = 50;
  static const _maximumReceiptsPerResponse = 100;
  static const _maximumCursorLength = 500;
  static const _maximumReadBatch = 100;
  static const _reportReasons = {
    'harassment',
    'spam',
    'unsafe_content',
    'other',
  };

  final TranslationService _translation;
  final OnlineService _online;
  final http.Client _client;
  final bool _ownsClient;
  final String _endpoint;
  final String _apiToken;
  final Duration previewConnectDelay;
  final Duration previewReplyDelay;
  final Duration pollInterval;
  final Duration maximumPollInterval;
  final bool automaticPolling;

  ConversationStatus _status = ConversationStatus.idle;
  final List<ConversationMessage> _messages = [];
  final Set<String> _acknowledgedReadIds = {};
  final Set<String> _pendingReadIds = {};
  Timer? _pollTimer;
  String? _sessionId;
  String? _cursor;
  String? _error;
  String? _syncError;
  DateTime? _lastSyncedAt;
  String _peerName = 'GloboGuide';
  String _sourceLanguage = 'en';
  String _targetLanguage = 'en';
  int _messageSequence = 0;
  int _generation = 0;
  int _syncFailures = 0;
  bool _isStarting = false;
  bool _isSending = false;
  bool _isSyncing = false;
  bool _isAcknowledgingRead = false;
  bool _isReporting = false;
  bool _isReported = false;
  bool _isForeground = true;
  bool _isDisposed = false;

  ConversationStatus get status => _status;
  List<ConversationMessage> get messages => List.unmodifiable(_messages);
  String? get sessionId => _sessionId;
  String? get error => _error;
  String? get syncError => _syncError;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String get peerName => _peerName;
  String get sourceLanguage => _sourceLanguage;
  String get targetLanguage => _targetLanguage;
  bool get isStarting => _isStarting;
  bool get isSending => _isSending;
  bool get isSyncing => _isSyncing;
  bool get isReporting => _isReporting;
  bool get isReported => _isReported;
  bool get isPreviewMode => _endpoint.isEmpty;
  bool get isActive => _status == ConversationStatus.active;
  bool get isReconnecting =>
      isActive && !isPreviewMode && (!_online.isConnected || _syncFailures > 0);

  Future<bool> start({
    required String sourceLanguage,
    required String targetLanguage,
    CommunityRoom? room,
    WorldMember? member,
    String fallbackPeerName = 'Conversation',
  }) {
    if (_isDisposed || _isStarting) return Future<bool>.value(false);
    _isStarting = true;
    notifyListeners();
    return _startConversation(
      room: room,
      member: member,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      fallbackPeerName: fallbackPeerName,
    ).whenComplete(() {
      if (_isDisposed) return;
      _isStarting = false;
      notifyListeners();
    });
  }

  Future<bool> _startConversation({
    required String sourceLanguage,
    required String targetLanguage,
    required String fallbackPeerName,
    CommunityRoom? room,
    WorldMember? member,
  }) async {
    await end(notify: false);
    if (_isDisposed) return false;

    final generation = ++_generation;
    _messages.clear();
    _acknowledgedReadIds.clear();
    _pendingReadIds.clear();
    _messageSequence = 0;
    _cursor = null;
    _error = null;
    _syncError = null;
    _lastSyncedAt = null;
    _syncFailures = 0;
    _isReported = false;
    _isReporting = false;
    _isSending = false;
    _isSyncing = false;
    _isAcknowledgingRead = false;
    _sourceLanguage = _languageOrFallback(sourceLanguage, 'en');
    _targetLanguage = _languageOrFallback(targetLanguage, 'en');
    final cleanFallbackName = fallbackPeerName.trim();
    _peerName =
        member?.name ??
        room?.title ??
        (cleanFallbackName.isEmpty || cleanFallbackName.length > 100
            ? 'Conversation'
            : cleanFallbackName);
    _status = ConversationStatus.connecting;
    notifyListeners();

    if (isPreviewMode) {
      await Future<void>.delayed(previewConnectDelay);
      if (!_ownsGeneration(generation) ||
          _status != ConversationStatus.connecting) {
        return false;
      }
      _peerName = 'GloboGuide';
      _sessionId = 'preview-${DateTime.now().microsecondsSinceEpoch}';
      _status = ConversationStatus.active;
      notifyListeners();
      return true;
    }

    if (!_online.isConnected) {
      _failStart(generation, 'No network connection.');
      return false;
    }

    try {
      final response = await _client
          .post(
            _uri('/sessions'),
            headers: _headers,
            body: jsonEncode({
              'sourceLanguage': _sourceLanguage,
              'targetLanguage': _targetLanguage,
              if (room != null) 'roomId': room.id,
              if (member != null) 'peerId': member.id,
            }),
          )
          .timeout(_requestTimeout);
      final payload = _decodeResponse(response);
      final sessionId = _requiredIdentifier(
        payload['id'] ?? payload['sessionId'],
        'Conversation session ID',
      );
      final peerName = _readPeerName(payload) ?? _peerName;
      final cursor = _cursorFromPayload(payload);
      final initialMessages = await _translateIncoming(
        _messagesFromPayload(payload),
        generation,
      );

      if (!_ownsGeneration(generation) ||
          _status != ConversationStatus.connecting) {
        return false;
      }
      _sessionId = sessionId;
      _peerName = peerName;
      _cursor = cursor;
      _messages.addAll(initialMessages);
      _applyReceipts(payload);
      _lastSyncedAt = DateTime.now();
      _status = ConversationStatus.active;
      _schedulePoll(generation);
      notifyListeners();
      return true;
    } catch (error) {
      _failStart(generation, _friendlyError(error));
      return false;
    }
  }

  Future<bool> send(String value) async {
    final text = value.trim();
    if (text.isEmpty || text.length > _maximumMessageLength) return false;
    return _submit(text);
  }

  Future<bool> retry(String messageId) async {
    if (!isActive || _isSending) return false;
    final index = _messages.indexWhere(
      (message) =>
          message.id == messageId &&
          message.isMine &&
          message.deliveryState == MessageDeliveryState.failed,
    );
    if (index < 0) return false;
    return _submit(_messages[index].text, retryMessage: _messages[index]);
  }

  Future<bool> syncNow() async {
    final generation = _generation;
    final sessionId = _sessionId;
    if (sessionId == null || !_canPoll(generation) || _isSyncing) {
      return false;
    }

    _pollTimer?.cancel();
    _pollTimer = null;
    _isSyncing = true;
    notifyListeners();

    try {
      final response = await _client
          .get(_messagesUri(sessionId), headers: _headers)
          .timeout(_requestTimeout);
      final payload = _decodeResponse(response);
      final received = await _translateIncoming(
        _messagesFromPayload(payload),
        generation,
      );
      if (!_canPoll(generation)) return false;

      _cursor = _cursorFromPayload(payload, fallback: _cursor);
      _appendUnique(received);
      _applyReceipts(payload);
      _syncFailures = 0;
      _syncError = null;
      _lastSyncedAt = DateTime.now();
      return true;
    } catch (error) {
      if (_canPoll(generation)) {
        _syncFailures += 1;
        _syncError = _friendlyError(error);
      }
      return false;
    } finally {
      if (_ownsGeneration(generation)) {
        _isSyncing = false;
        _schedulePoll(generation);
        notifyListeners();
      }
    }
  }

  Future<bool> markIncomingRead() async {
    if (!isActive || _sessionId == null) return false;
    for (final message in _messages) {
      if (message.sender == ConversationMessageSender.peer &&
          !_acknowledgedReadIds.contains(message.id)) {
        _pendingReadIds.add(message.id);
      }
    }
    if (_pendingReadIds.isEmpty) return true;

    if (isPreviewMode) {
      _acknowledgedReadIds.addAll(_pendingReadIds);
      _pendingReadIds.clear();
      return true;
    }
    if (!_online.isConnected || !_isForeground) return false;
    if (_isAcknowledgingRead) return true;

    final generation = _generation;
    final sessionId = _sessionId;
    if (sessionId == null) return false;
    _isAcknowledgingRead = true;
    try {
      while (_pendingReadIds.isNotEmpty && _isCurrentSession(generation)) {
        final batch = _pendingReadIds.take(_maximumReadBatch).toList();
        final response = await _client
            .post(
              _uri('/sessions/${Uri.encodeComponent(sessionId)}/read'),
              headers: _headers,
              body: jsonEncode({
                'messageIds': batch,
                'readAt': DateTime.now().toUtc().toIso8601String(),
              }),
            )
            .timeout(_requestTimeout);
        _ensureSuccess(response);
        if (!_isCurrentSession(generation)) return false;
        _acknowledgedReadIds.addAll(batch);
        _pendingReadIds.removeAll(batch);
      }
      return _pendingReadIds.isEmpty;
    } catch (_) {
      return false;
    } finally {
      if (_ownsGeneration(generation)) _isAcknowledgingRead = false;
    }
  }

  Future<bool> reportCurrent(String reason) async {
    final sessionId = _sessionId;
    if (sessionId == null ||
        !isActive ||
        _isReporting ||
        _isReported ||
        !_reportReasons.contains(reason)) {
      return false;
    }

    final generation = _generation;
    _isReporting = true;
    _error = null;
    notifyListeners();

    try {
      if (!isPreviewMode) {
        final response = await _client
            .post(
              _uri('/sessions/${Uri.encodeComponent(sessionId)}/reports'),
              headers: _headers,
              body: jsonEncode({
                'reason': reason,
                'reportedAt': DateTime.now().toUtc().toIso8601String(),
              }),
            )
            .timeout(_requestTimeout);
        _ensureSuccess(response);
      }

      if (!_isCurrentSession(generation)) return false;
      _isReported = true;
      return true;
    } catch (error) {
      if (_ownsGeneration(generation)) {
        _error = _friendlyError(error);
      }
      return false;
    } finally {
      if (_ownsGeneration(generation)) {
        _isReporting = false;
        notifyListeners();
      }
    }
  }

  Future<void> end({bool notify = true}) async {
    final sessionId = _sessionId;
    final shouldDelete = sessionId != null && !isPreviewMode;
    _generation += 1;
    _pollTimer?.cancel();
    _pollTimer = null;
    _sessionId = null;
    _cursor = null;
    _syncError = null;
    _lastSyncedAt = null;
    _syncFailures = 0;
    _isSending = false;
    _isSyncing = false;
    _isAcknowledgingRead = false;
    _isReporting = false;
    _messages.clear();
    _acknowledgedReadIds.clear();
    _pendingReadIds.clear();

    if (_status != ConversationStatus.idle) {
      _status = ConversationStatus.ended;
    }
    if (notify && !_isDisposed) notifyListeners();

    if (!shouldDelete || sessionId == null) return;
    try {
      final response = await _client
          .delete(
            _uri('/sessions/${Uri.encodeComponent(sessionId)}'),
            headers: _headers,
          )
          .timeout(_endTimeout);
      _ensureSuccess(response);
    } catch (_) {
      // Ending locally must never trap a user in the conversation UI.
    }
  }

  Future<bool> _submit(String text, {ConversationMessage? retryMessage}) async {
    if (!isActive || _isSending || _sessionId == null) return false;

    final generation = _generation;
    _isSending = true;
    _error = null;
    var pendingMessage =
        retryMessage?.copyWith(deliveryState: MessageDeliveryState.sending) ??
        ConversationMessage(
          id: _nextMessageId('me'),
          sender: ConversationMessageSender.me,
          text: text,
          sourceLanguage: _sourceLanguage,
          targetLanguage: _targetLanguage,
          timestamp: DateTime.now(),
          deliveryState: MessageDeliveryState.sending,
        );
    if (retryMessage == null) {
      _messages.add(pendingMessage);
    } else {
      _replaceMessage(pendingMessage);
    }
    notifyListeners();

    try {
      final translation = isPreviewMode
          ? _translation.translateOffline(
              text: text,
              sourceLanguage: _sourceLanguage,
              targetLanguage: _targetLanguage,
            )
          : await _translation.translate(
              text: text,
              sourceLanguage: _sourceLanguage,
              targetLanguage: _targetLanguage,
            );
      if (translation == null) {
        throw StateError('Translation is temporarily unavailable.');
      }
      if (!_isCurrentSession(generation)) return false;

      pendingMessage = pendingMessage.copyWith(
        translatedText: translation.text,
      );
      _replaceMessage(pendingMessage);
      notifyListeners();

      if (isPreviewMode) {
        _replaceMessage(
          pendingMessage.copyWith(deliveryState: MessageDeliveryState.sent),
        );
        notifyListeners();
        await _addPreviewReply(text, generation);
      } else {
        final sessionId = _sessionId;
        if (sessionId == null) return false;
        final response = await _client
            .post(
              _uri('/sessions/${Uri.encodeComponent(sessionId)}/messages'),
              headers: _headers,
              body: jsonEncode({
                'id': pendingMessage.id,
                'text': pendingMessage.text,
                'translatedText': translation.text,
                'sourceLanguage': pendingMessage.sourceLanguage,
                'targetLanguage': pendingMessage.targetLanguage,
                'timestamp': pendingMessage.timestamp.toUtc().toIso8601String(),
              }),
            )
            .timeout(_requestTimeout);
        final payload = _decodeResponse(response);
        final received = await _translateIncoming(
          _messagesFromPayload(payload),
          generation,
        );
        if (!_isCurrentSession(generation)) return false;

        _replaceMessage(
          pendingMessage.copyWith(deliveryState: MessageDeliveryState.sent),
        );
        _appendUnique(received);
        _applyReceipts(payload);
        _schedulePoll(generation, delay: Duration.zero);
        notifyListeners();
      }
      return true;
    } catch (error) {
      if (_isCurrentSession(generation)) {
        _replaceMessage(
          pendingMessage.copyWith(deliveryState: MessageDeliveryState.failed),
        );
        _error = _friendlyError(error);
        notifyListeners();
      }
      return false;
    } finally {
      if (_ownsGeneration(generation)) {
        _isSending = false;
        notifyListeners();
      }
    }
  }

  Future<void> _addPreviewReply(String input, int generation) async {
    await Future<void>.delayed(previewReplyDelay);
    if (!_isCurrentSession(generation)) return;

    final normalized = input.toLowerCase();
    String reply;
    if (normalized.contains('thank') ||
        normalized.contains('ташаккур') ||
        normalized.contains('спасибо') ||
        normalized.contains('rahmat')) {
      reply = 'Have a nice day';
    } else if (normalized.contains('where') ||
        normalized.contains('аз куҷо') ||
        normalized.contains('откуда') ||
        normalized.contains('qayer')) {
      reply = 'I am from GloboVerse';
    } else {
      reply = 'Nice to meet you';
    }

    final translation = _translation.translateOffline(
      text: reply,
      sourceLanguage: 'en',
      targetLanguage: _sourceLanguage,
    );
    if (!_isCurrentSession(generation)) return;

    _messages.add(
      ConversationMessage(
        id: _nextMessageId('peer'),
        sender: ConversationMessageSender.peer,
        text: reply,
        translatedText: translation?.text,
        sourceLanguage: 'en',
        targetLanguage: _sourceLanguage,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  List<ConversationMessage> _messagesFromPayload(Map<String, dynamic> payload) {
    final rawMessages = payload['messages'];
    final values = rawMessages is List
        ? rawMessages
        : payload['message'] == null
        ? const <Object?>[]
        : <Object?>[payload['message']];
    final messages = <ConversationMessage>[];
    final ids = <String>{};
    for (final value in values) {
      final message = _messageFromPayload(value);
      if (message != null && ids.add(message.id)) messages.add(message);
      if (messages.length >= _maximumMessagesPerResponse) break;
    }
    return messages;
  }

  Future<List<ConversationMessage>> _translateIncoming(
    List<ConversationMessage> messages,
    int generation,
  ) async {
    final translated = <ConversationMessage>[];
    final knownIds = _messages.map((message) => message.id).toSet();
    for (final message in messages) {
      if (!_ownsGeneration(generation)) break;
      if (knownIds.contains(message.id)) continue;
      if (message.translatedText != null ||
          message.sourceLanguage == message.targetLanguage) {
        translated.add(message);
        continue;
      }
      final result = await _translation.translate(
        text: message.text,
        sourceLanguage: message.sourceLanguage,
        targetLanguage: message.targetLanguage,
      );
      translated.add(
        result == null
            ? message
            : message.copyWith(translatedText: result.text),
      );
    }
    return translated;
  }

  ConversationMessage? _messageFromPayload(Object? value) {
    if (value is! Map) return null;
    final idValue = value['id'];
    final textValue = value['text'];
    if (idValue is! String || textValue is! String) return null;
    final id = idValue.trim();
    final text = textValue.trim();
    if (id.isEmpty ||
        id.length > _maximumIdentifierLength ||
        text.isEmpty ||
        text.length > _maximumServerTextLength) {
      return null;
    }

    final translatedValue = value['translatedText'];
    if (translatedValue != null && translatedValue is! String) return null;
    final translatedText = translatedValue is String
        ? translatedValue.trim()
        : null;
    if (translatedText != null &&
        translatedText.length > _maximumServerTextLength) {
      return null;
    }

    final sourceLanguage = _optionalLanguage(
      value['sourceLanguage'],
      _targetLanguage,
    );
    final targetLanguage = _optionalLanguage(
      value['targetLanguage'],
      _sourceLanguage,
    );
    if (sourceLanguage == null || targetLanguage == null) return null;

    final timestamp = _optionalTimestamp(value['timestamp']);
    if (timestamp == null) return null;

    return ConversationMessage(
      id: id,
      sender: _sender(value['sender']),
      text: text,
      translatedText: translatedText == null || translatedText.isEmpty
          ? null
          : translatedText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      timestamp: timestamp,
      deliveryState: _deliveryState(value['deliveryState']),
    );
  }

  void _appendUnique(List<ConversationMessage> received) {
    final knownIds = _messages.map((message) => message.id).toSet();
    for (final message in received) {
      if (knownIds.add(message.id)) _messages.add(message);
    }
  }

  void _applyReceipts(Map<String, dynamic> payload) {
    final values = payload['receipts'];
    if (values is! List) return;
    var processed = 0;
    for (final value in values) {
      if (processed >= _maximumReceiptsPerResponse) break;
      processed += 1;
      if (value is! Map) continue;
      final idValue = value['messageId'] ?? value['id'];
      final state = _receiptState(value['deliveryState']);
      if (idValue is! String ||
          idValue.isEmpty ||
          idValue.length > _maximumIdentifierLength ||
          state == null) {
        continue;
      }
      final index = _messages.indexWhere(
        (message) => message.isMine && message.id == idValue,
      );
      if (index < 0) continue;
      final current = _messages[index];
      if (current.deliveryState == MessageDeliveryState.failed ||
          _deliveryRank(state) > _deliveryRank(current.deliveryState)) {
        _messages[index] = current.copyWith(deliveryState: state);
      }
    }
  }

  MessageDeliveryState? _receiptState(Object? value) {
    if (value == MessageDeliveryState.sent.name) {
      return MessageDeliveryState.sent;
    }
    if (value == MessageDeliveryState.delivered.name) {
      return MessageDeliveryState.delivered;
    }
    if (value == MessageDeliveryState.read.name) {
      return MessageDeliveryState.read;
    }
    return null;
  }

  int _deliveryRank(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.failed:
        return -1;
      case MessageDeliveryState.sending:
        return 0;
      case MessageDeliveryState.sent:
        return 1;
      case MessageDeliveryState.delivered:
        return 2;
      case MessageDeliveryState.read:
        return 3;
    }
  }

  void _replaceMessage(ConversationMessage replacement) {
    final index = _messages.indexWhere(
      (message) => message.id == replacement.id,
    );
    if (index >= 0) _messages[index] = replacement;
  }

  void _failStart(int generation, String message) {
    if (!_ownsGeneration(generation)) return;
    _sessionId = null;
    _error = message;
    _status = ConversationStatus.error;
    notifyListeners();
  }

  bool _ownsGeneration(int generation) {
    return !_isDisposed && generation == _generation;
  }

  bool _isCurrentSession(int generation) {
    return _ownsGeneration(generation) && isActive && _sessionId != null;
  }

  String _nextMessageId(String sender) {
    _messageSequence += 1;
    return '$sender-${DateTime.now().microsecondsSinceEpoch}-$_messageSequence';
  }

  String _requiredIdentifier(Object? value, String field) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.trim().length > _maximumIdentifierLength) {
      throw FormatException('$field is missing or invalid.');
    }
    return value.trim();
  }

  String? _readPeerName(Map<String, dynamic> payload) {
    Object? value = payload['peerName'];
    final peer = payload['peer'];
    if (peer is Map && peer['name'] is String) value = peer['name'];
    if (value is! String) return null;
    final name = value.trim();
    if (name.isEmpty || name.length > 100) return null;
    return name;
  }

  String _languageOrFallback(Object? value, String fallback) {
    if (value is! String) return fallback;
    final normalized = value.trim().toLowerCase().replaceAll('_', '-');
    return _isLanguageCode(normalized) ? normalized : fallback;
  }

  String? _optionalLanguage(Object? value, String fallback) {
    if (value == null) return fallback;
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase().replaceAll('_', '-');
    return _isLanguageCode(normalized) ? normalized : null;
  }

  bool _isLanguageCode(String value) {
    return RegExp(r'^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$').hasMatch(value);
  }

  DateTime? _optionalTimestamp(Object? value) {
    if (value == null) return DateTime.now();
    if (value is! String) return null;
    final timestamp = DateTime.tryParse(value);
    if (timestamp == null) return null;
    final now = DateTime.now();
    if (timestamp.isAfter(now.add(const Duration(days: 1))) ||
        timestamp.isBefore(now.subtract(const Duration(days: 365)))) {
      return null;
    }
    return timestamp;
  }

  ConversationMessageSender _sender(Object? value) {
    if (value is String) {
      for (final sender in ConversationMessageSender.values) {
        if (sender.name == value) return sender;
      }
    }
    return ConversationMessageSender.peer;
  }

  MessageDeliveryState _deliveryState(Object? value) {
    if (value is String) {
      for (final state in MessageDeliveryState.values) {
        if (state.name == value) return state;
      }
    }
    return MessageDeliveryState.sent;
  }

  String? _cursorFromPayload(Map<String, dynamic> payload, {String? fallback}) {
    final value = payload['cursor'] ?? payload['nextCursor'];
    if (value == null) return fallback;
    if (value is! String) return fallback;
    final cursor = value.trim();
    if (cursor.isEmpty || cursor.length > _maximumCursorLength) {
      return fallback;
    }
    return cursor;
  }

  Uri _messagesUri(String sessionId) {
    final uri = _uri('/sessions/${Uri.encodeComponent(sessionId)}/messages');
    final cursor = _cursor;
    if (cursor == null) return uri;
    return uri.replace(queryParameters: {'after': cursor});
  }

  bool _canPoll(int generation) {
    return _isCurrentSession(generation) &&
        !isPreviewMode &&
        _isForeground &&
        _online.isConnected;
  }

  void _schedulePoll(int generation, {Duration? delay}) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!automaticPolling || _isSyncing || !_canPoll(generation)) return;
    _pollTimer = Timer(delay ?? _nextPollDelay(), () {
      _pollTimer = null;
      if (_canPoll(generation)) unawaited(syncNow());
    });
  }

  Duration _nextPollDelay() {
    var multiplier = 1;
    final steps = _syncFailures > 6 ? 6 : _syncFailures;
    for (var index = 0; index < steps; index += 1) {
      multiplier *= 2;
    }
    final candidate = pollInterval * multiplier;
    return candidate > maximumPollInterval ? maximumPollInterval : candidate;
  }

  void _handleConnectivityChanged() {
    if (_isDisposed || !isActive || isPreviewMode) return;
    if (!_online.isConnected) {
      _pollTimer?.cancel();
      _pollTimer = null;
    } else {
      _schedulePoll(_generation, delay: Duration.zero);
      unawaited(markIncomingRead());
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_isForeground == foreground) return;
    _isForeground = foreground;
    if (!foreground) {
      _pollTimer?.cancel();
      _pollTimer = null;
    } else if (isActive && !isPreviewMode) {
      _schedulePoll(_generation, delay: Duration.zero);
      unawaited(markIncomingRead());
    }
    if (isActive) notifyListeners();
  }

  Uri _uri(String path) {
    final base = Uri.tryParse(_endpoint);
    if (base == null ||
        !base.hasScheme ||
        !base.hasAuthority ||
        base.hasQuery ||
        base.hasFragment ||
        (base.scheme != 'https' && base.scheme != 'http')) {
      throw const FormatException('Conversation API URL is invalid.');
    }
    return Uri.parse('$_endpoint$path');
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_apiToken.isNotEmpty) 'Authorization': 'Bearer $_apiToken',
  };

  Map<String, dynamic> _decodeResponse(http.Response response) {
    _ensureSuccess(response);
    if (response.bodyBytes.length > _maximumResponseBytes) {
      throw const FormatException('Conversation response is too large.');
    }
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final payload = jsonDecode(response.body);
    if (payload is! Map) {
      throw const FormatException('Invalid conversation response.');
    }
    return Map<String, dynamic>.from(payload);
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Conversation server returned ${response.statusCode}.',
        response.request?.url,
      );
    }
  }

  String _friendlyError(Object error) {
    if (error is TimeoutException) return 'Conversation request timed out.';
    if (error is FormatException) return error.message.toString();
    if (error is http.ClientException) return error.message;
    return 'Conversation request failed.';
  }

  @override
  void dispose() {
    _isDisposed = true;
    _generation += 1;
    _pollTimer?.cancel();
    _online.removeListener(_handleConnectivityChanged);
    WidgetsBinding.instance.removeObserver(this);
    _messages.clear();
    _acknowledgedReadIds.clear();
    _pendingReadIds.clear();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}

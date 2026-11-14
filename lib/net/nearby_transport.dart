import 'dart:async';
import 'dart:math';

import 'package:nearby_connections/nearby_connections.dart';

import 'messages.dart';
import 'transport.dart';

const String _serviceId = 'com.example.matgo';
const String _roomPrefix = 'MATGO-';
const Duration _pingEvery = Duration(seconds: 3);
const Duration _deadAfter = Duration(seconds: 10);
const Duration _seekRetry = Duration(seconds: 6);

String _randomId() {
  final r = Random.secure();
  return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
}

/// 방장 쪽에서 참가자 한 명의 연결 정보
class _NPeer {
  _NPeer(this.dev, this.seat);
  final String dev;
  final int seat;
  String? endpoint; // 지금 연결된 endpoint (끊기면 null)
  DateTime lastRx = DateTime.now();
  bool get alive => endpoint != null;
}

/// 근처(블루투스/와이파이 다이렉트) 대전. 방장이 중심(STAR)이고 참가자 1~2명이 방장에게 붙는다.
/// 방 이름은 `MATGO-1234-3` 처럼 끝에 인원수가 붙는다.
class NearbyTransport implements GameTransport {
  final Nearby _nearby = Nearby();

  final _stateC = StreamController<LinkState>.broadcast();
  final _roomsC = StreamController<List<Room>>.broadcast();
  final _msgC = StreamController<Map<String, dynamic>>.broadcast();
  final _logC = StreamController<String>.broadcast();

  final String _myDeviceId = _randomId();
  final Map<String, String> _found = {};

  LinkState _state = LinkState.idle;
  bool _isHost = false;
  bool _closed = false;
  bool _everConnected = false; // 참가자: 방장과 한 번이라도 연결됨
  bool _everFull = false; // 방장: 자리가 한 번이라도 다 참
  bool _requesting = false;
  int _players = 2;
  int _mySeat = 0;
  String _roomName = '';

  // 방장 쪽
  final Map<String, _NPeer> _peers = {}; // deviceId → 참가자
  final Set<String> _pending = {}; // 연결은 됐지만 아직 hello 를 안 보낸 endpoint
  bool _advertising = false;

  // 참가자 쪽
  String? _hostEndpoint;
  DateTime _lastRx = DateTime.now();

  Timer? _reconnectTimer;
  Timer? _seekTimer;
  Timer? _pingTimer;

  String get _deviceLabel => 'P-$_myDeviceId';

  @override
  Stream<LinkState> get state => _stateC.stream;
  @override
  Stream<List<Room>> get rooms => _roomsC.stream;
  @override
  Stream<Map<String, dynamic>> get messages => _msgC.stream;
  @override
  Stream<String> get logs => _logC.stream;
  @override
  LinkState get current => _state;
  @override
  bool get isHost => _isHost;
  @override
  String? get roomCode => null;
  @override
  int get players => _players;
  @override
  int get mySeat => _mySeat;
  @override
  int get joined => _peers.length;

  /// 방 이름에서 인원수를 읽는다 (MATGO-1234-3 → 3). 없으면 2.
  static int playersOf(String roomName) {
    final m = RegExp(r'-(\d)$').firstMatch(roomName);
    final n = m == null ? 2 : int.parse(m.group(1)!);
    return n == 3 ? 3 : 2;
  }

  // ---------------------------------------------------------------- 공개 API

  @override
  Future<void> host({int players = 2}) async {
    await _reset();
    _isHost = true;
    _players = players;
    _mySeat = 0;
    _roomName = '$_roomPrefix${1000 + Random().nextInt(9000)}-$players';
    _log('방 이름: $_roomName');
    await _advertise();
  }

  @override
  Future<void> startSearch() async {
    await _reset();
    _isHost = false;
    _set(LinkState.discovering);
    await _seek();
  }

  @override
  Future<void> join(Room room) async {
    _roomName = room.name;
    _players = playersOf(room.name);
    _set(LinkState.connecting);
    await _requestTo(room.endpointId);
  }

  @override
  Future<bool> send(String type, [Map<String, dynamic> data = const {}]) async {
    if (_isHost) {
      var any = false;
      for (final p in _peers.values) {
        final id = p.endpoint;
        if (id != null && await _sendRaw(id, type, data)) any = true;
      }
      return any;
    }
    final id = _hostEndpoint;
    if (_state != LinkState.connected || id == null) return false;
    return _sendRaw(id, type, data);
  }

  @override
  Future<bool> sendTo(int seat, String type,
      [Map<String, dynamic> data = const {}]) async {
    if (!_isHost) return send(type, data);
    for (final p in _peers.values) {
      final id = p.endpoint;
      if (p.seat == seat && id != null) return _sendRaw(id, type, data);
    }
    return false;
  }

  @override
  Future<void> debugDrop() async {
    final ids = _isHost
        ? _peers.values.map((p) => p.endpoint).whereType<String>().toList()
        : [if (_hostEndpoint != null) _hostEndpoint!];
    _log('[테스트] 강제 끊기');
    for (final id in ids) {
      try {
        await _nearby.disconnectFromEndpoint(id);
      } catch (_) {}
      _onDisconnected(id);
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    if (_isHost) {
      for (final p in _peers.values) {
        final id = p.endpoint;
        if (id != null) await _sendRaw(id, Msg.bye, {'reason': 'leave'});
      }
    } else if (_hostEndpoint != null) {
      await _sendRaw(_hostEndpoint!, Msg.bye, {'reason': 'leave'});
    }
    await _teardown();
    _set(LinkState.idle);
  }

  // ------------------------------------------------------------- 방장: 광고

  Future<void> _advertise() async {
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    try {
      final ok = await _nearby.startAdvertising(
        _roomName,
        Strategy.P2P_STAR,
        onConnectionInitiated: _onInitiated,
        onConnectionResult: _onResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      if (!ok) {
        _advertiseFailed('광고 시작 실패');
        return;
      }
      _advertising = true;
      if (_state != LinkState.reconnecting && _state != LinkState.connected) {
        _set(LinkState.advertising);
      }
    } catch (e) {
      _advertiseFailed('광고 오류: $e');
    }
  }

  void _stopAdvertising() {
    if (!_advertising) return;
    _advertising = false;
    _nearby.stopAdvertising();
  }

  void _advertiseFailed(String why) {
    if (_state == LinkState.reconnecting || _state == LinkState.advertising) {
      _log('$why - 재시도');
      _seekTimer?.cancel();
      _seekTimer = Timer(_seekRetry, () {
        if (!_closed && (_state == LinkState.reconnecting || _state == LinkState.advertising)) {
          _advertise();
        }
      });
    } else {
      _fail(why);
    }
  }

  // --------------------------------------------------------- 참가자: 탐색

  Future<void> _seek() async {
    _seekTimer?.cancel();
    _requesting = false;
    try {
      await _nearby.stopDiscovery();
    } catch (_) {}
    try {
      final ok = await _nearby.startDiscovery(
        _deviceLabel,
        Strategy.P2P_STAR,
        onEndpointFound: _onFound,
        onEndpointLost: _onLost,
        serviceId: _serviceId,
      );
      if (!ok) _log('탐색 시작 실패');
    } catch (e) {
      _log('탐색 오류: $e');
    }
    // 재연결 중일 때만 주기적으로 탐색을 다시 시작한다
    if (_state == LinkState.reconnecting) {
      _seekTimer = Timer(_seekRetry, () {
        if (_state == LinkState.reconnecting) _seek();
      });
    }
  }

  void _onFound(String id, String name, String serviceId) {
    if (!name.startsWith(_roomPrefix)) return;
    if (_state == LinkState.reconnecting) {
      // 재연결 중에는 처음 들어갔던 방 이름과 같은 방만 자동으로 다시 붙는다
      if (name == _roomName && !_requesting) {
        _requesting = true;
        _requestTo(id);
      }
      return;
    }
    _found[id] = name;
    _emitRooms();
  }

  void _onLost(String? id) {
    if (id == null) return;
    _found.remove(id);
    _emitRooms();
  }

  Future<void> _requestTo(String id) async {
    try {
      await _nearby.requestConnection(
        _deviceLabel,
        id,
        onConnectionInitiated: _onInitiated,
        onConnectionResult: _onResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      _log('연결 요청 실패: $e');
      _requesting = false;
      if (_state == LinkState.connecting) _set(LinkState.discovering);
    }
  }

  // ------------------------------------------------------ 연결 콜백(공통)

  void _onInitiated(String id, ConnectionInfo info) {
    if (!_isHost && _hostEndpoint != null && _hostEndpoint != id) {
      _nearby.rejectConnection(id);
      return;
    }
    _log('연결 수락: ${info.endpointName}');
    _nearby.acceptConnection(id, onPayLoadRecieved: _onPayload);
  }

  void _onResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      _lastRx = DateTime.now();
      if (_isHost) {
        _pending.add(id); // hello 가 오면 자리를 정한다
      } else {
        _hostEndpoint = id;
        _seekTimer?.cancel();
        _nearby.stopDiscovery();
        _sendRaw(id, Msg.hello, {'deviceId': _myDeviceId});
      }
    } else {
      _log('연결 실패: $status');
      _requesting = false;
      if (!_isHost && _state == LinkState.connecting) {
        _set(LinkState.discovering);
      }
    }
  }

  void _onDisconnected(String id) {
    if (_isHost) {
      _pending.remove(id);
      for (final p in _peers.values) {
        if (p.endpoint == id) {
          _peerDropped(p);
          return;
        }
      }
      return;
    }
    if (id != _hostEndpoint) return;
    _dropHost();
  }

  // ------------------------------------------------------------ 메시지 처리

  _NPeer? _peerAt(String id) {
    for (final p in _peers.values) {
      if (p.endpoint == id) return p;
    }
    return null;
  }

  void _onPayload(String id, Payload p) {
    if (p.type != PayloadType.BYTES || p.bytes == null) return;
    final m = Msg.decode(p.bytes!);
    if (m == null) return;
    if (_isHost) {
      final peer = _peerAt(id);
      peer?.lastRx = DateTime.now();
      switch (m['type']) {
        case Msg.hello:
          _onHello(id, m);
          return;
        case Msg.ping:
          _sendRaw(id, Msg.pong);
          return;
        case Msg.pong:
          return;
        case Msg.bye:
          if (peer != null) _onPeerBye(peer);
          return;
        default:
          if (peer != null) _msgC.add({...m, '_from': peer.seat});
          return;
      }
    }
    _lastRx = DateTime.now();
    switch (m['type']) {
      case Msg.welcome:
        _onWelcome(m);
        break;
      case Msg.ping:
        _sendRaw(id, Msg.pong);
        break;
      case Msg.pong:
        break;
      case Msg.bye:
        _fail(m['reason'] == 'room_full' ? '이미 사람이 다 찬 방이야' : '방장이 나갔어');
        break;
      default:
        _msgC.add({...m, '_from': 0});
    }
  }

  int _freeSeat() {
    for (var s = 1; s < _players; s++) {
      if (!_peers.values.any((p) => p.seat == s)) return s;
    }
    return -1;
  }

  void _onHello(String id, Map<String, dynamic> m) {
    final dev = m['deviceId'];
    if (dev is! String) return;
    _pending.remove(id);

    var peer = _peers[dev];
    var resumed = false;
    if (peer == null) {
      final seat = _freeSeat();
      if (seat < 0) {
        // 자리가 다 찬 방에 낯선 기기가 들어옴
        _sendRaw(id, Msg.bye, {'reason': 'room_full'});
        _nearby.disconnectFromEndpoint(id);
        return;
      }
      peer = _NPeer(dev, seat);
      _peers[dev] = peer;
      _log('${peer.seat}번 자리에 참가자가 들어왔어 (${_peers.length}/${_players - 1})');
    } else {
      resumed = true;
      final old = peer.endpoint;
      if (old != null && old != id) _nearby.disconnectFromEndpoint(old);
    }
    peer.endpoint = id;
    peer.lastRx = DateTime.now();
    _sendRaw(id, Msg.welcome, {
      'resumed': resumed,
      'seat': peer.seat,
      'players': _players,
    });
    _refreshHostState();
    _startPing();
    if (resumed) _msgC.add({'type': '_resumed', '_from': peer.seat});
  }

  void _onPeerBye(_NPeer peer) {
    if (_everFull) {
      _fail('${peer.seat}번 자리 사람이 나갔어');
      return;
    }
    final id = peer.endpoint;
    _peers.remove(peer.dev);
    if (id != null) _nearby.disconnectFromEndpoint(id);
    _log('${peer.seat}번 자리 사람이 나갔어');
    _refreshHostState();
  }

  void _peerDropped(_NPeer peer) {
    peer.endpoint = null;
    if (_closed || _state == LinkState.failed || _state == LinkState.idle) return;
    if (!_everFull) {
      _peers.remove(peer.dev);
      _log('${peer.seat}번 자리 연결이 끊김 (게임 시작 전)');
    } else {
      _log('${peer.seat}번 자리 연결 끊김 - ${kReconnectWindow.inSeconds}초 동안 재연결 대기');
    }
    _refreshHostState();
  }

  /// 방장의 상태를 참가자들 연결 상황에 맞춰 정한다
  void _refreshHostState() {
    if (_closed || _state == LinkState.failed || _state == LinkState.idle) return;
    if (_peers.length < _players - 1) {
      if (_state != LinkState.advertising) _set(LinkState.advertising);
      else _stateC.add(LinkState.advertising); // 인원 표시를 위해 다시 알림
      if (!_advertising) _advertise();
      return;
    }
    _everFull = true;
    if (_peers.values.every((p) => p.alive)) {
      _reconnectTimer?.cancel();
      _stopAdvertising();
      if (_state != LinkState.connected) _set(LinkState.connected);
    } else {
      if (_state != LinkState.reconnecting) {
        _set(LinkState.reconnecting);
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(kReconnectWindow, () => _fail('재연결 시간 초과'));
      }
      if (!_advertising) _advertise(); // 끊긴 사람이 다시 들어올 수 있게
    }
  }

  void _onWelcome(Map<String, dynamic> m) {
    if (_isHost) return;
    _everConnected = true;
    _mySeat = (m['seat'] as int?) ?? 1;
    _players = (m['players'] as int?) ?? _players;
    _reconnectTimer?.cancel();
    _seekTimer?.cancel();
    _set(LinkState.connected);
    _startPing();
    if (m['resumed'] == true) _msgC.add({'type': '_resumed'});
  }

  Future<bool> _sendRaw(String id, String type,
      [Map<String, dynamic> data = const {}]) async {
    try {
      await _nearby.sendBytesPayload(id, Msg.encode(type, data));
      return true;
    } catch (e) {
      _log('전송 실패: $e');
      return false;
    }
  }

  // ------------------------------------------------------- 끊김과 재연결

  void _startPing() {
    if (_pingTimer?.isActive == true) return;
    _lastRx = DateTime.now();
    _pingTimer = Timer.periodic(_pingEvery, (_) {
      if (_closed) return;
      if (_isHost) {
        for (final p in _peers.values.toList()) {
          final id = p.endpoint;
          if (id == null) continue;
          if (DateTime.now().difference(p.lastRx) > _deadAfter) {
            _log('${p.seat}번 자리 응답 없음 - 연결 재설정');
            _nearby.disconnectFromEndpoint(id);
            _peerDropped(p);
          } else {
            _sendRaw(id, Msg.ping);
          }
        }
        return;
      }
      if (_state != LinkState.connected) return;
      final id = _hostEndpoint;
      if (id == null) return;
      if (DateTime.now().difference(_lastRx) > _deadAfter) {
        _log('응답 없음 - 연결 재설정');
        _nearby.disconnectFromEndpoint(id);
        _dropHost();
        return;
      }
      _sendRaw(id, Msg.ping);
    });
  }

  /// 참가자: 방장과의 연결이 끊김
  void _dropHost() {
    _hostEndpoint = null;
    if (_closed || _state == LinkState.failed || _state == LinkState.idle) return;

    if (!_everConnected) {
      _log('연결 전에 끊김');
      _set(LinkState.discovering);
      _seek();
      return;
    }

    _log('연결 끊김 - ${kReconnectWindow.inSeconds}초 동안 재연결 시도');
    _set(LinkState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(kReconnectWindow, () => _fail('재연결 시간 초과'));
    _seek();
  }

  Future<void> _fail(String why) async {
    _log('연결 종료: $why');
    await _teardown();
    _set(LinkState.failed);
  }

  Future<void> _teardown() async {
    _reconnectTimer?.cancel();
    _seekTimer?.cancel();
    _pingTimer?.cancel();
    _hostEndpoint = null;
    _advertising = false;
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    try {
      await _nearby.stopDiscovery();
    } catch (_) {}
    try {
      await _nearby.stopAllEndpoints();
    } catch (_) {}
  }

  Future<void> _reset() async {
    await _teardown();
    _closed = false;
    _everConnected = false;
    _everFull = false;
    _requesting = false;
    _peers.clear();
    _pending.clear();
    _mySeat = 0;
    _players = 2;
    _found.clear();
    _emitRooms();
  }

  // ------------------------------------------------------------------ 기타

  void _set(LinkState s) {
    _state = s;
    _stateC.add(s);
  }

  void _emitRooms() {
    _roomsC.add(_found.entries.map((e) => Room(e.key, e.value)).toList());
  }

  void _log(String m) {
    _logC.add('[${_isHost ? '방장' : '참가자'}] $m');
  }
}

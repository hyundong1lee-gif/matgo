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
  bool _everConnected = false;
  bool _requesting = false;
  String _roomName = '';
  String? _peerEndpoint;
  String? _peerDeviceId;
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

  // ---------------------------------------------------------------- 공개 API

  @override
  Future<void> host() async {
    await _reset();
    _isHost = true;
    _roomName = '$_roomPrefix${1000 + Random().nextInt(9000)}';
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
    _set(LinkState.connecting);
    await _requestTo(room.endpointId);
  }

  @override
  Future<bool> send(String type, [Map<String, dynamic> data = const {}]) async {
    if (_state != LinkState.connected) return false;
    return _sendRaw(type, data);
  }

  @override
  Future<void> debugDrop() async {
    final id = _peerEndpoint;
    if (id == null) return;
    _log('[테스트] 강제 끊기');
    try {
      await _nearby.disconnectFromEndpoint(id);
    } catch (_) {}
    _dropPeer();
  }

  @override
  Future<void> close() async {
    _closed = true;
    if (_peerEndpoint != null) await _sendRaw(Msg.bye, {'reason': 'leave'});
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
        Strategy.P2P_POINT_TO_POINT,
        onConnectionInitiated: _onInitiated,
        onConnectionResult: _onResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      if (!ok) {
        _advertiseFailed('광고 시작 실패');
        return;
      }
      if (_state != LinkState.reconnecting) _set(LinkState.advertising);
    } catch (e) {
      _advertiseFailed('광고 오류: $e');
    }
  }

  void _advertiseFailed(String why) {
    if (_state == LinkState.reconnecting) {
      _log('$why - 재시도');
      _seekTimer?.cancel();
      _seekTimer = Timer(_seekRetry, () {
        if (_state == LinkState.reconnecting) _advertise();
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
        Strategy.P2P_POINT_TO_POINT,
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
    if (_state == LinkState.connected &&
        _peerEndpoint != null &&
        _peerEndpoint != id) {
      _nearby.rejectConnection(id);
      return;
    }
    _log('연결 수락: ${info.endpointName}');
    _nearby.acceptConnection(id, onPayLoadRecieved: _onPayload);
  }

  void _onResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      _peerEndpoint = id;
      _lastRx = DateTime.now();
      _seekTimer?.cancel();
      _nearby.stopAdvertising();
      _nearby.stopDiscovery();
      if (!_isHost) _sendRaw(Msg.hello, {'deviceId': _myDeviceId});
    } else {
      _log('연결 실패: $status');
      _requesting = false;
      if (!_isHost && _state == LinkState.connecting) {
        _set(LinkState.discovering);
      }
    }
  }

  void _onDisconnected(String id) {
    if (id != _peerEndpoint) return;
    _dropPeer();
  }

  // ------------------------------------------------------------ 메시지 처리

  void _onPayload(String id, Payload p) {
    if (p.type != PayloadType.BYTES || p.bytes == null) return;
    final m = Msg.decode(p.bytes!);
    if (m == null) return;
    _lastRx = DateTime.now();
    switch (m['type']) {
      case Msg.hello:
        _onHello(id, m);
        break;
      case Msg.welcome:
        _onWelcome(m);
        break;
      case Msg.ping:
        _sendRaw(Msg.pong);
        break;
      case Msg.pong:
        break;
      case Msg.bye:
        _fail(m['reason'] == 'room_full' ? '이미 다른 상대가 있는 방이야' : '상대가 나갔어');
        break;
      default:
        _msgC.add(m);
    }
  }

  void _onHello(String id, Map<String, dynamic> m) {
    if (!_isHost) return;
    final dev = m['deviceId'];
    if (dev is! String) return;

    if (_everConnected && _peerDeviceId != dev) {
      // 이미 정해진 상대가 있는 방에 낯선 기기가 들어옴
      _sendRaw(Msg.bye, {'reason': 'room_full'});
      _nearby.disconnectFromEndpoint(id);
      _peerEndpoint = null;
      _advertise();
      return;
    }

    final resumed = _everConnected && _peerDeviceId == dev;
    _peerDeviceId = dev;
    _everConnected = true;
    _reconnectTimer?.cancel();
    _sendRaw(Msg.welcome, {'resumed': resumed});
    _set(LinkState.connected);
    _startPing();
    if (resumed) _msgC.add({'type': '_resumed'});
  }

  void _onWelcome(Map<String, dynamic> m) {
    if (_isHost) return;
    _everConnected = true;
    _reconnectTimer?.cancel();
    _seekTimer?.cancel();
    _set(LinkState.connected);
    _startPing();
    if (m['resumed'] == true) _msgC.add({'type': '_resumed'});
  }

  Future<bool> _sendRaw(String type, [Map<String, dynamic> data = const {}]) async {
    final id = _peerEndpoint;
    if (id == null) return false;
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
    _pingTimer?.cancel();
    _lastRx = DateTime.now();
    _pingTimer = Timer.periodic(_pingEvery, (_) {
      if (_state != LinkState.connected) return;
      if (DateTime.now().difference(_lastRx) > _deadAfter) {
        _log('응답 없음 - 연결 재설정');
        final id = _peerEndpoint;
        if (id != null) _nearby.disconnectFromEndpoint(id);
        _dropPeer();
        return;
      }
      _sendRaw(Msg.ping);
    });
  }

  void _dropPeer() {
    _peerEndpoint = null;
    _pingTimer?.cancel();
    if (_closed || _state == LinkState.failed || _state == LinkState.idle) return;

    if (!_everConnected) {
      _log('연결 전에 끊김');
      if (_isHost) {
        _set(LinkState.advertising);
        _advertise();
      } else {
        _set(LinkState.discovering);
        _seek();
      }
      return;
    }

    _log('연결 끊김 - ${kReconnectWindow.inSeconds}초 동안 재연결 시도');
    _set(LinkState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(kReconnectWindow, () => _fail('재연결 시간 초과'));
    if (_isHost) {
      _advertise();
    } else {
      _seek();
    }
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
    _peerEndpoint = null;
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
    _requesting = false;
    _peerDeviceId = null;
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

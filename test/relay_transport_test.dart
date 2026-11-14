import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matgo/net/relay.dart';
import 'package:matgo/net/relay_transport.dart';
import 'package:matgo/net/transport.dart';

/// 메모리 안에서 동작하는 가짜 중계 서버
class FakeBroker {
  final List<FakeRelay> relays = [];
  bool blocked = false; // true면 모든 전달이 막힘 (인터넷 끊김 흉내)
  bool dup = false; // true면 모든 메시지를 두 번 전달
  Relay make() {
    final r = FakeRelay(this);
    relays.add(r);
    return r;
  }
}

class FakeRelay implements Relay {
  FakeRelay(this.b);
  final FakeBroker b;
  final _in = StreamController<RelayMsg>.broadcast();
  final _on = StreamController<bool>.broadcast();
  final Set<String> subs = {};
  bool closed = false;
  bool muted = false; // true면 이 기기만 보내지도 받지도 못함

  @override
  Stream<RelayMsg> get incoming => _in.stream;
  @override
  Stream<bool> get online => _on.stream;
  @override
  Future<bool> connect() async => true;
  @override
  void subscribe(String topic) => subs.add(topic);
  @override
  void publish(String topic, String payload) {
    if (b.blocked || muted) return;
    for (final r in List.of(b.relays)) {
      if (!r.closed && !r.muted && r.subs.contains(topic)) {
        Future.microtask(() {
          if (!r.closed && !r.muted) r._in.add(RelayMsg(topic, payload));
        });
        if (b.dup) {
          Future.microtask(() {
            if (!r.closed && !r.muted) r._in.add(RelayMsg(topic, payload));
          });
        }
      }
    }
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class FailRelay extends FakeRelay {
  FailRelay(super.b);
  @override
  Future<bool> connect() async => false;
}

RelayTransport mk(FakeBroker b) => RelayTransport(
      b.make,
      pingEvery: const Duration(milliseconds: 40),
      deadAfter: const Duration(milliseconds: 200),
      helloEvery: const Duration(milliseconds: 50),
      joinTimeout: const Duration(milliseconds: 300),
      reconnectWindow: const Duration(milliseconds: 600),
    );

Future<void> wait(bool Function() ok, [int ms = 1500]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!ok() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('방 코드로 들어가면 양쪽이 연결되고 메시지가 오간다', () async {
    final b = FakeBroker();
    final host = mk(b);
    final guest = mk(b);
    final gotHost = <Map<String, dynamic>>[];
    final gotGuest = <Map<String, dynamic>>[];
    host.messages.listen(gotHost.add);
    guest.messages.listen(gotGuest.add);

    await host.host();
    expect(host.current, LinkState.advertising);
    final code = host.roomCode!;
    expect(RegExp(r'^[0-9]{2}$').hasMatch(code), true);

    await guest.join(Room(code.toLowerCase(), code));
    await wait(() =>
        host.current == LinkState.connected &&
        guest.current == LinkState.connected);
    expect(host.current, LinkState.connected);
    expect(guest.current, LinkState.connected);

    await guest.send('play_card', {'cardId': 7});
    await host.send('state', {'x': '한글'});
    await wait(() => gotHost.isNotEmpty && gotGuest.isNotEmpty);
    expect(gotHost.single['cardId'], 7);
    expect(gotGuest.single['x'], '한글');

    await host.close();
    await guest.close();
  });

  test('서버가 같은 메시지를 두 번 줘도 한 번만 전달', () async {
    final b = FakeBroker()..dup = true;
    final host = mk(b);
    final guest = mk(b);
    final gotHost = <Map<String, dynamic>>[];
    host.messages.listen((m) {
      if (m['type'] == 'play_card') gotHost.add(m);
    });
    await host.host();
    await guest.join(Room(host.roomCode!, ''));
    await wait(() => guest.current == LinkState.connected);
    await guest.send('play_card', {'cardId': 1});
    await guest.send('play_card', {'cardId': 2});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(gotHost.map((m) => m['cardId']).toList(), [1, 2]);
    await host.close();
    await guest.close();
  });

  test('없는 방 코드는 시간이 지나면 실패', () async {
    final b = FakeBroker();
    final guest = mk(b);
    await guest.join(const Room('XX', ''));
    await wait(() => guest.current == LinkState.failed);
    expect(guest.current, LinkState.failed);
  });

  test('이미 상대가 있는 방에 제3자가 들어가면 거절', () async {
    final b = FakeBroker();
    final host = mk(b);
    final a = mk(b);
    final c = mk(b);
    await host.host();
    await a.join(Room(host.roomCode!, ''));
    await wait(() => a.current == LinkState.connected);
    await c.join(Room(host.roomCode!, ''));
    await wait(() => c.current == LinkState.failed);
    expect(c.current, LinkState.failed);
    expect(a.current, LinkState.connected);
    expect(host.current, LinkState.connected);
    await host.close();
    await a.close();
  });

  test('연결이 잠깐 끊겼다 돌아오면 재연결 알림', () async {
    final b = FakeBroker();
    final host = mk(b);
    final guest = mk(b);
    final resumed = <String>[];
    host.messages.listen((m) {
      if (m['type'] == '_resumed') resumed.add('h');
    });
    guest.messages.listen((m) {
      if (m['type'] == '_resumed') resumed.add('g');
    });
    await host.host();
    await guest.join(Room(host.roomCode!, ''));
    await wait(() => guest.current == LinkState.connected);
    resumed.clear();

    b.blocked = true;
    await wait(() =>
        host.current == LinkState.reconnecting &&
        guest.current == LinkState.reconnecting);
    expect(host.current, LinkState.reconnecting);
    expect(guest.current, LinkState.reconnecting);

    b.blocked = false;
    await wait(() =>
        host.current == LinkState.connected &&
        guest.current == LinkState.connected);
    expect(host.current, LinkState.connected);
    expect(guest.current, LinkState.connected);
    await wait(() => resumed.contains('h') && resumed.contains('g'));
    expect(resumed, containsAll(['h', 'g']));
    await host.close();
    await guest.close();
  });

  test('오래 끊기면 실패', () async {
    final b = FakeBroker();
    final host = mk(b);
    final guest = mk(b);
    await host.host();
    await guest.join(Room(host.roomCode!, ''));
    await wait(() => guest.current == LinkState.connected);
    b.blocked = true;
    await wait(() => guest.current == LinkState.failed, 3000);
    expect(guest.current, LinkState.failed);
    expect(host.current, LinkState.failed);
  });

  test('한쪽이 나가면 상대는 종료 상태', () async {
    final b = FakeBroker();
    final host = mk(b);
    final guest = mk(b);
    await host.host();
    await guest.join(Room(host.roomCode!, ''));
    await wait(() => guest.current == LinkState.connected);
    await guest.close();
    await wait(() => host.current == LinkState.failed);
    expect(host.current, LinkState.failed);
  });

  test('3인방: 두 명이 들어오면 연결되고 자리 번호가 다르다', () async {
    final b = FakeBroker();
    final host = mk(b);
    final a = mk(b);
    final c = mk(b);
    final gotHost = <Map<String, dynamic>>[];
    final gotA = <Map<String, dynamic>>[];
    final gotC = <Map<String, dynamic>>[];
    host.messages.listen(gotHost.add);
    a.messages.listen(gotA.add);
    c.messages.listen(gotC.add);

    await host.host(players: 3);
    expect(host.players, 3);
    await a.join(Room(host.roomCode!, ''));
    await wait(() => a.current == LinkState.connected);
    // 한 명만 들어온 상태: 방장은 계속 기다림
    expect(host.current, LinkState.advertising);
    expect(host.joined, 1);

    await c.join(Room(host.roomCode!, ''));
    await wait(() =>
        host.current == LinkState.connected && c.current == LinkState.connected);
    expect(host.joined, 2);
    expect(a.mySeat, 1);
    expect(c.mySeat, 2);
    expect(a.players, 3);
    expect(c.players, 3);

    // 방장이 한 명에게만 / 전체에게
    await host.sendTo(2, 'view', {'v': 'only2'});
    await host.send('all', {'v': 'all'});
    await a.send('play_card', {'cardId': 3});
    await c.send('play_card', {'cardId': 4});
    await wait(() => gotHost.length >= 2 && gotC.length >= 2 && gotA.isNotEmpty);
    expect(gotA.map((m) => m['type']).toList(), ['all']);
    expect(gotC.map((m) => m['type']).toList(), ['view', 'all']);
    final byFrom = {for (final m in gotHost) m['_from']: m['cardId']};
    expect(byFrom, {1: 3, 2: 4});

    await host.close();
    await a.close();
    await c.close();
  });

  test('3인방: 정원이 차면 낯선 기기는 거절', () async {
    final b = FakeBroker();
    final host = mk(b);
    final a = mk(b);
    final c = mk(b);
    final d = mk(b);
    await host.host(players: 3);
    await a.join(Room(host.roomCode!, ''));
    await c.join(Room(host.roomCode!, ''));
    await wait(() => host.current == LinkState.connected);
    await d.join(Room(host.roomCode!, ''));
    await wait(() => d.current == LinkState.failed);
    expect(d.current, LinkState.failed);
    expect(host.current, LinkState.connected);
    await host.close();
    await a.close();
    await c.close();
  });

  test('3인방: 한 명만 끊기면 방장은 재연결 대기 후 복구', () async {
    final b = FakeBroker();
    final host = mk(b);
    final a = mk(b);
    final c = mk(b);
    final resumed = <Object?>[];
    host.messages.listen((m) {
      if (m['type'] == '_resumed') resumed.add(m['_from']);
    });
    await host.host(players: 3);
    await a.join(Room(host.roomCode!, ''));
    await c.join(Room(host.roomCode!, ''));
    await wait(() => host.current == LinkState.connected);
    resumed.clear();

    // a 기기만 인터넷이 끊긴 상황
    final aRelay = b.relays[1];
    aRelay.muted = true;
    await wait(() => host.current == LinkState.reconnecting);
    expect(host.current, LinkState.reconnecting);
    aRelay.muted = false;
    await wait(() => host.current == LinkState.connected, 2000);
    expect(host.current, LinkState.connected);
    expect(resumed, contains(1));
    await host.close();
    await a.close();
    await c.close();
  });

  test('서버에 못 붙으면 실패', () async {
    final b = FakeBroker();
    final t = RelayTransport(() => FailRelay(b));
    await t.host();
    expect(t.current, LinkState.failed);
  });
}

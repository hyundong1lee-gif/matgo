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
    if (b.blocked) return;
    for (final r in List.of(b.relays)) {
      if (!r.closed && r.subs.contains(topic)) {
        Future.microtask(() {
          if (!r.closed) r._in.add(RelayMsg(topic, payload));
        });
        if (b.dup) {
          Future.microtask(() {
            if (!r.closed) r._in.add(RelayMsg(topic, payload));
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

  test('서버에 못 붙으면 실패', () async {
    final b = FakeBroker();
    final t = RelayTransport(() => FailRelay(b));
    await t.host();
    expect(t.current, LinkState.failed);
  });
}

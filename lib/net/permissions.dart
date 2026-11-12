import 'package:permission_handler/permission_handler.dart';

enum PermIssue { none, denied, deniedForever, bluetoothOff, locationOff }

String permIssueText(PermIssue i) {
  switch (i) {
    case PermIssue.none:
      return '';
    case PermIssue.denied:
      return '근처 기기 권한이 필요해. 다시 시도해서 허용해줘.';
    case PermIssue.deniedForever:
      return '권한이 영구 거부됐어. 설정에서 직접 허용해줘.';
    case PermIssue.bluetoothOff:
      return '블루투스가 꺼져 있어. 켜고 다시 시도해줘.';
    case PermIssue.locationOff:
      return '위치(GPS)가 꺼져 있어. 연결 안정성을 위해 켜줘.';
  }
}

/// 권한 요청과 블루투스/위치 켜짐 확인.
/// 위치 권한 자체는 Android 13 이상에서 요청해도 거부로 나올 수 있어 결과를 판정에서 뺐다.
/// (대신 위치 서비스가 켜져 있는지는 확인한다)
Future<PermIssue> checkNearbyPermissions() async {
  final results = await [
    Permission.bluetoothScan,
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
    Permission.nearbyWifiDevices,
    Permission.locationWhenInUse,
  ].request();

  final core = [
    Permission.bluetoothScan,
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
    Permission.nearbyWifiDevices,
  ].map((p) => results[p]);

  if (core.any((s) => s != null && s.isPermanentlyDenied)) {
    return PermIssue.deniedForever;
  }
  if (core.any((s) => s != null && s.isDenied)) return PermIssue.denied;

  if (!await Permission.bluetooth.serviceStatus.isEnabled) {
    return PermIssue.bluetoothOff;
  }
  if (!await Permission.locationWhenInUse.serviceStatus.isEnabled) {
    return PermIssue.locationOff;
  }
  return PermIssue.none;
}

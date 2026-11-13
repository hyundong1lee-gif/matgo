/// 점수표와 박 기준은 전부 여기서 바꾼다. 다른 파일에는 숫자를 직접 쓰지 않는다.
class MatgoConfig {
  // 분배
  static const int handSize = 10;
  static const int floorSize = 8;

  // 스톱 가능한 최소 점수
  static const int minScoreToStop = 3;

  // 광
  static const int gwang3 = 3;
  static const int gwang3WithBigwang = 2; // 비광이 섞인 3광
  static const int gwang4 = 4;
  static const int gwang5 = 15;

  // 족보
  static const int godori = 5;
  static const int dan = 3; // 홍단 청단 초단 각각

  // 장수 점수 (시작 장수 이상이면 1점 + 초과 장수)
  static const int yeolStart = 5;
  static const int ttiStart = 5;
  static const int piStart = 10;

  // 고
  static const int goAddFirst = 1;
  static const int goAddSecond = 2;
  static const int goMultiplierFrom = 3; // 이 횟수부터 고마다 ×2

  // 박
  static const int gwangBakMultiplier = 2;
  static const int piBakMultiplier = 2;
  static const int goBakMultiplier = 2; // 고를 부른 쪽이 지면 (고박)
  static const int piBakMaxPi = 5; // 진 쪽 피가 이 값 이하이면 피박

  // 뻑 먹기 따닥 쪽 싹쓸이로 가져오는 피 장수
  static const int stealPiCount = 1;
}

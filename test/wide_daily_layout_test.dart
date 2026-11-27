import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/ui/pages/details_page.dart';

void main() {
  test('daily hero keeps phone ratio and bounds wide-screen height', () {
    expect(dailyHeroHeight(const Size(400, 860)), closeTo(360 / 1.62, .01));
    expect(dailyHeroHeight(const Size(820, 1180)), 260);
    expect(dailyHeroHeight(const Size(1180, 820)), closeTo(221.4, .01));
    expect(dailyHeroHeight(const Size(850, 390)), 170);
  });
}

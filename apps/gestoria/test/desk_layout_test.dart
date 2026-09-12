import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/presentation/widgets/app_widgets.dart';

void main() {
  test('na stole je 10 řádků, zbytek až po Historie', () {
    expect(
      historyPreviewCount(3, expanded: false),
      3,
    );
    expect(
      historyPreviewCount(10, expanded: false),
      10,
    );
    expect(
      historyPreviewCount(24, expanded: false),
      10,
    );
    expect(
      historyPreviewCount(24, expanded: true),
      24,
    );
  });
}

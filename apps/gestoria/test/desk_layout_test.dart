import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/presentation/widgets/app_widgets.dart';
import 'package:gestoria_os/features/clientes/cliente_card_controller.dart';

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

  test('vysypaný doklad zmizí z koše na kartě', () {
    const live = ClienteDocumento(
      id: 'a',
      tipo: 'pasaporte',
      storagePath: 't/c/a.jpg',
      originalName: 'pas.jpg',
    );
    const purged = ClienteDocumento(
      id: 'b',
      tipo: 'dni_nie',
      storagePath: 't/c/b.pdf',
      originalName: 'nie.pdf',
      storagePurged: true,
    );
    expect(trashVisibleOnCard([live, purged]), [live]);
    expect(trashVisibleOnCard([purged]), isEmpty);
  });
}

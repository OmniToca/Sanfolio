import 'package:easy_localization/easy_localization.dart';

import '../../core/print/office_print.dart';
import '../../core/time/office_date.dart';
import 'bloque_template.dart';
import 'carpeta_controller.dart';
import 'carpeta_print.dart';

/// Dva A4 v prohlížeči. PDF uloží gestor z dialogu tisku, ne server.
void openCarpetaPrint({
  required CarpetaView view,
  required List<BloqueTemplate> templates,
  required String officeName,
}) {
  final name = officeName.trim();
  printHtmlDocument(
    carpetaPrintHtml(
      buildCarpetaPrintModel(
        view: view,
        templates: templates,
        officeName: name.isEmpty ? 'folder.title'.tr() : name,
        printedOn: formatDmyDate(calendarDay(DateTime.now())),
        bloqueLabel: (k) => 'blocks.$k'.tr(),
        fieldLabel: (k) => k.tr(),
        docLabel: (t) => 'docs.$t'.tr(),
        statusLabel: (s) => carpetaPrintStatusI18nKey(s).tr(),
        sheet1Title: 'folder.printSheet1'.tr(),
        sheet2Title: 'folder.printSheet2'.tr(),
        printLabel: 'folder.print'.tr(),
        offHeading: 'folder.printOff'.tr(),
        titularesHeading: 'folder.titulares'.tr(),
        docHave: 'folder.printDocHave'.tr(),
        docMissing: 'folder.printDocMissing'.tr(),
        ladoComprador: 'folder.ladoComprador'.tr(),
        ladoVendedor: 'folder.ladoVendedor'.tr(),
        nombreLabel: 'fields.nombre'.tr(),
      ),
    ),
  );
}

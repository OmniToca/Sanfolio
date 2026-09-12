import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

const expedienteEstadoKeys = <String>[
  'abierto',
  'en_curso',
  'espera_cliente',
  'espera_admin',
  'hecho',
  'archivado',
];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Inbox stale: jen `en_curso`, N dní z nastavení, 0 = vypnuto.
bool isExpedienteStale({
  required String estado,
  required DateTime updatedAt,
  required int staleDays,
  required DateTime today,
}) {
  if (estado != 'en_curso' || staleDays <= 0) return false;
  final limit = _day(today).subtract(Duration(days: staleDays));
  return !_day(updatedAt).isAfter(limit);
}

class ExpedienteEstadoPicker extends StatelessWidget {
  const ExpedienteEstadoPicker({
    super.key,
    required this.estado,
    required this.onChanged,
  });

  final String estado;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final current =
        expedienteEstadoKeys.contains(estado) ? estado : 'abierto';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'expedientes.estadoLabel'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in expedienteEstadoKeys)
              ChoiceChip(
                label: Text('expedientes.estado.$k'.tr()),
                selected: k == current,
                onSelected: (_) {
                  if (k == current) return;
                  onChanged(k);
                },
                selectedColor: AppTheme.accentSoft,
                labelStyle: TextStyle(
                  color: k == current ? AppTheme.accent : AppTheme.ink,
                  fontWeight: k == current ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

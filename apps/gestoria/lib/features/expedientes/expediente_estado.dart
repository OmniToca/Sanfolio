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

/// Pracovní řada. Archiv je odbočka, ne pátý chevron Hotovo.
const expedienteWorkingEstadoKeys = <String>[
  'abierto',
  'en_curso',
  'espera_cliente',
  'espera_admin',
  'hecho',
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
        LayoutBuilder(
          builder: (context, constraints) {
            final tight = constraints.maxWidth < 720;
            if (tight) {
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in expedienteWorkingEstadoKeys)
                    _EstadoDot(
                      label: 'expedientes.estado.$k'.tr(),
                      selected: k == current,
                      onTap: () {
                        if (k == current) return;
                        onChanged(k);
                      },
                    ),
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < expedienteWorkingEstadoKeys.length; i++) ...[
                  if (i > 0)
                    Expanded(
                      child: Container(height: 2, color: AppTheme.rule),
                    ),
                  Flexible(
                    child: _EstadoDot(
                      label:
                          'expedientes.estado.${expedienteWorkingEstadoKeys[i]}'
                              .tr(),
                      selected:
                          expedienteWorkingEstadoKeys[i] == current,
                      onTap: () {
                        final k = expedienteWorkingEstadoKeys[i];
                        if (k == current) return;
                        onChanged(k);
                      },
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            label: Text('expedientes.estado.archivado'.tr()),
            selected: current == 'archivado',
            onSelected: (_) {
              if (current == 'archivado') return;
              onChanged('archivado');
            },
            selectedColor: AppTheme.surfaceMuted,
            labelStyle: TextStyle(
              color: current == 'archivado' ? AppTheme.ink : AppTheme.pencil,
            ),
          ),
        ),
      ],
    );
  }
}

/// Jen aktuální krok je zvýrazněný — skok je povolený, není to lockstep.
class _EstadoDot extends StatelessWidget {
  const _EstadoDot({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.accentSoft : AppTheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppTheme.accent : AppTheme.rule,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppTheme.accent : AppTheme.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

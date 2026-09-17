import 'dart:convert';

/// Nejvýš jedna dávka v UI; SQL bere 80. 500 karet Jarky se vejde.
const clienteCsvMaxRows = 600;
const clienteCsvChunkSize = 40;

const clienteCsvHeader = 'nombre;nie;email;tel;direccion;locale';

const clienteCsvLocales = <String>{'cs', 'en', 'es', 'de', 'fr'};

/// Šablona pro Excel. Středník, protože španělský Excel čárku bere jako desetinnou.
String clienteCsvTemplate() => '$clienteCsvHeader\n';

enum ClienteCsvStatus { ready, skipEmptyName, skipDuplicate }

class ClienteCsvDraft {
  const ClienteCsvDraft({
    required this.line,
    required this.nombre,
    required this.nie,
    required this.email,
    required this.tel,
    required this.direccion,
    required this.locale,
    required this.status,
  });

  final int line;
  final String nombre;
  final String nie;
  final String email;
  final String tel;
  final String direccion;
  final String locale;
  final ClienteCsvStatus status;

  Map<String, String> toRpcRow() => {
    'nombre': nombre,
    'nie': nie,
    'email': email,
    'tel': tel,
    'direccion': direccion,
    if (locale.isNotEmpty) 'locale': locale,
  };
}

class ClienteCsvParse {
  const ClienteCsvParse({required this.rows, this.error});

  final List<ClienteCsvDraft> rows;
  final String? error;

  int get readyCount =>
      rows.where((r) => r.status == ClienteCsvStatus.ready).length;
  int get emptyCount =>
      rows.where((r) => r.status == ClienteCsvStatus.skipEmptyName).length;
  int get duplicateCount =>
      rows.where((r) => r.status == ClienteCsvStatus.skipDuplicate).length;
}

class ClienteCsvImportResult {
  const ClienteCsvImportResult({
    required this.created,
    required this.skippedEmpty,
    required this.skippedDuplicate,
    required this.errors,
  });

  final int created;
  final int skippedEmpty;
  final int skippedDuplicate;
  final int errors;

  ClienteCsvImportResult operator +(ClienteCsvImportResult other) {
    return ClienteCsvImportResult(
      created: created + other.created,
      skippedEmpty: skippedEmpty + other.skippedEmpty,
      skippedDuplicate: skippedDuplicate + other.skippedDuplicate,
      errors: errors + other.errors,
    );
  }
}

/// Stejná normalizace jako `normalize_id` bez RPC — náhled duplicit.
String normalizeCsvNie(String raw) {
  return raw.trim().toUpperCase().replaceAll(RegExp(r'[\s\-\./]'), '');
}

String normalizeCsvLocale(String raw) {
  final v = raw.trim().toLowerCase();
  if (clienteCsvLocales.contains(v)) return v;
  return '';
}

String decodeClienteCsvBytes(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String detectCsvDelimiter(String header) {
  final semi = ';'.allMatches(header).length;
  final tab = '\t'.allMatches(header).length;
  final comma = ','.allMatches(header).length;
  if (semi > 0 && semi >= comma && semi >= tab) return ';';
  if (tab > comma) return '\t';
  return ',';
}

List<String> splitCsvLine(String line, String sep) {
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}

String _normHeader(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll('\uFEFF', '')
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ý', 'y')
      .replaceAll('ě', 'e')
      .replaceAll('š', 's')
      .replaceAll('č', 'c')
      .replaceAll('ř', 'r')
      .replaceAll('ž', 'z')
      .replaceAll('ň', 'n')
      .replaceAll('ů', 'u')
      .replaceAll(' ', '')
      .replaceAll('_', '')
      .replaceAll('-', '');
}

const _nombreHeaders = {
  'nombre',
  'name',
  'jmeno',
  'client',
  'cliente',
  'nazev',
};
const _nieHeaders = {'nie', 'dni', 'nif', 'id', 'identificacion'};
const _emailHeaders = {'email', 'e-mail', 'mail'};
const _telHeaders = {'tel', 'telefono', 'phone', 'mobil', 'mobile'};
const _dirHeaders = {'direccion', 'address', 'adresa'};
const _localeHeaders = {'locale', 'jazyk', 'language', 'idioma'};

int? _col(List<String> headers, Set<String> aliases) {
  for (var i = 0; i < headers.length; i++) {
    if (aliases.contains(_normHeader(headers[i]))) return i;
  }
  return null;
}

String _cell(List<String> cells, int? index) {
  if (index == null || index < 0 || index >= cells.length) return '';
  return cells[index].trim();
}

/// Parse + klasifikace. [liveNies] jsou už normalizovaná živá čísla tenanta.
ClienteCsvParse parseClienteCsv(
  String raw, {
  Iterable<String> liveNies = const [],
}) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.isEmpty) {
    return const ClienteCsvParse(rows: [], error: 'empty');
  }
  final lines = [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line,
  ];
  if (lines.isEmpty) {
    return const ClienteCsvParse(rows: [], error: 'empty');
  }
  final sep = detectCsvDelimiter(lines.first);
  final headers = splitCsvLine(lines.first, sep);
  final nombreI = _col(headers, _nombreHeaders);
  if (nombreI == null) {
    return const ClienteCsvParse(rows: [], error: 'header');
  }
  final nieI = _col(headers, _nieHeaders);
  final emailI = _col(headers, _emailHeaders);
  final telI = _col(headers, _telHeaders);
  final dirI = _col(headers, _dirHeaders);
  final localeI = _col(headers, _localeHeaders);

  final seen = <String>{
    for (final n in liveNies)
      if (n.trim().isNotEmpty) n.trim().toUpperCase(),
  };
  final rows = <ClienteCsvDraft>[];
  final data = lines.skip(1).toList();
  final limit = data.length > clienteCsvMaxRows
      ? clienteCsvMaxRows
      : data.length;
  for (var i = 0; i < limit; i++) {
    final cells = splitCsvLine(data[i], sep);
    final nombre = _cell(cells, nombreI);
    final nie = _cell(cells, nieI);
    final nieNorm = normalizeCsvNie(nie);
    ClienteCsvStatus status;
    if (nombre.isEmpty) {
      status = ClienteCsvStatus.skipEmptyName;
    } else if (nieNorm.isNotEmpty && seen.contains(nieNorm)) {
      status = ClienteCsvStatus.skipDuplicate;
    } else {
      status = ClienteCsvStatus.ready;
      if (nieNorm.isNotEmpty) seen.add(nieNorm);
    }
    rows.add(
      ClienteCsvDraft(
        line: i + 2,
        nombre: nombre,
        nie: nie,
        email: _cell(cells, emailI),
        tel: _cell(cells, telI),
        direccion: _cell(cells, dirI),
        locale: normalizeCsvLocale(_cell(cells, localeI)),
        status: status,
      ),
    );
  }
  return ClienteCsvParse(
    rows: rows,
    error: data.length > clienteCsvMaxRows ? 'tooMany' : null,
  );
}

ClienteCsvImportResult clienteCsvImportResultFromRpc(Object? raw) {
  Map<String, dynamic>? map;
  if (raw is Map) {
    map = Map<String, dynamic>.from(raw);
  }
  int n(Object? v) {
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  final errors = map?['errors'];
  return ClienteCsvImportResult(
    created: n(map?['created']),
    skippedEmpty: n(map?['skipped_empty']),
    skippedDuplicate: n(map?['skipped_duplicate']),
    errors: errors is List ? errors.length : n(errors),
  );
}

List<Map<String, String>> clienteCsvReadyPayload(List<ClienteCsvDraft> rows) {
  return [
    for (final row in rows)
      if (row.status == ClienteCsvStatus.ready) row.toRpcRow(),
  ];
}

List<List<Map<String, String>>> chunkClienteCsvPayload(
  List<Map<String, String>> rows, {
  int size = clienteCsvChunkSize,
}) {
  if (size <= 0) return [rows];
  final out = <List<Map<String, String>>>[];
  for (var i = 0; i < rows.length; i += size) {
    final end = i + size > rows.length ? rows.length : i + size;
    out.add(rows.sublist(i, end));
  }
  return out;
}

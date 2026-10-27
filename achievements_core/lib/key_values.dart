/// **İkili KeyValues** — Valve'ın şema dosyalarının biçimi.
///
/// Steam, başarımı olan her oyunun tanımını
/// `appcache/stats/UserGameStatsSchema_<appid>.bin` içine yazıyor. Dosya düz
/// metin değil, Valve'ın ikili KeyValues biçiminde.
///
/// ## Biçim
///
/// Akış, her biri şöyle olan düğümlerden oluşuyor:
///
///     [1 bayt tip][ad: null ile biten UTF-8][değer]
///
/// Tip `none` ise düğümün çocukları var ve `end` baytına kadar sürüyor.
/// `end` düğümünün adı ve değeri yok — akıştaki tek başına bir bayt.
///
/// | tip | anlam    | değer                        |
/// |-----|----------|------------------------------|
/// | 0   | none     | çocuklar, `end` ile kapanır  |
/// | 1   | string   | null ile biten UTF-8         |
/// | 2   | int32    | 4 bayt, little endian        |
/// | 3   | float32  | 4 bayt                       |
/// | 4   | pointer  | 4 bayt (yok sayılıyor)       |
/// | 5   | wstring  | null ile biten UTF-16        |
/// | 6   | color    | 4 bayt                       |
/// | 7   | uint64   | 8 bayt                       |
/// | 8   | end      | —                            |
///
/// ## Neden hoşgörülü
///
/// Bu dosyaları Steam yazıyor ve biçim sürümlerle değişti. Tanınmayan bir
/// tiple karşılaşınca çözümleme **duruyor** ve o ana kadar okunanı
/// döndürüyor: yarım bir liste, hiç liste olmamasından iyi. Bir oyunun
/// şeması bozuk diye uygulamanın tamamı kullanılmaz olmamalı.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Bir KeyValues düğümü.
class KeyValue {
  KeyValue(this.name, {this.value, List<KeyValue>? children})
      : children = children ?? <KeyValue>[];

  final String name;

  /// Yaprak düğümün değeri (metin olarak; sayılar da metne çevriliyor).
  final String? value;

  final List<KeyValue> children;

  /// Adı [key] olan ilk çocuk (yoksa null). Arama **büyük/küçük harf
  /// duyarsız**: Steam aynı anahtarı farklı yazımlarla kullanabiliyor.
  KeyValue? operator [](String key) {
    final k = key.toLowerCase();
    for (final c in children) {
      if (c.name.toLowerCase() == k) return c;
    }
    return null;
  }

  String asString([String fallback = '']) => value ?? fallback;

  int asInt([int fallback = 0]) =>
      int.tryParse(value ?? '') ?? double.tryParse(value ?? '')?.toInt() ??
          fallback;

  bool asBool([bool fallback = false]) {
    final v = value?.trim().toLowerCase();
    if (v == null || v.isEmpty) return fallback;
    if (v == '1' || v == 'true' || v == 'yes') return true;
    if (v == '0' || v == 'false' || v == 'no') return false;
    return fallback;
  }

  @override
  String toString() => value == null
      ? '$name { ${children.length} }'
      : '$name = $value';
}

/// İkili KeyValues çözer. Boş/bozuk girdide adı boş bir kök döner.
KeyValue parseBinaryKeyValues(Uint8List bytes) {
  final r = _Reader(bytes);
  final root = KeyValue('');
  try {
    _readChildren(r, root);
  } catch (_) {
    // Gerekçe kitaplık başlığında: yarım liste > hiç liste.
  }
  return root;
}

void _readChildren(_Reader r, KeyValue parent) {
  while (true) {
    if (r.eof) return;
    final type = r.u8();
    if (type == 8) return; // end
    final name = r.cstring();
    switch (type) {
      case 0: // none — çocuklar
        final node = KeyValue(name);
        parent.children.add(node);
        _readChildren(r, node);
        break;
      case 1:
        parent.children.add(KeyValue(name, value: r.cstring()));
        break;
      case 5:
        parent.children.add(KeyValue(name, value: r.wstring()));
        break;
      case 2:
        parent.children.add(KeyValue(name, value: '${r.i32()}'));
        break;
      case 3:
        parent.children.add(KeyValue(name, value: '${r.f32()}'));
        break;
      case 4: // pointer
      case 6: // color
        parent.children.add(KeyValue(name, value: '${r.i32()}'));
        break;
      case 7:
        parent.children.add(KeyValue(name, value: '${r.u64()}'));
        break;
      default:
        // Tanınmayan tip: akışın neresinde olduğumuzu artık bilmiyoruz.
        throw const FormatException('bilinmeyen KeyValues tipi');
    }
  }
}

class _Reader {
  _Reader(this.b) : d = ByteData.sublistView(b);
  final Uint8List b;
  final ByteData d;
  int i = 0;

  bool get eof => i >= b.length;

  int u8() => b[i++];

  int i32() {
    final v = d.getInt32(i, Endian.little);
    i += 4;
    return v;
  }

  double f32() {
    final v = d.getFloat32(i, Endian.little);
    i += 4;
    return v;
  }

  int u64() {
    final v = d.getUint64(i, Endian.little);
    i += 8;
    return v;
  }

  String cstring() {
    final start = i;
    while (i < b.length && b[i] != 0) {
      i++;
    }
    final s = utf8.decode(b.sublist(start, i), allowMalformed: true);
    i++; // null
    return s;
  }

  String wstring() {
    final start = i;
    while (i + 1 < b.length && !(b[i] == 0 && b[i + 1] == 0)) {
      i += 2;
    }
    final units = <int>[];
    for (var k = start; k + 1 < i; k += 2) {
      units.add(b[k] | (b[k + 1] << 8));
    }
    i += 2; // null
    return String.fromCharCodes(units);
  }
}

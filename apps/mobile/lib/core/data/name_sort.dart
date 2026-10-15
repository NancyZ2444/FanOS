import 'package:lpinyin/lpinyin.dart';

final _sortKeys = <String, String>{};
String _key(String title) {
  if (_sortKeys.length > 2048) _sortKeys.clear();
  return _sortKeys.putIfAbsent(title, () {
    // Convert only Han runs; retain Latin/Korean text and punctuation otherwise.
    return title
        .trim()
        .replaceAllMapped(
          RegExp(r'[\u3400-\u9fff]+'),
          (m) =>
              PinyinHelper.getPinyinE(m[0]!, separator: '', defPinyin: m[0]!),
        )
        .toLowerCase();
  });
}

int compareDisplayNames(String a, String b) {
  final result = _key(a).compareTo(_key(b));
  return result != 0 ? result : a.compareTo(b);
}

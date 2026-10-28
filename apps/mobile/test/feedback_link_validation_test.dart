import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optional reference links require complete safe HTTP URLs', () {
    for (final value in [
      '',
      '  \n ',
      'https://example.com/source',
      'http://example.com/a\nhttps://example.org/b?q=hello',
    ]) {
      expect(feedbackLinkError(value), isNull, reason: value);
    }
    for (final value in [
      'test',
      'https://',
      'ftp://example.com',
      'https://example.com/a b',
      'https://user:pass@example.com',
    ]) {
      expect(feedbackLinkError(value), isNotNull, reason: value);
    }
    expect(
      feedbackLinkError(List.filled(7, 'https://example.com').join('\n')),
      contains('最多填写6条'),
    );
    expect(
      feedbackLinkError('https://example.com/${'a' * 800}'),
      contains('不能超过800字符'),
    );
  });
}

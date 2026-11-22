/// Finds the one-time code in an SMS body (EC-23).
///
/// Built-in strategies:
///
/// - [OtpExtractor.auto]: 4–8 digits, the number closest to a keyword wins.
/// - [OtpExtractor.digits]: exactly `length` digits.
/// - [OtpExtractor.regex]: a group of your own pattern.
/// - [OtpExtractor.keyword]: only numbers near a keyword, in any language.
///
/// For other formats, extend this class and override [extract]. An extractor
/// that throws yields `code == null`; the full message is still delivered.
///
/// The digit-based strategies also read Arabic-Indic, Persian, Devanagari
/// and full-width digits and return the code in ASCII digits.
abstract class OtpExtractor {
  /// Constant constructor for subclasses.
  const OtpExtractor();

  /// 4–8 digit numbers that are not amounts, dates, times or phone numbers.
  /// The one closest to one of [defaultKeywords] wins; without a keyword in
  /// the message, the first one.
  const factory OtpExtractor.auto() = _AutoExtractor;

  /// Like [OtpExtractor.auto], but only numbers of exactly [length] digits.
  const factory OtpExtractor.digits({required int length}) = _DigitsExtractor;

  /// Group [group] of the first match of [pattern]; `null` if it does not
  /// match or the group did not participate.
  ///
  /// ```dart
  /// const OtpExtractor.regex(r'([A-Z0-9]{3}-[A-Z0-9]{3})', group: 1)
  /// ```
  const factory OtpExtractor.regex(String pattern, {int group}) =
      _RegexExtractor;

  /// The number of [minLength]–[maxLength] digits closest to one of
  /// [keywords]; `null` if the message contains none of them.
  ///
  /// Keywords match case-insensitively at the start of a word, so `kod`
  /// also matches `kodunuz`. For Turkish: `keywords: ['kod', 'şifre']`.
  const factory OtpExtractor.keyword({
    List<String> keywords,
    int minLength,
    int maxLength,
  }) = _KeywordExtractor;

  /// Keywords used by [OtpExtractor.auto] and [OtpExtractor.digits], and by
  /// default by [OtpExtractor.keyword].
  static const List<String> defaultKeywords = <String>[
    'code',
    'otp',
    'pin',
    'password',
    'passcode',
  ];

  /// Returns the code in [message], or `null` if there is none.
  String? extract(String message);
}

final class _AutoExtractor extends OtpExtractor {
  const _AutoExtractor();

  @override
  String? extract(String message) =>
      _pick(message, 4, 8, OtpExtractor.defaultKeywords, requireKeyword: false);
}

final class _DigitsExtractor extends OtpExtractor {
  const _DigitsExtractor({required this.length})
      : assert(length > 0, 'length must be positive.');

  final int length;

  @override
  String? extract(String message) =>
      _pick(message, length, length, OtpExtractor.defaultKeywords,
          requireKeyword: false);
}

final class _RegexExtractor extends OtpExtractor {
  const _RegexExtractor(this.pattern, {this.group = 0})
      : assert(group >= 0, 'group must not be negative.');

  final String pattern;
  final int group;

  @override
  String? extract(String message) {
    final match = RegExp(pattern).firstMatch(message);
    if (match == null || group > match.groupCount) return null;
    return match.group(group);
  }
}

final class _KeywordExtractor extends OtpExtractor {
  const _KeywordExtractor({
    this.keywords = OtpExtractor.defaultKeywords,
    this.minLength = 4,
    this.maxLength = 8,
  })  : assert(minLength > 0, 'minLength must be positive.'),
        assert(minLength <= maxLength, 'minLength must be <= maxLength.');

  final List<String> keywords;
  final int minLength;
  final int maxLength;

  @override
  String? extract(String message) =>
      _pick(message, minLength, maxLength, keywords, requireKeyword: true);
}

/// A standalone number: not touching letters or other digits. Separators
/// between digit groups are kept in the token, so amounts (`1,250.00`),
/// dates (`12/11/2026`), times (`12:30`) and grouped numbers (`555-0100`)
/// form one token and are dropped as a whole.
final RegExp _numberToken = RegExp(
  r'(?<![\p{L}\p{N}])\d+(?:[.,:/\-]\d+)*(?![\p{L}\p{N}])',
  unicode: true,
);

final RegExp _onlyDigits = RegExp(r'^\d+$');

const String _currencySymbols = r'$€£¥₺₹₽₩₪₫฿₴₦¢';
const String _currencyCodes =
    'usd|eur|gbp|try|tl|inr|rs|rub|jpy|cny|aed|sar|brl|mxn|idr|rp|ngn|pkr|egp';

/// Money or a phone number right before the number: `$`, `TL `, `Rs.`, `+`.
final RegExp _moneyBefore = RegExp(
  '(?:[$_currencySymbols+#]|(?<![\\p{L}])(?:$_currencyCodes)\\.?)\\s?\$',
  caseSensitive: false,
  unicode: true,
);

/// Money or a percentage right after the number: `€`, ` TL`, `%`.
final RegExp _moneyAfter = RegExp(
  '^\\s?(?:[$_currencySymbols%]|(?:$_currencyCodes)(?![\\p{L}]))',
  caseSensitive: false,
  unicode: true,
);

String? _pick(
  String message,
  int minLength,
  int maxLength,
  List<String> keywords, {
  required bool requireKeyword,
}) {
  final text = _asciiDigits(message);
  final candidates = <RegExpMatch>[
    for (final match in _numberToken.allMatches(text))
      if (_isCandidate(text, match, minLength, maxLength)) match,
  ];

  final anchors = <RegExpMatch>[
    for (final keyword in keywords)
      if (keyword.isNotEmpty)
        ...RegExp('(?<![\\p{L}])${RegExp.escape(keyword)}',
                caseSensitive: false, unicode: true)
            .allMatches(text),
  ];
  if (anchors.isEmpty) {
    return requireKeyword || candidates.isEmpty ? null : candidates.first[0];
  }
  if (candidates.isEmpty) return null;

  RegExpMatch? best;
  var bestDistance = 0;
  for (final candidate in candidates) {
    for (final anchor in anchors) {
      final distance = anchor.end <= candidate.start
          ? candidate.start - anchor.end
          : anchor.start - candidate.end;
      // Strictly closer only: on a tie the earlier number wins.
      if (best == null || distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
  }
  return best![0];
}

bool _isCandidate(String text, RegExpMatch match, int min, int max) {
  final token = match[0]!;
  if (token.length < min || token.length > max) return false;
  if (!_onlyDigits.hasMatch(token)) return false;
  if (_moneyBefore.hasMatch(text.substring(0, match.start))) return false;
  if (_moneyAfter.hasMatch(text.substring(match.end))) return false;
  return true;
}

/// Maps non-ASCII decimal digits to ASCII one to one, so match positions
/// stay valid.
String _asciiDigits(String text) {
  int? asciiOf(int unit) {
    for (final zero in const [0x0660, 0x06F0, 0x0966, 0xFF10]) {
      if (unit >= zero && unit <= zero + 9) return 0x30 + unit - zero;
    }
    return null;
  }

  final units = text.codeUnits;
  if (!units.any((u) => u > 0x7F && asciiOf(u) != null)) return text;
  return String.fromCharCodes([for (final u in units) asciiOf(u) ?? u]);
}

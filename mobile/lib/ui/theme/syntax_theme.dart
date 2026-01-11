import 'package:flutter/material.dart';

@immutable
class SyntaxTheme extends ThemeExtension<SyntaxTheme> {
  const SyntaxTheme({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.primary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.keyword,
    required this.string,
    required this.number,
    required this.comment,
    required this.typeColor,
    required this.function,
    required this.variable,
    required this.punctuation,
  });

  final Color background;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color text;
  final Color textMuted;

  final Color primary;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  final Color keyword;
  final Color string;
  final Color number;
  final Color comment;
  final Color typeColor;
  final Color function;
  final Color variable;
  final Color punctuation;

  static const dark = SyntaxTheme(
    background: Color(0xFF0B0B10),
    surface: Color(0x0DFFFFFF),
    surface2: Color(0x14FFFFFF),
    border: Color(0x1AFFFFFF),
    text: Color(0xFFF8FAFC),
    textMuted: Color(0xFF94A3B8),
    primary: Color(0xFF2563EB),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    info: Color(0xFF3B82F6),
    keyword: Color(0xFFA78BFA),
    string: Color(0xFF4ADE80),
    number: Color(0xFFF97316),
    comment: Color(0xFF64748B),
    typeColor: Color(0xFF2DD4BF),
    function: Color(0xFF60A5FA),
    variable: Color(0xFFF472B6),
    punctuation: Color(0xFFCBD5E1),
  );

  static const light = SyntaxTheme(
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    text: Color(0xFF0F172A),
    textMuted: Color(0xFF475569),
    primary: Color(0xFF2563EB),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    info: Color(0xFF0891B2),
    keyword: Color(0xFF7C3AED),
    string: Color(0xFF15803D),
    number: Color(0xFFB45309),
    comment: Color(0xFF64748B),
    typeColor: Color(0xFF0D9488),
    function: Color(0xFF1D4ED8),
    variable: Color(0xFFBE185D),
    punctuation: Color(0xFF334155),
  );

  static SyntaxTheme of(BuildContext context) {
    final theme = Theme.of(context).extension<SyntaxTheme>();
    return theme ?? (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  @override
  SyntaxTheme copyWith({
    Color? background,
    Color? surface,
    Color? surface2,
    Color? border,
    Color? text,
    Color? textMuted,
    Color? primary,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? keyword,
    Color? string,
    Color? number,
    Color? comment,
    Color? typeColor,
    Color? function,
    Color? variable,
    Color? punctuation,
  }) {
    return SyntaxTheme(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      border: border ?? this.border,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      keyword: keyword ?? this.keyword,
      string: string ?? this.string,
      number: number ?? this.number,
      comment: comment ?? this.comment,
      typeColor: typeColor ?? this.typeColor,
      function: function ?? this.function,
      variable: variable ?? this.variable,
      punctuation: punctuation ?? this.punctuation,
    );
  }

  @override
  ThemeExtension<SyntaxTheme> lerp(ThemeExtension<SyntaxTheme>? other, double t) {
    if (other is! SyntaxTheme) return this;

    return SyntaxTheme(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      keyword: Color.lerp(keyword, other.keyword, t)!,
      string: Color.lerp(string, other.string, t)!,
      number: Color.lerp(number, other.number, t)!,
      comment: Color.lerp(comment, other.comment, t)!,
      typeColor: Color.lerp(typeColor, other.typeColor, t)!,
      function: Color.lerp(function, other.function, t)!,
      variable: Color.lerp(variable, other.variable, t)!,
      punctuation: Color.lerp(punctuation, other.punctuation, t)!,
    );
  }
}

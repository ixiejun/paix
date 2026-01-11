import 'dart:ui';

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../theme/syntax_theme.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.borderColor,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);
    final radius = borderRadius ?? BorderRadius.circular(16);

    final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');

    if (isFlutterTest) {
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ?? syntax.surface,
            borderRadius: radius,
            border: Border.all(color: borderColor ?? syntax.border),
          ),
          child: child,
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ?? syntax.surface,
            borderRadius: radius,
            border: Border.all(color: borderColor ?? syntax.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

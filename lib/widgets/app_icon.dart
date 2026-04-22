import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum AppIconStyle { bold, linear }

class AppIcon extends StatelessWidget {
  final String name;
  final AppIconStyle style;
  final double? size;
  final Color? color;

  const AppIcon(
    this.name, {
    super.key,
    this.style = AppIconStyle.bold,
    this.size,
    this.color,
  });

  const AppIcon.linear(
    this.name, {
    super.key,
    this.size,
    this.color,
  }) : style = AppIconStyle.linear;

  const AppIcon.bold(
    this.name, {
    super.key,
    this.size,
    this.color,
  }) : style = AppIconStyle.bold;

  @override
  Widget build(BuildContext context) {
    final folder = style == AppIconStyle.bold ? 'bold' : 'linear';
    final resolved = color ?? IconTheme.of(context).color ?? Colors.black87;
    final svg = SvgPicture.asset(
      'assets/icons/$folder/$name.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
    );
    if (size == null) return svg;
    return SizedBox(width: size, height: size, child: svg);
  }
}

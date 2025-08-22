import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

// A map of all possible task icons you will use
const Map<int, IconData> _iconMap = {
  Iconsax.task_square.codePoint: Iconsax.task_square,
  Iconsax.book.codePoint: Iconsax.book,
  Iconsax.briefcase.codePoint: Iconsax.briefcase,
  Iconsax.danger.codePoint: Iconsax.danger,
  Iconsax.code.codePoint: Iconsax.code,
  // TODO: Add any other icons from the Iconsax package that you want to use for tasks
};

IconData getIconFromCodePoint(int codePoint) {
  // Return the icon from the map, or a default icon if it's not found
  return _iconMap[codePoint] ?? Iconsax.task_square;
}
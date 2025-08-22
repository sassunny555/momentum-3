import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:momentum/models/achievement_model.dart';

void showAchievementUnlockedDialog(BuildContext context, Achievement achievement) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Iconsax.award, color: Colors.amber, size: 60),
          const SizedBox(height: 16),
          const Text(
            'ACHIEVEMENT UNLOCKED!',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.amber,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: achievement.color,
            ),
            child: Icon(achievement.icon, size: 32, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            achievement.title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            achievement.description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Awesome!'),
        ),
      ],
      actionsAlignment: MainAxisAlignment.center,
    ),
  );
}
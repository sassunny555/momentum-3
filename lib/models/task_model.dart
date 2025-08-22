import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Helper function to map icon code points to constant IconData objects
IconData getIconFromCodePoint(int codePoint) {
  // A map of all possible task icons you will use.
  // The integer keys are the actual code points for the icons.
  const Map<int, IconData> iconMap = {
    59915: Iconsax.task_square, // 0xea0b
    59791: Iconsax.book,        // 0xe92f
    59700: Iconsax.briefcase,   // 0xe934
    59764: Iconsax.danger,      // 0xe974
    59743: Iconsax.code,        // 0xe95f
    // Add any other icons you want to use here with their code points.
  };

  // Return the icon from the map, or a default icon if it's not found
  return iconMap[codePoint] ?? Iconsax.task_square;
}


class Task {
  final String id;
  final String title;
  final String? description;
  final IconData icon;
  final bool isCompleted;
  final int totalPomodoros;
  final int timePerPomodoro;
  final int completedPomodoros;
  final int totalMinutesCompleted;
  final bool isDeleted;
  final Timestamp? deletedAt;
  final Timestamp? lastFocusedAt;
  final Timestamp? completedAt;
  final Timestamp? dueDate;
  final int attemptCount;
  final int? priority;

  Task({
    this.id = '',
    required this.title,
    this.description,
    this.icon = Iconsax.task_square,
    this.isCompleted = false,
    required this.totalPomodoros,
    required this.timePerPomodoro,
    this.completedPomodoros = 0,
    this.totalMinutesCompleted = 0,
    this.isDeleted = false,
    this.deletedAt,
    this.lastFocusedAt,
    this.completedAt,
    this.dueDate,
    this.attemptCount = 1,
    this.priority,
  });

  factory Task.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Task(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'],
      // <-- FIXED: Use the helper function to get a constant IconData
      icon: getIconFromCodePoint(data['iconCodePoint'] ?? 59915),
      isCompleted: data['isCompleted'] ?? false,
      totalPomodoros: (data['totalPomodoros'] as num? ?? 0).toInt(),
      timePerPomodoro: (data['timePerPomodoro'] as num? ?? 1500).toInt(),
      completedPomodoros: (data['completedPomodoros'] as num? ?? 0).toInt(),
      totalMinutesCompleted: (data['totalMinutesCompleted'] as num? ?? 0).toInt(),
      isDeleted: data['isDeleted'] ?? false,
      deletedAt: data['deletedAt'] as Timestamp?,
      lastFocusedAt: data['lastFocusedAt'] as Timestamp?,
      completedAt: data['completedAt'] as Timestamp?,
      dueDate: data['dueDate'] as Timestamp?,
      attemptCount: (data['attemptCount'] as num? ?? 1).toInt(),
      priority: data['priority'] as int?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'iconCodePoint': icon.codePoint,
      'isCompleted': isCompleted,
      'createdAt': FieldValue.serverTimestamp(),
      'totalPomodoros': totalPomodoros,
      'timePerPomodoro': timePerPomodoro,
      'completedPomodoros': completedPomodoros,
      'totalMinutesCompleted': totalMinutesCompleted,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt,
      'lastFocusedAt': lastFocusedAt,
      'completedAt': isCompleted ? FieldValue.serverTimestamp() : null,
      'dueDate': dueDate,
      'attemptCount': attemptCount,
      'priority': priority,
    };
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';

class UserStats {
  final int totalSessionsCompleted;
  final int totalTasksCompleted;
  final int totalFocusMinutes;
  final int totalTasksCreated;
  final bool isPremium; // <-- RE-ADDED THIS LINE

  UserStats({
    this.totalSessionsCompleted = 0,
    this.totalTasksCompleted = 0,
    this.totalFocusMinutes = 0,
    this.totalTasksCreated = 0,
    this.isPremium = false, // <-- RE-ADDED THIS LINE
  });

  factory UserStats.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return UserStats(
      totalSessionsCompleted: (data['totalSessionsCompleted'] as num? ?? 0).toInt(),
      totalTasksCompleted: (data['totalTasksCompleted'] as num? ?? 0).toInt(),
      totalFocusMinutes: (data['totalFocusMinutes'] as num? ?? 0).toInt(),
      totalTasksCreated: (data['totalTasksCreated'] as num? ?? 0).toInt(),
      isPremium: data['isPremium'] as bool? ?? false, // <-- RE-ADDED THIS LINE
    );
  }
}

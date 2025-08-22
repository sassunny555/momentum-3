import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:momentum/models/achievement_model.dart';

// <-- MODIFIED: Added the new 'Task Initiator' badge
List<Achievement> allAchievements = [
  // Getting Started
  Achievement(id: 'task_initiator', title: 'Task Initiator', description: 'Create your first task.', icon: Iconsax.add_square, color: Colors.teal),
  Achievement(id: 'first_session', title: 'First Step', description: 'Complete your first Pomodoro session.', icon: Iconsax.play_circle, color: Colors.green),
  Achievement(id: 'first_task', title: 'Task Taker', description: 'Complete your first task.', icon: Iconsax.task_square, color: Colors.orange),
  Achievement(id: 'planner', title: 'Planner', description: "Schedule a task using 'Date & Time'.", icon: Iconsax.calendar_add, color: Colors.cyan),
  Achievement(id: 'well_rested', title: 'Well-Rested', description: 'Take your first long break.', icon: Iconsax.coffee, color: Colors.brown),

  // Consistency
  Achievement(id: 'early_bird', title: 'Early Bird', description: 'Complete a session before 8 AM.', icon: Iconsax.sun, color: Colors.yellow.shade700),
  Achievement(id: 'night_owl', title: 'Night Owl', description: 'Complete a session after 10 PM.', icon: Iconsax.moon, color: Colors.indigo),
  Achievement(id: 'weekend_warrior', title: 'Weekend Warrior', description: 'Complete a session on a Saturday & Sunday.', icon: Iconsax.calendar_tick, color: Colors.pink),
  Achievement(id: 'perfect_week', title: 'Perfect Week', description: 'Complete a session every day for 7 days.', icon: Iconsax.star_1, color: Colors.amber),
  Achievement(id: 'momentum_master', title: 'Momentum Master', description: 'Complete a session every day for 30 days.', icon: Iconsax.award, color: Colors.red),

  // Milestones
  Achievement(id: 'ten_sessions', title: 'Focused Finisher', description: 'Complete 10 Pomodoro sessions.', icon: Iconsax.timer_1, color: Colors.blue),
  Achievement(id: 'fifty_sessions', title: 'Pomodoro Pro', description: 'Complete 50 Pomodoro sessions.', icon: Iconsax.timer_pause, color: Colors.blue.shade700),
  Achievement(id: 'hundred_sessions', title: 'The Centurion', description: 'Complete 100 Pomodoro sessions.', icon: Iconsax.cup, color: Colors.teal),
  Achievement(id: 'ten_tasks', title: 'Task Master', description: 'Complete 10 tasks.', icon: Iconsax.verify, color: Colors.purple),
  Achievement(id: 'fifty_tasks', title: 'Task Slayer', description: 'Complete 50 tasks.', icon: Iconsax.clipboard_tick, color: Colors.purple.shade700),
  Achievement(id: 'thousand_minutes', title: 'Focus Champion', description: 'Log 1,000 minutes of focus time.', icon: Iconsax.chart_21, color: Colors.lightGreen),

  // Work Styles
  Achievement(id: 'marathoner', title: 'Marathoner', description: 'Complete 4+ Pomodoro sessions in a single day.', icon: Iconsax.flash_1, color: Colors.deepOrange),
  Achievement(id: 'finisher', title: 'Finisher', description: 'Complete a task that had 5 or more sessions.', icon: Iconsax.flag, color: Colors.redAccent),
];

class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please sign in to see achievements."));

    final unlockedStream = FirebaseFirestore.instance
        .collection('users').doc(user.uid).collection('unlocked_achievements')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: unlockedStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final unlockedIds = snapshot.hasData
              ? snapshot.data!.docs.map((doc) => doc.id).toSet()
              : <String>{};

          return GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.9,
            ),
            itemCount: allAchievements.length,
            itemBuilder: (context, index) {
              final achievement = allAchievements[index];
              final isUnlocked = unlockedIds.contains(achievement.id);
              return AchievementCard(
                achievement: achievement,
                isUnlocked: isUnlocked,
              );
            },
          );
        },
      ),
    );
  }
}

class AchievementCard extends StatelessWidget {
  final Achievement achievement;
  final bool isUnlocked;

  const AchievementCard({
    super.key,
    required this.achievement,
    required this.isUnlocked,
  });

  @override
  Widget build(BuildContext context) {
    final color = isUnlocked ? achievement.color : Colors.grey.shade800;
    final iconColor = isUnlocked ? Colors.white : Colors.grey.shade600;

    return Container(
      decoration: BoxDecoration(
        color: isUnlocked ? color.withOpacity(0.15) : const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(isUnlocked ? 1.0 : 0.5),
                boxShadow: isUnlocked ? [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ] : [],
              ),
              child: Icon(achievement.icon, size: 40, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(
              achievement.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isUnlocked ? Colors.white : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              achievement.description,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
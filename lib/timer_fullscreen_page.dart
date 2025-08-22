import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/task_model.dart';
import 'widgets/pomodoro_timer_widget.dart';
import 'timer_service.dart';

class TimerFullScreenPage extends StatelessWidget {
  final String? activeTaskId;
  // We need this function to be able to start a new session
  final Function(Task)? onSetActiveTask;

  const TimerFullScreenPage({super.key, this.activeTaskId, this.onSetActiveTask});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final timerService = Provider.of<TimerService>(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: activeTaskId == null || user == null ? null : FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(activeTaskId).snapshots(),
                  builder: (context, snapshot) {
                    final task = snapshot.hasData ? Task.fromFirestore(snapshot.data!) : null;
                    return PomodoroTimerWidget(activeTask: task);
                  }
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Iconsax.refresh), onPressed: timerService.resetTimer),
                  const SizedBox(width: 20),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: activeTaskId == null || user == null ? null : FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(activeTaskId).snapshots(),
                      builder: (context, snapshot) {
                        final task = snapshot.hasData ? Task.fromFirestore(snapshot.data!) : null;
                        return FloatingActionButton(
                          // FIX: Updated logic to handle resuming or starting the next session
                          onPressed: () {
                            if (timerService.isRunning) {
                              timerService.stopTimer();
                            } else {
                              if (task != null && onSetActiveTask != null) {
                                // If a session just finished (time is 0), start the next one.
                                // Otherwise, just resume.
                                if (timerService.remainingDuration.inSeconds == 0) {
                                  onSetActiveTask!(task);
                                } else {
                                  timerService.resumeTimer();
                                }
                              }
                            }
                          },
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          child: Icon(timerService.isRunning ? Iconsax.pause : Iconsax.play, color: Colors.black, size: 30),
                        );
                      }
                  ),
                  const SizedBox(width: 20),
                  IconButton(icon: const Icon(Iconsax.minus_square), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
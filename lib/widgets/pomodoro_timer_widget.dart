import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_model.dart';
import '../timer_service.dart';
import 'timer_painter.dart';

class PomodoroTimerWidget extends StatelessWidget {
  final Task? activeTask;
  const PomodoroTimerWidget({super.key, this.activeTask});

  @override
  Widget build(BuildContext context) {
    final timerService = Provider.of<TimerService>(context);
    final theme = Theme.of(context);

    // <-- MODIFIED: Choose color and text based on the timer's mode
    Color progressColor;
    String statusText;

    switch (timerService.currentMode) {
      case TimerMode.focus:
        progressColor = theme.colorScheme.primary;
        statusText = activeTask != null ? activeTask!.title : (timerService.isRunning ? "Focus Session" : "Choose a task");
        break;
      case TimerMode.shortBreak:
        progressColor = Colors.blue.shade400;
        statusText = "Short Break";
        break;
      case TimerMode.longBreak:
        progressColor = Colors.blue.shade700;
        statusText = "Long Break";
        break;
    }

    return SizedBox(
      width: 300,
      height: 300,
      child: CustomPaint(
        painter: TimerPainter(
          progress: timerService.progress,
          trackColor: const Color(0xFF2D2D2D),
          progressColor: progressColor, // <-- Use the dynamic color
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                timerService.timeFormatted,
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Text(
                  statusText, // <-- Use the dynamic status text
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
              const SizedBox(height: 4),
              // Only show session count during a focus session with an active task
              if (activeTask != null && timerService.currentMode == TimerMode.focus)
                Text(
                  '${activeTask!.completedPomodoros} of ${activeTask!.totalPomodoros} sessions',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                )
            ],
          ),
        ),
      ),
    );
  }
}
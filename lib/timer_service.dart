import 'dart:async';
import 'package:flutter/material.dart';
import 'notification_service.dart'; // Import the notification service

enum TimerMode { focus, shortBreak, longBreak }

class TimerService extends ChangeNotifier {
  Timer? _timer;
  Duration _totalDuration = const Duration(minutes: 25);
  Duration _remainingDuration = const Duration(minutes: 25);
  bool _isRunning = false;
  VoidCallback? _onTimerEnd;

  TimerMode _currentMode = TimerMode.focus;

  // --- Notification IDs ---
  // Using distinct negative numbers to avoid clashes with task ID hashes.
  static const int _focusEndNotificationId = -2;
  static const int _breakEndNotificationId = -3;


  Duration get remainingDuration => _remainingDuration;
  Duration get totalDuration => _totalDuration;
  bool get isRunning => _isRunning;
  TimerMode get currentMode => _currentMode;

  double get progress => _totalDuration.inSeconds > 0
      ? (_totalDuration.inSeconds - _remainingDuration.inSeconds) /
      _totalDuration.inSeconds
      : 0;

  String get timeFormatted {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(_remainingDuration.inMinutes);
    // FIX: Corrected the typo from _remainingduration to _remainingDuration
    final seconds = twoDigits(_remainingDuration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  void startTimer({required Duration duration, VoidCallback? onTimerEnd}) {
    if (_isRunning) stopTimer();

    _onTimerEnd = onTimerEnd;
    _totalDuration = duration;
    _remainingDuration = _totalDuration;
    _currentMode = TimerMode.focus;

    // Schedule a notification for when the focus session ends.
    notificationService.scheduleSessionEndNotification(
      inDuration: _remainingDuration,
      title: 'Focus Session Complete!',
      body: 'Great work! Time for a well-deserved break.',
      id: _focusEndNotificationId,
    );

    resumeTimer();
  }

  void startShortBreak() {
    if (_isRunning) stopTimer();
    _totalDuration = const Duration(minutes: 5);
    _remainingDuration = _totalDuration;
    _currentMode = TimerMode.shortBreak;
    _onTimerEnd = null;

    // Schedule a notification for when the break ends.
    notificationService.scheduleSessionEndNotification(
      inDuration: _remainingDuration,
      title: 'Break Over!',
      body: 'Time to get back to it and start your next focus session.',
      id: _breakEndNotificationId,
    );
    resumeTimer();
  }

  void startLongBreak() {
    if (_isRunning) stopTimer();
    _totalDuration = const Duration(minutes: 15);
    _remainingDuration = _totalDuration;
    _currentMode = TimerMode.longBreak;
    _onTimerEnd = null;

    // Schedule a notification for when the break ends.
    notificationService.scheduleSessionEndNotification(
      inDuration: _remainingDuration,
      title: 'Break Over!',
      body: 'Time to get back to it and start your next focus session.',
      id: _breakEndNotificationId,
    );
    resumeTimer();
  }

  void resumeTimer() {
    if (_isRunning || _remainingDuration.inSeconds == 0) return;

    _isRunning = true;
    notifyListeners();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingDuration.inSeconds > 0) {
        _remainingDuration -= const Duration(seconds: 1);
        notifyListeners();
      } else {
        stopTimer(completed: true);
      }
    });
  }

  void stopTimer({bool completed = false}) {
    _timer?.cancel();
    _isRunning = false;

    // Cancel any pending session notifications when the timer is stopped manually.
    if (!completed) {
      notificationService.cancelNotification(_focusEndNotificationId);
      notificationService.cancelNotification(_breakEndNotificationId);
    }

    if (completed && _currentMode == TimerMode.focus) {
      _onTimerEnd?.call();
    }
    notifyListeners();
  }

  void resetTimer() {
    _onTimerEnd = null;
    stopTimer();
    _remainingDuration = _totalDuration;
    if (_currentMode != TimerMode.focus) {
      resetToDefault();
    }
    notifyListeners();
  }

  void resetToDefault() {
    _onTimerEnd = null;
    stopTimer();
    _currentMode = TimerMode.focus;
    _totalDuration = const Duration(minutes: 25);
    _remainingDuration = _totalDuration;
    notifyListeners();
  }
}

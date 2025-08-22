import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'dart:async';


import 'add_task_sheet.dart';
import 'models/task_model.dart';
import 'models/user_stats_model.dart';
import 'models/achievement_model.dart';
import 'timer_service.dart';
import 'widgets/pomodoro_timer_widget.dart';
import 'widgets/achievement_unlocked_dialog.dart';
import 'timer_fullscreen_page.dart';
import 'premium_page.dart';
import 'achievements_page.dart';
import 'notification_service.dart';
import 'notification_settings_page.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});
  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;
  String? _activeTaskId;
  late ConfettiController _confettiController;
  String? _localProfileImagePath;

  bool _isPremium = false;
  StreamSubscription<DocumentSnapshot>? _userStatsSubscription;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _loadLastActiveTask();
    _loadUserProfileImage();
    _listenToUserStats();
  }

  void _listenToUserStats() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userStatsSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          final userStats = UserStats.fromFirestore(snapshot);
          if (mounted) {
            setState(() {
              _isPremium = userStats.isPremium;
            });
          }
        }
      });
    }
  }

  void _loadUserProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('profile_image_path')) {
      setState(() {
        _localProfileImagePath = prefs.getString('profile_image_path');
      });
    }
  }

  void _loadLastActiveTask() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final querySnapshot = await FirebaseFirestore.instance
        .collection('users').doc(user.uid).collection('tasks')
        .where('isCompleted', isEqualTo: false)
        .where('isDeleted', isEqualTo: false)
        .orderBy('lastFocusedAt', descending: true)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      if (mounted) {
        setState(() {
          _activeTaskId = querySnapshot.docs.first.id;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _activeTaskId = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _userStatsSubscription?.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  void _onPomodoroComplete() async {
    if (_activeTaskId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final taskDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(_activeTaskId!);
    final taskSnapshot = await taskDocRef.get();
    if (!taskSnapshot.exists) return;

    final task = Task.fromFirestore(taskSnapshot);
    final minutesForThisSession = (task.timePerPomodoro / 60).round();

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    userDocRef.set({
      'totalSessionsCompleted': FieldValue.increment(1),
      'totalFocusMinutes': FieldValue.increment(minutesForThisSession),
    }, SetOptions(merge: true));

    if (task.completedPomodoros >= task.totalPomodoros) return;

    int newCompletedPomodoros = task.completedPomodoros + 1;
    int newTotalMinutesCompleted = task.totalMinutesCompleted + minutesForThisSession;
    bool isTaskNowFinished = newCompletedPomodoros >= task.totalPomodoros;

    await taskDocRef.update({
      'completedPomodoros': newCompletedPomodoros,
      'totalMinutesCompleted': newTotalMinutesCompleted,
      'isCompleted': isTaskNowFinished,
      if (isTaskNowFinished) 'completedAt': FieldValue.serverTimestamp(),
    });

    _checkAndAwardAchievements(context, lastCompletedTask: task);

    if (isTaskNowFinished) {
      _showTaskCompletedDialog();
      setState(() => _activeTaskId = null);
    } else {
      _showPomodoroCompleteDialog(newCompletedPomodoros, task.totalPomodoros);
    }
  }

  void _setActiveTask(Task task) {
    if (task.isCompleted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Refocus on Task?'),
          content: const Text('This task is already completed. Would you like to start a new attempt? This will reset its progress.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetTaskForRefocus(task);
              },
              child: const Text('Focus Again'),
            ),
          ],
        ),
      );
      return;
    }

    final timerService = Provider.of<TimerService>(context, listen: false);
    if (timerService.isRunning && _activeTaskId != null && _activeTaskId != task.id) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Switch Task?'),
          content: const Text('Another task is in progress. Starting this new task will reset the current timer.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                timerService.stopTimer();
                _startNewTask(task, timerService);
              },
              child: const Text('Proceed'),
            ),
          ],
        ),
      );
    } else {
      _startNewTask(task, timerService);
    }
  }

  Future<void> _resetTaskForRefocus(Task task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(task.id).update({
      'isCompleted': false,
      'completedPomodoros': 0,
      'totalMinutesCompleted': 0,
      'completedAt': null,
      'attemptCount': FieldValue.increment(1),
    });

    final updatedDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(task.id).get();
    final updatedTask = Task.fromFirestore(updatedDoc);

    if (!mounted) return;
    _startNewTask(updatedTask, Provider.of<TimerService>(context, listen: false));
  }

  void _startNewTask(Task task, TimerService timerService) {
    setState(() {
      _activeTaskId = task.id;
      _selectedIndex = 0;
    });
    timerService.startTimer(
      duration: Duration(seconds: task.timePerPomodoro),
      onTimerEnd: _onPomodoroComplete,
    );

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(task.id).update({
        'lastFocusedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _clearActiveTask() {
    Provider.of<TimerService>(context, listen: false).resetToDefault();
    setState(() {
      _activeTaskId = null;
    });
  }

  void _showPomodoroCompleteDialog(int completed, int total) {
    final timerService = Provider.of<TimerService>(context, listen: false);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Session Complete!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.tick_circle, color: Colors.green, size: 50),
            const SizedBox(height: 16),
            Text('You have completed $completed of $total sessions.', style: const TextStyle(color: Colors.grey)),
            const Text('Time for a break?', style: const TextStyle(color: Colors.grey)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  timerService.startShortBreak();
                },
                child: const Text('Start Short Break (5 min)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  timerService.startLongBreak();
                },
                child: const Text('Start Long Break (15 min)'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Skip Break'),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _showTaskCompletedDialog() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      userDocRef.set({
        'totalTasksCompleted': FieldValue.increment(1),
      }, SetOptions(merge: true));

      _checkAndAwardAchievements(context);
    }

    _confettiController.play();
    showDialog(context: context, builder: (context) => Stack(
      alignment: Alignment.center,
      children: [
        AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text('Task Completed!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Iconsax.cup, color: Colors.amber, size: 60),
              SizedBox(height: 16),
              Text('You stayed on track and finished a task. Time for a well-deserved break!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () {
                _confettiController.stop();
                Navigator.of(context).pop();
              },
              child: const Text('Back to Home'),
            ),
          ],
        ),
        ConfettiWidget(
          confettiController: _confettiController,
          blastDirectionality: BlastDirectionality.explosive,
          shouldLoop: false,
          colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
        ),
      ],
    ));
  }

  Future<void> _checkAndAwardAchievements(BuildContext context, {Task? newlyCreatedTask, Task? lastCompletedTask}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await Future.delayed(const Duration(seconds: 2));

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final unlockedAchievementsRef = userDocRef.collection('unlocked_achievements');

    final results = await Future.wait([
      userDocRef.get(),
      unlockedAchievementsRef.get(),
    ]);

    final userSnapshot = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final unlockedSnapshot = results[1] as QuerySnapshot;

    if (!userSnapshot.exists) return;

    final userStats = UserStats.fromFirestore(userSnapshot);
    final unlockedIds = unlockedSnapshot.docs.map((doc) => doc.id).toSet();
    final List<Achievement> newlyUnlocked = [];

    for (final achievement in allAchievements) {
      if (unlockedIds.contains(achievement.id)) continue;

      bool isEarned = false;
      switch (achievement.id) {
        case 'task_initiator':
          if (userStats.totalTasksCreated >= 1) isEarned = true;
          break;
        case 'first_session':
          if (userStats.totalSessionsCompleted >= 1) isEarned = true;
          break;
        case 'first_task':
          if (userStats.totalTasksCompleted >= 1) isEarned = true;
          break;
        case 'planner':
          if (newlyCreatedTask?.dueDate != null) isEarned = true;
          break;
        case 'ten_sessions':
          if (userStats.totalSessionsCompleted >= 10) isEarned = true;
          break;
      // ... other rules
      }

      if (isEarned) {
        newlyUnlocked.add(achievement);
        await unlockedAchievementsRef.doc(achievement.id).set({
          'unlockedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (newlyUnlocked.isNotEmpty && context.mounted) {
      for (final achievement in newlyUnlocked) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (context.mounted) {
          showAchievementUnlockedDialog(context, achievement);
        }
      }
    }
  }

  // FIX: Refactored to remove the extra network call, preventing the race condition.
  void _addTask(Task task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    userDocRef.set({
      'totalTasksCreated': FieldValue.increment(1),
    }, SetOptions(merge: true));

    // Add the task to Firestore. The `docRef` contains the new unique ID.
    final docRef = await userDocRef.collection('tasks').add(task.toFirestore());

    // Instead of fetching the document again, create a new Task object locally
    // using the properties from the original task and the new ID from the docRef.
    final newTaskWithId = Task(
      id: docRef.id,
      title: task.title,
      description: task.description,
      icon: task.icon,
      isCompleted: task.isCompleted,
      totalPomodoros: task.totalPomodoros,
      timePerPomodoro: task.timePerPomodoro,
      completedPomodoros: task.completedPomodoros,
      totalMinutesCompleted: task.totalMinutesCompleted,
      dueDate: task.dueDate,
      priority: task.priority,
      // other properties...
    );

    _checkAndAwardAchievements(context, newlyCreatedTask: newTaskWithId);
    // Schedule the notification immediately with the complete Task object.
    await notificationService.scheduleTaskNotification(newTaskWithId);
  }


  void _updateTask(Task task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(task.id).update(task.toFirestore());
    _checkAndAwardAchievements(context, newlyCreatedTask: task);
    await notificationService.scheduleTaskNotification(task);
  }

  Future<void> _updateUserProfile(String newName, File? imageFile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String? newPhotoPath;

    if (imageFile != null) {
      try {
        final documentsDirectory = await getApplicationDocumentsDirectory();
        final fileName = '${user.uid}.jpg';
        final savedImage = await imageFile.copy(path.join(documentsDirectory.path, fileName));
        newPhotoPath = savedImage.path;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_image_path', newPhotoPath);

        await user.updateProfile(photoURL: '');

      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving image: ${e.toString()}'))
        );
        return;
      }
    }

    try {
      await user.updateProfile(displayName: newName);

      setState(() {
        if(newPhotoPath != null) {
          _localProfileImagePath = newPhotoPath;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: ${e.toString()}'))
      );
    }
  }

  void _softDeleteTask(Task task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(task.id).update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });
    if (task.id == _activeTaskId) {
      _clearActiveTask();
    }
    await notificationService.cancelNotification(task.id.hashCode);
  }

  void _restoreTask(Task task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(task.id).update({
      'isDeleted': false,
      'deletedAt': null,
    });
    await notificationService.scheduleTaskNotification(task);
  }

  void _permanentDeleteTask(Task task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (task.id == _activeTaskId) {
      _clearActiveTask();
    }
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(task.id).delete();
    await notificationService.cancelNotification(task.id.hashCode);
  }

  Future<void> _exportTaskHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating your report...'))
    );

    final querySnapshot = await FirebaseFirestore.instance
        .collection('users').doc(user.uid).collection('tasks')
        .where('isCompleted', isEqualTo: true)
        .orderBy('completedAt', descending: true)
        .get();

    final tasks = querySnapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();

    if (tasks.isEmpty) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No completed tasks to export.'))
        );
      }
      return;
    }

    List<List<dynamic>> rows = [];
    rows.add(['Title', 'Description', 'Sessions Completed', 'Minutes Focused', 'Date Completed', 'Attempt']);
    for (var task in tasks) {
      rows.add([
        task.title,
        task.description ?? '',
        task.completedPomodoros,
        task.totalMinutesCompleted,
        task.completedAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(task.completedAt!.toDate()) : 'N/A',
        task.attemptCount
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);

    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/momentum_export.csv';
    final file = File(filePath);
    await file.writeAsString(csv);

    await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Here is my completed task history from the Momentum app.'
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      HomePage(
        onNavigate: _onItemTapped,
        activeTaskId: _activeTaskId,
        onSetActiveTask: _setActiveTask,
        onClearActiveTask: _clearActiveTask,
        localImagePath: _localProfileImagePath,
        isPremium: _isPremium,
        onRestoreTask: _restoreTask,
        onPermanentDeleteTask: _permanentDeleteTask,
        onUpdateProfile: _updateUserProfile,
        onExportData: _exportTaskHistory,
      ),
      TaskPage(onNavigate: _onItemTapped, onAddTask: _addTask, onUpdateTask: _updateTask, onDeleteTask: _softDeleteTask, onSetActiveTask: _setActiveTask, activeTaskId: _activeTaskId, onClearActiveTask: _clearActiveTask, isPremium: _isPremium),
      CalendarPage(onNavigate: _onItemTapped, onSetActiveTask: _setActiveTask, onUpdateTask: _updateTask, isPremium: _isPremium),
      PremiumBlocker(
        isPremium: _isPremium,
        child: ReportPage(onNavigate: _onItemTapped),
      ),
      PremiumBlocker(
        isPremium: _isPremium,
        child: const AchievementsPage(),
      ),
    ];

    return Scaffold(
      body: Center(child: pages.elementAt(_selectedIndex)),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1C1C1E),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Iconsax.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Iconsax.task_square), label: 'Tasks'),
          BottomNavigationBarItem(icon: Icon(Iconsax.calendar_1), label: 'Calendar'),
          BottomNavigationBarItem(icon: Icon(Iconsax.status_up), label: 'Report'),
          BottomNavigationBarItem(icon: Icon(Iconsax.cup), label: 'Achieve'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

class PremiumBlocker extends StatelessWidget {
  final Widget child;
  final bool isPremium;

  const PremiumBlocker({
    super.key,
    required this.child,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    if (isPremium) {
      return child;
    } else {
      return Stack(
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: child,
          ),
          Container(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(24.0),
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Iconsax.crown_1, color: Colors.amber, size: 50),
                    const SizedBox(height: 16),
                    const Text(
                      'Premium Feature',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This feature is exclusive to our premium members. Upgrade to unlock your full potential.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => const PremiumPage(),
                        ));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'Upgrade Now',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
  }
}


enum ReportTimeframe { day, week, month, allTime }

class HomePage extends StatefulWidget {
  final Function(int) onNavigate;
  final String? activeTaskId;
  final Function(Task) onSetActiveTask;
  final VoidCallback onClearActiveTask;
  final String? localImagePath;
  final bool isPremium;
  final Function(Task) onRestoreTask;
  final Function(Task) onPermanentDeleteTask;
  final Future<void> Function(String, File?) onUpdateProfile;
  final VoidCallback onExportData;

  const HomePage({
    super.key,
    required this.onNavigate,
    this.activeTaskId,
    required this.onSetActiveTask,
    required this.onClearActiveTask,
    this.localImagePath,
    required this.isPremium,
    required this.onRestoreTask,
    required this.onPermanentDeleteTask,
    required this.onUpdateProfile,
    required this.onExportData,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _recentTasksStream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _recentTasksStream = FirebaseFirestore.instance
          .collection('users').doc(user.uid).collection('tasks')
          .where('isDeleted', isEqualTo: false)
          .where('isCompleted', isEqualTo: false)
          .orderBy('lastFocusedAt', descending: true)
          .limit(10)
          .snapshots();
    }
  }

  void _showGenericTimerCompleteDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      title: const Text('Session Complete!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      content: const Text('Your 25-minute focus session is over.', style: TextStyle(color: Colors.grey)),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final timerService = Provider.of<TimerService>(context);

    return Scaffold(
      drawer: AppDrawer(
        localImagePath: widget.localImagePath,
        isPremium: widget.isPremium,
        onUpdateProfile: widget.onUpdateProfile,
        onRestoreTask: widget.onRestoreTask,
        onPermanentDeleteTask: widget.onPermanentDeleteTask,
        onExportData: widget.onExportData,
      ),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Welcome Back! 👋', style: TextStyle(fontSize: 14, color: Colors.grey)),
            Text(user?.displayName ?? 'Beautiful Person', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: const [
          SizedBox(width: 48)
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 24),
              if (widget.activeTaskId != null && user != null)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(widget.activeTaskId).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                        child: const Row(children: [
                          Icon(Iconsax.info_circle, color: Colors.grey),
                          SizedBox(width: 16),
                          Expanded(child: Text("Go to the Tasks tab to start a new session.", style: TextStyle(color: Colors.grey))),
                        ]),
                      );
                    }
                    final task = Task.fromFirestore(snapshot.data!);
                    return Dismissible(
                      key: Key(task.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (direction) async {
                        return await showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text("Cancel Session"),
                              content: const Text("Are you sure you want to cancel this active session?"),
                              actions: <Widget>[
                                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Keep Going")),
                                ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Cancel")),
                              ],
                            );
                          },
                        );
                      },
                      onDismissed: (direction) {
                        widget.onClearActiveTask();
                      },
                      background: Container(
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16.0)),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          alignment: Alignment.centerRight,
                          child: const Icon(Iconsax.close_circle, color: Colors.white)
                      ),
                      child: TaskListItem(
                          task: task,
                          onPlay: () {},
                          onTap: () {},
                          customTrailing: const Icon(Iconsax.arrow_down_1, size: 20, color: Colors.grey)
                      ),
                    );
                  },
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                  child: const Row(children: [
                    Icon(Iconsax.info_circle, color: Colors.grey),
                    SizedBox(width: 16),
                    Expanded(child: Text("Go to the Tasks tab to start a new session.", style: TextStyle(color: Colors.grey))),
                  ]),
                ),

              const SizedBox(height: 40),

              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: widget.activeTaskId == null || user == null ? null : FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks').doc(widget.activeTaskId).snapshots(),
                  builder: (context, snapshot) {
                    final task = snapshot.hasData && snapshot.data!.exists ? Task.fromFirestore(snapshot.data!) : null;
                    return PomodoroTimerWidget(activeTask: task);
                  }
              ),

              const SizedBox(height: 40),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Iconsax.refresh), onPressed: timerService.resetTimer),
                  const SizedBox(width: 20),
                  FloatingActionButton(
                    onPressed: () {
                      if (timerService.isRunning) {
                        timerService.stopTimer();
                      } else {
                        if (widget.activeTaskId != null) {
                          FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('tasks').doc(widget.activeTaskId).get().then((doc) {
                            if (doc.exists) {
                              final task = Task.fromFirestore(doc);
                              if (timerService.remainingDuration.inSeconds == 0) {
                                widget.onSetActiveTask(task);
                              } else {
                                timerService.resumeTimer();
                              }
                            }
                          });
                        } else {
                          if (timerService.remainingDuration > Duration.zero && timerService.remainingDuration < timerService.totalDuration) {
                            timerService.resumeTimer();
                          } else {
                            timerService.startTimer(
                              duration: const Duration(minutes: 25),
                              onTimerEnd: () => _showGenericTimerCompleteDialog(context),
                            );
                          }
                        }
                      }
                    },
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(timerService.isRunning ? Iconsax.pause : Iconsax.play, color: Colors.black, size: 30),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                      icon: const Icon(Iconsax.maximize_4),
                      onPressed: () {
                        if(widget.activeTaskId != null || timerService.isRunning) {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => TimerFullScreenPage(activeTaskId: widget.activeTaskId, onSetActiveTask: widget.onSetActiveTask),
                          ));
                        }
                      }
                  ),
                ],
              ),

              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton(onPressed: () => widget.onNavigate(1), child: const Text('View All >')),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 250,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: user == null ? null : _recentTasksStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (snapshot.hasError) return const Center(child: Text('Check Firestore Indexes.', style: TextStyle(color: Colors.red)));
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No recent tasks.', style: TextStyle(color: Colors.grey)));

                    final tasks = snapshot.data!.docs.map((doc) => Task.fromFirestore(doc)).toList();
                    return ListView.builder(
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return TaskListItem(task: task, onPlay: () => widget.onSetActiveTask(task), onTap: () => widget.onSetActiveTask(task));
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  final String? localImagePath;
  final bool isPremium;
  final Function(Task) onRestoreTask;
  final Function(Task) onPermanentDeleteTask;
  final Future<void> Function(String, File?) onUpdateProfile;
  final VoidCallback onExportData;

  const AppDrawer({
    super.key,
    this.localImagePath,
    required this.isPremium,
    required this.onRestoreTask,
    required this.onPermanentDeleteTask,
    required this.onUpdateProfile,
    required this.onExportData,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1C1C1E),
      child: AppDrawerContent(
        localImagePath: localImagePath,
        isPremium: isPremium,
        onUpdateProfile: onUpdateProfile,
        onRestoreTask: onRestoreTask,
        onPermanentDeleteTask: onPermanentDeleteTask,
        onExportData: onExportData,
      ),
    );
  }
}

class AppDrawerContent extends StatelessWidget {
  final String? localImagePath;
  final bool isPremium;
  final Function(Task) onRestoreTask;
  final Function(Task) onPermanentDeleteTask;
  final Future<void> Function(String, File?) onUpdateProfile;
  final VoidCallback onExportData;

  const AppDrawerContent({
    super.key,
    this.localImagePath,
    required this.isPremium,
    required this.onRestoreTask,
    required this.onPermanentDeleteTask,
    required this.onUpdateProfile,
    required this.onExportData,
  });

  void _showEditProfileSheet(BuildContext context, User user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
        ),
        child: _EditProfileSheet(
          currentUser: user,
          onSave: onUpdateProfile,
          localImagePath: localImagePath,
        ),
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _shareApp() {
    Share.share('Check out Momentum, my favorite focus app! [Your App Store Link Here]');
  }

  void _sendFeedbackEmail() {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'support@momentumapp.com',
      query: 'subject=Momentum App Feedback',
    );
    launchUrl(emailLaunchUri);
  }

  void _changePassword(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
    }
  }

  void _deleteAccount(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Account'),
          content: const Text('Are you sure you want to delete your account? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await user.delete();
                  Navigator.of(context).pop();
                } on FirebaseAuthException catch (e) {
                  Navigator.of(context).pop();
                  if (e.code == 'requires-recent-login') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please log in again to delete your account.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.message}')),
                    );
                  }
                }
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Not logged in."));

    ImageProvider? profileImage;
    if (localImagePath != null) {
      profileImage = FileImage(File(localImagePath!));
    } else if (user.photoURL != null && user.photoURL!.isNotEmpty) {
      profileImage = NetworkImage(user.photoURL!);
    }

    final deletedTasksStream = FirebaseFirestore.instance
        .collection('users').doc(user.uid).collection('tasks')
        .where('isDeleted', isEqualTo: true)
        .orderBy('deletedAt', descending: true)
        .snapshots();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 32,
                  backgroundImage: profileImage,
                  child: profileImage == null ? const Icon(Iconsax.user, size: 32) : null,
                ),
                title: Text(
                  user.displayName ?? 'No Name',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
                ),
                subtitle: Text(
                  user.email ?? '',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                trailing: const Icon(Iconsax.edit),
                onTap: () {
                  Navigator.pop(context);
                  _showEditProfileSheet(context, user);
                },
              ),
            ],
          ),
        ),

        _buildSectionHeader('Account'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            isPremium ? 'Premium Account' : 'Free Account',
            style: TextStyle(
              color: isPremium ? Colors.amber : Colors.grey.shade400,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (!isPremium)
          ListTile(
            leading: const Icon(Iconsax.crown_1, color: Colors.amber),
            title: const Text('Upgrade to Premium'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const PremiumPage()));
            },
          ),

        _buildSectionHeader('Settings'),
        ListTile(
          leading: const Icon(Iconsax.notification),
          title: const Text('Notifications'),
          trailing: !isPremium ? const Icon(Iconsax.crown_1, size: 16, color: Colors.amber) : null,
          onTap: () {
            Navigator.pop(context);
            if (isPremium) {
              Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const NotificationSettingsPage()));
            } else {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const PremiumPage()));
            }
          },
        ),

        _buildSectionHeader('Data'),
        ListTile(
          leading: const Icon(Iconsax.document_upload),
          title: const Text('Export Task History'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isPremium) const Icon(Iconsax.crown_1, size: 16, color: Colors.amber),
              const SizedBox(width: 8),
            ],
          ),
          onTap: () {
            Navigator.pop(context);
            if(isPremium) {
              onExportData();
            } else {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const PremiumPage()));
            }
          },
        ),

        _buildSectionHeader('Support & Feedback'),
        ListTile(
          leading: const Icon(Iconsax.star),
          title: const Text('Rate the App'),
          onTap: () {
            _launchURL('https://play.google.com/store/apps/details?id=com.twoman.momentum.momentum');
          },
        ),
        ListTile(
          leading: const Icon(Iconsax.share),
          title: const Text('Share with a Friend'),
          onTap: _shareApp,
        ),
        ListTile(
          leading: const Icon(Iconsax.message_question),
          title: const Text('Send Feedback'),
          onTap: _sendFeedbackEmail,
        ),
        ListTile(
          leading: const Icon(Iconsax.security_safe),
          title: const Text('Privacy Policy'),
          onTap: () {
            _launchURL('https://yourwebsite.com/privacy');
          },
        ),

        const Divider(height: 32),

        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: deletedTasksStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return const Center(child: Text('Something went wrong.'));

            final tasks = snapshot.hasData ? snapshot.data!.docs.map((doc) => Task.fromFirestore(doc)).toList() : [];

            return ExpansionTile(
              title: Row(
                children: [
                  Icon(Iconsax.trash, color: Colors.grey.shade500, size: 18),
                  const SizedBox(width: 8),
                  const Text('Recycle Bin'),
                ],
              ),
              subtitle: Text('${tasks.length} items'),
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              iconColor: Theme.of(context).colorScheme.primary,
              collapsedIconColor: Colors.grey,
              children: tasks.isEmpty
                  ? [const ListTile(title: Text('Recycle bin is empty.', style: TextStyle(color: Colors.grey)))]
                  : tasks.map((task) {
                return Dismissible(
                  key: Key(task.id),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (direction) => onRestoreTask(task),
                  background: Container(
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    margin: const EdgeInsets.only(bottom: 12.0),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.centerLeft,
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Iconsax.refresh, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Restore', style: TextStyle(color: Colors.white))
                    ]),
                  ),
                  child: TaskListItem(
                    task: task,
                    onPlay: () {},
                    onTap: () {},
                    customTrailing: IconButton(
                      icon: const Icon(Iconsax.trash, color: Colors.red),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Permanently?'),
                            content: const Text('This action cannot be undone. Are you sure?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  onPermanentDeleteTask(task);
                                },
                                child: const Text('Delete'),
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        ListTile(
          leading: const Icon(Iconsax.logout),
          title: const Text('Logout'),
          onTap: () => FirebaseAuth.instance.signOut(),
        ),
        ListTile(
          leading: const Icon(Iconsax.key),
          title: const Text('Change Password'),
          onTap: () => _changePassword(context),
        ),
        ListTile(
          leading: const Icon(Iconsax.user_remove),
          title: const Text('Delete Account'),
          onTap: () => _deleteAccount(context),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
            color: Colors.grey.shade500,
            fontWeight: FontWeight.bold,
            fontSize: 12
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final User currentUser;
  final Future<void> Function(String newName, File? imageFile) onSave;
  final String? localImagePath;

  const _EditProfileSheet({required this.currentUser, required this.onSave, this.localImagePath});

  @override
  State<_EditProfileSheet> createState() => __EditProfileSheetState();
}

class __EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameController;
  File? _imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUser.displayName);
  }

  Future<void> _pickImage(ImageSource source) async {
    final imagePicker = ImagePicker();
    final pickedFile = await imagePicker.pickImage(source: source, imageQuality: 50, maxWidth: 400);

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Photo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Iconsax.camera),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Iconsax.gallery),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? backgroundImage;
    if (_imageFile != null) {
      backgroundImage = FileImage(_imageFile!);
    } else if (widget.localImagePath != null) {
      backgroundImage = FileImage(File(widget.localImagePath!));
    } else if (widget.currentUser.photoURL != null && widget.currentUser.photoURL!.isNotEmpty) {
      backgroundImage = NetworkImage(widget.currentUser.photoURL!);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 50,
            backgroundImage: backgroundImage,
            child: backgroundImage == null ? const Icon(Iconsax.user, size: 50) : null,
          ),
          TextButton(onPressed: _showImageSourceDialog, child: const Text('Change Photo')),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Display Name'),
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const CircularProgressIndicator()
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              onPressed: () async {
                setState(() => _isLoading = true);
                await widget.onSave(_nameController.text.trim(), _imageFile);
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Save Changes'),
            ),
        ],
      ),
    );
  }
}

class TaskPage extends StatefulWidget {
  final Function(int) onNavigate;
  final Function(Task) onAddTask;
  final Function(Task) onUpdateTask;
  final Function(Task) onDeleteTask;
  final Function(Task) onSetActiveTask;
  final String? activeTaskId;
  final VoidCallback onClearActiveTask;
  final bool isPremium;

  const TaskPage({
    super.key,
    required this.onNavigate,
    required this.onAddTask,
    required this.onUpdateTask,
    required this.onDeleteTask,
    required this.onSetActiveTask,
    this.activeTaskId,
    required this.onClearActiveTask,
    required this.isPremium,
  });

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _ongoingTasksStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _completedTasksStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final tasksCollection = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tasks');
      _ongoingTasksStream = tasksCollection.where('isDeleted', isEqualTo: false).where('isCompleted', isEqualTo: false).orderBy('createdAt', descending: true).snapshots();
      _completedTasksStream = tasksCollection.where('isDeleted', isEqualTo: false).where('isCompleted', isEqualTo: true).orderBy('createdAt', descending: true).snapshots();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please log in."));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [Tab(text: 'Ongoing'), Tab(text: 'Completed')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTaskListStream(stream: _ongoingTasksStream),
          _buildTaskListStream(stream: _completedTasksStream),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final newTask = await showModalBottomSheet<Task>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => AddTaskSheet(taskToEdit: null, isPremium: widget.isPremium));
          if (newTask != null) {
            widget.onAddTask(newTask);
          }
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Iconsax.add, color: Colors.black),
      ),
    );
  }

  Widget _buildTaskListStream({required Stream<QuerySnapshot<Map<String, dynamic>>> stream}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return const Center(child: Text('Something went wrong.'));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Text(stream == _completedTasksStream ? 'No completed tasks yet.' : 'No ongoing tasks. Add one!', style: TextStyle(color: Colors.grey.shade600)));
        final tasks = snapshot.data!.docs.map((doc) => Task.fromFirestore(doc)).toList();
        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return Dismissible(
              key: Key(task.id),
              direction: DismissDirection.endToStart,
              confirmDismiss: (direction) async {
                if (task.id == widget.activeTaskId) {
                  return await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text("Confirm Deletion"),
                        content: const Text("This task is currently active. Are you sure you want to delete it? This will stop the timer."),
                        actions: <Widget>[
                          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
                          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Delete")),
                        ],
                      );
                    },
                  );
                }
                return true;
              },
              onDismissed: (direction) {
                widget.onDeleteTask(task);
                if (task.id == widget.activeTaskId) {
                  widget.onClearActiveTask();
                }
              },
              background: Container(color: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 20), alignment: Alignment.centerRight, child: const Icon(Iconsax.trash, color: Colors.white)),
              child: TaskListItem(
                task: task,
                onPlay: () => widget.onSetActiveTask(task),
                onTap: () async {
                  final updatedTask = await showModalBottomSheet<Task>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => AddTaskSheet(taskToEdit: task, isPremium: widget.isPremium));
                  if (updatedTask != null) {
                    widget.onUpdateTask(updatedTask);
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}

class TaskListItem extends StatelessWidget {
  final Task task;
  final VoidCallback onPlay;
  final VoidCallback onTap;
  final Widget? customTrailing;

  const TaskListItem({super.key, required this.task, required this.onPlay, required this.onTap, this.customTrailing});

  @override
  Widget build(BuildContext context) {
    int remainingPomodoros = task.totalPomodoros - task.completedPomodoros;
    if (remainingPomodoros < 0) remainingPomodoros = 0;
    final totalGoalMinutes = task.totalMinutesCompleted + (remainingPomodoros * (task.timePerPomodoro / 60)).round();
    final priorities = {
      0: {'label': 'Easy', 'icon': Iconsax.arrow_down, 'color': Colors.green},
      1: {'label': 'Medium', 'icon': Iconsax.minus, 'color': Colors.orange},
      2: {'label': 'Hard', 'icon': Iconsax.arrow_up_3, 'color': Colors.red}
    };
    final priorityInfo = task.priority != null ? priorities[task.priority] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16.0)),
      child: ListTile(
        onTap: onTap,
        leading: Icon(task.icon, color: Colors.grey),
        title: Row(
          children: [
            Flexible(
              child: Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
              ),
            ),
            if (task.attemptCount > 1) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'ATTEMPT ${task.attemptCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ]
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Iconsax.repeat, color: Colors.grey, size: 16),
                const SizedBox(width: 4),
                Text('${task.completedPomodoros}/${task.totalPomodoros}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 16),
                const Icon(Iconsax.clock, color: Colors.grey, size: 16),
                const SizedBox(width: 4),
                Text('${task.totalMinutesCompleted} / $totalGoalMinutes mins', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if (priorityInfo != null && task.dueDate == null) ...[
                  const SizedBox(width: 16),
                  Icon(priorityInfo['icon'] as IconData, color: priorityInfo['color'] as Color, size: 16),
                ],
              ]),
              if (task.dueDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    children: [
                      const Icon(Iconsax.calendar_1, color: Colors.grey, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('MMM d, hh:mm a').format(task.dueDate!.toDate()),
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      if (priorityInfo != null) ...[
                        const SizedBox(width: 16),
                        Icon(priorityInfo['icon'] as IconData, color: priorityInfo['color'] as Color, size: 16),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        trailing: customTrailing ?? IconButton(icon: Icon(Iconsax.play_circle, color: Theme.of(context).colorScheme.primary, size: 30), onPressed: onPlay),
      ),
    );
  }
}

class CalendarPage extends StatefulWidget {
  final Function(int) onNavigate;
  final Function(Task) onSetActiveTask;
  final Function(Task) onUpdateTask;
  final bool isPremium;

  const CalendarPage({
    super.key,
    required this.onNavigate,
    required this.onSetActiveTask,
    required this.onUpdateTask,
    required this.isPremium,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late Stream<List<Task>> _tasksStream;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _setupTasksStream();
  }

  void _setupTasksStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _tasksStream = FirebaseFirestore.instance
          .collection('users').doc(user.uid).collection('tasks')
          .where('isDeleted', isEqualTo: false)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList());
    } else {
      _tasksStream = Stream.value([]);
    }
  }

  List<Task> _getTasksForDay(DateTime day, List<Task> allTasks) {
    return allTasks.where((task) {
      if (task.dueDate == null) return false;
      final taskDate = task.dueDate!.toDate();
      return isSameDay(taskDate, day);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: StreamBuilder<List<Task>>(
        stream: _tasksStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text("Could not load tasks."));
          }

          final allTasks = snapshot.data!;
          final selectedTasks = _getTasksForDay(_selectedDay!, allTasks);

          return Column(
            children: [
              TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                eventLoader: (day) => _getTasksForDay(day, allTasks),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                ),
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: const TextStyle(color: Colors.black),
                  markerDecoration: BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: _buildTaskList(selectedTasks),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTaskList(List<Task> tasks) {
    if (tasks.isEmpty) {
      return const Center(
        child: Text("No tasks for this day.", style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return TaskListItem(
          task: task,
          onPlay: () => widget.onSetActiveTask(task),
          onTap: () async {
            final updatedTask = await showModalBottomSheet<Task>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => AddTaskSheet(taskToEdit: task, isPremium: widget.isPremium));
            if (updatedTask != null) {
              widget.onUpdateTask(updatedTask);
            }
          },
        );
      },
    );
  }
}

class ReportPage extends StatefulWidget {
  final Function(int) onNavigate;
  const ReportPage({super.key, required this.onNavigate});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  ReportTimeframe _selectedTimeframe = ReportTimeframe.week;
  bool _isLoading = true;

  int _totalCompletedSessions = 0;
  int _totalFocusMinutes = 0;

  Map<String, dynamic>? _bestDayStats;

  Map<int, double> _hourlySummary = {};
  Map<int, double> _dailySummary = {};
  List<double> _weeklySummary = List.filled(7, 0.0);

  @override
  void initState() {
    super.initState();
    _fetchReportData();
  }

  Future<void> _fetchReportData() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final now = DateTime.now();
    DateTime? startDate;

    switch (_selectedTimeframe) {
      case ReportTimeframe.day:
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case ReportTimeframe.week:
        startDate = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        break;
      case ReportTimeframe.month:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case ReportTimeframe.allTime:
        startDate = null;
        break;
    }

    Query query = FirebaseFirestore.instance
        .collection('users').doc(user.uid).collection('tasks')
        .where('isCompleted', isEqualTo: true);

    if (startDate != null) {
      query = query.where('completedAt', isGreaterThanOrEqualTo: startDate);
    }

    final querySnapshot = await query.get();
    final tasks = querySnapshot.docs.map((doc) => Task.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>)).toList();

    int sessionSum = 0;
    int minuteSum = 0;
    Map<int, double> hourly = {};
    Map<int, double> daily = {};
    List<double> weekly = List.filled(7, 0.0);

    Map<int, Map<String, int>> weeklyDayAggregates = {};
    Map<DateTime, Map<String, int>> specificDateAggregates = {};

    for (final task in tasks) {
      if (task.completedAt == null) continue;

      final completedAtDate = task.completedAt!.toDate();
      final minutes = task.totalMinutesCompleted;
      final sessions = task.completedPomodoros;

      sessionSum += sessions;
      minuteSum += minutes;

      final dayOfWeek = completedAtDate.weekday;
      weeklyDayAggregates.putIfAbsent(dayOfWeek, () => {'minutes': 0, 'sessions': 0});
      weeklyDayAggregates[dayOfWeek]!['minutes'] = weeklyDayAggregates[dayOfWeek]!['minutes']! + minutes;
      weeklyDayAggregates[dayOfWeek]!['sessions'] = weeklyDayAggregates[dayOfWeek]!['sessions']! + sessions;

      final specificDate = DateTime(completedAtDate.year, completedAtDate.month, completedAtDate.day);
      specificDateAggregates.putIfAbsent(specificDate, () => {'minutes': 0, 'sessions': 0});
      specificDateAggregates[specificDate]!['minutes'] = specificDateAggregates[specificDate]!['minutes']! + minutes;
      specificDateAggregates[specificDate]!['sessions'] = specificDateAggregates[specificDate]!['sessions']! + sessions;

      if (_selectedTimeframe == ReportTimeframe.week) {
        weekly[dayOfWeek - 1] += minutes.toDouble();
      } else if (_selectedTimeframe == ReportTimeframe.month) {
        final dayOfMonth = completedAtDate.day;
        daily.update(dayOfMonth, (value) => value + minutes, ifAbsent: () => minutes.toDouble());
      } else if (_selectedTimeframe == ReportTimeframe.day) {
        final hour = completedAtDate.hour;
        hourly.update(hour, (value) => value + minutes, ifAbsent: () => minutes.toDouble());
      }
    }

    Map<String, dynamic>? bestDayResult;
    if (_selectedTimeframe == ReportTimeframe.week) {
      if (weeklyDayAggregates.isNotEmpty) {
        int bestDayIndex = -1, maxMinutes = -1;
        weeklyDayAggregates.forEach((dayIndex, stats) {
          if (stats['minutes']! > maxMinutes) {
            maxMinutes = stats['minutes']!;
            bestDayIndex = dayIndex;
          }
        });
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        bestDayResult = {'dayName': days[bestDayIndex - 1], 'minutes': maxMinutes, 'sessions': weeklyDayAggregates[bestDayIndex]!['sessions']};
      }
    } else if (_selectedTimeframe == ReportTimeframe.month || _selectedTimeframe == ReportTimeframe.allTime) {
      if (specificDateAggregates.isNotEmpty) {
        DateTime? bestDate;
        int maxMinutes = -1;

        specificDateAggregates.forEach((date, stats) {
          if (stats['minutes']! > maxMinutes) {
            maxMinutes = stats['minutes']!;
            bestDate = date;
          }
        });

        if (bestDate != null) {
          bestDayResult = {'date': bestDate, 'minutes': maxMinutes, 'sessions': specificDateAggregates[bestDate]!['sessions']};
        }
      }
    }


    if (mounted) {
      setState(() {
        _totalCompletedSessions = sessionSum;
        _totalFocusMinutes = minuteSum;
        _bestDayStats = bestDayResult;
        _weeklySummary = weekly;
        _dailySummary = daily;
        _hourlySummary = hourly;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Productivity Report')),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _fetchReportData,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildTimeframeSelector(),
              const SizedBox(height: 24),
              _buildSectionHeader('Overview'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildStatCard('Sessions', _totalCompletedSessions.toString(), Iconsax.repeat, Colors.orange)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard('Focus Time', '${_totalFocusMinutes}m', Iconsax.clock, Colors.blue)),
                ],
              ),
              if (_bestDayStats != null) ...[
                const SizedBox(height: 16),
                _buildBestDayCard(),
              ],
              const SizedBox(height: 32),

              if (_selectedTimeframe == ReportTimeframe.week) ...[
                _buildSectionHeader("This Week's Focus"),
                const SizedBox(height: 16),
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                  child: WeeklyBarChart(weeklySummary: _weeklySummary),
                ),
              ] else if (_selectedTimeframe == ReportTimeframe.day) ...[
                _buildSectionHeader("Today's Focus by Hour"),
                const SizedBox(height: 16),
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                  child: HourlyBarChart(hourlySummary: _hourlySummary),
                ),
              ] else if (_selectedTimeframe == ReportTimeframe.month) ...[
                _buildSectionHeader("This Month's Focus by Day"),
                const SizedBox(height: 16),
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                  child: MonthlyBarChart(dailySummary: _dailySummary),
                ),
              ],
            ],
          ),
        )
    );
  }

  Widget _buildBestDayCard() {
    final stats = _bestDayStats!;
    final String title = stats.containsKey('date') ? DateFormat('MMMM d, yyyy').format(stats['date']) : stats['dayName'];
    final String subtitle = _selectedTimeframe == ReportTimeframe.week ? 'Your Best Day This Week' : 'Your Most Productive Day';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.amber,
            radius: 24,
            child: const Icon(Iconsax.cup, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${stats['minutes']} mins', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('${stats['sessions']} sessions', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white));
  }

  Widget _buildTimeframeSelector() {
    final timeframes = ReportTimeframe.values;
    final isSelected = timeframes.map((e) => _selectedTimeframe == e).toList();

    return Center(
      child: ToggleButtons(
        isSelected: isSelected,
        onPressed: (index) {
          setState(() {
            _selectedTimeframe = timeframes[index];
            _fetchReportData();
          });
        },
        borderRadius: BorderRadius.circular(30),
        selectedColor: Colors.black,
        color: Colors.white,
        fillColor: Theme.of(context).colorScheme.primary,
        borderColor: Colors.grey.shade700,
        selectedBorderColor: Theme.of(context).colorScheme.primary,
        children: [
          SizedBox(width: (MediaQuery.of(context).size.width - 40) / 4, child: const Center(child: Text('Day'))),
          SizedBox(width: (MediaQuery.of(context).size.width - 40) / 4, child: const Center(child: Text('Week'))),
          SizedBox(width: (MediaQuery.of(context).size.width - 40) / 4, child: const Center(child: Text('Month'))),
          SizedBox(width: (MediaQuery.of(context).size.width - 40) / 4, child: const Center(child: Text('All Time'))),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.2),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class WeeklyBarChart extends StatelessWidget {
  final List<double> weeklySummary;
  const WeeklyBarChart({super.key, required this.weeklySummary});

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: weeklySummary.isEmpty || weeklySummary.every((d) => d == 0) ? 50 : weeklySummary.reduce(max) * 1.2,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.round()} min',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                const style = TextStyle(color: Colors.grey, fontSize: 12);
                String text;
                switch (value.toInt()) {
                  case 0: text = 'M'; break;
                  case 1: text = 'T'; break;
                  case 2: text = 'W'; break;
                  case 3: text = 'T'; break;
                  case 4: text = 'F'; break;
                  case 5: text = 'S'; break;
                  case 6: text = 'S'; break;
                  default: text = ''; break;
                }
                return SideTitleWidget(axisSide: meta.axisSide, child: Text(text, style: style));
              },
              reservedSize: 28,
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barGroups: List.generate(7, (i) => BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: weeklySummary.length > i ? weeklySummary[i] : 0,
              color: Theme.of(context).colorScheme.primary,
              width: 15,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        )),
      ),
    );
  }
}

class HourlyBarChart extends StatelessWidget {
  final Map<int, double> hourlySummary;
  const HourlyBarChart({super.key, required this.hourlySummary});

  @override
  Widget build(BuildContext context) {
    final maxY = hourlySummary.values.isEmpty ? 50.0 : hourlySummary.values.reduce(max) * 1.2;

    return BarChart(
      BarChartData(
        maxY: maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.round()} min',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                const style = TextStyle(color: Colors.grey, fontSize: 10);
                String text;
                switch (value.toInt()) {
                  case 0: text = '12A'; break;
                  case 6: text = '6A'; break;
                  case 12: text = '12P'; break;
                  case 18: text = '6P'; break;
                  default: text = ''; break;
                }
                return SideTitleWidget(axisSide: meta.axisSide, child: Text(text, style: style));
              },
              reservedSize: 22,
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barGroups: List.generate(24, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: hourlySummary[i] ?? 0,
                color: Theme.of(context).colorScheme.primary,
                width: 5,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class MonthlyBarChart extends StatelessWidget {
  final Map<int, double> dailySummary;
  const MonthlyBarChart({super.key, required this.dailySummary});

  @override
  Widget build(BuildContext context) {
    final maxY = dailySummary.values.isEmpty ? 50.0 : dailySummary.values.reduce(max) * 1.2;
    final daysInMonth = DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;

    return BarChart(
      BarChartData(
        maxY: maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                'Day ${group.x.toInt()}: ${rod.toY.round()} min',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                const style = TextStyle(color: Colors.grey, fontSize: 10);
                if (value.toInt() % 7 == 1 || value.toInt() == daysInMonth) {
                  return SideTitleWidget(axisSide: meta.axisSide, child: Text(value.toInt().toString(), style: style));
                }
                return const SizedBox.shrink();
              },
              reservedSize: 22,
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barGroups: List.generate(daysInMonth, (i) {
          final day = i + 1;
          return BarChartGroupData(
            x: day,
            barRods: [
              BarChartRodData(
                toY: dailySummary[day] ?? 0,
                color: Theme.of(context).colorScheme.primary,
                width: 7,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
      ),
    );
  }
}

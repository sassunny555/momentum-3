import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'models/task_model.dart';

// A global instance of the notification service that can be accessed from anywhere.
final NotificationService notificationService = NotificationService();

class NotificationService {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();
  static const String _notificationsEnabledKey = 'notifications_enabled';

  // Channel details for Android notifications.
  static const AndroidNotificationDetails _androidDetails =
  AndroidNotificationDetails(
    'momentum_channel_id',
    'Momentum Reminders',
    channelDescription: 'Channel for Momentum task and session reminders',
    importance: Importance.max,
    priority: Priority.high,
  );

  static const DarwinNotificationDetails _iosDetails =
  DarwinNotificationDetails();
  static const NotificationDetails _platformDetails =
  NotificationDetails(android: _androidDetails, iOS: _iosDetails);

  /// Initializes the notification service, setting up timezones and platform settings.
  Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // Request all necessary permissions on iOS upon initialization.
    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  /// Checks if the user has enabled notifications in the app's settings.
  Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? false;
  }

  /// Schedules a notification for a task's due date.
  Future<void> scheduleTaskNotification(Task task) async {
    if (!await areNotificationsEnabled() || task.dueDate == null) return;

    final scheduledDateTime =
    tz.TZDateTime.from(task.dueDate!.toDate(), tz.local);

    // FIX: Removed the isBefore() check that was causing the race condition.
    // The OS will handle scheduling for times that are very close to now.

    await flutterLocalNotificationsPlugin.zonedSchedule(
      task.id.hashCode, // Use a hash of the task ID for a unique notification ID.
      'Task Reminder',
      'Time to start focusing on: ${task.title}',
      scheduledDateTime,
      _platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedules a notification for when a timer session (focus, break) ends.
  Future<void> scheduleSessionEndNotification({
    required Duration inDuration,
    required String title,
    required String body,
    required int id, // A unique ID for this type of notification.
  }) async {
    if (!await areNotificationsEnabled()) return;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.now(tz.local).add(inDuration),
      _platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Sends an immediate test notification.
  Future<void> sendTestNotification() async {
    await flutterLocalNotificationsPlugin.show(
      -1, // A unique ID for the test notification.
      'Test Notification',
      'This is a sample reminder from Momentum!',
      _platformDetails,
    );
  }

  /// Cancels a specific scheduled notification using its unique ID.
  Future<void> cancelNotification(int notificationId) async {
    await flutterLocalNotificationsPlugin.cancel(notificationId);
  }
}

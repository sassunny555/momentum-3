import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _notificationsEnabled = false;
  PermissionStatus _permissionStatus = PermissionStatus.denied;
  // For Android, we need a separate permission to schedule exact alarms.
  PermissionStatus _alarmPermissionStatus = PermissionStatus.denied;
  final String _notificationsEnabledKey = 'notifications_enabled';

  @override
  void initState() {
    super.initState();
    _loadSettingsAndPermissions();
  }

  /// Loads the user's saved preference and current system permission status.
  Future<void> _loadSettingsAndPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final status = await Permission.notification.status;
    final alarmStatus = await Permission.scheduleExactAlarm.status;
    setState(() {
      _notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? false;
      _permissionStatus = status;
      _alarmPermissionStatus = alarmStatus;
    });
  }

  /// Handles the logic when the user toggles the notification switch.
  Future<void> _toggleNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      // Request both notification and exact alarm permissions.
      final statuses = await [
        Permission.notification,
        Permission.scheduleExactAlarm,
      ].request();

      final notificationStatus = statuses[Permission.notification];
      final alarmStatus = statuses[Permission.scheduleExactAlarm];

      setState(() {
        _permissionStatus = notificationStatus ?? PermissionStatus.denied;
        _alarmPermissionStatus = alarmStatus ?? PermissionStatus.denied;
      });

      // Only enable if both permissions are granted.
      if (_permissionStatus.isGranted && _alarmPermissionStatus.isGranted) {
        await prefs.setBool(_notificationsEnabledKey, true);
        setState(() {
          _notificationsEnabled = true;
        });
      } else {
        // If permissions are denied, keep the switch off and show a dialog.
        await prefs.setBool(_notificationsEnabledKey, false);
        setState(() {
          _notificationsEnabled = false;
        });
        _showPermissionDialog();
      }
    } else {
      // If the user toggles it off, just save the preference.
      await prefs.setBool(_notificationsEnabledKey, false);
      setState(() {
        _notificationsEnabled = false;
      });
    }
  }

  /// Shows a dialog guiding the user to their phone's settings.
  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
            'To receive reminders, you need to grant notification and alarm permissions in your phone\'s settings.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text('Open Settings'),
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The master switch is only "on" if the user setting is true AND both permissions are granted.
    final bool isSwitchOn = _notificationsEnabled &&
        _permissionStatus.isGranted &&
        _alarmPermissionStatus.isGranted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Enable Task Reminders'),
            subtitle:
            const Text('Receive notifications for tasks and sessions.'),
            value: isSwitchOn,
            onChanged: _toggleNotifications,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Iconsax.notification_status),
            title: const Text('Send a Test Notification'),
            subtitle: !isSwitchOn
                ? const Text('Enable reminders to test',
                style: TextStyle(color: Colors.grey))
                : null,
            enabled: isSwitchOn,
            onTap: () {
              notificationService.sendTestNotification();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Test notification sent!')),
              );
            },
          ),
          // Show the helper card if permissions are missing.
          if (!_permissionStatus.isGranted || !_alarmPermissionStatus.isGranted)
            _buildPermissionHelper(),
        ],
      ),
    );
  }

  /// A helper widget that appears when permissions are not granted.
  Widget _buildPermissionHelper() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        color: Colors.red.withOpacity(0.2),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text(
                'Permissions Required',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Notifications and alarms are currently disabled for Momentum. Please enable them in your phone\'s settings to receive reminders.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: openAppSettings,
                child: const Text('Open App Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:momentum/main_scaffold.dart';
import 'package:momentum/models/task_model.dart';
import 'package:momentum/notification_settings_page.dart';
import 'package:momentum/premium_page.dart';

class ProfilePage extends StatelessWidget {
  final Function(int) onNavigate;
  final Function(Task) onRestoreTask;
  final Function(Task) onPermanentDeleteTask;
  final bool isPremium;
  final Future<void> Function(String newName, File? imageFile) onUpdateProfile;
  final String? localImagePath;

  const ProfilePage({
    super.key,
    required this.onNavigate,
    required this.onRestoreTask,
    required this.onPermanentDeleteTask,
    required this.isPremium,
    required this.onUpdateProfile,
    this.localImagePath,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Me'),
        actions: [
          IconButton(
              icon: const Icon(Iconsax.logout),
              onPressed: () => FirebaseAuth.instance.signOut())
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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
            onTap: () => _showEditProfileSheet(context, user),
          ),

          _buildSectionHeader('Account'),
          ListTile(
            leading: const Icon(Iconsax.crown_1, color: Colors.amber),
            title: const Text('Upgrade to Premium'),
            trailing: const Icon(Iconsax.arrow_right_3),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const PremiumPage()));
            },
          ),

          _buildSectionHeader('Settings'),
          ListTile(
            leading: const Icon(Iconsax.notification),
            title: const Text('Notifications'),
            trailing: const Icon(Iconsax.arrow_right_3),
            onTap: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (ctx) => const NotificationSettingsPage())
              );
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
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
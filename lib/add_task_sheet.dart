import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/task_model.dart';
import 'premium_page.dart';

class AddTaskSheet extends StatefulWidget {
  final Task? taskToEdit;
  // <-- ADDED: We now need to know if the user is premium
  final bool isPremium;

  const AddTaskSheet({super.key, this.taskToEdit, required this.isPremium});

  @override
  State<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<AddTaskSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isEditMode = false;

  IconData _selectedIcon = Iconsax.task_square;
  DateTime? _selectedDateTime;
  int _selectedPomodoros = 1;
  int _selectedTimePerPomodoro = 1500;
  int? _selectedPriority;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.taskToEdit != null) {
      _isEditMode = true;
      final task = widget.taskToEdit!;
      _titleController.text = task.title;
      _descriptionController.text = task.description ?? '';
      _selectedIcon = task.icon;
      _selectedPomodoros = task.totalPomodoros;
      _selectedTimePerPomodoro = task.timePerPomodoro;
      if (task.dueDate != null) {
        _selectedDateTime = task.dueDate!.toDate();
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _saveTask() {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Task title cannot be empty.");
      return;
    }

    final task = Task(
      id: _isEditMode ? widget.taskToEdit!.id : '',
      completedPomodoros: _isEditMode ? widget.taskToEdit!.completedPomodoros : 0,
      totalMinutesCompleted: _isEditMode ? widget.taskToEdit!.totalMinutesCompleted : 0,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      icon: _selectedIcon,
      totalPomodoros: _selectedPomodoros,
      timePerPomodoro: _selectedTimePerPomodoro,
      dueDate: _selectedDateTime == null ? null : Timestamp.fromDate(_selectedDateTime!),
      // Note: attemptCount is handled automatically by the refocus logic
    );

    Navigator.of(context).pop(task);
  }

  Future<void> _showIconPicker() async {
    final List<IconData> icons = [
      Iconsax.task_square, Iconsax.briefcase, Iconsax.book, Iconsax.personalcard,
      Iconsax.health, Iconsax.home_2, Iconsax.dollar_circle, Iconsax.cup,
      Iconsax.airplane, Iconsax.shopping_cart, Iconsax.heart, Iconsax.gift,
      Iconsax.music, Iconsax.pen_tool, Iconsax.camera, Iconsax.message,
      Iconsax.gameboy, Iconsax.command, Iconsax.flash, Iconsax.weight,
      Iconsax.shield_tick, Iconsax.sun, Iconsax.moon, Iconsax.code,
    ];

    final IconData? selectedIcon = await showDialog<IconData>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text('Choose an Icon', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 16.0,
                mainAxisSpacing: 16.0,
              ),
              itemCount: icons.length,
              itemBuilder: (BuildContext context, int index) {
                return IconButton(
                  icon: Icon(icons[index], color: Colors.white, size: 30),
                  onPressed: () {
                    Navigator.of(context).pop(icons[index]);
                  },
                );
              },
            ),
          ),
        );
      },
    );

    if (selectedIcon != null) {
      setState(() {
        _selectedIcon = selectedIcon;
      });
    }
  }

  // <-- MODIFIED: This function now checks for premium status
  Future<void> _pickDateTime() async {
    if (!widget.isPremium) {
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => const PremiumPage()));
      return;
    }

    final DateTime? date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2101));
    if (!context.mounted || date == null) return;
    final TimeOfDay? time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(DateTime.now()));
    if (!context.mounted || time == null) return;
    setState(() {
      _selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _navigateToPremiumPage() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => const PremiumPage(),
    ));
  }

  void _showCustomSessionSelector() {
    showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (BuildContext context) {
        return SizedBox(
          height: 300,
          child: ListView.builder(
            itemCount: 50,
            itemBuilder: (context, index) {
              final sessionNumber = index + 1;
              return ListTile(
                title: Center(child: Text('$sessionNumber Sessions', style: const TextStyle(color: Colors.white))),
                onTap: () {
                  setState(() => _selectedPomodoros = sessionNumber);
                  Navigator.pop(context);
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      labelStyle: const TextStyle(color: Colors.grey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0), borderSide: BorderSide(color: Colors.grey.shade800)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: const BoxDecoration(color: Color(0xFF1C1C1E), borderRadius: BorderRadius.vertical(top: Radius.circular(24.0))),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: GestureDetector(
                onTap: _showIconPicker,
                child: CircleAvatar(radius: 30, backgroundColor: Colors.grey.shade800, child: Icon(_selectedIcon, size: 30, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              maxLength: 50,
              decoration: inputDecoration.copyWith(labelText: 'Task title', counterText: ""),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _descriptionController,
              style: const TextStyle(color: Colors.white),
              maxLength: 200,
              decoration: inputDecoration.copyWith(labelText: 'Task description (optional)', counterText: ""),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Estimated Pomodoros'),
            _buildScrollableSelector<int>(
              options: {for (var i = 1; i <= 9; i++) i: '$i'}..addAll({99: 'Custom'}),
              selectedValue: _selectedPomodoros,
              onSelected: (value) {
                if(value == 99) {
                  widget.isPremium ? _showCustomSessionSelector() : _navigateToPremiumPage();
                } else {
                  setState(() => _selectedPomodoros = value);
                }
              },
              disabledValues: List.generate(widget.taskToEdit?.completedPomodoros ?? 0, (index) => index + 1),
              isPremium: widget.isPremium,
              premiumCondition: (value) => value > 1 && value != 99,
              onPremiumTap: _navigateToPremiumPage,
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Time per Pomodoro'),
            _buildScrollableSelector<int>(
              options: {600: '10m', 1500: '25m', 2700: '45m', 3600: '60m', 5400: '90m'},
              selectedValue: _selectedTimePerPomodoro,
              onSelected: (value) => setState(() => _selectedTimePerPomodoro = value),
              isPremium: widget.isPremium,
              premiumCondition: (value) => value != 1500,
              onPremiumTap: _navigateToPremiumPage,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _buildOptionButton(icon: Iconsax.calendar, label: _selectedDateTime == null ? 'Date & Time' : DateFormat('MMM d, h:mm a').format(_selectedDateTime!), onTap: _pickDateTime)),
                const SizedBox(width: 16),
                Expanded(child: _buildPriorityMenu()),
              ],
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12))),
              ),
            _isEditMode ? _buildEditButtons() : _buildCreateButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _saveTask,
        style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, padding: const EdgeInsets.symmetric(vertical: 16), shape: const StadiumBorder()),
        child: const Text('Create Task', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  Widget _buildEditButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: const StadiumBorder(), side: BorderSide(color: Colors.grey.shade800)),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _saveTask,
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, padding: const EdgeInsets.symmetric(vertical: 16), shape: const StadiumBorder()),
            child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Text(title, style: TextStyle(color: Colors.grey[400], fontSize: 14)));
  }

  Widget _buildScrollableSelector<T>({required Map<T, String> options, T? selectedValue, required ValueChanged<T> onSelected, List<T>? disabledValues, required bool isPremium, required bool Function(T) premiumCondition, required VoidCallback onPremiumTap}) {
    disabledValues ??= [];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.entries.map((entry) {
          final isSelected = selectedValue == entry.key;
          final isDisabled = disabledValues!.contains(entry.key);
          final isLocked = !isPremium && premiumCondition(entry.key);

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: OutlinedButton(
              onPressed: isDisabled ? null : (isLocked ? onPremiumTap : () => onSelected(entry.key)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: isSelected ? Colors.black : Colors.white,
                  backgroundColor: isDisabled ? Colors.grey.shade900 : (isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade800),
                  side: BorderSide(color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade700),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entry.value),
                  if (isLocked) ...[
                    const SizedBox(width: 6),
                    const Icon(Iconsax.crown_1, size: 14, color: Colors.amber),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPriorityMenu() {
    final priorities = {0: {'label': 'Easy', 'icon': Iconsax.arrow_down, 'color': Colors.green}, 1: {'label': 'Medium', 'icon': Iconsax.minus, 'color': Colors.orange}, 2: {'label': 'Hard', 'icon': Iconsax.arrow_up_3, 'color': Colors.red}};
    return PopupMenuButton<int>(
      initialValue: _selectedPriority,
      onSelected: (int item) => setState(() => _selectedPriority = item),
      itemBuilder: (context) => priorities.entries.map((entry) {
        return PopupMenuItem<int>(value: entry.key, child: Row(children: [Icon(entry.value['icon'] as IconData, color: entry.value['color'] as Color), const SizedBox(width: 8), Text(entry.value['label'] as String)]));
      }).toList(),
      child: _buildOptionButton(
        icon: _selectedPriority == null ? Iconsax.flag : priorities[_selectedPriority]!['icon'] as IconData,
        label: _selectedPriority == null ? 'Priority' : priorities[_selectedPriority]!['label'] as String,
        iconColor: _selectedPriority == null ? Colors.grey : priorities[_selectedPriority]!['color'] as Color,
      ),
    );
  }

  Widget _buildOptionButton({required IconData icon, required String label, VoidCallback? onTap, Color? iconColor}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.grey.shade800)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 20, color: iconColor ?? Colors.grey), const SizedBox(width: 8), Text(label, style: const TextStyle(color: Colors.white))]),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  int _selectedPlanIndex = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final plans = [
      {'title': 'Monthly', 'price': '\$5.99', 'description': 'per month'},
      {'title': 'Annual', 'price': '\$49.99', 'description': 'per year'},
      {'title': 'Lifetime', 'price': '\$149.99', 'description': 'one-time'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Momentum Premium'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withOpacity(0.5),
                      theme.colorScheme.primary.withOpacity(0.2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(Iconsax.crown_1, color: Colors.amber, size: 50),
                    SizedBox(height: 16),
                    Text(
                      'Unlock Your Full Potential',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Upgrade to access all exclusive features and\nmaximize your productivity.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              _buildFeatureRow(Iconsax.chart_2, 'Advanced Productivity Reports', Colors.amber.shade300),
              _buildFeatureRow(Iconsax.cup, 'Unlock All Achievements', Colors.amber.shade300),
              _buildFeatureRow(Iconsax.document_upload, 'Export Task History (CSV)', Colors.amber.shade300),
              _buildFeatureRow(Iconsax.timer_start, 'Custom Pomodoro Durations', Colors.amber.shade300),
              _buildFeatureRow(Iconsax.notification, 'Task Due Date Reminders', Colors.amber.shade300),
              _buildFeatureRow(Iconsax.repeat, 'Unlimited Custom Sessions', Colors.amber.shade300),


              const SizedBox(height: 32),

              Row(
                children: [
                  for (int i = 0; i < plans.length; i++)
                    Expanded(
                      child: _buildPricingCard(
                        title: plans[i]['title']!,
                        price: plans[i]['price']!,
                        description: plans[i]['description']!,
                        isSelected: i == _selectedPlanIndex,
                        onTap: () {
                          setState(() {
                            _selectedPlanIndex = i;
                          });
                        },
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 40),

              ElevatedButton(
                onPressed: () {
                  // TODO: Implement purchase logic
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  'Upgrade for ${plans[_selectedPlanIndex]['price']}',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 16),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4.0),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.2) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.grey.shade800,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(price, style: TextStyle(color: theme.colorScheme.primary, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main_scaffold.dart';
import 'welcome_screen.dart';



class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasData) {
          return const MainScaffold();
        }
        return const WelcomeScreen();
      },
    );
  }
}

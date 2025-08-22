import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore

class LoginScreen extends StatefulWidget {
  final bool startAsLogin;

  const LoginScreen({super.key, required this.startAsLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _isLogin;
  bool _isPasswordVisible = false;
  bool _rememberMe = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isLogin = widget.startAsLogin;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(email);
  }

  // NEW: Function to create the user document in Firestore
  Future<void> _createUserDocument(User user, [String? displayName]) async {
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    await userDocRef.set({
      'email': user.email,
      'displayName': displayName ?? user.displayName ?? 'New User',
      'createdAt': FieldValue.serverTimestamp(),
      'isPremium': false, // Set default premium status
      // Initialize other stats to 0
      'totalSessionsCompleted': 0,
      'totalTasksCompleted': 0,
      'totalFocusMinutes': 0,
      'totalTasksCreated': 0,
    });
    // Also update the auth profile display name if provided
    if (displayName != null && (user.displayName == null || user.displayName!.isEmpty)) {
      await user.updateProfile(displayName: displayName);
    }
  }

  Future<void> _signUp() async {
    if (_fullNameController.text.trim().isEmpty || _emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      setState(() { _errorMessage = "Please fill in all required fields."; });
      return;
    }
    if (!_isValidEmail(_emailController.text.trim())) {
      setState(() { _errorMessage = "Please enter a valid email address."; });
      return;
    }
    if (_passwordController.text.trim() != _confirmPasswordController.text.trim()) {
      setState(() { _errorMessage = "Passwords do not match."; });
      return;
    }

    setState(() { _errorMessage = null; });
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      final UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: _emailController.text.trim(), password: _passwordController.text.trim());

      // FIX: Create the user document in Firestore after sign up
      if (userCredential.user != null) {
        await _createUserDocument(userCredential.user!, _fullNameController.text.trim());
      }

      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);

    } on FirebaseAuthException catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog("Sign-Up Failed", e.message ?? "An unknown error occurred.");
    }
  }

  Future<void> _signIn() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      setState(() { _errorMessage = "Please enter your email and password."; });
      return;
    }
    if (!_isValidEmail(_emailController.text.trim())) {
      setState(() { _errorMessage = "Please enter a valid email address."; });
      return;
    }

    setState(() { _errorMessage = null; });
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _emailController.text.trim(), password: _passwordController.text.trim());
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog("Login Failed", e.message ?? "An unknown error occurred.");
    }
  }

  Future<void> _signInWithGoogle() async {
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      // FIX: Check if it's a new user and create their document if so
      if (userCredential.additionalUserInfo?.isNewUser == true && userCredential.user != null) {
        await _createUserDocument(userCredential.user!);
      }

      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);

    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog("Google Sign-In Failed", "An unexpected error occurred. Please try again.");
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !_isValidEmail(email)) {
      _showErrorDialog("Invalid Email", "Please enter a valid email address to reset your password.");
      return;
    }

    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog("Password Reset", "A password reset link has been sent to your email address.");
    } on FirebaseAuthException catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog("Error", e.message ?? "Could not send reset email.");
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(context: context, builder: (context) => AlertDialog(title: Text(title), content: Text(message), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))]));
  }

  void _showTermsDialog() {
    showDialog(context: context, builder: (BuildContext context) => AlertDialog(backgroundColor: const Color(0xFF1C1C1E), title: const Text('Terms & Conditions', style: TextStyle(color: Colors.white)), content: const SingleChildScrollView(child: Text('Here are the terms and conditions of using the Momentum app...', style: TextStyle(color: Colors.grey))), actions: <Widget>[TextButton(child: const Text('Close'), onPressed: () => Navigator.of(context).pop())]));
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      contentPadding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 24.0),
      labelStyle: const TextStyle(color: Colors.grey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0), borderSide: BorderSide(color: Colors.grey.shade800)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0), borderSide: BorderSide(color: Colors.grey.shade800)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Iconsax.arrow_left, color: Colors.white, size: 24), onPressed: () => Navigator.of(context).pop()),
        title: Image.asset('assets/images/app_logo.png', height: 30),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text(_isLogin ? 'Login Now' : 'Create an Account', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 48),

                if (!_isLogin)
                  TextFormField(controller: _fullNameController, style: const TextStyle(color: Colors.white), decoration: inputDecoration.copyWith(labelText: 'Full Name', prefixIcon: const Icon(Iconsax.user, color: Colors.grey))),
                if (!_isLogin) const SizedBox(height: 20),

                TextFormField(controller: _emailController, style: const TextStyle(color: Colors.white), decoration: inputDecoration.copyWith(labelText: 'Email', prefixIcon: const Icon(Iconsax.sms, color: Colors.grey)), keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 20),

                TextFormField(controller: _passwordController, style: const TextStyle(color: Colors.white), obscureText: !_isPasswordVisible, decoration: inputDecoration.copyWith(labelText: 'Password', prefixIcon: const Icon(Iconsax.lock, color: Colors.grey), suffixIcon: Padding(padding: const EdgeInsets.only(right: 12.0), child: IconButton(icon: Icon(_isPasswordVisible ? Iconsax.eye : Iconsax.eye_slash, color: Colors.grey), onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible))))),
                const SizedBox(height: 20),

                if (!_isLogin)
                  TextFormField(controller: _confirmPasswordController, style: const TextStyle(color: Colors.white), obscureText: !_isPasswordVisible, decoration: inputDecoration.copyWith(labelText: 'Confirm Password', prefixIcon: const Icon(Iconsax.lock, color: Colors.grey))),

                if (!_isLogin) const SizedBox(height: 20),

                if (!_isLogin)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                    child: RichText(textAlign: TextAlign.center, text: TextSpan(style: TextStyle(color: Colors.grey[600], fontSize: 12), children: <TextSpan>[const TextSpan(text: 'By signing up, you agree to our '), TextSpan(text: 'Terms & Conditions', style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = _showTermsDialog)])),
                  ),

                if (_isLogin)
                  Row(children: [
                    SizedBox(width: 24, height: 24, child: Checkbox(value: _rememberMe, onChanged: (bool? value) => setState(() => _rememberMe = value ?? false), checkColor: Colors.black, activeColor: const Color(0xFF7DFF00), side: BorderSide(color: Colors.grey.shade700))),
                    const SizedBox(width: 8),
                    const Text('Remember me', style: TextStyle(color: Colors.white)),
                    const Spacer(),
                    TextButton(onPressed: _forgotPassword, child: const Text('Forgot password?'))
                  ]),

                if (_errorMessage != null)
                  Padding(padding: const EdgeInsets.only(top: 8.0, bottom: 8.0), child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12), textAlign: TextAlign.center)),

                const SizedBox(height: 10),

                ElevatedButton(
                  onPressed: _isLogin ? _signIn : _signUp,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7DFF00), padding: const EdgeInsets.symmetric(vertical: 16), shape: const StadiumBorder()),
                  child: Text(_isLogin ? 'Login' : 'Sign Up', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                ),
                const SizedBox(height: 32),

                Center(child: Text(_isLogin ? 'Or Log in with' : 'Or Sign up with', style: TextStyle(color: Colors.grey[600]))),
                const SizedBox(height: 24),

                Center(
                  child: SizedBox(
                    width: 250,
                    child: OutlinedButton.icon(
                      onPressed: _signInWithGoogle,
                      icon: Image.asset('assets/images/ic_google_logo.png', height: 20),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), side: BorderSide(color: Colors.grey.shade800), shape: const StadiumBorder()),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_isLogin ? "Didn't have an account?" : 'Already have an account?', style: TextStyle(color: Colors.grey[600])),
                  TextButton(onPressed: () => setState(() => _isLogin = !_isLogin), child: Text(_isLogin ? 'Sign Up' : 'Login')),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

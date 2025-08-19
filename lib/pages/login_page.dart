import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:risol_galuh/pages/layanan_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    // Delay untuk animasi fade-in logo
    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() {
        _opacity = 1.0;
      });
    });
  }

  Future<void> login() async {
    setState(() => isLoading = true);

    final res = await http.post(
      Uri.parse('https://bpjsapi.quantumtechapp.com/risol-api/login.php'),
      body: {
        'username': usernameController.text,
        'password': passwordController.text,
      },
    );

    final data = jsonDecode(res.body);
    setState(() => isLoading = false);

    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      final user = data['user'];

      await prefs.setString('token', data['token'] ?? '');
      await prefs.setString('nama', user['nama'] ?? '');
      await prefs.setString('role', user['role'] ?? '');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LayananPage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message'] ?? 'Login gagal')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedOpacity(
                  duration: const Duration(seconds: 1),
                  opacity: _opacity,
                  child: Image.asset(
                    'assets/logo.png',
                    width: 120,
                    height: 120,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Risol Galuh',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton.icon(
                          onPressed: login,
                          icon: const Icon(Icons.login),
                          label: const Text('Login'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';
import 'user/user_main_screen.dart';
import 'admin/admin_main_screen.dart';
import '../newsfeeds/home_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String _selectedRole = '';
  Map<String, dynamic>? _savedUser;

  @override
  void initState() {
    super.initState();
    _checkSavedRole();
    _loadSavedUser();
  }

  Future<void> _loadSavedUser() async {
    final user = await _authService.getLastUser();
    if (user != null && mounted) {
      String savedRole = (user['role'] ?? '').toString().toLowerCase();
      // Map super_admin to admin for the dropdown/logic
      if (savedRole == 'super_admin') {
        savedRole = 'admin';
      }
      
      setState(() {
        _savedUser = user;
        _emailController.text = user['email'] ?? user['username'] ?? '';
        _selectedRole = savedRole;
      });
    }
  }

  Future<void> _checkSavedRole() async {
    final accessToken = await _authService.getAccessToken();
    if (accessToken != null) {
      final user = await _authService.getUser();
      if (user != null && mounted) {
        final isActive = user['isActive'] ?? false;
        if (!isActive) {
          await _authService.logout();
          return;
        }

        final role = user['role'];
        if (role == 'admin') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminMainScreen()));
        } else if (role == 'employee') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => UserMainScreen(initialIndex: 0)));
        }
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final email = _savedUser != null 
          ? (_savedUser!['email'] ?? _savedUser!['username'] ?? '').toString()
          : _emailController.text.trim();
      final password = _passwordController.text;
      String role = _savedUser != null 
          ? (_savedUser!['role'] ?? '').toString().toLowerCase()
          : _selectedRole;
      
      // Map specific roles to login categories if needed
      if (role == 'super_admin') {
        role = 'admin';
      }

      final result = await _authService.login(email, password, role);
      setState(() => _isLoading = false);

      if (mounted) {
        if (result['success'] == true) {
          final role = result['role'];
          final isActive = result['isActive'] ?? false;
          final userData = result['data'];

          if (!isActive) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission Denied'), backgroundColor: Colors.redAccent));
            return;
          }

          if (userData != null) {
            await _authService.saveLocalSession(userData);
            _authService.registerFcmInBackground();
          }

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome back, $role!'), backgroundColor: const Color(0xFF00A884)));

          if (role == 'admin') {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminMainScreen()));
          } else if (role == 'employee') {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => UserMainScreen(initialIndex: 0)));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Login failed'), backgroundColor: Colors.redAccent));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color waDarkBg = Color(0xFF111B21);
    const Color waTeal = Color(0xFF00A884);

    return Scaffold(
      backgroundColor: waDarkBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen())),
        ),
        title: const Text('Login Portal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(color: waTeal.withOpacity(0.1), shape: BoxShape.circle),
                    child: _savedUser != null && AuthService.getProfileImage(_savedUser) != null
                        ? CircleAvatar(
                            radius: 40,
                            backgroundImage: NetworkImage(_authService.getFullUrl(AuthService.getProfileImage(_savedUser))!),
                          )
                        : const Icon(Icons.admin_panel_settings_outlined, size: 48, color: waTeal),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _savedUser != null ? 'Welcome Back, ${_savedUser!['name']}' : 'Welcome Back',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _savedUser != null ? 'Enter password to continue' : 'Sign in to continue to your dashboard',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                  const SizedBox(height: 48),
                  if (_savedUser == null) ...[
                    _buildTextField(_emailController, 'Usermail', Icons.email_outlined),
                    const SizedBox(height: 20),
                    _buildRoleDropdown(),
                    const SizedBox(height: 20),
                  ],
                  _buildTextField(_passwordController, 'Password', Icons.lock_outline, obscure: _obscurePassword, isPassword: true),
                  const SizedBox(height: 12),
                  if (_savedUser != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _savedUser = null;
                            _emailController.clear();
                            _selectedRole = '';
                          });
                        },
                        child: const Text('Switch Account', style: TextStyle(color: waTeal, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: waTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool obscure = false, bool isPassword = false}) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.white60),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white60),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF202C33),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF00A884))),
      ),
      validator: (value) => (value == null || value.trim().isEmpty) ? 'Required field' : null,
    );
  }

  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedRole,
      dropdownColor: const Color(0xFF202C33),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Role',
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: const Icon(Icons.badge_outlined, color: Colors.white60),
        filled: true,
        fillColor: const Color(0xFF202C33),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF00A884))),
      ),
      items: const [
        DropdownMenuItem(value: '', child: Text('Select Role', style: TextStyle(color: Colors.white38))),
        DropdownMenuItem(value: 'admin', child: Text('Admin')),
        DropdownMenuItem(value: 'employee', child: Text('Employee')),
      ],
      onChanged: (value) => setState(() => _selectedRole = value ?? ''),
      validator: (value) => (value == null || value.isEmpty) ? 'Please select a role' : null,
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/signin/signedin_user_details.dart' as auth_models;
import '../../services/auth_service.dart';
import 'common_widgets/user_layout.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  auth_models.User? _user;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
  }

  Future<void> _loadUserDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('signedinuser');
      if (userJson != null) {
        final Map<String, dynamic> data = jsonDecode(userJson);
        if (mounted) {
          setState(() {
            _user = auth_models.User.fromJson(data);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _onRefresh() async {
    await _loadUserDetails();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile reloaded'), backgroundColor: Color(0xFF00A884)),
      );
    }
  }

  void _showChangePasswordDialog() {
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF202C33),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Change Password', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSettingsTextField(_oldPasswordController, 'Old Password', true),
                  const SizedBox(height: 16),
                  _buildSettingsTextField(_newPasswordController, 'New Password', true),
                  const SizedBox(height: 16),
                  _buildSettingsTextField(_confirmPasswordController, 'Confirm New Password', true),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final oldPass = _oldPasswordController.text.trim();
                        final newPass = _newPasswordController.text.trim();
                        final confPass = _confirmPasswordController.text.trim();

                        if (oldPass.isEmpty || newPass.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please fill all fields')),
                          );
                          return;
                        }

                        if (newPass != confPass) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Passwords do not match')),
                          );
                          return;
                        }

                        if (newPass.length < 8) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('New password must be at least 8 characters')),
                          );
                          return;
                        }

                        setModalState(() => isSubmitting = true);
                        final result = await AuthService().changePassword(
                          oldPassword: oldPass,
                          newPassword: newPass,
                        );

                        if (!mounted) return;
                        setModalState(() => isSubmitting = false);

                        if (result['success'] == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result['message'] ?? 'Password changed successfully'),
                              backgroundColor: const Color(0xFF25D366),
                            ),
                          );
                          _oldPasswordController.clear();
                          _newPasswordController.clear();
                          _confirmPasswordController.clear();
                          Navigator.pop(context);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result['message'] ?? 'Failed to change password'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884)),
                child: isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit'),
              ),
            ],
          );
        });
      },
    );
  }

  void _showEditDetailsDialog() {
    final nameCtrl = TextEditingController(text: _user?.username ?? '');
    final emailCtrl = TextEditingController(text: _user?.email ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF202C33),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSettingsTextField(nameCtrl, 'Name', false),
              const SizedBox(height: 16),
              _buildSettingsTextField(emailCtrl, 'Mail ID (Disabled)', false, enabled: false),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884)),
              child: const Text('Save Details'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsTextField(TextEditingController controller, String label, bool obscure, {bool enabled = true}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        filled: !enabled,
        fillColor: enabled ? Colors.transparent : Colors.white.withOpacity(0.05),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return UserLayout(
      title: 'Profile',
      currentIndex: 2,
      onRefresh: _onRefresh,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF202C33),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Profile Details',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        onPressed: _showEditDetailsDialog,
                        icon: const Icon(Icons.edit_note, color: Color(0xFF00A884)),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                  _buildDetailRow('Name', _user?.username ?? 'Loading...'),
                  _buildDetailRow('Mail ID', _user?.email ?? 'Loading...'),
                  _buildDetailRow('Username', _user?.username ?? 'Loading...'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF202C33),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: ListTile(
                leading: const Icon(Icons.lock_outline, color: Color(0xFF00A884)),
                title: const Text('Change Password', style: TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white24),
                onTap: _showChangePasswordDialog,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

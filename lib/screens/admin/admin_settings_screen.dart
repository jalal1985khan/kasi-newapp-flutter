import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/signin/signedin_user_details.dart';
import '../../services/auth_service.dart';
import 'admin_common_widgets/admin_layout.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  User? _user;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
  }

  Future<void> _loadUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('signedinuser');
    if (userJson != null) {
      if (mounted) {
        setState(() {
          _user = User.fromJson(jsonDecode(userJson));
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    await _loadUserDetails();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings reloaded'), backgroundColor: Color(0xFF00A884)),
      );
    }
  }

  void _showChangePasswordDialog() {
    bool isSubmitting = false;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: modalBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Change Password', style: TextStyle(color: textColor)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSettingsTextField(_oldPasswordController, 'Old Password', true, isDark, textColor),
                  const SizedBox(height: 16),
                  _buildSettingsTextField(_newPasswordController, 'New Password', true, isDark, textColor),
                  const SizedBox(height: 16),
                  _buildSettingsTextField(_confirmPasswordController, 'Confirm New Password', true, isDark, textColor),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884), foregroundColor: Colors.white),
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
    final nameCtrl = TextEditingController(text: _user?.name ?? '');
    final emailCtrl = TextEditingController(text: _user?.email ?? '');

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: modalBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Edit Details', style: TextStyle(color: textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSettingsTextField(nameCtrl, 'Name', false, isDark, textColor),
              const SizedBox(height: 16),
              _buildSettingsTextField(emailCtrl, 'Email (Disabled)', false, isDark, textColor, enabled: false),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
            ),
            ElevatedButton(
              onPressed: () {
                // Future API integration
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884), foregroundColor: Colors.white),
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsTextField(TextEditingController controller, String label, bool obscure, bool isDark, Color textColor, {bool enabled = true}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: textColor.withOpacity(0.6)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
        filled: !enabled,
        fillColor: enabled ? Colors.transparent : textColor.withOpacity(0.05),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;

    return AdminLayout(
      title: 'Settings',
      currentIndex: 3,
      onRefresh: _onRefresh,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: textColor.withOpacity(0.05)),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Profile Details',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                      ),
                      IconButton(
                        onPressed: _showEditDetailsDialog,
                        icon: const Icon(Icons.edit_note_outlined, color: Color(0xFF00A884)),
                      ),
                    ],
                  ),
                  Divider(color: isDark ? Colors.white10 : Colors.black12),
                  _buildDetailRow('Name', _user?.name ?? 'Loading...', textColor, subTextColor),
                  _buildDetailRow('Mail ID', _user?.email ?? 'Loading...', textColor, subTextColor),
                  _buildDetailRow('Username', _user?.username ?? 'Loading...', textColor, subTextColor),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: textColor.withOpacity(0.05)),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: ListTile(
                leading: const Icon(Icons.lock_outline, color: Color(0xFF00A884)),
                title: Text('Change Password', style: TextStyle(color: textColor)),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: subTextColor.withOpacity(0.5)),
                onTap: _showChangePasswordDialog,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: subTextColor, fontWeight: FontWeight.w500),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

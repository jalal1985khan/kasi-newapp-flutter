import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/signin/signedin_user_details.dart' as auth_models;
import '../../services/auth_service.dart';
import 'common_widgets/user_layout.dart';
import '../../utils/premium_widgets.dart';
import 'package:image_picker/image_picker.dart';

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
  bool _isUploadingImage = false;

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

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white70 : Colors.black54;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            decoration: BoxDecoration(
              color: modalBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Change Password',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Update your account security by choosing a new password.',
                  style: TextStyle(color: subTextColor, fontSize: 14),
                ),
                const SizedBox(height: 24),
                _buildSettingsTextField(_oldPasswordController, 'Current Password', true, isDark, textColor),
                const SizedBox(height: 16),
                _buildSettingsTextField(_newPasswordController, 'New Password', true, isDark, textColor),
                const SizedBox(height: 16),
                _buildSettingsTextField(_confirmPasswordController, 'Confirm New Password', true, isDark, textColor),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A884),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: isSubmitting
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Update Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: subTextColor)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image == null) return;

    if (mounted) setState(() => _isUploadingImage = true);

    try {
      final uploadResult = await AuthService().uploadProfileImage(image.path);
      if (uploadResult['success'] == true) {
        final imageUrl = uploadResult['url'];
        final updateResult = await AuthService().updateProfile(profileImage: imageUrl);
        
        if (updateResult['success'] == true) {
          await _loadUserDetails();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile image updated'), backgroundColor: Color(0xFF25D366)),
            );
          }
        } else {
          throw Exception(updateResult['message']);
        }
      } else {
        throw Exception(uploadResult['message']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _showEditDetailsDialog() {
    final nameCtrl = TextEditingController(text: _user?.name ?? '');
    final emailCtrl = TextEditingController(text: _user?.email ?? '');

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color modalBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white70 : Colors.black54;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          decoration: BoxDecoration(
            color: modalBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Keep your profile information up to date.',
                style: TextStyle(color: subTextColor, fontSize: 14),
              ),
              const SizedBox(height: 24),
              _buildSettingsTextField(nameCtrl, 'Full Name', false, isDark, textColor),
              const SizedBox(height: 16),
              _buildSettingsTextField(emailCtrl, 'Email Address (System Only)', false, isDark, textColor, enabled: false),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    // Future API integration
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A884),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Discard Changes', style: TextStyle(color: subTextColor)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsTextField(TextEditingController controller, String label, bool obscure, bool isDark, Color textColor, {bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: textColor.withOpacity(0.6),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark ? (enabled ? const Color(0xFF202C33) : Colors.white.withOpacity(0.05)) : (enabled ? Colors.grey[50] : Colors.grey[100]),
            hintStyle: TextStyle(color: textColor.withOpacity(0.3)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF00A884), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.6) : Colors.black54;

    return UserLayout(
      title: 'Profile',
      currentIndex: 2,
      onRefresh: _onRefresh,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // ── PROFILE HEADER ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111B21) : Colors.white,
                border: Border(bottom: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05))),
              ),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF00A884), width: 2),
                        ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: const Color(0xFF00A884).withOpacity(0.1),
                            backgroundImage: _user?.profileImage != null && _user!.profileImage!.isNotEmpty
                                ? NetworkImage(_user!.profileImage!)
                                : null,
                            child: _isUploadingImage
                                ? const CircularProgressIndicator(color: Colors.white)
                                : (_user?.profileImage == null || _user!.profileImage!.isEmpty
                                    ? Text(
                                        _user?.name.isNotEmpty == true ? _user!.name[0].toUpperCase() : '?',
                                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF00A884)),
                                      )
                                    : null),
                          ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _pickAndUploadImage,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Color(0xFF00A884), shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _user?.name ?? 'Loading...',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _user?.email ?? '...',
                    style: TextStyle(fontSize: 14, color: subTextColor),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A884).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ACTIVE EMPLOYEE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00A884), letterSpacing: 1),
                    ),
                  ),
                ],
              ),
            ),

            // ── DETAILS SECTION ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACCOUNT INFORMATION',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    isDark,
                    [
                      _buildDetailRow('Display Name', _user?.name ?? '...', textColor, subTextColor, Icons.person_outline),
                      _buildDetailRow('Email ID', _user?.email ?? '...', textColor, subTextColor, Icons.mail_outline),
                      _buildDetailRow('Username', _user?.username ?? '...', textColor, subTextColor, Icons.alternate_email),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  Text(
                    'SECURITY',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    isDark,
                    [
                      SoftTouchWrapper(
                        onTap: _showChangePasswordDialog,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: const Icon(Icons.lock_reset_rounded, color: Color(0xFF00A884)),
                          title: Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
                          subtitle: Text('Regularly update for better security', style: TextStyle(fontSize: 12, color: subTextColor)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      'App Version 2.4.0',
                      style: TextStyle(fontSize: 12, color: subTextColor.withOpacity(0.5)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(bool isDark, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202C33) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color textColor, Color subTextColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: textColor.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF00A884)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

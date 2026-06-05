import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/signin/signedin_user_details.dart';
import '../../services/auth_service.dart';
import 'admin_common_widgets/admin_layout.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/chat/local_database_service.dart';
import '../../services/update/update_service.dart';

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
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final ver = await UpdateService.getResolvedVersion();
      if (mounted) {
        setState(() {
          _appVersion = ver.isNotEmpty ? 'App Version $ver' : '';
        });
      }
    } catch (e) {
      debugPrint('Error loading app version: $e');
      if (mounted) {
        setState(() {
          _appVersion = '';
        });
      }
    }
  }

  bool _isUploadingImage = false;

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
    await AuthService().fetchUserProfile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings reloaded'), backgroundColor: Color(0xFF00A884)),
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
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                  _buildSettingsTextField(emailCtrl, 'Email Address', false, isDark, textColor),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final newName = nameCtrl.text.trim();
                              final newEmail = emailCtrl.text.trim();

                              if (newName.isEmpty || newEmail.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please fill all fields')),
                                );
                                return;
                              }

                              setModalState(() => isSubmitting = true);

                              final result = await AuthService().updateProfile(
                                name: newName,
                                email: newEmail,
                              );

                              if (!mounted) return;
                              setModalState(() => isSubmitting = false);

                              if (result['success'] == true) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(result['message'] ?? 'Profile updated successfully'),
                                    backgroundColor: const Color(0xFF25D366),
                                  ),
                                );
                                await _loadUserDetails();
                                Navigator.pop(context);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(result['message'] ?? 'Failed to update profile'),
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
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
    final Color cardBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white.withOpacity(0.6) : Colors.black54;

    return AdminLayout(
      showBottomNav: false,
      title: 'Settings',
      currentIndex: -1, // Settings is usually index 4
      onRefresh: _onRefresh,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: AuthService.userNotifier,
              builder: (context, user, child) {
                return Container(
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
                              backgroundImage: AuthService.getProfileImage(user) != null && AuthService.getProfileImage(user)!.isNotEmpty
                                  ? NetworkImage("${AuthService().getFullUrl(AuthService.getProfileImage(user))}?t=${user?['updatedAt'] ?? user?['updated_at'] ?? '1'}")
                                  : null,
                              child: _isUploadingImage
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : (AuthService.getProfileImage(user) == null || AuthService.getProfileImage(user)!.isEmpty
                                      ? Text(
                                          user?['name'] != null && user!['name'].toString().isNotEmpty ? user['name'].toString()[0].toUpperCase() : '?',
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
                        user?['name'] ?? 'Loading...',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?['email'] ?? '...',
                        style: TextStyle(fontSize: 14, color: subTextColor),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A884).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'ACTIVE ACCOUNT',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00A884), letterSpacing: 1),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ── DETAILS SECTION ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'ACCOUNT INFORMATION',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.2),
                              ),
                              GestureDetector(
                                onTap: _showEditDetailsDialog,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00A884).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_rounded, size: 14, color: Color(0xFF00A884)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Edit',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00A884)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                  ValueListenableBuilder<Map<String, dynamic>?>(
                    valueListenable: AuthService.userNotifier,
                    builder: (context, user, child) {
                      return _buildSectionCard(
                        isDark,
                        [
                          _buildDetailRow('Display Name', user?['name'] ?? '...', textColor, subTextColor, Icons.person_outline),
                          _buildDetailRow('Email ID', user?['email'] ?? '...', textColor, subTextColor, Icons.mail_outline),
                          _buildDetailRow('Username', user?['username'] ?? '...', textColor, subTextColor, Icons.alternate_email),
                        ],
                      );
                    },
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
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: const Icon(Icons.lock_reset_rounded, color: Color(0xFF00A884)),
                        title: Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
                        subtitle: Text('Regularly update for better security', style: TextStyle(fontSize: 12, color: subTextColor)),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: _showChangePasswordDialog,
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      _appVersion,
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

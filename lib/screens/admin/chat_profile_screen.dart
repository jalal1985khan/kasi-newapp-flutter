import 'package:flutter/material.dart';

class ChatProfileScreen extends StatelessWidget {
  final String name;
  final String? avatar;
  final bool isOnline;

  const ChatProfileScreen({
    super.key, 
    required this.name, 
    this.avatar, 
    this.isOnline = false
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white38 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 80,
                  backgroundColor: isDark ? const Color(0xFF202C33) : Colors.grey[200],
                  child: avatar != null && avatar!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(80),
                          child: Image.network(avatar!, fit: BoxFit.cover, width: 160, height: 160),
                        )
                      : Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: isDark ? Colors.white24 : Colors.black12),
                        ),
                ),
                if (isOnline)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366), 
                        shape: BoxShape.circle, 
                        border: Border.all(color: bgColor, width: 3)
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              name,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(height: 8),
            Text(
              isOnline ? 'Online' : 'Offline',
              style: TextStyle(
                color: isOnline ? const Color(0xFF25D366) : subTextColor, 
                fontSize: 16, 
                fontWeight: FontWeight.w500
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/chat_message_model.dart';
import '../../models/chat_conversation_model.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'chat_database.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create Conversations Table
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        tenantId TEXT,
        participants TEXT,
        lastMessage TEXT,
        unreadCount INTEGER,
        updatedAt TEXT,
        createdAt TEXT,
        participantDetails TEXT
      )
    ''');

    // Create Messages Table
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversationId TEXT,
        tenantId TEXT,
        senderId TEXT,
        receiverId TEXT,
        type TEXT,
        content TEXT,
        fileName TEXT,
        fileSize INTEGER,
        duration INTEGER,
        isRead INTEGER,
        readAt TEXT,
        deletedFor TEXT,
        createdAt TEXT,
        senderName TEXT,
        senderRole TEXT,
        reaction TEXT,
        replyToContent TEXT,
        replyToSenderName TEXT,
        replyTo TEXT,
        isForwarded INTEGER,
        caption TEXT,
        senderProfileImage TEXT,
        uploadProgress REAL,
        uploadStatus TEXT,
        localPath TEXT,
        previewUrl TEXT
      )
    ''');

    // Indexes for faster querying
    await db.execute('CREATE INDEX idx_messages_conversationId ON messages (conversationId)');
    await db.execute('CREATE INDEX idx_messages_createdAt ON messages (createdAt DESC)');
  }

  // ======================
  // MESSAGES CRUD
  // ======================

  Future<void> insertMessage(ChatMessage message) async {
    final db = await database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertMessages(List<ChatMessage> messages) async {
    final db = await database;
    Batch batch = db.batch();
    for (var message in messages) {
      batch.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ChatMessage>> getMessagesByConversation(String conversationId, {int limit = 50, int offset = 0}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => ChatMessage.fromMap(e)).toList();
  }
  
  Future<ChatMessage?> getLatestMessage(String conversationId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return ChatMessage.fromMap(maps.first);
    }
    return null;
  }

  Future<void> updateMessageStatus(String messageId, {required bool isRead}) async {
    final db = await database;
    await db.update(
      'messages',
      {'isRead': isRead ? 1 : 0},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  // ======================
  // CONVERSATIONS CRUD
  // ======================

  Future<void> insertConversation(Conversation conversation) async {
    final db = await database;
    await db.insert(
      'conversations',
      conversation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertConversations(List<Conversation> conversations) async {
    final db = await database;
    Batch batch = db.batch();
    for (var conv in conversations) {
      batch.insert(
        'conversations',
        conv.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Conversation>> getConversations() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'conversations',
      orderBy: 'updatedAt DESC',
    );
    return maps.map((e) => Conversation.fromMap(e)).toList();
  }
  
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('conversations');
  }
}

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/time_record.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'time_tracker.db');

    _database = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE time_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            durationSeconds INTEGER NOT NULL,
            createdAt INTEGER NOT NULL,
            activityDate INTEGER NOT NULL,
            note TEXT
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_time_records_date
          ON time_records(activityDate)
        ''');

                await db.execute('''
          CREATE TABLE activity_definitions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            createdAt INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE app_state (
            stateKey TEXT PRIMARY KEY,
            stateValue TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE activity_definitions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              createdAt INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE app_state (
              stateKey TEXT PRIMARY KEY,
              stateValue TEXT NOT NULL
            )
          ''');
        }
      },
    );

    return _database!;
  }

  Future<void> saveAppState(
    String key,
    String value,
  ) async {
    final db = await database;

    await db.insert(
      'app_state',
      {
        'stateKey': key,
        'stateValue': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getAppState(String key) async {
    final db = await database;

    final rows = await db.query(
      'app_state',
      columns: ['stateValue'],
      where: 'stateKey = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return rows.first['stateValue'] as String;
  }

  Future<void> deleteAppState(String key) async {
    final db = await database;

    await db.delete(
      'app_state',
      where: 'stateKey = ?',
      whereArgs: [key],
    );
  }

  Future<int> insertRecord(TimeRecord record) async {
    final db = await database;
    return db.insert('time_records', record.toMap());
  }

  Future<List<TimeRecord>> getAllRecords() async {
    final db = await database;

    final rows = await db.query(
      'time_records',
      orderBy: 'activityDate DESC, id DESC',
    );

    return rows.map(TimeRecord.fromMap).toList();
  }

  Future<int> updateRecord(TimeRecord record) async {
    if (record.id == null) {
      throw ArgumentError('شناسهٔ رکورد مشخص نیست.');
    }

    final db = await database;

    return db.update(
      'time_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<int> deleteRecord(int id) async {
    final db = await database;

    return db.delete(
      'time_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getTotalSeconds({
    DateTime? start,
    DateTime? end,
    String? category,
  }) async {
    final db = await database;

    final conditions = <String>[];
    final args = <Object?>[];

    if (start != null) {
      conditions.add('activityDate >= ?');
      args.add(start.millisecondsSinceEpoch);
    }

    if (end != null) {
      conditions.add('activityDate < ?');
      args.add(end.millisecondsSinceEpoch);
    }

    if (category != null && category.isNotEmpty) {
      conditions.add('category = ?');
      args.add(category);
    }

    final where =
        conditions.isEmpty ? '' : ' WHERE ${conditions.join(' AND ')}';

    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(durationSeconds), 0) AS total '
      'FROM time_records$where',
      args,
    );

    return (result.first['total'] as num).toInt();
  }
  Future<int> addActivity(String name) async {
    final db = await database;
    return db.insert(
      'activity_definitions',
      {'name': name.trim(), 'createdAt': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<String>> getActivityNames() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT name FROM activity_definitions
      UNION
      SELECT title AS name FROM time_records
      ORDER BY name COLLATE NOCASE
    ''');
    return rows.map((row) => row['name'] as String).toList();
  }

  Future<List<TimeRecord>> getRecordsForActivity(String title) async {
    final db = await database;
    final rows = await db.query(
      'time_records',
      where: 'title = ?',
      whereArgs: [title],
      orderBy: 'activityDate DESC, id DESC',
    );
    return rows.map(TimeRecord.fromMap).toList();
  }

}

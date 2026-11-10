import '../utils/jalali_date_storage.dart';
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
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE time_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            durationSeconds INTEGER NOT NULL,
            createdAt TEXT NOT NULL,
            activityDate TEXT NOT NULL,
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
            createdAt TEXT NOT NULL
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
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS activity_definitions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              createdAt TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_state (
              stateKey TEXT PRIMARY KEY,
              stateValue TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 5) {
          // Rebuild date-bearing tables with TEXT columns and Jalali values.
          final oldRecords = await db.query('time_records');
          await db.execute('DROP TABLE time_records');
          await db.execute('''
            CREATE TABLE time_records (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              category TEXT NOT NULL,
              durationSeconds INTEGER NOT NULL,
              createdAt TEXT NOT NULL,
              activityDate TEXT NOT NULL,
              note TEXT
            )
          ''');
          await db.execute('''
            CREATE INDEX idx_time_records_date
            ON time_records(activityDate)
          ''');
          for (final row in oldRecords) {
            await db.insert('time_records', {
              'id': row['id'],
              'title': row['title'],
              'category': row['category'],
              'durationSeconds': row['durationSeconds'],
              'createdAt': JalaliDateStorage.encode(JalaliDateStorage.decode(row['createdAt'])),
              'activityDate': JalaliDateStorage.encode(JalaliDateStorage.decode(row['activityDate'])),
              'note': row['note'],
            });
          }

          final oldDefinitions = await db.query('activity_definitions');
          await db.execute('DROP TABLE activity_definitions');
          await db.execute('''
            CREATE TABLE activity_definitions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              createdAt TEXT NOT NULL
            )
          ''');
          for (final row in oldDefinitions) {
            await db.insert('activity_definitions', {
              'id': row['id'],
              'name': row['name'],
              'createdAt': JalaliDateStorage.encode(JalaliDateStorage.decode(row['createdAt'])),
            });
          }

          final states = await db.query('app_state');
          for (final row in states) {
            final key = row['stateKey'] as String;
            final value = row['stateValue'] as String;
            await db.update('app_state', {
              'stateValue': JalaliDateStorage.normalizeStateJson(key, value),
            }, where: 'stateKey = ?', whereArgs: [key]);
          }
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
        'stateValue': JalaliDateStorage.normalizeStateJson(key, value),
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

  Future<Map<String, String>> getAllAppStates() async {
    final db = await database;
    final rows = await db.query('app_state');
    return {
      for (final row in rows)
        row['stateKey'] as String: row['stateValue'] as String,
    };
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

  Future<int> saveActivityRecord(TimeRecord record) async {
    final db = await database;
    final title = record.title.trim();
    if (title.isEmpty) {
      throw ArgumentError('نام فعالیت نمی‌تواند خالی باشد.');
    }
    return db.transaction((txn) async {
      await txn.insert(
        'activity_definitions',
        {
          'name': title,
          'createdAt': JalaliDateStorage.encode(DateTime.now()),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      final values = record.toMap();
      values['title'] = title;
      return txn.insert('time_records', values);
    });
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
      args.add(JalaliDateStorage.encode(start));
    }

    if (end != null) {
      conditions.add('activityDate < ?');
      args.add(JalaliDateStorage.encode(end));
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
      {'name': name.trim(), 'createdAt': JalaliDateStorage.encode(DateTime.now())},
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

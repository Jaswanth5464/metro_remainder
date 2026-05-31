import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/station.dart';
import '../models/journey.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('metro_wake_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      const idType = 'TEXT PRIMARY KEY';
      const textType = 'TEXT NOT NULL';
      await db.execute('''
CREATE TABLE favorites (
  id $idType,
  startStationId $textType,
  destinationStationId $textType
)
''');
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const realType = 'REAL NOT NULL';
    const intType = 'INTEGER NOT NULL';
    const boolType = 'INTEGER NOT NULL';

    await db.execute('''
CREATE TABLE stations (
  id $idType,
  name $textType,
  lat $realType,
  lng $realType,
  line $textType,
  orderIndex $intType
)
''');

    await db.execute('''
CREATE TABLE journeys (
  id $idType,
  startStationId $textType,
  destinationStationId $textType,
  startTime $textType,
  active $boolType
)
''');

    await db.execute('''
CREATE TABLE runtime_state (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lastKnownSpeed REAL,
  currentStationId TEXT,
  mode TEXT,
  timestamp INTEGER
)
''');

    await db.execute('''
CREATE TABLE favorites (
  id $idType,
  startStationId $textType,
  destinationStationId $textType
)
''');
  }

  Future<void> bootstrapData() async {
    final db = await instance.database;
    // Always clear and re-insert stations from JSON to ensure
    // coordinates are never stale from an old install.
    await db.delete('stations');
    final jsonString =
        await rootBundle.loadString('assets/metro_stations.json');
    final List<dynamic> jsonList = jsonDecode(jsonString);
    Batch batch = db.batch();
    for (var json in jsonList) {
      final station = Station.fromJson(json);
      batch.insert('stations', station.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Station>> getAllStations() async {
    final db = await instance.database;
    final maps = await db.query('stations', orderBy: 'name ASC');
    return maps.map((json) => Station.fromJson(json)).toList();
  }

  Future<Station?> getStationById(String id) async {
    final db = await instance.database;
    final maps = await db.query(
      'stations',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Station.fromJson(maps.first);
    } else {
      return null;
    }
  }

  Future<void> createJourney(Journey journey) async {
    final db = await instance.database;
    // ensure only 1 active journey
    await db.update('journeys', {'active': 0}, where: 'active = 1');
    await db.insert('journeys', journey.toMap());
  }

  Future<Journey?> getActiveJourney() async {
    final db = await instance.database;
    final maps = await db.query(
      'journeys',
      where: 'active = ?',
      whereArgs: [1],
    );

    if (maps.isNotEmpty) {
      return Journey.fromMap(maps.first);
    }
    return null;
  }

  Future<void> stopActiveJourney() async {
    final db = await instance.database;
    await db.update('journeys', {'active': 0}, where: 'active = 1');
  }

  // ── Favorites ────────────────────────────────────────────────

  Future<void> addFavorite(String startId, String destId) async {
    final db = await instance.database;
    final id = '${startId}_$destId';
    await db.insert('favorites', {
      'id': id,
      'startStationId': startId,
      'destinationStationId': destId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeFavorite(String startId, String destId) async {
    final db = await instance.database;
    final id = '${startId}_$destId';
    await db.delete('favorites', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getFavorites() async {
    final db = await instance.database;
    return await db.query('favorites');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}

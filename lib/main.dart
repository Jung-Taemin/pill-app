import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_localizations/flutter_localizations.dart';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await notifications.initialize(initSettings);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
        scaffoldBackgroundColor: const Color(0xFFF9F9FB),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime? startDate;
  int pillDays = 21;
  int breakDays = 7;

  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay;

  Map<String, bool> takenMap = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  String _dateKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      pillDays = prefs.getInt('pillDays') ?? 21;
      breakDays = prefs.getInt('breakDays') ?? 7;

      final millis = prefs.getInt('startDate');
      if (millis != null) {
        startDate = DateTime.fromMillisecondsSinceEpoch(millis);
      }

      final takenStr = prefs.getString('takenMap');
      if (takenStr != null) {
        takenMap = Map<String, bool>.from(jsonDecode(takenStr));
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pillDays', pillDays);
    await prefs.setInt('breakDays', breakDays);
    if (startDate != null) {
      await prefs.setInt('startDate', startDate!.millisecondsSinceEpoch);
    }
  }

  Future<void> _saveTakenMap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('takenMap', jsonEncode(takenMap));
  }

  Future<void> _toggleTodayTaken() async {
    final key = _dateKey(DateTime.now());
    setState(() {
      if (takenMap[key] == true) {
        takenMap.remove(key);
      } else {
        takenMap[key] = true;
      }
    });
    await _saveTakenMap();
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = _dateKey(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '약 복용 달력',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _openPatternSelector,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: const Text('복용 시작일 선택'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _pickDate,
            ),
          ),
          const SizedBox(height: 12),

          if (startDate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTodayStatus(),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _toggleTodayTaken,
                      child: Text(
                        takenMap[todayKey] == true ? '복용 취소' : '복용 완료',
                      ),
                    ),
                  ],
                ),
              ),
            ),

          /// 📅 달력 (좌우 여백 적용)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TableCalendar(
              locale: 'ko_KR',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2035, 12, 31),
              focusedDay: focusedDay,
              rowHeight: 48,
              daysOfWeekHeight: 32,
              selectedDayPredicate: (day) => isSameDay(selectedDay, day),
              onDaySelected: (selected, focused) {
                setState(() {
                  selectedDay = selected;
                  focusedDay = focused;
                });
              },
              headerStyle: const HeaderStyle(
                titleCentered: true,
                formatButtonVisible: false,
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, _) => _buildSquareCell(day),
                todayBuilder: (context, day, _) =>
                    _buildSquareCell(day, isToday: true),
                selectedBuilder: (context, day, _) =>
                    _buildSquareCell(day, isSelected: true),
              ),
            ),
          ),

          const SizedBox(height: 12),

          /// 🎨 범례 (설명)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _legendItem(const Color(0xFFE3F2FD), '복용일'),
                const SizedBox(width: 16),
                _legendItem(const Color(0xFFFFF3E0), '휴약일'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.grey.shade400),
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _buildSquareCell(
    DateTime day, {
    bool isToday = false,
    bool isSelected = false,
  }) {
    Color bgColor = Colors.white;
    Color borderColor = Colors.grey.shade400;

    final type = _getDayType(day);
    if (type == 'pill') bgColor = const Color(0xFFE3F2FD);
    if (type == 'break') bgColor = const Color(0xFFFFF3E0);

    if (isSelected) borderColor = Colors.blue;
    if (isToday) borderColor = Colors.red;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
      ),
      child: Stack(
        children: [
          Center(
            child: Text('${day.day}', style: const TextStyle(fontSize: 14)),
          ),
          if (takenMap[_dateKey(day)] == true)
            const Positioned(
              top: 4,
              right: 4,
              child: Text('💊', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  String _getDayType(DateTime day) {
    if (startDate == null) return 'none';
    final start = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final target = DateTime(day.year, day.month, day.day);
    final diffDays = target.difference(start).inDays;
    final cycle = pillDays + breakDays;
    if (diffDays < 0 || cycle == 0) return 'none';
    return diffDays % cycle < pillDays ? 'pill' : 'break';
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (selected != null) {
      setState(() => startDate = selected);
      await _saveSettings();
    }
  }

  void _openPatternSelector() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _patternTile('21일 복용 / 7일 휴약', 21, 7),
          _patternTile('24일 복용 / 4일 휴약', 24, 4),
          _patternTile('28일 연속 복용', 28, 0),
        ],
      ),
    );
  }

  Widget _patternTile(String text, int p, int b) {
    return ListTile(
      title: Text(text),
      onTap: () async {
        setState(() {
          pillDays = p;
          breakDays = b;
        });
        await _saveSettings();
        Navigator.pop(context);
      },
    );
  }

  Widget _buildTodayStatus() {
    final type = _getDayType(DateTime.now());
    if (type == 'pill') return const Text('💊 오늘은 복용일입니다');
    if (type == 'break') return const Text('💤 오늘은 휴약일입니다');
    return const Text('복용 시작일을 선택해주세요');
  }
}

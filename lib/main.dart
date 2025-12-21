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

      /// ⭐⭐⭐ 한글 로케일 설정 (이게 핵심)
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      pillDays = prefs.getInt('pillDays') ?? 21;
      breakDays = prefs.getInt('breakDays') ?? 7;
      final millis = prefs.getInt('startDate');
      if (millis != null) {
        startDate = DateTime.fromMillisecondsSinceEpoch(millis);
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

  @override
  Widget build(BuildContext context) {
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

          /// 📅 네모 + 붙어있는 달력
          TableCalendar(
            locale: 'ko_KR',

            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: focusedDay,
            rowHeight: 48,

            // 달력이랑 월화수 간격
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
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(fontWeight: FontWeight.bold),
              weekendStyle: TextStyle(fontWeight: FontWeight.bold),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focused) => _buildSquareCell(day),
              todayBuilder: (context, day, focused) =>
                  _buildSquareCell(day, isToday: true),
              selectedBuilder: (context, day, focused) =>
                  _buildSquareCell(day, isSelected: true),
            ),
          ),

          if (selectedDay != null && startDate != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _getDayText(selectedDay!),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// ⬛ 네모 셀 (핵심)
  Widget _buildSquareCell(
    DateTime day, {
    bool isToday = false,
    bool isSelected = false,
  }) {
    Color bgColor = Colors.white;
    Color borderColor = Colors.grey.shade400;

    final type = _getDayType(day);
    if (type == 'pill') {
      bgColor = const Color(0xFFE3F2FD); // 복용일
    } else if (type == 'break') {
      bgColor = const Color(0xFFFFF3E0); // 휴약일
    }

    if (isSelected) {
      borderColor = Colors.blue;
    } else if (isToday) {
      borderColor = Colors.red;
    }

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text('${day.day}', style: const TextStyle(fontSize: 14)),
    );
  }

  String _getDayText(DateTime day) {
    final type = _getDayType(day);
    if (type == 'pill') return '이 날은 💊 복용일이에요';
    if (type == 'break') return '이 날은 💤 휴약일이에요';
    return '';
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
    final pillCtrl = TextEditingController(text: pillDays.toString());
    final breakCtrl = TextEditingController(text: breakDays.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _patternTile('21일 복용 / 7일 휴약', 21, 7),
            _patternTile('24일 복용 / 4일 휴약', 24, 4),
            _patternTile('28일 연속 복용', 28, 0),
            const Divider(),
            const Text('직접 설정', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pillCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '복용일수',
                      suffixText: '일',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: breakCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '휴약일수',
                      suffixText: '일',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                child: const Text('적용'),
                onPressed: () async {
                  final p = int.tryParse(pillCtrl.text);
                  final b = int.tryParse(breakCtrl.text);
                  if (p == null || b == null || p <= 0) return;

                  setState(() {
                    pillDays = p;
                    breakDays = b;
                  });
                  await _saveSettings();
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
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
}

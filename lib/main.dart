import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
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

  final TextEditingController pillController = TextEditingController(
    text: '21',
  );
  final TextEditingController breakController = TextEditingController(
    text: '7',
  );

  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // 🔹 저장된 설정 불러오기
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      pillDays = prefs.getInt('pillDays') ?? 21;
      breakDays = prefs.getInt('breakDays') ?? 7;

      pillController.text = pillDays.toString();
      breakController.text = breakDays.toString();

      final millis = prefs.getInt('startDate');
      if (millis != null) {
        startDate = DateTime.fromMillisecondsSinceEpoch(millis);
      }
    });
  }

  // 🔹 설정 저장
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
        title: const Text('약 복용 달력'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openPatternSelector,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _pickDate, child: const Text('복용 시작일 선택')),
          const SizedBox(height: 8),
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: focusedDay,
            selectedDayPredicate: (day) => isSameDay(selectedDay, day),
            onDaySelected: (selected, focused) {
              setState(() {
                selectedDay = selected;
                focusedDay = focused;
              });
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focused) => _buildCell(day),
              todayBuilder: (context, day, focused) =>
                  _buildCell(day, isToday: true),
              selectedBuilder: (context, day, focused) =>
                  _buildSelectedCell(day),
            ),
          ),
          if (selectedDay != null && startDate != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _getDayText(selectedDay!),
                style: const TextStyle(fontSize: 18),
              ),
            ),
        ],
      ),
    );
  }

  // 📅 달력 셀
  Widget _buildCell(DateTime day, {bool isToday = false}) {
    final icon = _getIcon(day);
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isToday ? Colors.blue : Colors.grey.shade300,
          width: isToday ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Text('${day.day}'), if (icon != null) icon],
      ),
    );
  }

  Widget _buildSelectedCell(DateTime day) {
    final icon = _getIcon(day);
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Text('${day.day}'), if (icon != null) icon],
      ),
    );
  }

  // 💊 / 💤 아이콘
  Widget? _getIcon(DateTime day) {
    if (startDate == null) return null;
    final type = _getDayType(day);
    if (type == 'pill') return const Icon(Icons.medication, size: 16);
    if (type == 'break') return const Icon(Icons.hotel, size: 16);
    return null;
  }

  String _getDayText(DateTime day) {
    final type = _getDayType(day);
    if (type == 'pill') return '이 날은 💊 복용일이에요';
    if (type == 'break') return '이 날은 💤 휴약일이에요';
    return '';
  }

  // 🧠 핵심 계산 로직
  String _getDayType(DateTime day) {
    if (startDate == null) return 'none';

    final start = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final target = DateTime(day.year, day.month, day.day);

    final diffDays = target.difference(start).inDays;
    final cycle = pillDays + breakDays;

    if (diffDays < 0 || cycle == 0) return 'none';
    final dayInCycle = diffDays % cycle;

    return dayInCycle < pillDays ? 'pill' : 'break';
  }

  // 📆 시작일 선택
  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (selected != null) {
      setState(() {
        startDate = selected;
      });
      await _saveSettings();
      await _scheduleTodayNotification();
    }
  }

  // 🔔 오늘 복용일이면 알림
  Future<void> _scheduleTodayNotification() async {
    if (startDate == null) return;

    final now = DateTime.now();
    if (_getDayType(now) != 'pill') return;

    final scheduledTime = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      21,
      0,
    );

    if (scheduledTime.isBefore(tz.TZDateTime.now(tz.local))) return;

    await notifications.zonedSchedule(
      0,
      '약 복용 알림 💊',
      '오늘 약 먹을 시간이에요!',
      scheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'pill_channel',
          'Pill Reminder',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ⚙️ 복용 패턴 선택 + 직접 설정
  void _openPatternSelector() {
    final TextEditingController pillController = TextEditingController(
      text: pillDays.toString(),
    );
    final TextEditingController breakController = TextEditingController(
      text: breakDays.toString(),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 기존 패턴
              ListTile(
                title: const Text('21일 복용 / 7일 휴약'),
                onTap: () async {
                  setState(() {
                    pillDays = 21;
                    breakDays = 7;
                  });
                  await _saveSettings();
                  await _scheduleTodayNotification();
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('24일 복용 / 4일 휴약'),
                onTap: () async {
                  setState(() {
                    pillDays = 24;
                    breakDays = 4;
                  });
                  await _saveSettings();
                  await _scheduleTodayNotification();
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('28일 연속 복용'),
                onTap: () async {
                  setState(() {
                    pillDays = 28;
                    breakDays = 0;
                  });
                  await _saveSettings();
                  await _scheduleTodayNotification();
                  Navigator.pop(context);
                },
              ),

              const Divider(height: 32),

              // 🔹 직접 설정
              const Text(
                '직접 설정',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: pillController,
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
                      controller: breakController,
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

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final pill = int.tryParse(pillController.text);
                    final rest = int.tryParse(breakController.text);

                    if (pill == null || rest == null || pill <= 0) return;

                    setState(() {
                      pillDays = pill;
                      breakDays = rest;
                    });

                    await _saveSettings();
                    await _scheduleTodayNotification();
                    Navigator.pop(context);
                  },
                  child: const Text('적용'),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

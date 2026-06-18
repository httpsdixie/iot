import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb; // Added to check environment
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'config_store.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MADJIC TempSens',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ADAPTIVE INITIALIZATION:
  // Uses "localhost" if running on Desktop/Web, and the Hotspot IP if running on Mobile.
  String serverIp = kIsWeb ? "localhost" : "192.168.137.1";

  String r1RoomName = "Living Room";
  String r2RoomName = "Bedroom";
  String r3RoomName = "Kitchen";
  bool isDarkMode = true;

  final String supabaseKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

  List<dynamic> allReadings = [];
  List<dynamic> filteredReadings = [];
  bool isLoading = true;
  String errorMessage = '';
  Timer? _refreshTimer;

  String currentTab = "Dashboard";
  String selectedFilter = "ALL";
  DateTime? selectedDateFilter;
  bool showAllLogsOverride = false;

  int selectedChannelIndex = 0;
  String _currentTimeString = "";
  Timer? _clockTimer;

  late TextEditingController _r1Controller;
  late TextEditingController _r2Controller;
  late TextEditingController _r3Controller;
  late TextEditingController _ipController;

  final Color violetThemeColor = const Color(0xFF8B5CF6);
  final Map<String, bool> _filterHoverStates = {};

  @override
  void initState() {
    super.initState();
    _r1Controller = TextEditingController();
    _r2Controller = TextEditingController();
    _r3Controller = TextEditingController();
    _ipController = TextEditingController();
    _updateTime();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _updateTime(),
    );
    _loadSettings();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) => fetchData(),
    );
  }

  void _updateTime() {
    final DateTime now = DateTime.now();
    final int hour = now.hour;
    final String amPm = hour >= 12 ? 'PM' : 'AM';
    final int displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final String formattedTime =
        "${displayHour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} $amPm";
    if (mounted) {
      setState(() {
        _currentTimeString = formattedTime;
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    _r1Controller.dispose();
    _r2Controller.dispose();
    _r3Controller.dispose();
    _ipController.dispose();
    super.dispose();
  }

  String get supabaseUrl =>
      "http://$serverIp:54321/rest/v1/sensor_readings?order=recorded_at.desc";

  Future<void> _loadSettings() async {
    try {
      final defaultIp = kIsWeb ? 'localhost' : '192.168.137.1';
      final ip = await ConfigStore.load('serverIp') ?? defaultIp;
      final r1 = await ConfigStore.load('r1RoomName') ?? 'Living Room';
      final r2 = await ConfigStore.load('r2RoomName') ?? 'Bedroom';
      final r3 = await ConfigStore.load('r3RoomName') ?? 'Kitchen';
      final dark = await ConfigStore.load('isDarkMode') ?? 'true';

      setState(() {
        serverIp = ip;
        r1RoomName = r1;
        r2RoomName = r2;
        r3RoomName = r3;
        isDarkMode = dark == 'true';

        _r1Controller.text = r1RoomName;
        _r2Controller.text = r2RoomName;
        _r3Controller.text = r3RoomName;
        _ipController.text = serverIp;
      });
    } catch (e) {
      // safe fallback
    }
    fetchData();
  }

  Future<void> _saveSetting(String key, String value) async {
    await ConfigStore.save(key, value);
  }

  String convertToHumanTime(String rawTimestamp) {
    try {
      String formattedToken = rawTimestamp;
      if (!formattedToken.endsWith('Z') && !formattedToken.contains('+')) {
        formattedToken = "${formattedToken}Z";
      }
      DateTime dt = DateTime.parse(formattedToken).toLocal();
      int hour = dt.hour;
      String period = "AM";
      if (hour >= 12) {
        period = "PM";
        if (hour > 12) hour -= 12;
      }
      if (hour == 0) hour = 12;
      String minute = dt.minute.toString().padLeft(2, '0');
      List<String> months = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ];
      return "${months[dt.month - 1]} ${dt.day} • $hour:$minute $period";
    } catch (e) {
      return rawTimestamp;
    }
  }

  String extractShortTime(String rawTimestamp) {
    try {
      String formattedToken = rawTimestamp;
      if (!formattedToken.endsWith('Z') && !formattedToken.contains('+')) {
        formattedToken = "${formattedToken}Z";
      }
      DateTime dt = DateTime.parse(formattedToken).toLocal();
      int hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      String minute = dt.minute.toString().padLeft(2, '0');
      String period = dt.hour >= 12 ? "PM" : "AM";
      return "$hour:$minute $period";
    } catch (e) {
      return '';
    }
  }

  Future<void> fetchData() async {
    try {
      final response = await http
          .get(
            Uri.parse(supabaseUrl),
            headers: {
              'apikey': supabaseKey,
              'Authorization': 'Bearer $supabaseKey',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          allReadings = json.decode(response.body);
          _applyFilter();
          isLoading = false;
          errorMessage = '';
        });
      } else {
        setState(() {
          errorMessage = 'Server Response Issue (${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage =
            'Unable to link with network backend at $serverIp.\nCheck host settings and Supabase containers.';
        isLoading = false;
      });
    }
  }

  void _applyFilter() {
    List<dynamic> processList = allReadings;

    if (selectedFilter != "ALL") {
      processList = processList.where((log) {
        final String name = (log['member_name'] ?? '').toString().toUpperCase();
        return name == selectedFilter.toUpperCase();
      }).toList();
    }

    if (selectedDateFilter != null) {
      processList = processList.where((log) {
        try {
          String rawTimestamp = log['recorded_at'] ?? '';
          if (!rawTimestamp.endsWith('Z') && !rawTimestamp.contains('+')) {
            rawTimestamp = "${rawTimestamp}Z";
          }
          DateTime logDate = DateTime.parse(rawTimestamp).toLocal();
          return logDate.year == selectedDateFilter!.year &&
              logDate.month == selectedDateFilter!.month &&
              logDate.day == selectedDateFilter!.day;
        } catch (e) {
          return false;
        }
      }).toList();
    }

    setState(() {
      filteredReadings = processList;
    });
  }

  List<String> getUniqueMembers() {
    final Set<String> members = {"ALL"};
    for (final r in allReadings) {
      final m = r['member_name']?.toString();
      if (m != null && m.trim().isNotEmpty) {
        members.add(m.trim().toUpperCase());
      }
    }
    return members.toList();
  }

  List<String> getUniqueRooms() {
    final Set<String> rooms = {};
    for (final r in allReadings) {
      final room = r['room_location']?.toString();
      if (room != null && room.trim().isNotEmpty) {
        rooms.add(room.trim());
      }
    }
    return rooms.toList();
  }

  Map<String, dynamic>? _getLatestReadingForRoom(String roomName) {
    try {
      return allReadings.firstWhere(
        (log) =>
            (log['room_location'] ?? '').toString().toLowerCase() ==
            roomName.toLowerCase(),
        orElse: () => null,
      );
    } catch (e) {
      return null;
    }
  }

  List<dynamic> _getChronologicalReadingsForRoom(String roomName) {
    try {
      final match = allReadings
          .where(
            (log) =>
                (log['room_location'] ?? '').toString().toLowerCase() ==
                roomName.toLowerCase(),
          )
          .toList();
      return match.reversed.toList();
    } catch (e) {
      return [];
    }
  }

  void _toggleTheme() {
    setState(() {
      isDarkMode = !isDarkMode;
      _saveSetting('isDarkMode', isDarkMode.toString());
    });
  }

  void _showSettingsDialog() {
    final uniqueRooms = getUniqueRooms();
    _r1Controller.text = r1RoomName;
    _r2Controller.text = r2RoomName;
    _r3Controller.text = r3RoomName;
    _ipController.text = serverIp;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dialogTheme = isDarkMode ? ThemeData.dark() : ThemeData.light();
            return Theme(
              data: dialogTheme.copyWith(
                dialogTheme: DialogThemeData(
                  backgroundColor: isDarkMode
                      ? const Color(0xFF16171B)
                      : Colors.white,
                ),
              ),
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: violetThemeColor.withOpacity(0.3), width: 1),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: violetThemeColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.tune_rounded, color: violetThemeColor),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'System Settings',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFF202227) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: violetThemeColor.withOpacity(0.2)),
                          ),
                          child: Text(
                            'Configure your dashboard experience, map physical nodes, and tweak the appearance of the interface below.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'NETWORK CONFIGURATION',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: violetThemeColor,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.hub_rounded, size: 16, color: violetThemeColor),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Server IP Address',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _ipController,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: isDarkMode
                                      ? const Color(0xFF202227)
                                      : const Color(0xFFF3F4F6),
                                  hintText: 'e.g., localhost or 192.168.1.10',
                                  hintStyle: TextStyle(
                                    color: isDarkMode ? Colors.white30 : Colors.black38,
                                    fontSize: 13,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 30, thickness: 1),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'SENSOR NODE MAPPING',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: violetThemeColor,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        _buildRoomSelector(
                          label: 'Sensor 1 - Blossom',
                          controller: _r1Controller,
                          uniqueRooms: uniqueRooms,
                          accentColor: const Color(0xFFFC3D73),
                        ),
                        _buildRoomSelector(
                          label: 'Sensor 2 - Bubbles',
                          controller: _r2Controller,
                          uniqueRooms: uniqueRooms,
                          accentColor: const Color(0xFF349DFB),
                        ),
                        _buildRoomSelector(
                          label: 'Sensor 3 - Buttercup',
                          controller: _r3Controller,
                          uniqueRooms: uniqueRooms,
                          accentColor: const Color(0xFF38C124),
                        ),
                      ],
                    ),
                  ),
                ),
                actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: isDarkMode ? Colors.white54 : Colors.black54),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: violetThemeColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text(
                      'Save & Apply',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      setState(() {
                        r1RoomName = _r1Controller.text.trim();
                        r2RoomName = _r2Controller.text.trim();
                        r3RoomName = _r3Controller.text.trim();
                        serverIp = _ipController.text.trim();
                        isLoading = true;
                      });
                      _saveSetting('r1RoomName', r1RoomName);
                      _saveSetting('r2RoomName', r2RoomName);
                      _saveSetting('r3RoomName', r3RoomName);
                      _saveSetting('serverIp', serverIp);
                      Navigator.of(context).pop();
                      fetchData();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final dialogTheme = isDarkMode ? ThemeData.dark() : ThemeData.light();
        return Theme(
          data: dialogTheme.copyWith(
            dialogTheme: DialogThemeData(
              backgroundColor: isDarkMode
                  ? const Color(0xFF16171B)
                  : Colors.white,
            ),
          ),
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: violetThemeColor),
                const SizedBox(width: 10),
                Text(
                  'Dashboard System Manual',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SYSTEM SPECIFICATIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: violetThemeColor,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildHelpSpecItem(
                      icon: Icons.spa_rounded,
                      iconColor: const Color(0xFFFC3D73),
                      title: 'Sensor 1 - Blossom',
                      description: 'Responsible for monitoring $r1RoomName. Color coded pink.',
                    ),
                    _buildHelpSpecItem(
                      icon: Icons.bubble_chart_rounded,
                      iconColor: const Color(0xFF349DFB),
                      title: 'Sensor 2 - Bubbles',
                      description: 'Responsible for monitoring $r2RoomName. Color coded blue.',
                    ),
                    _buildHelpSpecItem(
                      icon: Icons.eco_rounded,
                      iconColor: const Color(0xFF38C124),
                      title: 'Sensor 3 - Buttercup',
                      description: 'Responsible for monitoring $r3RoomName. Color coded green.',
                    ),
                    const Divider(height: 24, thickness: 1),
                    Text(
                      'AMBIENT METRICS STANDARDS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: violetThemeColor,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildHelpSpecItem(
                      icon: Icons.thermostat_rounded,
                      iconColor: Colors.orangeAccent,
                      title: 'Temperature Thresholds',
                      description: 'Optimal ranges are between 18.0°C and 30.0°C. Values above 30.0°C trigger warnings as too hot. Values below 18.0°C trigger warnings as too cold.',
                    ),
                    _buildHelpSpecItem(
                      icon: Icons.water_drop_rounded,
                      iconColor: Colors.blueAccent,
                      title: 'Humidity Thresholds',
                      description: 'Optimal humidity level is between 35% and 70%. Values above 70% represent excessive dampness. Values below 35% represent excessive dryness.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close Manual'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHelpSpecItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomSelector({
    required String label,
    required TextEditingController controller,
    required List<String> uniqueRooms,
    required Color accentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) return uniqueRooms;
              return uniqueRooms.where(
                (option) => option.toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                ),
              );
            },
            onSelected: (selection) => controller.text = selection,
            fieldViewBuilder:
                (context, fieldController, focusNode, onFieldSubmitted) {
                  if (fieldController.text != controller.text) {
                    fieldController.text = controller.text;
                  }
                  fieldController.addListener(
                    () => controller.text = fieldController.text,
                  );
                  return TextField(
                    controller: fieldController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDarkMode
                          ? const Color(0xFF202227)
                          : const Color(0xFFF3F4F6),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  );
                },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = isDarkMode
        ? const Color(0xFF0A0B0D)
        : const Color(0xFFF5F7FA);
    final Color cardBgColor = isDarkMode
        ? const Color(0xFF13151A)
        : Colors.white;
    final Color textColor = isDarkMode ? Colors.white : const Color(0xFF1F2937);
    final Color subtextColor = isDarkMode ? Colors.white60 : Colors.grey[500]!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 900;

        return Scaffold(
          backgroundColor: bgColor,
          drawer: isMobile
              ? Drawer(
                  child: Container(
                    color: isDarkMode ? const Color(0xFF111214) : Colors.white,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        DrawerHeader(
                          decoration: BoxDecoration(
                            color: violetThemeColor.withAlpha(30),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'MADJIC Corp',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                'Sensors Navigation',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: subtextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.dashboard_rounded),
                          title: const Text('Dashboard'),
                          selected: currentTab == "Dashboard",
                          selectedColor: violetThemeColor,
                          onTap: () {
                            setState(() => currentTab = "Dashboard");
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.history_toggle_off_rounded),
                          title: const Text('History Logs'),
                          selected: currentTab == "History Logs",
                          selectedColor: violetThemeColor,
                          onTap: () {
                            setState(() => currentTab = "History Logs");
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          appBar: isMobile
              ? AppBar(
                  toolbarHeight: 70,
                  backgroundColor: isDarkMode ? const Color(0xFF13151A) : Colors.white,
                  elevation: 0,
                  shape: Border(
                    bottom: BorderSide(
                      color: isDarkMode ? const Color(0xFF1E222B) : const Color(0xFFE5E7EB),
                      width: 1,
                    ),
                  ),
                  iconTheme: IconThemeData(color: textColor, size: 26),
                  title: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(shape: BoxShape.circle),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/Untitled-1.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Text(
                                  'M',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: violetThemeColor,
                                    fontSize: 16,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MADJIC TempSens',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                            ),
                          ),
                          Text(
                            'by MADJIC Corp',
                            style: TextStyle(fontSize: 10, color: subtextColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'System Manual',
                      icon: Icon(
                        Icons.help_outline_rounded,
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                      ),
                      onPressed: _showHelpDialog,
                    ),
                    IconButton(
                      tooltip: isDarkMode ? 'Light Mode' : 'Dark Mode',
                      icon: Icon(
                        isDarkMode ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
                        color: isDarkMode ? Colors.amber : Colors.blueGrey[700],
                      ),
                      onPressed: _toggleTheme,
                    ),
                    IconButton(
                      tooltip: 'Configurations',
                      icon: Icon(
                        Icons.settings_rounded,
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                      ),
                      onPressed: _showSettingsDialog,
                    ),
                    const SizedBox(width: 14),
                  ],
                )
              : null,
          body: SafeArea(
            child: isMobile
                ? (isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: violetThemeColor),
                      )
                    : RefreshIndicator(
                        onRefresh: fetchData,
                        color: violetThemeColor,
                        child: (currentTab == "Dashboard" || currentTab == "Temperature Only" || currentTab == "Humidity Only")
                            ? _buildDashboardView(
                                cardBgColor,
                                textColor,
                                subtextColor,
                                constraints.maxWidth,
                              )
                            : _buildHistoryView(
                                cardBgColor,
                                textColor,
                                subtextColor,
                              ),
                      ))
                : Row(
                    children: [
                      _buildLeftNavigationRail(textColor, subtextColor),
                      Expanded(
                        child: Column(
                          children: [
                            _buildFuturisticTopHeader(textColor, subtextColor),
                            Expanded(
                              child: isLoading
                                  ? Center(
                                      child: CircularProgressIndicator(
                                          color: violetThemeColor),
                                    )
                                  : (currentTab == "Dashboard" || currentTab == "Temperature Only" || currentTab == "Humidity Only")
                                      ? _buildDashboardView(
                                          cardBgColor,
                                          textColor,
                                          subtextColor,
                                          constraints.maxWidth,
                                        )
                                      : _buildHistoryView(
                                          cardBgColor,
                                          textColor,
                                          subtextColor,
                                        ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildLeftNavigationRail(Color textColor, Color subtextColor) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF13151A) : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDarkMode ? const Color(0xFF1E222B) : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 30),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/Untitled-1.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            'M',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: violetThemeColor,
                              fontSize: 16,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'MADJIC Corp',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildSidebarItem(
            icon: Icons.dashboard_rounded,
            title: 'Dashboard',
            isSelected: currentTab == "Dashboard",
            onTap: () => setState(() => currentTab = "Dashboard"),
            textColor: textColor,
          ),
          _buildSidebarItem(
            icon: Icons.thermostat_rounded,
            title: 'Temperature Only',
            isSelected: currentTab == "Temperature Only",
            onTap: () => setState(() => currentTab = "Temperature Only"),
            textColor: textColor,
          ),
          _buildSidebarItem(
            icon: Icons.water_drop_rounded,
            title: 'Humidity Only',
            isSelected: currentTab == "Humidity Only",
            onTap: () => setState(() => currentTab = "Humidity Only"),
            textColor: textColor,
          ),
          _buildSidebarItem(
            icon: Icons.history_toggle_off_rounded,
            title: 'History Logs',
            isSelected: currentTab == "History Logs",
            onTap: () => setState(() => currentTab = "History Logs"),
            textColor: textColor,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1A1C23) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode ? const Color(0xFF222430) : const Color(0xFFE5E7EB),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: errorMessage.isEmpty ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        errorMessage.isEmpty ? 'Connected' : 'Offline',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Host: $serverIp',
                    style: TextStyle(
                      fontSize: 10,
                      color: subtextColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    required Color textColor,
  }) {
    final Color itemTextColor = isSelected ? violetThemeColor : textColor.withAlpha(160);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? violetThemeColor.withAlpha(20) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: itemTextColor, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: itemTextColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFuturisticTopHeader(Color textColor, Color subtextColor) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF13151A) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? const Color(0xFF1E222B) : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'MADJIC TEMPSENS',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 1,
                height: 16,
                color: isDarkMode ? Colors.white24 : Colors.black12,
              ),
              const SizedBox(width: 10),
              Text(
                'Real-Time Climate Hub',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: subtextColor,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1A1C23) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDarkMode ? const Color(0xFF222430) : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 14, color: violetThemeColor),
                    const SizedBox(width: 8),
                    Text(
                      _currentTimeString,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                tooltip: 'System Manual',
                icon: Icon(
                  Icons.help_outline_rounded,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                ),
                onPressed: _showHelpDialog,
              ),
              IconButton(
                tooltip: isDarkMode ? 'Light Mode' : 'Dark Mode',
                icon: Icon(
                  isDarkMode ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
                  color: isDarkMode ? Colors.amber : Colors.blueGrey[700],
                ),
                onPressed: _toggleTheme,
              ),
              IconButton(
                tooltip: 'Configurations',
                icon: Icon(
                  Icons.settings_rounded,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                ),
                onPressed: _showSettingsDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Widget _buildWebNavPill(String tabName) {
  //   return CustomHoverNavPill(
  //     text: tabName,
  //     isSelected: currentTab == tabName,
  //     activeColor: violetThemeColor,
  //     isDarkMode: isDarkMode,
  //     onTap: () => setState(() {
  //       currentTab = tabName;
  //     }),
  //   );
  // }

  List<Map<String, dynamic>> _getActiveAlerts() {
    List<Map<String, dynamic>> alerts = [];
    for (var reading in allReadings.take(20)) {
      final double temp =
          double.tryParse(reading['temperature']?.toString() ?? '0') ?? 0.0;
      final double hum =
          double.tryParse(reading['humidity']?.toString() ?? '0') ?? 0.0;
      final String room = reading['room_location'] ?? 'Zone';
      final String time = extractShortTime(reading['recorded_at'] ?? '');

      String? condition;
      if (temp >= 30.0) {
        condition = "High Temp";
      } else if (temp < 18.0) {
        condition = "Low Temp";
      } else if (hum >= 70.0) {
        condition = "High Humidity";
      } else if (hum < 35.0) {
        condition = "Low Humidity";
      }

      if (condition != null) {
        alerts.add({
          'time': time,
          'room': room,
          'value': temp >= 30.0 || temp < 18.0
              ? "${temp.toStringAsFixed(1)}°C"
              : "${hum.toStringAsFixed(0)}%",
          'condition': condition,
        });
      }
    }
    return alerts;
  }

  Widget _buildDashboardView(
    Color cardBg,
    Color textCol,
    Color subtextCol,
    double screenWidth,
  ) {
    int alarmCount = 0;
    int faultCount = 0;
    int normalCount = 0;

    final r1 = _getLatestReadingForRoom(r1RoomName);
    final r2 = _getLatestReadingForRoom(r2RoomName);
    final r3 = _getLatestReadingForRoom(r3RoomName);

    void classifySensor(Map<String, dynamic>? reading) {
      if (reading == null) {
        faultCount++;
      } else {
        final double t =
            double.tryParse(reading['temperature']?.toString() ?? '0') ?? 0.0;
        final double h =
            double.tryParse(reading['humidity']?.toString() ?? '0') ?? 0.0;
        if (t >= 30.0 || t < 18.0 || h >= 70.0 || h < 35.0) {
          alarmCount++;
        } else {
          normalCount++;
        }
      }
    }

    classifySensor(r1);
    classifySensor(r2);
    classifySensor(r3);

    String selectedRoom = r1RoomName;
    Color selectedColor = const Color(0xFFFC3D73);
    if (selectedChannelIndex == 1) {
      selectedRoom = r2RoomName;
      selectedColor = const Color(0xFF349DFB);
    } else if (selectedChannelIndex == 2) {
      selectedRoom = r3RoomName;
      selectedColor = const Color(0xFF38C124);
    }

    final historicalData = _getChronologicalReadingsForRoom(selectedRoom);
    final dataPoints = historicalData.length > 8
        ? historicalData.sublist(historicalData.length - 8)
        : historicalData;

    List<double> temps = dataPoints
        .map((d) => double.tryParse(d['temperature']?.toString() ?? '0') ?? 0.0)
        .toList();
    List<double> humidities = dataPoints
        .map((d) => double.tryParse(d['humidity']?.toString() ?? '0') ?? 0.0)
        .toList();
    List<String> timestamps = dataPoints
        .map((d) => extractShortTime(d['recorded_at'] ?? ''))
        .toList();

    var activeAlerts = _getActiveAlerts();
    if (currentTab == "Temperature Only") {
      activeAlerts = activeAlerts.where((alert) => alert['condition'].toString().toLowerCase().contains('temp')).toList();
    } else if (currentTab == "Humidity Only") {
      activeAlerts = activeAlerts.where((alert) => alert['condition'].toString().toLowerCase().contains('humidity')).toList();
    }

    double maxTemp = -999.0;
    double minTemp = 999.0;
    double maxHum = -999.0;
    double minHum = 999.0;
    double avgHum = 0.0;
    int humCount = 0;

    void addStats(Map<String, dynamic>? reading) {
      if (reading != null) {
        final double t =
            double.tryParse(reading['temperature']?.toString() ?? '0') ?? 0.0;
        final double h =
            double.tryParse(reading['humidity']?.toString() ?? '0') ?? 0.0;
        if (t > maxTemp) {
          maxTemp = t;
        }
        if (t < minTemp) {
          minTemp = t;
        }
        if (h > maxHum) {
          maxHum = h;
        }
        if (h < minHum) {
          minHum = h;
        }
        avgHum += h;
        humCount++;
      }
    }

    addStats(r1);
    addStats(r2);
    addStats(r3);

    final String maxTempStr =
        maxTemp == -999.0 ? "N/A" : "${maxTemp.toStringAsFixed(1)}°C";
    final String minTempStr =
        minTemp == 999.0 ? "N/A" : "${minTemp.toStringAsFixed(1)}°C";
    final String maxHumStr =
        maxHum == -999.0 ? "N/A" : "${maxHum.toStringAsFixed(0)}%";
    final String minHumStr =
        minHum == 999.0 ? "N/A" : "${minHum.toStringAsFixed(0)}%";
    final String avgHumStr =
        humCount == 0 ? "N/A" : "${(avgHum / humCount).toStringAsFixed(0)}%";

    final bool isMobile = screenWidth < 900;

    if (isMobile) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHealthStatusCard(alarmCount, faultCount, normalCount),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child: _buildAlertLogCard(activeAlerts),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: _buildCentralChartCard(
                selectedRoom, selectedColor, temps, humidities, timestamps),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: _buildChannelSelectorRow(r1, r2, r3),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: _buildExtremesStatsCard(
              maxT: maxTempStr,
              minT: minTempStr,
              maxH: maxHumStr,
              minH: minHumStr,
              avgH: avgHumStr,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: _buildAlertLogCard(activeAlerts),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(
                  child: _buildCentralChartCard(
                      selectedRoom, selectedColor, temps, humidities, timestamps),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 135,
                  child: _buildChannelSelectorRow(r1, r2, r3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(
                  flex: 1,
                  child: _buildExtremesStatsCard(
                    maxT: maxTempStr,
                    minT: minTempStr,
                    maxH: maxHumStr,
                    minH: minHumStr,
                    avgH: avgHumStr,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 1,
                  child: _buildHealthStatusCard(alarmCount, faultCount, normalCount),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertLogCard(List<Map<String, dynamic>> alerts) {
    final Color borderCol =
        isDarkMode ? const Color(0xFF1E222B) : const Color(0xFFE5E7EB);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF13151A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded,
                  color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 10),
              Text(
                'ACTIVE AMBIENT ALERTS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isDarkMode ? Colors.white : const Color(0xFF1F2937),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: alerts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withAlpha(15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.gpp_good_rounded,
                            color: Color(0xFF10B981),
                            size: 44,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'ALL SYSTEMS NORMAL',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No threshold violations detected.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode ? Colors.white54 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        scrollbarTheme: ScrollbarThemeData(
                          thumbColor: MaterialStateProperty.all(violetThemeColor.withOpacity(0.5)),
                          radius: const Radius.circular(8),
                        ),
                      ),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12.0, bottom: 12.0),
                            child: Table(
                              columnWidths: const {
                        0: FlexColumnWidth(1),
                        1: FlexColumnWidth(1.5),
                        2: FlexColumnWidth(1),
                        3: FlexColumnWidth(1.5),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: borderCol)),
                          ),
                          children: [
                            _buildTableHeader('Time'),
                            _buildTableHeader('Source'),
                            _buildTableHeader('Value'),
                            _buildTableHeader('Alert'),
                          ],
                        ),
                        ...alerts.map((alert) {
                          final Color condColor =
                              alert['condition'].toString().contains('High')
                                  ? Colors.redAccent
                                  : Colors.blueAccent;
                          return TableRow(
                            children: [
                              _buildTableCell(alert['time'] ?? ''),
                              _buildTableCell(alert['room'] ?? ''),
                              _buildTableCell(alert['value'] ?? ''),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  alert['condition'] ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: condColor,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: isDarkMode ? Colors.white54 : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildTableCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: isDarkMode ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildCentralChartCard(
    String roomName,
    Color sensorColor,
    List<double> temps,
    List<double> humidities,
    List<String> timestamps,
  ) {
    final Color borderCol =
        isDarkMode ? const Color(0xFF1E222B) : const Color(0xFFE5E7EB);

    final bool showTemp = currentTab != "Humidity Only";
    final bool showHumidity = currentTab != "Temperature Only";

    String titleText = 'CHAMBER TIMELINE: ${roomName.toUpperCase()}';
    if (!showHumidity) {
      titleText = 'CHAMBER TEMPERATURE: ${roomName.toUpperCase()}';
    } else if (!showTemp) {
      titleText = 'CHAMBER HUMIDITY: ${roomName.toUpperCase()}';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF13151A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    showTemp ? Icons.thermostat_rounded : Icons.water_drop_rounded,
                    color: showTemp ? sensorColor : violetThemeColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    titleText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: isDarkMode ? Colors.white : const Color(0xFF1F2937),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (showTemp) ...[
                    _buildLegendItem(label: 'Temp (°C)', color: sensorColor),
                  ],
                  if (showTemp && showHumidity) const SizedBox(width: 12),
                  if (showHumidity) ...[
                    _buildLegendItem(label: 'Humidity (%)', color: violetThemeColor),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: temps.isEmpty
                ? const Center(child: Text('Awaiting network data streams...'))
                : SizedBox(
                    width: double.infinity,
                    child: CustomPaint(
                      painter: DoubleMetricLinePainter(
                        temps: temps,
                        humidities: humidities,
                        timestamps: timestamps,
                        tempColor: sensorColor,
                        humidityColor: violetThemeColor,
                        isDark: isDarkMode,
                        showTemp: showTemp,
                        showHumidity: showHumidity,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({required String label, required Color color}) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.white54 : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildChannelSelectorRow(
    Map<String, dynamic>? r1,
    Map<String, dynamic>? r2,
    Map<String, dynamic>? r3,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildChannelButton(
            index: 0,
            channelNum: 'CH 01',
            sensorName: 'Blossom',
            roomName: r1RoomName,
            reading: r1,
            accentColor: const Color(0xFFFC3D73),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildChannelButton(
            index: 1,
            channelNum: 'CH 02',
            sensorName: 'Bubbles',
            roomName: r2RoomName,
            reading: r2,
            accentColor: const Color(0xFF349DFB),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildChannelButton(
            index: 2,
            channelNum: 'CH 03',
            sensorName: 'Buttercup',
            roomName: r3RoomName,
            reading: r3,
            accentColor: const Color(0xFF38C124),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelButton({
    required int index,
    required String channelNum,
    required String sensorName,
    required String roomName,
    required Map<String, dynamic>? reading,
    required Color accentColor,
  }) {
    final bool isSelected = selectedChannelIndex == index;
    final bool hasData = reading != null;
    final double temp =
        double.tryParse(reading?['temperature']?.toString() ?? '0') ?? 0.0;
    final double hum =
        double.tryParse(reading?['humidity']?.toString() ?? '0') ?? 0.0;
    final Color borderCol =
        isDarkMode ? const Color(0xFF1E222B) : const Color(0xFFE5E7EB);

    return InkWell(
      onTap: () => setState(() => selectedChannelIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF13151A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accentColor.withAlpha(200) : borderCol,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withAlpha(20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  channelNum,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: accentColor,
                  ),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasData ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              roomName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : const Color(0xFF1F2937),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'Node: $sensorName',
              style: TextStyle(
                fontSize: 10,
                color: isDarkMode ? Colors.white54 : Colors.grey,
              ),
            ),
            const Divider(height: 12, thickness: 0.5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hasData ? '${temp.toStringAsFixed(1)}°C' : '--°C',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  hasData ? '${hum.toStringAsFixed(0)}%' : '--%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white70 : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtremesStatsCard({
    required String maxT,
    required String minT,
    required String maxH,
    required String minH,
    required String avgH,
  }) {
    final Color borderCol =
        isDarkMode ? const Color(0xFF1E222B) : const Color(0xFFE5E7EB);

    final List<Widget> rows = [];
    if (currentTab != "Humidity Only") {
      rows.add(_buildStatRow(Icons.thermostat_rounded, Colors.redAccent, 'Peak Temp Value', maxT));
      rows.add(_buildStatRow(Icons.severe_cold_rounded, Colors.blueAccent, 'Minimum Temp Value', minT));
    }
    if (currentTab != "Temperature Only") {
      if (currentTab == "Humidity Only") {
        rows.add(_buildStatRow(Icons.water_drop_rounded, violetThemeColor, 'Peak Humidity', maxH));
        rows.add(_buildStatRow(Icons.water_drop_rounded, Colors.blue, 'Minimum Humidity', minH));
      }
      rows.add(_buildStatRow(Icons.opacity_rounded, violetThemeColor, 'Chamber Avg Humidity', avgH));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF13151A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_rounded, color: violetThemeColor, size: 20),
              const SizedBox(width: 10),
              Text(
                'EXTREME RANGE SUMMARY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isDarkMode ? Colors.white : const Color(0xFF1F2937),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  for (int i = 0; i < rows.length; i++) ...[
                    rows[i],
                    if (i < rows.length - 1) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
      IconData icon, Color iconColor, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1A1C23) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF222430) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthStatusCard(int alarms, int faults, int normals) {
    final Color borderCol =
        isDarkMode ? const Color(0xFF1E222B) : const Color(0xFFE5E7EB);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF13151A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.health_and_safety_rounded,
                  color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 10),
              Text(
                'SENSOR NODE STATUS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isDarkMode ? Colors.white : const Color(0xFF1F2937),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildHealthStatChip(Colors.redAccent, 'Alarms', alarms),
                      _buildHealthStatChip(
                          Colors.orangeAccent, 'Faults', faults),
                      _buildHealthStatChip(Colors.green, 'Normal', normals),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Center(
                    child: FuturisticRadarDial(
                      hasAlarms: alarms > 0,
                      hasFaults: faults > 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthStatChip(Color color, String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryView(Color cardBg, Color textCol, Color subtextCol) {
    final bool hasMoreLogs = filteredReadings.length > 10;
    final int viewCount = (showAllLogsOverride || !hasMoreLogs)
        ? filteredReadings.length
        : 10;
    final List<dynamic> paginatedLogs = filteredReadings
        .take(viewCount)
        .toList();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedDateFilter != null
                          ? violetThemeColor
                          : (isDarkMode
                                ? const Color(0xFF16171B)
                                : Colors.white),
                      foregroundColor: selectedDateFilter != null
                          ? Colors.white
                          : textCol,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.calendar_month_rounded, size: 16),
                    label: Text(
                      selectedDateFilter == null
                          ? "Filter Date"
                          : "${selectedDateFilter!.year}-${selectedDateFilter!.month.toString().padLeft(2, '0')}-${selectedDateFilter!.day.toString().padLeft(2, '0')}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDateFilter ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: isDarkMode
                                ? ThemeData.dark().copyWith(
                                    colorScheme: ColorScheme.dark(
                                      primary: violetThemeColor,
                                      surface: const Color(0xFF16171B),
                                    ),
                                  )
                                : ThemeData.light().copyWith(
                                    colorScheme: ColorScheme.light(
                                      primary: violetThemeColor,
                                    ),
                                  ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDateFilter = picked;
                          showAllLogsOverride = false;
                          _applyFilter();
                        });
                      }
                    },
                  ),
                  if (selectedDateFilter != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      onPressed: () {
                        setState(() {
                          selectedDateFilter = null;
                          _applyFilter();
                        });
                      },
                    ),
                  ],
                  const SizedBox(width: 8),
                  Container(
                    width: 1,
                    height: 24,
                    color: isDarkMode ? Colors.white24 : Colors.black12,
                  ),
                  const SizedBox(width: 8),
                  ...getUniqueMembers().map(
                    (member) => _buildDynamicFilterTab(member),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (paginatedLogs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'No historical logs match selection criteria.',
                style: TextStyle(color: subtextCol),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == paginatedLogs.length) {
                    return GestureDetector(
                      onTap: () => setState(() => showAllLogsOverride = true),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 24, top: 4),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: violetThemeColor.withAlpha(25),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: violetThemeColor.withAlpha(80),
                          ),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.expand_more_rounded,
                                color: violetThemeColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Show All Remaining Logs (${filteredReadings.length - 10} more items)',
                                style: TextStyle(
                                  color: violetThemeColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final log = paginatedLogs[index];
                  final String name = log['member_name'] ?? 'Node';
                  final String location = log['room_location'] ?? 'Zone';
                  final String rawTime = log['recorded_at'] ?? '';
                  final double temp =
                      double.tryParse(log['temperature']?.toString() ?? '0') ??
                      0.0;
                  final double hum =
                      double.tryParse(log['humidity']?.toString() ?? '0') ??
                      0.0;

                  // MODIFIED: Generate highly readable, completely dynamic summaries based on ambient metrics
                  String tempStatus = "at a comfortable temperature";
                  if (temp >= 30.0) {
                    tempStatus = "too hot";
                  } else if (temp < 18.0) {
                    tempStatus = "too cold";
                  }

                  String humidityStatus = "comfortable humidity";
                  if (hum >= 70.0) {
                    humidityStatus = "very humid";
                  } else if (hum < 35.0) {
                    humidityStatus = "very dry";
                  }

                  final String dynamicRemark =
                      "The $location is $tempStatus with ${temp.toStringAsFixed(1)}°C and is $humidityStatus with ${hum.toStringAsFixed(0)}% humidity.";

                  Color labelSideColor = Colors.grey;
                  if (location.toLowerCase() == r1RoomName.toLowerCase()) {
                    labelSideColor = const Color(0xFFFC3D73);
                  }
                  if (location.toLowerCase() == r2RoomName.toLowerCase()) {
                    labelSideColor = const Color(0xFF349DFB);
                  }
                  if (location.toLowerCase() == r3RoomName.toLowerCase()) {
                    labelSideColor = const Color(0xFF38C124);
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDarkMode
                            ? const Color(0xFF22242B)
                            : const Color(0xFFF3F4F6),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Container(width: 5, color: labelSideColor),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // CHANGED: Primary header text is now the Room Location instead of member name
                                      Text(
                                        location.toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: textCol,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      // Secondary badge displays reporting device owner identifier
                                      Text(
                                        "ESP32: $name",
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: labelSideColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // CHANGED: Displaying our completely dynamic explanation string
                                  Text(
                                    dynamicRemark,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: subtextCol,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          _buildBadge(
                                            '${temp.toStringAsFixed(1)}°C',
                                            const Color(0xFFEF4444),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildBadge(
                                            '${hum.toStringAsFixed(0)}%',
                                            violetThemeColor,
                                          ),
                                        ],
                                      ),
                                      Text(
                                        convertToHumanTime(rawTime),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: subtextCol,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount:
                    paginatedLogs.length +
                    ((hasMoreLogs && !showAllLogsOverride) ? 1 : 0),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDynamicFilterTab(String value) {
    bool isActive = selectedFilter.toUpperCase() == value.toUpperCase();
    bool isHovered = _filterHoverStates[value] ?? false;

    Color bgSelectionColor = violetThemeColor;
    Color textSelectionColor = Colors.white;

    if (isActive) {
      if (value.toUpperCase() == "ALL") {
        bgSelectionColor = violetThemeColor;
      } else {
        final matchingLog = allReadings.firstWhere(
          (element) =>
              (element['member_name'] ?? '').toString().toUpperCase() ==
              value.toUpperCase(),
          orElse: () => null,
        );
          if (matchingLog != null) {
            final String location = matchingLog['room_location'] ?? '';
            if (location.toLowerCase() == r1RoomName.toLowerCase()) {
              bgSelectionColor = const Color(0xFFFC3D73);
            }
            if (location.toLowerCase() == r2RoomName.toLowerCase()) {
              bgSelectionColor = const Color(0xFF349DFB);
            }
            if (location.toLowerCase() == r3RoomName.toLowerCase()) {
              bgSelectionColor = const Color(0xFF38C124);
            }
          }
      }
    } else {
      if (isHovered) {
        bgSelectionColor = isDarkMode
            ? const Color(0xFF2C2E35)
            : violetThemeColor.withAlpha(35);
      } else {
        bgSelectionColor = isDarkMode ? const Color(0xFF16171B) : Colors.white;
      }
      textSelectionColor = isDarkMode
          ? const Color(0xFFDFDFDF)
          : Colors.black87;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _filterHoverStates[value] = true),
      onExit: (_) => setState(() => _filterHoverStates[value] = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgSelectionColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: !isActive && isHovered
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          onTap: () => setState(() {
            selectedFilter = value;
            showAllLogsOverride = false;
            _applyFilter();
          }),
          borderRadius: BorderRadius.circular(20),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isActive ? Colors.white : textSelectionColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // Widget _buildErrorBanner(String message) {
  //   return Container(
  //     margin: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
  //     padding: const EdgeInsets.all(12),
  //     decoration: BoxDecoration(
  //       color: Colors.red.withAlpha(25),
  //       borderRadius: BorderRadius.circular(12),
  //     ),
  //     child: Text(
  //       message,
  //       style: const TextStyle(color: Colors.redAccent, fontSize: 12),
  //     ),
  //   );
  // }
}

class SensorCard extends StatefulWidget {
  final String label;
  final String roomName;
  final Map<String, dynamic>? latestReading;
  final Color accentColor;
  final List<Color> lightGradient;
  final List<Color> darkGradient;
  final IconData icon;
  final double width;
  final bool isDarkMode;

  const SensorCard({
    super.key,
    required this.label,
    required this.roomName,
    required this.latestReading,
    required this.accentColor,
    required this.lightGradient,
    required this.darkGradient,
    required this.icon,
    required this.width,
    required this.isDarkMode,
  });

  @override
  State<SensorCard> createState() => _SensorCardState();
}

class _SensorCardState extends State<SensorCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool hasData = widget.latestReading != null;
    final double temp =
        double.tryParse(widget.latestReading?['temperature']?.toString() ?? '0') ??
        0.0;
    final double hum =
        double.tryParse(widget.latestReading?['humidity']?.toString() ?? '0') ?? 0.0;
    final gradient = widget.isDarkMode ? widget.darkGradient : widget.lightGradient;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0.0, _isHovered ? -6.0 : 0.0, 0.0),
        width: widget.width,
        height: 235,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isHovered 
                ? widget.accentColor.withAlpha(150)
                : widget.accentColor.withAlpha(50), 
            width: _isHovered ? 2.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.accentColor.withAlpha(_isHovered ? (widget.isDarkMode ? 50 : 25) : (widget.isDarkMode ? 30 : 5)),
              blurRadius: _isHovered ? 18 : 12,
              offset: Offset(0, _isHovered ? 8 : 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.accentColor,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Icon(widget.icon, color: widget.accentColor, size: 16),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.roomName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: widget.isDarkMode ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            if (hasData)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Temperature',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: widget.accentColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${temp.toStringAsFixed(1)}°C',
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              color: widget.isDarkMode ? Colors.white : Colors.black87,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Humidity',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: widget.accentColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${hum.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              color: widget.isDarkMode ? Colors.white : Colors.black87,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14.0),
                child: Text(
                  'No readings recorded',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasData ? widget.accentColor : Colors.grey,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  hasData ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: hasData
                        ? (widget.isDarkMode ? Colors.white54 : Colors.black54)
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CustomHoverNavPill extends StatefulWidget {
  final String text;
  final bool isSelected;
  final Color activeColor;
  final bool isDarkMode;
  final VoidCallback onTap;

  const CustomHoverNavPill({
    super.key,
    required this.text,
    required this.isSelected,
    required this.activeColor,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  State<CustomHoverNavPill> createState() => _CustomHoverNavPillState();
}

class _CustomHoverNavPillState extends State<CustomHoverNavPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color hoverColor = widget.isDarkMode
        ? const Color(0xFF22242A)
        : widget.activeColor.withAlpha(40);
    final Color unselectedTextColor = widget.isDarkMode
        ? const Color(0xFFDFDFDF)
        : Colors.black87;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? widget.activeColor
              : (_isHovered ? hoverColor : Colors.transparent),
          borderRadius: BorderRadius.circular(22),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(22),
          child: Text(
            widget.text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: widget.isSelected ? Colors.white : unselectedTextColor,
            ),
          ),
        ),
      ),
    );
  }
}

class SingleMetricLinePainter extends CustomPainter {
  final List<double> values;
  final List<String> timestamps;
  final Color lineColor;
  final bool isDark;
  final bool isPercent;

  SingleMetricLinePainter({
    required this.values,
    required this.timestamps,
    required this.lineColor,
    required this.isDark,
    required this.isPercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    double leftMargin = 45.0;
    double bottomMargin = 20.0;
    double topMargin = 15.0;
    double rightMargin = 15.0;

    double drawableWidth = size.width - leftMargin - rightMargin;
    double drawableHeight = size.height - topMargin - bottomMargin;

    double minVal = values.reduce(min);
    double maxVal = values.reduce(max);
    double valueRange = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    double boundsPadding = valueRange * 0.15;
    double minBound = minVal - boundsPadding;
    double maxBound = maxVal + boundsPadding;
    double finalRange = maxBound - minBound;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    final Color axisColor = isDark 
        ? Colors.white.withAlpha(20) 
        : Colors.black.withAlpha(15);
    final Color axisLabelColor = isDark 
        ? Colors.white.withAlpha(170) 
        : Colors.black.withAlpha(190);

    final int yGridCount = 3;
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.0;

    // Draw dashed horizontal grid lines and Y-axis labels
    for (int i = 0; i <= yGridCount; i++) {
      double pct = i / yGridCount;
      double yCoord = topMargin + drawableHeight - (pct * drawableHeight);
      double valLabel = minBound + (pct * finalRange);

      // Dash line drawing
      double startX = leftMargin;
      double endX = size.width - rightMargin;
      double dashWidth = 5.0;
      double dashSpace = 4.0;
      while (startX < endX) {
        canvas.drawLine(
          Offset(startX, yCoord),
          Offset(min(startX + dashWidth, endX), yCoord),
          axisPaint,
        );
        startX += dashWidth + dashSpace;
      }

      String suffix = isPercent ? '%' : '°';
      textPainter.text = TextSpan(
        text: '${valLabel.toStringAsFixed(1)}$suffix',
        style: TextStyle(
          color: axisLabelColor,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(4, yCoord - textPainter.height / 2));
    }

    double widthInterval =
        drawableWidth / (values.length == 1 ? 1 : values.length - 1);

    List<Offset> pointCoordinates = [];
    for (int i = 0; i < values.length; i++) {
      double x = leftMargin + (i * widthInterval);
      double normalizedY = (values[i] - minBound) / finalRange;
      double y = topMargin + drawableHeight - (normalizedY * drawableHeight);
      pointCoordinates.add(Offset(x, y));
    }

    if (pointCoordinates.isNotEmpty) {
      // 1. Build the smooth cubic Bezier path
      Path path = Path();
      path.moveTo(pointCoordinates[0].dx, pointCoordinates[0].dy);
      
      for (int i = 0; i < pointCoordinates.length - 1; i++) {
        var p0 = pointCoordinates[i];
        var p1 = pointCoordinates[i + 1];
        var controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
        var controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
        path.cubicTo(
          controlPoint1.dx, controlPoint1.dy,
          controlPoint2.dx, controlPoint2.dy,
          p1.dx, p1.dy,
        );
      }

      // 2. Draw the gradient area fill underneath the curve
      Path fillPath = Path.from(path);
      fillPath.lineTo(pointCoordinates.last.dx, topMargin + drawableHeight);
      fillPath.lineTo(pointCoordinates.first.dx, topMargin + drawableHeight);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withAlpha(70),
            lineColor.withAlpha(0),
          ],
        ).createShader(Rect.fromLTWH(
          leftMargin,
          topMargin,
          drawableWidth,
          drawableHeight,
        ));
      canvas.drawPath(fillPath, fillPaint);

      // 3. Draw the main stroke line
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, linePaint);

      // 4. Draw data point circles (small, subtle)
      final dotPaint = Paint()..color = lineColor;
      for (int i = 0; i < pointCoordinates.length - 1; i++) {
        canvas.drawCircle(pointCoordinates[i], 2.5, dotPaint);
      }

      // 5. Draw the final point with a special glowing halo indicator (focal point)
      final lastPoint = pointCoordinates.last;
      
      // Glow halo
      final glowPaint = Paint()
        ..color = lineColor.withAlpha(80)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(lastPoint, 7.0, glowPaint);

      // Center dot
      canvas.drawCircle(lastPoint, 3.5, dotPaint);
    }

    // Draw X-axis timestamps
    if (timestamps.isNotEmpty) {
      int xLabelInterval = (timestamps.length / 3).ceil().clamp(
        1,
        timestamps.length,
      );
      for (int i = 0; i < timestamps.length; i++) {
        if (i % xLabelInterval == 0 || i == timestamps.length - 1) {
          double x = leftMargin + (i * widthInterval);

          textPainter.text = TextSpan(
            text: timestamps[i],
            style: TextStyle(
              color: axisLabelColor,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          );
          textPainter.layout();

          double paintX = x - (textPainter.width / 2);
          if (paintX < leftMargin) {
            paintX = leftMargin;
          }
          if (paintX + textPainter.width > size.width) {
            paintX = size.width - textPainter.width;
          }

          textPainter.paint(
            canvas,
            Offset(paintX, size.height - bottomMargin + 4),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ============================================================================
// DUAL-AXIS CUSTOM SPLINE CHART PAINTER
// ============================================================================
class DoubleMetricLinePainter extends CustomPainter {
  final List<double> temps;
  final List<double> humidities;
  final List<String> timestamps;
  final Color tempColor;
  final Color humidityColor;
  final bool isDark;
  final bool showTemp;
  final bool showHumidity;

  DoubleMetricLinePainter({
    required this.temps,
    required this.humidities,
    required this.timestamps,
    required this.tempColor,
    required this.humidityColor,
    required this.isDark,
    required this.showTemp,
    required this.showHumidity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showTemp && !showHumidity) return;

    double leftMargin = 50.0;
    double bottomMargin = 20.0;
    double topMargin = 15.0;
    double rightMargin = 50.0;

    double drawableWidth = size.width - leftMargin - rightMargin;
    double drawableHeight = size.height - topMargin - bottomMargin;

    // Compute bounds for temperature
    double minT = 0.0;
    double maxT = 100.0;
    double finalTRange = 100.0;
    double minTBound = 0.0;
    if (temps.isNotEmpty) {
      minT = temps.reduce(min);
      maxT = temps.reduce(max);
      double tRange = (maxT - minT) == 0 ? 1.0 : (maxT - minT);
      double tPadding = tRange * 0.15;
      minTBound = minT - tPadding;
      double maxTBound = maxT + tPadding;
      finalTRange = maxTBound - minTBound;
    }

    // Compute bounds for humidity
    double minH = 0.0;
    double maxH = 100.0;
    double finalHRange = 100.0;
    double minHBound = 0.0;
    double maxHBound = 100.0;
    if (humidities.isNotEmpty) {
      minH = humidities.reduce(min);
      maxH = humidities.reduce(max);
      double hRange = (maxH - minH) == 0 ? 1.0 : (maxH - minH);
      double hPadding = hRange * 0.15;
      minHBound = (minH - hPadding).clamp(0.0, 100.0);
      maxHBound = (maxH + hPadding).clamp(0.0, 100.0);
      finalHRange = maxHBound - minHBound;
    }

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    final Color axisColor = isDark 
        ? Colors.white.withAlpha(20) 
        : Colors.black.withAlpha(15);
    final Color axisLabelColor = isDark 
        ? Colors.white.withAlpha(170) 
        : Colors.black.withAlpha(190);

    final int yGridCount = 3;
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.0;

    // Draw grid lines & Y-axis labels
    for (int i = 0; i <= yGridCount; i++) {
      double pct = i / yGridCount;
      double yCoord = topMargin + drawableHeight - (pct * drawableHeight);
      
      // Draw grid line
      double startX = leftMargin;
      double endX = size.width - rightMargin;
      double dashWidth = 5.0;
      double dashSpace = 4.0;
      while (startX < endX) {
        canvas.drawLine(
          Offset(startX, yCoord),
          Offset(min(startX + dashWidth, endX), yCoord),
          axisPaint,
        );
        startX += dashWidth + dashSpace;
      }

      // Left Y-axis (Temperature or Humidity if Temperature is hidden)
      if (showTemp) {
        double tVal = minTBound + (pct * finalTRange);
        textPainter.text = TextSpan(
          text: '${tVal.toStringAsFixed(1)}°C',
          style: TextStyle(
            color: tempColor.withAlpha(isDark ? 200 : 255),
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(4, yCoord - textPainter.height / 2));
      } else if (showHumidity) {
        double hVal = minHBound + (pct * finalHRange);
        textPainter.text = TextSpan(
          text: '${hVal.toStringAsFixed(0)}%',
          style: TextStyle(
            color: humidityColor.withAlpha(isDark ? 200 : 255),
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(4, yCoord - textPainter.height / 2));
      }

      // Right Y-axis (Humidity - only show if both are enabled)
      if (showHumidity && showTemp && humidities.isNotEmpty) {
        double hVal = minHBound + (pct * finalHRange);
        textPainter.text = TextSpan(
          text: '${hVal.toStringAsFixed(0)}%',
          style: TextStyle(
            color: humidityColor.withAlpha(isDark ? 200 : 255),
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(size.width - rightMargin + 6, yCoord - textPainter.height / 2),
        );
      }
    }

    double widthInterval =
        drawableWidth / (temps.length == 1 ? 1 : temps.length - 1);

    // Temperature Curve
    if (showTemp && temps.isNotEmpty) {
      List<Offset> tempCoords = [];
      for (int i = 0; i < temps.length; i++) {
        double x = leftMargin + (i * widthInterval);
        double normalizedY = (temps[i] - minTBound) / finalTRange;
        double y = topMargin + drawableHeight - (normalizedY * drawableHeight);
        tempCoords.add(Offset(x, y));
      }
      _drawSmoothCurve(canvas, tempCoords, tempColor, drawableHeight, topMargin, leftMargin, drawableWidth);
    }

    // Humidity Curve
    if (showHumidity && humidities.isNotEmpty) {
      List<Offset> humCoords = [];
      for (int i = 0; i < humidities.length; i++) {
        double x = leftMargin + (i * widthInterval);
        double normalizedY = (humidities[i] - minHBound) / finalHRange;
        double y = topMargin + drawableHeight - (normalizedY * drawableHeight);
        humCoords.add(Offset(x, y));
      }
      _drawSmoothCurve(canvas, humCoords, humidityColor, drawableHeight, topMargin, leftMargin, drawableWidth);
    }

    // X-axis timestamps
    if (timestamps.isNotEmpty) {
      int xLabelInterval = (timestamps.length / 3).ceil().clamp(1, timestamps.length);
      for (int i = 0; i < timestamps.length; i++) {
        if (i % xLabelInterval == 0 || i == timestamps.length - 1) {
          double x = leftMargin + (i * widthInterval);

          textPainter.text = TextSpan(
            text: timestamps[i],
            style: TextStyle(
              color: axisLabelColor,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          );
          textPainter.layout();

          double paintX = x - (textPainter.width / 2);
          if (paintX < leftMargin) {
            paintX = leftMargin;
          }
          if (paintX + textPainter.width > size.width - rightMargin) {
            paintX = size.width - rightMargin - textPainter.width;
          }

          textPainter.paint(
            canvas,
            Offset(paintX, size.height - bottomMargin + 4),
          );
        }
      }
    }
  }

  void _drawSmoothCurve(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double drawableHeight,
    double topMargin,
    double leftMargin,
    double drawableWidth,
  ) {
    if (points.isEmpty) return;

    // 1. Build smooth cubic Bezier path
    Path path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    
    for (int i = 0; i < points.length - 1; i++) {
      var p0 = points[i];
      var p1 = points[i + 1];
      var controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      var controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      path.cubicTo(
        controlPoint1.dx, controlPoint1.dy,
        controlPoint2.dx, controlPoint2.dy,
        p1.dx, p1.dy,
      );
    }

    // 2. Gradient Area Fill
    Path fillPath = Path.from(path);
    fillPath.lineTo(points.last.dx, topMargin + drawableHeight);
    fillPath.lineTo(points.first.dx, topMargin + drawableHeight);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withAlpha(50),
          color.withAlpha(0),
        ],
      ).createShader(Rect.fromLTWH(
        leftMargin,
        topMargin,
        drawableWidth,
        drawableHeight,
      ));
    canvas.drawPath(fillPath, fillPaint);

    // 3. Main Line Stroke
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // 4. Subtle Dots
    final dotPaint = Paint()..color = color;
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawCircle(points[i], 2.5, dotPaint);
    }

    // 5. Glowing Focal Point
    final lastPoint = points.last;
    final glowPaint = Paint()
      ..color = color.withAlpha(80)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(lastPoint, 7.0, glowPaint);
    canvas.drawCircle(lastPoint, 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ============================================================================
// FUTURISTIC RADAR DIAL WITH GLOWING RADAR SWEEP ANIMATION
// ============================================================================
class FuturisticRadarDial extends StatefulWidget {
  final bool hasAlarms;
  final bool hasFaults;

  const FuturisticRadarDial({
    super.key,
    required this.hasAlarms,
    required this.hasFaults,
  });

  @override
  State<FuturisticRadarDial> createState() => _FuturisticRadarDialState();
}

class _FuturisticRadarDialState extends State<FuturisticRadarDial>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor = Colors.green;
    IconData statusIcon = Icons.check_circle_outline_rounded;
    String statusText = "NORMAL";

    if (widget.hasAlarms) {
      statusColor = Colors.redAccent;
      statusIcon = Icons.error_outline_rounded;
      statusText = "ALARM";
    } else if (widget.hasFaults) {
      statusColor = Colors.orangeAccent;
      statusIcon = Icons.warning_amber_rounded;
      statusText = "FAULT";
    }

    return AspectRatio(
      aspectRatio: 1.0,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          double pulse = 1.0;
          if (widget.hasAlarms) {
            pulse = 1.0 + (sin(_controller.value * 2 * pi * 2) * 0.08);
          } else {
            pulse = 1.0 + (sin(_controller.value * 2 * pi) * 0.04);
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: RadarSweepPainter(
                  angle: _controller.value * 2 * pi,
                  color: statusColor,
                ),
              ),
              Transform.scale(
                scale: pulse,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor.withAlpha(20),
                    border: Border.all(
                      color: statusColor.withAlpha(150),
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withAlpha(60),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    statusIcon,
                    color: statusColor,
                    size: 26,
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    color: statusColor,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// RADAR SWEEP PAINTER (RADAR CIRCLES + SWEEP GRADIENT CONE)
// ============================================================================
class RadarSweepPainter extends CustomPainter {
  final double angle;
  final Color color;

  RadarSweepPainter({
    required this.angle,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double radius = min(size.width, size.height) / 2;
    Offset center = Offset(size.width / 2, size.height / 2);

    final Paint circlePaint = Paint()
      ..color = color.withAlpha(25)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw concentric radar circles
    canvas.drawCircle(center, radius, circlePaint);
    canvas.drawCircle(center, radius * 0.7, circlePaint);
    canvas.drawCircle(center, radius * 0.4, circlePaint);

    // Draw crosshair axes
    final Paint linePaint = Paint()
      ..color = color.withAlpha(15)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      linePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      linePaint,
    );

    // Draw sweep gradient sector
    final Paint sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: [
          color.withAlpha(0),
          color.withAlpha(10),
          color.withAlpha(50),
          color.withAlpha(120),
        ],
        stops: const [0.0, 0.5, 0.75, 1.0],
        transform: GradientRotation(angle - pi),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, sweepPaint);

    // Draw primary sweep beam line
    final double beamX = center.dx + radius * cos(angle);
    final double beamY = center.dy + radius * sin(angle);
    final Paint beamPaint = Paint()
      ..color = color.withAlpha(150)
      ..strokeWidth = 1.5;
    canvas.drawLine(center, Offset(beamX, beamY), beamPaint);
  }

  @override
  bool shouldRepaint(covariant RadarSweepPainter oldDelegate) {
    return oldDelegate.angle != angle || oldDelegate.color != color;
  }
}

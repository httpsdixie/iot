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

  late TextEditingController _r1Controller;
  late TextEditingController _r2Controller;
  late TextEditingController _r3Controller;

  final Color violetThemeColor = const Color(0xFF8B5CF6);
  final Map<String, bool> _filterHoverStates = {};

  @override
  void initState() {
    super.initState();
    _r1Controller = TextEditingController();
    _r2Controller = TextEditingController();
    _r3Controller = TextEditingController();
    _loadSettings();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) => fetchData(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _r1Controller.dispose();
    _r2Controller.dispose();
    _r3Controller.dispose();
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
                Icon(Icons.settings_rounded, color: violetThemeColor),
                const SizedBox(width: 10),
                Text(
                  'Configurations',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: violetThemeColor,
                ),
                onPressed: () {
                  setState(() {
                    r1RoomName = _r1Controller.text.trim();
                    r2RoomName = _r2Controller.text.trim();
                    r3RoomName = _r3Controller.text.trim();
                    isLoading = true;
                  });
                  _saveSetting('r1RoomName', r1RoomName);
                  _saveSetting('r2RoomName', r2RoomName);
                  _saveSetting('r3RoomName', r3RoomName);
                  Navigator.of(context).pop();
                  fetchData();
                },
                child: const Text(
                  'Save & Apply',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
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
          const SizedBox(height: 6),
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
        ? const Color(0xFF0C0D0E)
        : const Color(0xFFF7F7F7);
    final Color cardBgColor = isDarkMode
        ? const Color(0xFF16171B)
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
          appBar: AppBar(
            toolbarHeight: 70,
            backgroundColor: isDarkMode
                ? const Color(0xFF16171B)
                : Colors.white,
            elevation: 0,
            iconTheme: IconThemeData(color: textColor, size: 26),
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
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
                              fontSize: 18,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MADJIC TempSens',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                      ),
                    ),
                    Text(
                      'by MADJIC Corp',
                      style: TextStyle(fontSize: 11, color: subtextColor),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              if (!isMobile) ...[
                _buildWebNavPill("Dashboard"),
                const SizedBox(width: 12),
                _buildWebNavPill("History Logs"),
                const SizedBox(width: 20),
              ],
              IconButton(
                icon: Icon(
                  isDarkMode ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
                  color: isDarkMode ? Colors.amber : Colors.blueGrey[700],
                ),
                onPressed: _toggleTheme,
              ),
              IconButton(
                icon: Icon(
                  Icons.settings_rounded,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                ),
                onPressed: _showSettingsDialog,
              ),
              const SizedBox(width: 14),
            ],
          ),
          body: SafeArea(
            child: isLoading
                ? Center(
                    child: CircularProgressIndicator(color: violetThemeColor),
                  )
                : RefreshIndicator(
                    onRefresh: fetchData,
                    color: violetThemeColor,
                    child: currentTab == "Dashboard"
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
          ),
        );
      },
    );
  }

  Widget _buildWebNavPill(String tabName) {
    return CustomHoverNavPill(
      text: tabName,
      isSelected: currentTab == tabName,
      activeColor: violetThemeColor,
      isDarkMode: isDarkMode,
      onTap: () => setState(() {
        currentTab = tabName;
      }),
    );
  }

  Widget _buildDashboardView(
    Color cardBg,
    Color textCol,
    Color subtextCol,
    double currentWidth,
  ) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 20),
      children: [
        if (errorMessage.isNotEmpty) _buildErrorBanner(errorMessage),
        LayoutBuilder(
          builder: (context, constraints) {
            final double cardWidth = constraints.maxWidth < 900
                ? (constraints.maxWidth - 50) / 1.15
                : (constraints.maxWidth - 56) / 3;
            final bool isScrollable = constraints.maxWidth < 900;

            final cardsList = [
              _buildPpgCard(
                label: 'Sensor 1 • Blossom',
                roomName: r1RoomName,
                latestReading: _getLatestReadingForRoom(r1RoomName),
                accentColor: const Color(0xFFFC3D73),
                lightGradient: const [Color(0xFFFFF0F2), Color(0xFFFFDDE3)],
                darkGradient: const [Color(0xFF251318), Color(0xFF190D10)],
                icon: Icons.favorite_rounded,
                width: cardWidth,
              ),
              _buildPpgCard(
                label: 'Sensor 2 • Bubbles',
                roomName: r2RoomName,
                latestReading: _getLatestReadingForRoom(r2RoomName),
                accentColor: const Color(0xFF349DFB),
                lightGradient: const [Color(0xFFEBF6FF), Color(0xFFD6EBFF)],
                darkGradient: const [Color(0xFF0F1B2B), Color(0xFF0A121E)],
                icon: Icons.bubble_chart_rounded,
                width: cardWidth,
              ),
              _buildPpgCard(
                label: 'Sensor 3 • Buttercup',
                roomName: r3RoomName,
                latestReading: _getLatestReadingForRoom(r3RoomName),
                accentColor: const Color(0xFF38C124),
                lightGradient: const [Color(0xFFE8FFE9), Color(0xFFCEFCCE)],
                darkGradient: const [Color(0xFF102012), Color(0xFF0A140B)],
                icon: Icons.bolt_rounded,
                width: cardWidth,
              ),
            ];

            return isScrollable
                ? SizedBox(
                    height: 240,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: cardsList.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: cardsList[index],
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: cardsList,
                    ),
                  );
          },
        ),
        const SizedBox(height: 25),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'TEMPERATURE & HUMIDITY ANALYTICS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: textCol,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildSplitAnalyticsSection(
          r1RoomName,
          const Color(0xFFFC3D73),
          cardBg,
          textCol,
          subtextCol,
          currentWidth,
        ),
        _buildSplitAnalyticsSection(
          r2RoomName,
          const Color(0xFF349DFB),
          cardBg,
          textCol,
          subtextCol,
          currentWidth,
        ),
        _buildSplitAnalyticsSection(
          r3RoomName,
          const Color(0xFF38C124),
          cardBg,
          textCol,
          subtextCol,
          currentWidth,
        ),
      ],
    );
  }

  Widget _buildSplitAnalyticsSection(
    String roomName,
    Color sensorColor,
    Color cardBg,
    Color textCol,
    Color subtextCol,
    double screenWidth,
  ) {
    final historicalData = _getChronologicalReadingsForRoom(roomName);
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

    bool useVerticalLayout = screenWidth < 900;

    Widget leftChart = _buildIndividualChartFrame(
      title: '$roomName - Temperature',
      metricLabel: 'Temp (°C)',
      lineColor: sensorColor,
      values: temps,
      timestamps: timestamps,
      cardBg: cardBg,
      textCol: textCol,
      subtextCol: subtextCol,
      isPercent: false,
    );

    Widget rightChart = _buildIndividualChartFrame(
      title: '$roomName - Humidity',
      metricLabel: 'Humidity (%)',
      lineColor: violetThemeColor,
      values: humidities,
      timestamps: timestamps,
      cardBg: cardBg,
      textCol: textCol,
      subtextCol: subtextCol,
      isPercent: true,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: useVerticalLayout
          ? Column(
              children: [leftChart, const SizedBox(height: 12), rightChart],
            )
          : Row(
              children: [
                Expanded(child: leftChart),
                const SizedBox(width: 16),
                Expanded(child: rightChart),
              ],
            ),
    );
  }

  Widget _buildIndividualChartFrame({
    required String title,
    required String metricLabel,
    required Color lineColor,
    required List<double> values,
    required List<String> timestamps,
    required Color cardBg,
    required Color textCol,
    required Color subtextCol,
    required bool isPercent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF22242B) : const Color(0xFFF3F4F6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: textCol,
                ),
              ),
              Row(
                children: [
                  Container(width: 8, height: 8, color: lineColor),
                  const SizedBox(width: 6),
                  Text(
                    metricLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: subtextCol,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (values.isEmpty)
            const SizedBox(
              height: 140,
              child: Center(child: Text('Awaiting network data streams...')),
            )
          else
            SizedBox(
              height: 145,
              width: double.infinity,
              child: CustomPaint(
                painter: SingleMetricLinePainter(
                  values: values,
                  timestamps: timestamps,
                  lineColor: lineColor,
                  isDark: isDarkMode,
                  isPercent: isPercent,
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
                  ...getUniqueMembers().map(
                    (member) => _buildDynamicFilterTab(member),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 1,
                    height: 24,
                    color: isDarkMode ? Colors.white24 : Colors.black12,
                  ),
                  const SizedBox(width: 8),
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
                  if (location.toLowerCase() == r1RoomName.toLowerCase())
                    labelSideColor = const Color(0xFFFC3D73);
                  if (location.toLowerCase() == r2RoomName.toLowerCase())
                    labelSideColor = const Color(0xFF349DFB);
                  if (location.toLowerCase() == r3RoomName.toLowerCase())
                    labelSideColor = const Color(0xFF38C124);

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
          if (location.toLowerCase() == r1RoomName.toLowerCase())
            bgSelectionColor = const Color(0xFFFC3D73);
          if (location.toLowerCase() == r2RoomName.toLowerCase())
            bgSelectionColor = const Color(0xFF349DFB);
          if (location.toLowerCase() == r3RoomName.toLowerCase())
            bgSelectionColor = const Color(0xFF38C124);
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

  Widget _buildPpgCard({
    required String label,
    required String roomName,
    required Map<String, dynamic>? latestReading,
    required Color accentColor,
    required List<Color> lightGradient,
    required List<Color> darkGradient,
    required IconData icon,
    required double width,
  }) {
    final bool hasData = latestReading != null;
    final double temp =
        double.tryParse(latestReading?['temperature']?.toString() ?? '0') ??
        0.0;
    final double hum =
        double.tryParse(latestReading?['humidity']?.toString() ?? '0') ?? 0.0;
    final gradient = isDarkMode ? darkGradient : lightGradient;

    return Container(
      width: width,
      height: 235,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withAlpha(50), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDarkMode ? 40 : 5),
            blurRadius: 12,
            offset: const Offset(0, 6),
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
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: accentColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Icon(icon, color: accentColor, size: 16),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                roomName,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDarkMode ? Colors.white : Colors.black87,
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
                          color: accentColor,
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
                            color: isDarkMode ? Colors.white : Colors.black87,
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
                          color: accentColor,
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
                            color: isDarkMode ? Colors.white : Colors.black87,
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
                  color: hasData ? accentColor : Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hasData ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: hasData
                      ? (isDarkMode ? Colors.white54 : Colors.black54)
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ],
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

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
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

    double leftMargin = 40.0;
    double bottomMargin = 20.0;
    double topMargin = 10.0;
    double rightMargin = 10.0;

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

    final Color axisColor = isDark ? Colors.white24 : Colors.black26;
    final Color axisLabelColor = isDark ? Colors.white38 : Colors.black45;

    final int yGridCount = 3;
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.0;

    for (int i = 0; i <= yGridCount; i++) {
      double pct = i / yGridCount;
      double yCoord = topMargin + drawableHeight - (pct * drawableHeight);
      double valLabel = minBound + (pct * finalRange);

      canvas.drawLine(
        Offset(leftMargin, yCoord),
        Offset(size.width - rightMargin, yCoord),
        axisPaint,
      );

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
      textPainter.paint(canvas, Offset(2, yCoord - textPainter.height / 2));
    }

    double widthInterval =
        drawableWidth / (values.length == 1 ? 1 : values.length - 1);
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    Path path = Path();
    List<Offset> pointCoordinates = [];

    for (int i = 0; i < values.length; i++) {
      double x = leftMargin + (i * widthInterval);
      double normalizedY = (values[i] - minBound) / finalRange;
      double y = topMargin + drawableHeight - (normalizedY * drawableHeight);

      Offset point = Offset(x, y);
      pointCoordinates.add(point);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    final circlePaint = Paint()..color = lineColor;
    for (var point in pointCoordinates) {
      canvas.drawCircle(point, 3.5, circlePaint);
    }

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
          if (paintX < leftMargin) paintX = leftMargin;
          if (paintX + textPainter.width > size.width)
            paintX = size.width - textPainter.width;

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

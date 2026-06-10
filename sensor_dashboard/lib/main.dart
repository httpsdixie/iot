import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'config_store.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Ambient Dashboard',
      themeMode: ThemeMode.system, // We'll manage theme programmatically in DashboardScreen
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
  // Configurable state variables loaded from local storage
  String serverIp = "localhost";
  String r1RoomName = "Living Room"; // Blossom Pink
  String r2RoomName = "Bedroom";     // Bubbles Blue
  String r3RoomName = "Kitchen";     // Buttercup Green
  bool isDarkMode = false;

  final String supabaseKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

  List<dynamic> allReadings = [];
  List<dynamic> filteredReadings = [];
  bool isLoading = true;
  String errorMessage = '';
  Timer? _refreshTimer;
  
  String selectedFilter = "ALL"; 

  // Controller for manual text entries in settings
  late TextEditingController _ipController;
  late TextEditingController _r1Controller;
  late TextEditingController _r2Controller;
  late TextEditingController _r3Controller;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
    _r1Controller = TextEditingController();
    _r2Controller = TextEditingController();
    _r3Controller = TextEditingController();
    _loadSettings();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) => fetchData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ipController.dispose();
    _r1Controller.dispose();
    _r2Controller.dispose();
    _r3Controller.dispose();
    super.dispose();
  }

  // Build the supabase url dynamically
  String get supabaseUrl => "http://$serverIp:54321/rest/v1/sensor_readings?order=recorded_at.desc";

  Future<void> _loadSettings() async {
    try {
      final ip = await ConfigStore.load('serverIp') ?? 'localhost';
      final r1 = await ConfigStore.load('r1RoomName') ?? 'Living Room';
      final r2 = await ConfigStore.load('r2RoomName') ?? 'Bedroom';
      final r3 = await ConfigStore.load('r3RoomName') ?? 'Kitchen';
      final dark = await ConfigStore.load('isDarkMode') ?? 'false';

      setState(() {
        serverIp = ip;
        r1RoomName = r1;
        r2RoomName = r2;
        r3RoomName = r3;
        isDarkMode = dark == 'true';
        
        _ipController.text = serverIp;
        _r1Controller.text = r1RoomName;
        _r2Controller.text = r2RoomName;
        _r3Controller.text = r3RoomName;
      });
    } catch (e) {
      // Fallback defaults already set
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
      List<String> months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      return "${months[dt.month - 1]} ${dt.day} • $hour:$minute $period";
    } catch (e) {
      return rawTimestamp; 
    }
  }

  Future<void> fetchData() async {
    try {
      final response = await http.get(
        Uri.parse(supabaseUrl),
        headers: {
          'apikey': supabaseKey,
          'Authorization': 'Bearer $supabaseKey',
        },
      ).timeout(const Duration(seconds: 5));

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
        errorMessage = 'Unable to link with network backend at $serverIp.\nCheck host settings and Supabase containers.';
        isLoading = false;
      });
    }
  }

  void _applyFilter() {
    if (selectedFilter == "ALL") {
      filteredReadings = allReadings;
    } else {
      filteredReadings = allReadings.where((log) {
        final String name = (log['member_name'] ?? '').toString().toUpperCase();
        return name == selectedFilter.toUpperCase();
      }).toList();
    }
  }

  // Extract unique members dynamically from readings list
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

  // Extract unique rooms dynamically
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

  // Find the latest reading for a specific room location
  Map<String, dynamic>? _getLatestReadingForRoom(String roomName) {
    try {
      return allReadings.firstWhere(
        (log) => (log['room_location'] ?? '').toString().toLowerCase() == roomName.toLowerCase(),
        orElse: () => null,
      );
    } catch (e) {
      return null;
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
    
    // Set initial controller text
    _ipController.text = serverIp;
    _r1Controller.text = r1RoomName;
    _r2Controller.text = r2RoomName;
    _r3Controller.text = r3RoomName;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final dialogTheme = isDarkMode ? ThemeData.dark() : ThemeData.light();
        final textStyle = TextStyle(color: isDarkMode ? Colors.white : Colors.black87);
        final labelStyle = TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54, fontSize: 13, fontWeight: FontWeight.bold);

        return Theme(
          data: dialogTheme.copyWith(
            dialogTheme: DialogThemeData(
              backgroundColor: isDarkMode ? const Color(0xFF16171B) : Colors.white,
            ),
          ),
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Icon(Icons.settings_rounded, color: isDarkMode ? const Color(0xFFFD5E8A) : const Color(0xFFFC3D73)),
                const SizedBox(width: 10),
                Text(
                  'Configurations',
                  style: TextStyle(fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87),
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
                    Text(
                      'Server IP / Host IP',
                      style: labelStyle,
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _ipController,
                      style: textStyle,
                      decoration: InputDecoration(
                        hintText: 'e.g. localhost or 192.168.1.100',
                        filled: true,
                        fillColor: isDarkMode ? const Color(0xFF202227) : const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 10),
                    Text(
                      'Live Cards Mappings',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isDarkMode ? const Color(0xFF52B3FF) : const Color(0xFF349DFB)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Map cards to locations from the database.',
                      style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white38 : Colors.black38),
                    ),
                    const SizedBox(height: 16),
                    
                    // Card 1 Map (Blossom Pink)
                    _buildRoomSelector(
                      label: 'R1 - Blossom Card (Pink)',
                      controller: _r1Controller,
                      uniqueRooms: uniqueRooms,
                      accentColor: const Color(0xFFFC3D73),
                    ),
                    
                    // Card 2 Map (Bubbles Blue)
                    _buildRoomSelector(
                      label: 'R2 - Bubbles Card (Blue)',
                      controller: _r2Controller,
                      uniqueRooms: uniqueRooms,
                      accentColor: const Color(0xFF349DFB),
                    ),
                    
                    // Card 3 Map (Buttercup Green)
                    _buildRoomSelector(
                      label: 'R3 - Buttercup Card (Green)',
                      controller: _r3Controller,
                      uniqueRooms: uniqueRooms,
                      accentColor: const Color(0xFF38C124),
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.only(right: 16, bottom: 16, left: 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel', style: TextStyle(color: isDarkMode ? Colors.white60 : Colors.grey[600])),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDarkMode ? const Color(0xFFFD5E8A) : const Color(0xFFFC3D73),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  setState(() {
                    serverIp = _ipController.text.trim();
                    r1RoomName = _r1Controller.text.trim();
                    r2RoomName = _r2Controller.text.trim();
                    r3RoomName = _r3Controller.text.trim();
                    isLoading = true;
                  });
                  _saveSetting('serverIp', serverIp);
                  _saveSetting('r1RoomName', r1RoomName);
                  _saveSetting('r2RoomName', r2RoomName);
                  _saveSetting('r3RoomName', r3RoomName);
                  Navigator.of(context).pop();
                  fetchData();
                },
                child: const Text('Save & Apply', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
    final textStyle = TextStyle(color: isDarkMode ? Colors.white : Colors.black87, fontSize: 14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white70 : Colors.black54)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: textStyle,
                  decoration: InputDecoration(
                    hintText: 'Enter room name',
                    filled: true,
                    fillColor: isDarkMode ? const Color(0xFF202227) : const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              if (uniqueRooms.isNotEmpty) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(Icons.arrow_drop_down_circle_outlined, color: isDarkMode ? Colors.white60 : Colors.black54),
                  onSelected: (String val) {
                    controller.text = val;
                  },
                  itemBuilder: (BuildContext context) {
                    return uniqueRooms.map((room) {
                      return PopupMenuItem<String>(
                        value: room,
                        child: Text(room, style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87)),
                      );
                    }).toList();
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = isDarkMode ? const Color(0xFFFD5E8A) : const Color(0xFFFC3D73);
    final Color bgColor = isDarkMode ? const Color(0xFF0C0D0E) : const Color(0xFFFAFBFC);
    final Color cardBgColor = isDarkMode ? const Color(0xFF16171B) : Colors.white;
    final Color textColor = isDarkMode ? Colors.white : const Color(0xFF1F2937);
    final Color subtextColor = isDarkMode ? Colors.white60 : Colors.grey[500]!;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: fetchData,
          color: primaryColor,
          child: isLoading
              ? Center(child: CircularProgressIndicator(color: primaryColor))
              : CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Header Bar
                    SliverPadding(
                      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 8),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                // Styled PPG Star logo
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withAlpha(26),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.star_rounded, color: primaryColor, size: 28),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'IoT Telemetry',
                                      style: TextStyle(
                                        fontSize: 22, 
                                        fontWeight: FontWeight.w900, 
                                        color: textColor, 
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    Text(
                                      'Powerpuff Girls Theme 🌸🫧⚡', 
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: subtextColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                // Theme Toggle Button
                                IconButton(
                                  icon: Icon(
                                    isDarkMode ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
                                    color: isDarkMode ? Colors.amber : Colors.blueGrey[700],
                                  ),
                                  onPressed: _toggleTheme,
                                  tooltip: 'Toggle Theme',
                                ),
                                const SizedBox(width: 4),
                                // Settings Button
                                IconButton(
                                  icon: Icon(Icons.settings_rounded, color: isDarkMode ? Colors.white70 : Colors.black87),
                                  onPressed: _showSettingsDialog,
                                  tooltip: 'Configurations',
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),

                    // Error Notification if API offline
                    if (errorMessage.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFF2C1418) : const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.red.withAlpha(51)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Backend Connection Error',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: isDarkMode ? const Color(0xFFFCA5A5) : Colors.red[800]),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                errorMessage,
                                style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white70 : Colors.red[600]),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red[400],
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                icon: const Icon(Icons.settings_rounded, size: 16),
                                label: const Text('Open Settings', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: _showSettingsDialog,
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Horizontal/Responsive Powerpuff Girls Live Cards Row
                    SliverToBoxAdapter(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final double cardWidth = constraints.maxWidth < 600 ? (constraints.maxWidth - 50) / 1.3 : (constraints.maxWidth - 56) / 3;
                          final bool isScrollable = constraints.maxWidth < 600;

                          final cardsList = [
                            _buildPpgCard(
                              label: 'R1 • Blossom',
                              roomName: r1RoomName,
                              latestReading: _getLatestReadingForRoom(r1RoomName),
                              accentColor: const Color(0xFFFC3D73),
                              lightGradient: const [Color(0xFFFFF0F2), Color(0xFFFFDDE3)],
                              darkGradient: const [Color(0xFF261014), Color(0xFF3F151F)],
                              lightBorder: const Color(0xFFFFBCC9),
                              darkBorder: const Color(0xFF6B1D33),
                              icon: Icons.favorite_rounded, // Blossom's heart
                              width: cardWidth,
                            ),
                            _buildPpgCard(
                              label: 'R2 • Bubbles',
                              roomName: r2RoomName,
                              latestReading: _getLatestReadingForRoom(r2RoomName),
                              accentColor: const Color(0xFF349DFB),
                              lightGradient: const [Color(0xFFEBF6FF), Color(0xFFD6EBFF)],
                              darkGradient: const [Color(0xFF0F1E2E), Color(0xFF162D45)],
                              lightBorder: const Color(0xFFB5DBFF),
                              darkBorder: const Color(0xFF1F4875),
                              icon: Icons.bubble_chart_rounded, // Bubbles' bubble
                              width: cardWidth,
                            ),
                            _buildPpgCard(
                              label: 'R3 • Buttercup',
                              roomName: r3RoomName,
                              latestReading: _getLatestReadingForRoom(r3RoomName),
                              accentColor: const Color(0xFF38C124),
                              lightGradient: const [Color(0xFFE8FFE9), Color(0xFFCEFCCE)],
                              darkGradient: const [Color(0xFF0E2214), Color(0xFF163820)],
                              lightBorder: const Color(0xFFAEF4B1),
                              darkBorder: const Color(0xFF1C522B),
                              icon: Icons.bolt_rounded, // Buttercup's lightning
                              width: cardWidth,
                            ),
                          ];

                          if (isScrollable) {
                            return SizedBox(
                              height: 180,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                itemCount: cardsList.length,
                                itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: cardsList[index],
                                ),
                              ),
                            );
                          } else {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: cardsList,
                              ),
                            );
                          }
                        },
                      ),
                    ),

                    // Filter Dashboard Summary Board
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: isDarkMode ? const Color(0xFF16171B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(isDarkMode ? 20 : 5),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                          border: Border.all(
                            color: isDarkMode ? const Color(0xFF22242B) : const Color(0xFFECEEF2),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem('Records Count', '${filteredReadings.length} logs', textColor, subtextColor),
                            Container(width: 1, height: 35, color: isDarkMode ? const Color(0xFF2C2E35) : const Color(0xFFE5E7EB)),
                            _buildStatItem('Active Filter', selectedFilter, textColor, subtextColor),
                          ],
                        ),
                      ),
                    ),

                    // History Section Header
                    SliverPadding(
                      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 4),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'HISTORY LOGS',
                          style: TextStyle(
                            fontSize: 14, 
                            fontWeight: FontWeight.w900, 
                            color: textColor,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),

                    // Dynamic Filter Tabs (Derived dynamically from data)
                    SliverToBoxAdapter(
                      child: Container(
                        height: 40,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: getUniqueMembers().map((member) => _buildFilterTab(member, primaryColor)).toList(),
                        ),
                      ),
                    ),

                    // List of Historical readings
                    if (filteredReadings.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              errorMessage.isNotEmpty ? 'Offline database data inaccessible.' : 'No readings found for filter "$selectedFilter".',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: subtextColor, height: 1.5),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final log = filteredReadings[index];
                              final String name = log['member_name'] ?? 'Node';
                              final String location = log['room_location'] ?? 'Zone';
                              final String remark = log['readable_summary'] ?? log['remark'] ?? ''; 
                              final String rawTime = log['recorded_at'] ?? '';
                              final double temp = double.tryParse(log['temperature']?.toString() ?? '0') ?? 0.0;
                              final double hum = double.tryParse(log['humidity']?.toString() ?? '0') ?? 0.0;

                              // Style dynamic left border matching R1/R2/R3 settings
                              Color borderLeftColor = Colors.grey[400]!;
                              if (location.toLowerCase() == r1RoomName.toLowerCase()) {
                                borderLeftColor = const Color(0xFFFC3D73);
                              } else if (location.toLowerCase() == r2RoomName.toLowerCase()) {
                                borderLeftColor = const Color(0xFF349DFB);
                              } else if (location.toLowerCase() == r3RoomName.toLowerCase()) {
                                borderLeftColor = const Color(0xFF38C124);
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: cardBgColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDarkMode ? const Color(0xFF22242B) : const Color(0xFFF3F4F6),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(isDarkMode ? 15 : 4), 
                                      blurRadius: 8, 
                                      offset: const Offset(0, 3),
                                    )
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        // Left Indicator Strip matching the room mapping
                                        Container(width: 6, color: borderLeftColor),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(
                                                      name, 
                                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: borderLeftColor.withAlpha(30), 
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        location.toUpperCase(), 
                                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: borderLeftColor),
                                                      ),
                                                    )
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  remark, 
                                                  style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white70 : const Color(0xFF4B5563), height: 1.4),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        _buildBadge(
                                                          Icons.thermostat_rounded, 
                                                          '${temp.toStringAsFixed(1)}°C', 
                                                          isDarkMode ? const Color(0xFF4C1D24) : const Color(0xFFFEE2E2), 
                                                          const Color(0xFFEF4444),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        _buildBadge(
                                                          Icons.water_drop_rounded, 
                                                          '${hum.toStringAsFixed(1)}%', 
                                                          isDarkMode ? const Color(0xFF102A45) : const Color(0xFFE0F2FE), 
                                                          const Color(0xFF0EA5E9),
                                                        ),
                                                      ],
                                                    ),
                                                    Text(
                                                      convertToHumanTime(rawTime), 
                                                      style: TextStyle(fontSize: 11, color: subtextColor),
                                                    ),
                                                  ],
                                                )
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            childCount: filteredReadings.length,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  // PPG Card Builder
  Widget _buildPpgCard({
    required String label,
    required String roomName,
    required Map<String, dynamic>? latestReading,
    required Color accentColor,
    required List<Color> lightGradient,
    required List<Color> darkGradient,
    required Color lightBorder,
    required Color darkBorder,
    required IconData icon,
    required double width,
  }) {
    final bool hasData = latestReading != null;
    final double temp = double.tryParse(latestReading?['temperature']?.toString() ?? '0') ?? 0.0;
    final double hum = double.tryParse(latestReading?['humidity']?.toString() ?? '0') ?? 0.0;
    
    final gradient = isDarkMode ? darkGradient : lightGradient;
    final borderColor = isDarkMode ? darkBorder : lightBorder;
    final titleColor = isDarkMode ? accentColor.withRed(200).withGreen(200).withBlue(255) : accentColor.darken();
    final bodyTextColor = isDarkMode ? Colors.white : const Color(0xFF374151);

    return Container(
      width: width,
      height: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withAlpha(isDarkMode ? 30 : 15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Card Header: PPG Name and Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label, 
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: titleColor, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roomName,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(icon, color: accentColor, size: 20),
            ],
          ),
          
          // Temperature and Humidity Values
          if (hasData)
            Row(
              children: [
                Text(
                  '${temp.toStringAsFixed(1)}°C',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: bodyTextColor, letterSpacing: -1),
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 16, color: bodyTextColor.withAlpha(51)),
                const SizedBox(width: 8),
                Text(
                  '${hum.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: bodyTextColor, letterSpacing: -1),
                ),
              ],
            )
          else
            Text(
              'No Readings',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white38 : Colors.grey[500]),
            ),

          // Bottom Current Badge with Breathing dot
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  BreathingDot(color: hasData ? Colors.green : Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    hasData ? 'current' : 'offline',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: hasData ? Colors.green : Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String value, Color primaryColor) {
    bool isActive = selectedFilter.toUpperCase() == value.toUpperCase();
    final Color activeColor = isDarkMode ? const Color(0xFFFD5E8A) : const Color(0xFFFC3D73);
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedFilter = value;
          _applyFilter();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? activeColor : (isDarkMode ? const Color(0xFF16171B) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.transparent : (isDarkMode ? const Color(0xFF22242B) : Colors.grey[200]!),
          ),
        ),
        child: Center(
          child: Text(
            value,
            style: TextStyle(
              color: isActive ? Colors.white : (isDarkMode ? Colors.white70 : const Color(0xFF4B5563)), 
              fontWeight: FontWeight.bold, 
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color textColor, Color subtextColor) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: subtextColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildBadge(IconData icon, String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textColor)),
        ],
      ),
    );
  }
}

// Helper extension on Color to darken it for Light theme PPG cards text readability
extension ColorDarken on Color {
  Color darken([double amount = .15]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}

class BreathingDot extends StatefulWidget {
  final Color color;
  const BreathingDot({super.key, required this.color});

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.3,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withAlpha(128),
              blurRadius: 4,
              spreadRadius: 2,
            )
          ],
        ),
      ),
    );
  }
}
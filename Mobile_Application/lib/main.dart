import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';
import 'weather_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NZEB Monitor',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

double parseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final db = FirebaseDatabase.instance.ref();
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: const [DashboardTab(), RoomsTab(), HistoryTab()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.meeting_room), label: 'Rooms'),
          NavigationDestination(icon: Icon(Icons.timeline), label: 'History'),
        ],
      ),
    );
  }
}

// DASHBOARD TAB
class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WeatherBanner(),
          const SizedBox(height: 20),

          // Solar & Battery cards in a row
          Row(
            children: [
              Expanded(
                child: StreamBuilder(
                  stream: db.child("Solar").onValue,
                  builder: (context, snap) {
                    if (!snap.hasData || snap.data!.snapshot.value == null) {
                      return const _InfoCard(
                        title: "Solar",
                        icon: Icons.solar_power,
                        value: "--",
                        unit: "W",
                        color: Colors.orange,
                      );
                    }
                    final data = snap.data!.snapshot.value as Map;
                    final powerMW = parseDouble(data['Power']);
                    return _InfoCard(
                      title: "Solar",
                      icon: Icons.solar_power,
                      value: powerMW.toStringAsFixed(0), // Show whole mW
                      unit: "mW",
                      color: Colors.orange,
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder(
                  stream: db.child("Battery").onValue,
                  builder: (context, snap) {
                    if (!snap.hasData || snap.data!.snapshot.value == null) {
                      return const _InfoCard(
                        title: "Battery",
                        icon: Icons.battery_std,
                        value: "--",
                        unit: "%",
                        color: Colors.green,
                      );
                    }
                    final data = snap.data!.snapshot.value as Map;
                    final pct = parseDouble(data['Percentage']);
                    return _InfoCard(
                      title: "Battery",
                      icon: Icons.battery_std,
                      value: pct.toStringAsFixed(0),
                      unit: "%",
                      color: pct > 50 ? Colors.green : Colors.orange,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Environment
          StreamBuilder(
            stream: db.child("Environment").onValue,
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.snapshot.value == null) {
                return const SizedBox();
              }
              final data = snap.data!.snapshot.value as Map;
              final temp = parseDouble(data['Temperature']);
              final hum = parseDouble(data['Humidity']);

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Icon(
                            Icons.thermostat,
                            color: Colors.red,
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${temp.toStringAsFixed(1)}°C",
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            "Temperature",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(
                            Icons.water_drop,
                            color: Colors.blue,
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${hum.toStringAsFixed(0)}%",
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            "Humidity",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // Room power summary
          const Text(
            "Room Power",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            children: ["Room1", "Room2"].map((room) {
              return Expanded(
                child: StreamBuilder(
                  stream: db.child("Downstairs/$room").onValue,
                  builder: (context, snap) {
                    if (!snap.hasData || snap.data!.snapshot.value == null) {
                      return const _InfoCard(
                        title: "Room",
                        icon: Icons.home,
                        value: "--",
                        unit: "W",
                        color: Colors.blue,
                      );
                    }
                    final data = snap.data!.snapshot.value as Map;
                    final power = parseDouble(data['Power']) / 1000;
                    return _InfoCard(
                      title: room,
                      icon: Icons.home,
                      value: power.toStringAsFixed(1),
                      unit: "W",
                      color: Colors.blue,
                    );
                  },
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title, value, unit;
  final IconData icon;
  final Color color;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text("$value $unit", style: TextStyle(fontSize: 20, color: color)),
          ],
        ),
      ),
    );
  }
}

// ROOMS TAB
class RoomsTab extends StatelessWidget {
  const RoomsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: ["Room1", "Room2"].map((room) {
        return StreamBuilder(
          stream: db.child("Downstairs/$room").onValue,
          builder: (context, snap) {
            if (!snap.hasData || snap.data!.snapshot.value == null) {
              return const Card(
                child: SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final data = snap.data!.snapshot.value as Map;
            final relay = data['Relay']?.toString() ?? "OFF";
            final power = parseDouble(data['Power']) / 1000;
            final current = parseDouble(data['Current']);
            final voltage = parseDouble(data['Voltage']);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          room,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Switch(
                          value: relay == "ON",
                          onChanged: (v) {
                            db
                                .child("Downstairs/$room/Relay")
                                .set(v ? "ON" : "OFF");
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(
                          label: "Power",
                          value: "${power.toStringAsFixed(1)}W",
                        ),
                        _StatItem(
                          label: "Current",
                          value: "${current.toStringAsFixed(2)}mA",
                        ),
                        _StatItem(
                          label: "Voltage",
                          value: "${voltage.toStringAsFixed(1)}V",
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(height: 150, child: _RoomPowerChart(room: room)),
                  ],
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label, value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

class _RoomPowerChart extends StatelessWidget {
  final String room;
  const _RoomPowerChart({required this.room});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();

    return FutureBuilder(
      future: db.child("History/$room").limitToLast(12).get(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.value == null) {
          return const Center(child: Text("No data yet"));
        }

        final data = snap.data!.value as Map;
        final spots = <FlSpot>[];
        int i = 0;

        data.forEach((key, value) {
          spots.add(FlSpot(i.toDouble(), parseDouble(value['Power']) / 1000));
          i++;
        });

        if (spots.isEmpty) return const Center(child: Text("No data"));

        return LineChart(
          LineChartData(
            minY: 0,
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: Colors.teal,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: Colors.teal.withOpacity(0.1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// HISTORY TAB
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  String _selected = "Room1";

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();

    return Column(
      children: [
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: ["Room1", "Room2", "Solar", "Battery", "Environment"].map(
              (type) {
                final selected = _selected == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(type),
                    selected: selected,
                    onSelected: (_) => setState(() => _selected = type),
                  ),
                );
              },
            ).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: FutureBuilder(
            future: db.child("History/$_selected").limitToLast(50).get(),
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.value == null) {
                return const Center(child: Text("No history yet"));
              }

              final data = snap.data!.value as Map;
              final entries = data.entries.toList()
                ..sort((a, b) {
                  final aTime = (a.value as Map)['Timestamp'] ?? 0;
                  final bTime = (b.value as Map)['Timestamp'] ?? 0;
                  return bTime.compareTo(aTime);
                });

              if (_selected == "Environment") {
                return _buildEnvHistory(entries);
              } else if (_selected == "Solar" || _selected == "Battery") {
                return _buildPowerHistory(entries, _selected);
              } else {
                return _buildRoomHistory(entries);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRoomHistory(List<MapEntry> entries) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final v = entries[i].value as Map;
        final power = parseDouble(v['Power']) / 1000;
        final ts = v['Timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(v['Timestamp'])
            : DateTime.now();

        return ListTile(
          leading: const Icon(Icons.flash_on, color: Colors.teal),
          title: Text("${power.toStringAsFixed(1)} W"),
          subtitle: Text(DateFormat('MMM d, HH:mm').format(ts)),
          trailing: Text(
            "${parseDouble(v['Voltage']).toStringAsFixed(1)}V",
            style: const TextStyle(color: Colors.grey),
          ),
        );
      },
    );
  }

  Widget _buildEnvHistory(List<MapEntry> entries) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final v = entries[i].value as Map;
        final temp = parseDouble(v['Temperature']);
        final hum = parseDouble(v['Humidity']);

        return ListTile(
          leading: const Icon(Icons.thermostat, color: Colors.red),
          title: Text(
            "${temp.toStringAsFixed(1)}°C | ${hum.toStringAsFixed(0)}%",
          ),
          subtitle: Text(DateFormat('MMM d, HH:mm').format(DateTime.now())),
        );
      },
    );
  }

  Widget _buildPowerHistory(List<MapEntry> entries, String type) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final v = entries[i].value as Map;
        final power = parseDouble(v['Power'] ?? v['Power_mW']) / 1000;
        final voltage = parseDouble(v['Voltage'] ?? v['Voltage_V']);

        return ListTile(
          leading: Icon(
            type == "Solar" ? Icons.solar_power : Icons.battery_std,
            color: type == "Solar" ? Colors.orange : Colors.green,
          ),
          title: Text("${power.toStringAsFixed(1)} W"),
          subtitle: Text("${voltage.toStringAsFixed(1)}V"),
        );
      },
    );
  }
}

// WEATHER
class WeatherBanner extends StatelessWidget {
  const WeatherBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: http.get(
        Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?q=Maynooth&appid=${WeatherConfig.apiKey}&units=metric',
        ),
      ),
      builder: (context, snap) {
        if (!snap.hasData)
          return const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          );

        final data = json.decode(snap.data!.body);
        final temp = data['main']['temp'];
        final desc = data['weather'][0]['description'];
        final icon = data['weather'][0]['icon'];

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ForecastPage()),
            );
          },
          child: Card(
            color: Colors.teal.shade700,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Image.network(
                    "https://openweathermap.org/img/wn/$icon@2x.png",
                    width: 50,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Maynooth",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        "${temp.toStringAsFixed(0)}°C, $desc",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    "5-day >",
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// FORECAST PAGE
class ForecastPage extends StatelessWidget {
  const ForecastPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("5-Day Forecast")),
      body: FutureBuilder(
        future: http.get(
          Uri.parse(
            'https://api.openweathermap.org/data/2.5/forecast?q=Maynooth&appid=${WeatherConfig.apiKey}&units=metric',
          ),
        ),
        builder: (context, snap) {
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());

          final data = json.decode(snap.data!.body);
          final list = data['list'] as List;

          // Group by date
          Map<String, List> grouped = {};
          for (var item in list) {
            final date = item['dt_txt'].toString().substring(0, 10);
            grouped.putIfAbsent(date, () => []).add(item);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: grouped.entries.map((day) {
              final forecasts = day.value;
              double maxTemp = -999, minTemp = 999;
              String icon = '01d', desc = '';

              for (var f in forecasts) {
                final t = (f['main']['temp'] as num).toDouble();
                if (t > maxTemp) maxTemp = t;
                if (t < minTemp) minTemp = t;
                if (desc.isEmpty) {
                  desc = f['weather'][0]['description'];
                  icon = f['weather'][0]['icon'];
                }
              }

              final dateStr = DateFormat(
                'EEEE, MMM d',
              ).format(DateTime.parse(day.key));

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: Image.network(
                    "https://openweathermap.org/img/wn/$icon@2x.png",
                    width: 40,
                  ),
                  title: Text(dateStr),
                  subtitle: Text(
                    "$desc • ${maxTemp.toStringAsFixed(0)}° / ${minTemp.toStringAsFixed(0)}°",
                  ),
                  children: forecasts.map((f) {
                    final time = f['dt_txt'].toString().substring(11, 16);
                    final t = (f['main']['temp'] as num).toDouble();
                    final w = f['weather'][0]['description'];
                    return ListTile(
                      title: Text(time),
                      trailing: Text("${t.toStringAsFixed(0)}°C"),
                      subtitle: Text(w),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

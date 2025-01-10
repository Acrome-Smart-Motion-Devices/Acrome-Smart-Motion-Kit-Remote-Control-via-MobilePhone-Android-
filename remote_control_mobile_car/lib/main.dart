import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; 
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io';
String selectedIp = ''; 
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home:  IPScanner(),
    );
  }
}
class IPScanner extends StatefulWidget {
  @override
  _IPScannerState createState() => _IPScannerState();
}

class _IPScannerState extends State<IPScanner> {
  final NetworkInfo _networkInfo = NetworkInfo();
  String? subnetAddress;
  List<Map<String, String>> devices = [];
  bool isScanning = false;

  Future<void> scanNetwork() async {
    setState(() {
      isScanning = true;
      devices.clear();
    });

    final ipAddress = await _networkInfo.getWifiIP();
    if (ipAddress != null) {
      final subnet = ipAddress.substring(0, ipAddress.lastIndexOf('.'));
      subnetAddress = subnet;

      List<Future> pingTasks = [];
      for (int i = 1; i < 255; i++) {
        final targetIp = '$subnet.$i';
        pingTasks.add(_scanLinuxDevice(targetIp));
      }

      await Future.wait(pingTasks);
    }

    setState(() {
      isScanning = false;
    });
  }

  Future<void> _scanLinuxDevice(String ip) async {
    try {
      final result = await _checkSSHPort(ip);
      if (result) {
        String deviceName = await _getDeviceNameFromSSH(ip);
        setState(() {
          if (!devices.any((device) => device['ip'] == ip)) {
            devices.add({'ip': ip, 'name': deviceName});
          }
        });
      }
    } catch (e) {
      print('Error scanning device $ip: $e');
    }
  }

  Future<bool> _checkSSHPort(String ip) async {
    try {
      final socket = await Socket.connect(ip, 22, timeout: Duration(seconds: 1));
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String> _getDeviceNameFromSSH(String ip) async {
    try {
      final result = await Process.run('ssh', ['-o', 'StrictHostKeyChecking=no', 'aytac@$ip', 'hostname']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      print('Error getting device hostname via SSH: $e');
    }
    return '';
  }

  void _selectIp(String ip) {
    setState(() {
      selectedIp = ip;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('IP Scanner'),
        centerTitle: true,
        backgroundColor: Colors.redAccent,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: isScanning ? null : scanNetwork,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.redAccent,
              ),
              child: Text(isScanning ? 'Scanning...' : 'Scan the Devices'),
            ),
            if (subnetAddress != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text("Subnet IP Address: $subnetAddress"),
              ),
            if (isScanning) CircularProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return ListTile(
                    title: Text(device['ip']!),
                    subtitle: Text(device['name']!),
                    onTap: () => _selectIp(device['ip']!),
                    tileColor: selectedIp == device['ip'] ? Colors.red[100] : null,
                  );
                },
              ),
            ),
            if (selectedIp.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => MyHomePage(title:"Remote_Control_Car")),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Selected IP: $selectedIp')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Colors.redAccent,
                  ),
                  child: Text(
                    'Continue',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Flask API URL
  final String apiUrl = "http://$selectedIp:5005/control";

  Timer? _timer; // Veri gönderimi için timer

  // Komut gönderme fonksiyonu
  Future<void> sendCommand(String direction) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
        body: json.encode({'direction': direction}),
      );

      if (response.statusCode == 200) {
        print("Robot command sent: $direction");
      } else {
        print("Failed to send command");
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  // Basılı tutma işlemi başladığında çağrılır
  void startSending(String direction) {
    sendCommand(direction); // İlk komut hemen gönderiliyor
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      sendCommand(direction); // Her 100ms'de bir komut gönder
    });
  }

  // Basılı tutma işlemi bırakıldığında çağrılır
  void stopSending() {
    _timer?.cancel(); // Timer'ı iptal et
    sendCommand('0'); // Robotu durdur
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        backgroundColor: Colors.redAccent,
        
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Robot Controller',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 50),
            // Kontrol paneli
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Sol Buton
                GestureDetector(
                  onTapDown: (_) => startSending('2'), // Basılmaya başladığında
                  onTapUp: (_) => stopSending(), // Basma bırakıldığında
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: CircleBorder(),
                        padding: EdgeInsets.all(30),
                        backgroundColor: Colors.blue,
                      ),
                      onPressed: null,
                      child: const Icon(Icons.arrow_left, size: 40, color: Colors.white),
                    ),
                  ),
                ),
                // Yukarı Buton
                GestureDetector(
                  onTapDown: (_) => startSending('1'),
                  onTapUp: (_) => stopSending(),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: CircleBorder(),
                        padding: EdgeInsets.all(30),
                        backgroundColor: Colors.blue,
                      ),
                      onPressed: null,
                      child: const Icon(Icons.arrow_upward, size: 40, color: Colors.white),
                    ),
                  ),
                ),
                // Sağ Buton
                GestureDetector(
                  onTapDown: (_) => startSending('3'),
                  onTapUp: (_) => stopSending(),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: CircleBorder(),
                        padding: EdgeInsets.all(30),
                        backgroundColor: Colors.blue,
                      ),
                      onPressed: null,
                      child: const Icon(Icons.arrow_right, size: 40, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 50),
            // Aşağı Buton
            GestureDetector(
              onTapDown: (_) => startSending('4'),
              onTapUp: (_) => stopSending(),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: CircleBorder(),
                    padding: EdgeInsets.all(30),
                    backgroundColor: Colors.blue,
                  ),
                  onPressed: null,
                  child: const Icon(Icons.arrow_downward, size: 40, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 30),
            // Durduğunda buton
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(),
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                backgroundColor: Colors.red,
              ),
              onPressed: stopSending,
              child: const Text('Stop', style: TextStyle(fontSize: 20, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

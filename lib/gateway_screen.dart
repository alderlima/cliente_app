import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:usb_serial/usb_serial.dart';
import 'traccar_gateway_service.dart';
import 'arduino_serial_service.dart';
import 'command_log_service.dart';

/// Tela do Gateway Traccar-Arduino
/// Permite configurar e monitorar o fluxo de comandos entre o servidor Traccar e o Arduino

class GatewayScreen extends StatefulWidget {
  const GatewayScreen({super.key});

  @override
  State<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends State<GatewayScreen> {
  final TraccarGatewayService _gatewayService = TraccarGatewayService();
  final ScrollController _logScrollController = ScrollController();
  
  bool _isRunning = false;
  bool _isArduinoConnected = false;
  int _selectedBaudRate = 9600;
  List<UsbDevice> _availableDevices = [];
  UsbDevice? _selectedDevice;
  
  // Estatísticas
  int _commandsReceived = 0;
  int _commandsForwarded = 0;
  int _responsesReceived = 0;
  
  // Logs
  final List<String> _logs = [];
  
  // Subscriptions
  StreamSubscription? _gatewaySubscription;
  StreamSubscription? _logSubscription;

  @override
  void initState() {
    super.initState();
    _initListeners();
    _refreshDevices();
    
    // Verifica estado inicial
    setState(() {
      _isRunning = _gatewayService.isRunning;
      _isArduinoConnected = _gatewayService.isArduinoConnected;
      _commandsReceived = _gatewayService.commandsReceived;
      _commandsForwarded = _gatewayService.commandsForwarded;
      _responsesReceived = _gatewayService.responsesReceived;
    });
  }

  void _initListeners() {
    // Listener de eventos do gateway
    _gatewaySubscription = _gatewayService.gatewayStream.listen((event) {
      setState(() {
        _isRunning = _gatewayService.isRunning;
        _isArduinoConnected = _gatewayService.isArduinoConnected;
        _commandsReceived = _gatewayService.commandsReceived;
        _commandsForwarded = _gatewayService.commandsForwarded;
        _responsesReceived = _gatewayService.responsesReceived;
      });
    });

    // Listener de logs
    _logSubscription = _gatewayService.logStream.listen((log) {
      setState(() {
        _logs.add(log);
        if (_logs.length > 300) {
          _logs.removeAt(0);
        }
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _refreshDevices() async {
    List<UsbDevice> devices = await _gatewayService.listArduinoDevices();
    setState(() {
      _availableDevices = devices;
    });
  }

  Future<void> _startGateway() async {
    try {
      await _gatewayService.start(
        serverPort: 5023,
        baudRate: _selectedBaudRate,
        autoConnectArduino: true,
      );
      
      setState(() {
        _isRunning = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gateway iniciado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao iniciar gateway: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopGateway() async {
    await _gatewayService.stop();
    setState(() {
      _isRunning = false;
    });
  }

  Future<void> _connectArduino() async {
    if (_selectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um dispositivo Arduino')),
      );
      return;
    }

    bool connected = await _gatewayService.connectArduino(_selectedDevice!);
    
    if (connected) {
      setState(() {
        _isArduinoConnected = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arduino conectado!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao conectar Arduino'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _disconnectArduino() async {
    await _gatewayService.disconnectArduino();
    setState(() {
      _isArduinoConnected = false;
    });
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  void _clearStats() {
    _gatewayService.clearStats();
    setState(() {
      _commandsReceived = 0;
      _commandsForwarded = 0;
      _responsesReceived = 0;
    });
  }

  @override
  void dispose() {
    _gatewaySubscription?.cancel();
    _logSubscription?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gateway Traccar-Arduino'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.settings), text: 'Configuração'),
              Tab(icon: Icon(Icons.analytics), text: 'Monitor'),
              Tab(icon: Icon(Icons.terminal), text: 'Logs'),
            ],
          ),
          actions: [
            // Indicador de status
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isRunning 
                    ? Colors.green.withOpacity(0.2) 
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isRunning ? Colors.green : Colors.red,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: _isRunning ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isRunning ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(
                      color: _isRunning ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildConfigTab(),
            _buildMonitorTab(),
            _buildLogsTab(),
          ],
        ),
      ),
    );
  }

  /// Aba de Configuração
  Widget _buildConfigTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card do Servidor
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.router, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Servidor Traccar (GT06)',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Porta
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.settings_ethernet),
                    title: const Text('Porta TCP'),
                    subtitle: const Text('5023 (Protocolo GT06)'),
                  ),
                  
                  // Status
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _isRunning ? Icons.check_circle : Icons.error,
                      color: _isRunning ? Colors.green : Colors.red,
                    ),
                    title: const Text('Status'),
                    subtitle: Text(_isRunning ? 'Rodando' : 'Parado'),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Botão iniciar/parar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isRunning ? _stopGateway : _startGateway,
                      icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(
                        _isRunning ? 'PARAR GATEWAY' : 'INICIAR GATEWAY',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRunning ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Card do Arduino
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.memory, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Arduino (USB Serial)',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Baud Rate
                  DropdownButtonFormField<int>(
                    value: _selectedBaudRate,
                    decoration: InputDecoration(
                      labelText: 'Baud Rate',
                      prefixIcon: const Icon(Icons.speed),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: ArduinoSerialService.availableBaudRates.map((rate) {
                      return DropdownMenuItem(
                        value: rate,
                        child: Text('$rate bps'),
                      );
                    }).toList(),
                    onChanged: _isRunning 
                        ? null 
                        : (value) {
                            setState(() {
                              _selectedBaudRate = value!;
                            });
                          },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Seleção de dispositivo
                  Row(
                    children: [
                      Expanded(
                        child: _availableDevices.isEmpty
                            ? const Text(
                                'Nenhum dispositivo USB encontrado',
                                style: TextStyle(color: Colors.grey),
                              )
                            : DropdownButtonFormField<UsbDevice>(
                                value: _selectedDevice,
                                decoration: InputDecoration(
                                  labelText: 'Dispositivo Arduino',
                                  prefixIcon: const Icon(Icons.usb),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                hint: const Text('Selecione o Arduino'),
                                items: _availableDevices.map((device) {
                                  return DropdownMenuItem(
                                    value: device,
                                    child: Text(
                                      '${device.productName ?? 'Desconhecido'} (${device.manufacturerName ?? 'N/A'})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (device) {
                                  setState(() {
                                    _selectedDevice = device;
                                  });
                                },
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _refreshDevices,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Atualizar dispositivos',
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Status e botão conectar
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _isArduinoConnected 
                                ? Icons.check_circle 
                                : Icons.error,
                            color: _isArduinoConnected 
                                ? Colors.green 
                                : Colors.red,
                          ),
                          title: const Text('Status'),
                          subtitle: Text(
                            _isArduinoConnected 
                                ? 'Conectado' 
                                : 'Desconectado',
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isArduinoConnected 
                            ? _disconnectArduino 
                            : _connectArduino,
                        icon: Icon(
                          _isArduinoConnected 
                              ? Icons.link_off 
                              : Icons.usb,
                        ),
                        label: Text(
                          _isArduinoConnected 
                              ? 'DESCONECTAR' 
                              : 'CONECTAR',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isArduinoConnected 
                              ? Colors.red 
                              : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Instruções
          Card(
            elevation: 2,
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Como funciona',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '1. Conecte o Arduino ao celular via cabo USB-OTG\n'
                    '2. Selecione o baud rate correto (padrão: 9600)\n'
                    '3. Inicie o Gateway\n'
                    '4. Configure seu servidor Traccar para enviar comandos para o IP do celular na porta 5023\n'
                    '5. Os comandos serão automaticamente repassados ao Arduino via USB',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Aba de Monitoramento
  Widget _buildMonitorTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Status Cards
          Row(
            children: [
              Expanded(
                child: _buildStatusCard(
                  icon: Icons.router,
                  title: 'Servidor',
                  value: _isRunning ? 'ONLINE' : 'OFFLINE',
                  color: _isRunning ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusCard(
                  icon: Icons.memory,
                  title: 'Arduino',
                  value: _isArduinoConnected ? 'CONECTADO' : 'DESC.',
                  color: _isArduinoConnected ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Estatísticas
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Estatísticas',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: _clearStats,
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Zerar estatísticas',
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  _buildStatRow(
                    icon: Icons.download,
                    label: 'Comandos Recebidos (Traccar)',
                    value: '$_commandsReceived',
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow(
                    icon: Icons.forward,
                    label: 'Comandos Enviados (Arduino)',
                    value: '$_commandsForwarded',
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow(
                    icon: Icons.upload,
                    label: 'Respostas do Arduino',
                    value: '$_responsesReceived',
                    color: Colors.green,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Fluxo de dados
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fluxo de Dados',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Diagrama do fluxo
                  Row(
                    children: [
                      Expanded(
                        child: _buildFlowNode(
                          icon: Icons.cloud,
                          label: 'Servidor\nTraccar',
                          color: Colors.blue,
                        ),
                      ),
                      Icon(Icons.arrow_forward, color: Colors.grey[400]),
                      Expanded(
                        child: _buildFlowNode(
                          icon: Icons.phone_android,
                          label: 'Gateway\nApp',
                          color: _isRunning ? Colors.green : Colors.grey,
                        ),
                      ),
                      Icon(Icons.arrow_forward, color: Colors.grey[400]),
                      Expanded(
                        child: _buildFlowNode(
                          icon: Icons.memory,
                          label: 'Arduino\nUSB',
                          color: _isArduinoConnected ? Colors.orange : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Portas
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        _buildPortRow('Porta Traccar:', '5023 (GT06)'),
                        const SizedBox(height: 4),
                        _buildPortRow('Porta Serial:', 'USB-OTG @ $_selectedBaudRate bps'),
                      ],
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

  Widget _buildStatusCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFlowNode({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 32),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPortRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Aba de Logs
  Widget _buildLogsTab() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Logs do Gateway',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text('${_logs.length} linhas'),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _clearLogs,
                icon: const Icon(Icons.delete, size: 20),
                tooltip: 'Limpar logs',
              ),
            ],
          ),
        ),
        
        // Lista de logs
        Expanded(
          child: Container(
            color: Colors.black87,
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum log disponível\nInicie o gateway para ver os logs',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      Color logColor = Colors.white;
                      
                      if (log.contains('✓')) logColor = Colors.green;
                      else if (log.contains('✗')) logColor = Colors.red;
                      else if (log.contains('⚠')) logColor = Colors.orange;
                      else if (log.contains('→')) logColor = Colors.cyan;
                      else if (log.contains('←')) logColor = Colors.yellow;
                      else if (log.contains('===')) logColor = Colors.blue;
                      
                      return SelectableText(
                        log,
                        style: TextStyle(
                          color: logColor,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

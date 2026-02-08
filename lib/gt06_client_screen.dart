import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'gt06_client_service.dart';
import 'command_log_service.dart';
import 'preferences.dart';

/// ============================================================================
/// TELA DO CLIENTE GT06
/// ============================================================================
/// 
/// Interface para configurar e monitorar o cliente GT06 que se conecta
/// ao servidor Traccar via protocolo TCP GT06.
///
/// FUNCIONALIDADES:
/// - Configurar servidor, porta e IMEI
/// - Conectar/desconectar do servidor
/// - Visualizar status da conexão (Online/Offline)
/// - Monitorar heartbeat e posições enviadas
/// - Receber e visualizar comandos do servidor
/// - Logs em tempo real
/// ============================================================================

class GT06ClientScreen extends StatefulWidget {
  const GT06ClientScreen({super.key});

  @override
  State<GT06ClientScreen> createState() => _GT06ClientScreenState();
}

class _GT06ClientScreenState extends State<GT06ClientScreen> {
  final GT06ClientService _clientService = GT06ClientService();
  final ScrollController _logScrollController = ScrollController();
  final TextEditingController _serverController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _imeiController = TextEditingController();
  final TextEditingController _heartbeatController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  
  // Estado
  bool _isConnected = false;
  bool _isLoggedIn = false;
  String _statusText = 'Desconectado';
  Color _statusColor = Colors.grey;
  
  // Estatísticas
  int _heartbeatsSent = 0;
  int _locationsSent = 0;
  int _commandsReceived = 0;
  DateTime? _lastCommunication;
  
  // Logs
  final List<String> _logs = [];
  
  // Subscriptions
  StreamSubscription? _eventSubscription;
  StreamSubscription? _commandSubscription;
  StreamSubscription? _logSubscription;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initListeners();
    
    // Verifica estado inicial
    setState(() {
      _isConnected = _clientService.isConnected;
      _isLoggedIn = _clientService.isLoggedIn;
      _updateStatus();
    });
  }

  void _loadSettings() {
    // Carrega configurações salvas ou usa padrões
    final deviceId = Preferences.instance.getString(Preferences.id) ?? '';
    final defaultImei = deviceId.length >= 15 
        ? deviceId.substring(0, 15) 
        : deviceId.padLeft(15, '0');
    
    _serverController.text = Preferences.instance.getString('gt06_server') ?? '';
    _portController.text = Preferences.instance.getString('gt06_port') ?? '5023';
    _imeiController.text = Preferences.instance.getString('gt06_imei') ?? defaultImei;
    _heartbeatController.text = Preferences.instance.getString('gt06_heartbeat') ?? '30';
    _locationController.text = Preferences.instance.getString('gt06_location') ?? '60';
  }

  Future<void> _saveSettings() async {
    await Preferences.instance.setString('gt06_server', _serverController.text);
    await Preferences.instance.setString('gt06_port', _portController.text);
    await Preferences.instance.setString('gt06_imei', _imeiController.text);
    await Preferences.instance.setString('gt06_heartbeat', _heartbeatController.text);
    await Preferences.instance.setString('gt06_location', _locationController.text);
  }

  void _initListeners() {
    // Listener de eventos do cliente
    _eventSubscription = _clientService.eventStream.listen((event) {
      setState(() {
        _isConnected = _clientService.isConnected;
        _isLoggedIn = _clientService.isLoggedIn;
        _lastCommunication = _clientService.lastCommunication;
        _updateStatus();
        
        // Atualiza estatísticas baseado no tipo de evento
        switch (event.type) {
          case GT06ClientEventType.heartbeatAck:
            _heartbeatsSent++;
            break;
          case GT06ClientEventType.locationAck:
            _locationsSent++;
            break;
          case GT06ClientEventType.commandReceived:
            _commandsReceived++;
            break;
          default:
            break;
        }
      });
      
      _addLog(event.message);
    });

    // Listener de comandos
    _commandSubscription = _clientService.commandStream.listen((command) {
      _addLog('🎮 COMANDO: ${command.action} (${command.rawCommand})');
      
      // Mostra notificação do comando
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Comando recebido: ${command.action}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    // Listener de logs
    _logSubscription = _clientService.logStream.listen((log) {
      _addLog(log);
    });
  }

  void _updateStatus() {
    if (_isLoggedIn) {
      _statusText = 'ONLINE (Logado)';
      _statusColor = Colors.green;
    } else if (_isConnected) {
      _statusText = 'Conectando...';
      _statusColor = Colors.orange;
    } else {
      _statusText = 'OFFLINE';
      _statusColor = Colors.red;
    }
  }

  void _addLog(String log) {
    setState(() {
      _logs.add(log);
      if (_logs.length > 500) {
        _logs.removeAt(0);
      }
    });
    _scrollToBottom();
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

  Future<void> _connect() async {
    // Valida campos
    if (_serverController.text.isEmpty) {
      _showError('Informe o endereço do servidor');
      return;
    }
    
    if (_portController.text.isEmpty) {
      _showError('Informe a porta do servidor');
      return;
    }
    
    if (_imeiController.text.isEmpty || _imeiController.text.length != 15) {
      _showError('IMEI deve ter 15 dígitos');
      return;
    }

    // Salva configurações
    await _saveSettings();

    // Inicializa o cliente
    _clientService.initialize(
      serverAddress: _serverController.text,
      serverPort: int.tryParse(_portController.text) ?? 5023,
      imei: _imeiController.text,
      heartbeatInterval: int.tryParse(_heartbeatController.text) ?? 30,
      locationInterval: int.tryParse(_locationController.text) ?? 60,
    );

    // Conecta
    try {
      await _clientService.connect();
    } catch (e) {
      _showError('Erro ao conectar: $e');
    }
  }

  Future<void> _disconnect() async {
    await _clientService.disconnect();
    setState(() {
      _heartbeatsSent = 0;
      _locationsSent = 0;
      _commandsReceived = 0;
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  void _clearStats() {
    setState(() {
      _heartbeatsSent = 0;
      _locationsSent = 0;
      _commandsReceived = 0;
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _commandSubscription?.cancel();
    _logSubscription?.cancel();
    _logScrollController.dispose();
    _serverController.dispose();
    _portController.dispose();
    _imeiController.dispose();
    _heartbeatController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cliente GT06'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.settings), text: 'Configuração'),
              Tab(icon: Icon(Icons.analytics), text: 'Status'),
              Tab(icon: Icon(Icons.terminal), text: 'Logs'),
            ],
          ),
          actions: [
            // Indicador de status
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _statusColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: _statusColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusText,
                    style: TextStyle(
                      color: _statusColor,
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
            _buildStatusTab(),
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
          // Card de Conexão
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Servidor Traccar',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Endereço do servidor
                  TextField(
                    controller: _serverController,
                    enabled: !_isConnected,
                    decoration: InputDecoration(
                      labelText: 'Endereço do Servidor',
                      hintText: 'ex: traccar.seudominio.com',
                      prefixIcon: const Icon(Icons.dns),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Porta
                  TextField(
                    controller: _portController,
                    enabled: !_isConnected,
                    decoration: InputDecoration(
                      labelText: 'Porta TCP',
                      hintText: '5023',
                      prefixIcon: const Icon(Icons.settings_ethernet),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // IMEI
                  TextField(
                    controller: _imeiController,
                    enabled: !_isConnected,
                    maxLength: 15,
                    decoration: InputDecoration(
                      labelText: 'IMEI do Dispositivo',
                      hintText: '15 dígitos',
                      prefixIcon: const Icon(Icons.perm_device_info),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      counterText: '',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(15),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Botão conectar/desconectar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isConnected ? _disconnect : _connect,
                      icon: Icon(_isConnected ? Icons.stop : Icons.play_arrow),
                      label: Text(
                        _isConnected ? 'DESCONECTAR' : 'CONECTAR',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isConnected ? Colors.red : Colors.green,
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
          
          // Card de Intervalos
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Intervalos',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Heartbeat
                  TextField(
                    controller: _heartbeatController,
                    enabled: !_isConnected,
                    decoration: InputDecoration(
                      labelText: 'Heartbeat (segundos)',
                      hintText: '30',
                      helperText: 'Intervalo para manter conexão ativa',
                      prefixIcon: const Icon(Icons.favorite),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Location
                  TextField(
                    controller: _locationController,
                    enabled: !_isConnected,
                    decoration: InputDecoration(
                      labelText: 'Location (segundos)',
                      hintText: '60',
                      helperText: 'Intervalo para enviar posição GPS',
                      prefixIcon: const Icon(Icons.location_on),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.number,
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
                        'Como configurar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '1. Informe o endereço do seu servidor Traccar\n'
                    '2. Use a porta 5023 (protocolo GT06)\n'
                    '3. O IMEI deve ser único e ter 15 dígitos\n'
                    '4. No Traccar, cadastre o dispositivo com o mesmo IMEI\n'
                    '5. Clique em CONECTAR para iniciar',
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

  /// Aba de Status
  Widget _buildStatusTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Status principal
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Ícone de status
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _statusColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: _statusColor, width: 3),
                    ),
                    child: Icon(
                      _isLoggedIn ? Icons.check_circle : Icons.error,
                      size: 40,
                      color: _statusColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _statusColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLoggedIn 
                        ? 'Dispositivo online no Traccar' 
                        : 'Dispositivo offline',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (_lastCommunication != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Última comunicação: ${_formatTime(_lastCommunication!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
                    icon: Icons.favorite,
                    label: 'Heartbeats Enviados',
                    value: '$_heartbeatsSent',
                    color: Colors.red,
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow(
                    icon: Icons.location_on,
                    label: 'Posições Enviadas',
                    value: '$_locationsSent',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow(
                    icon: Icons.gamepad,
                    label: 'Comandos Recebidos',
                    value: '$_commandsReceived',
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Informações do dispositivo
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Informações',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  _buildInfoRow('Servidor:', '${_serverController.text}:${_portController.text}'),
                  _buildInfoRow('IMEI:', _imeiController.text),
                  _buildInfoRow('Heartbeat:', '${_heartbeatController.text}s'),
                  _buildInfoRow('Location:', '${_locationController.text}s'),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Diagrama do fluxo
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fluxo de Comunicação',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildFlowNode(
                          icon: Icons.phone_android,
                          label: 'App\nCliente',
                          color: _isConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                      Icon(Icons.arrow_forward, color: Colors.grey[400]),
                      Expanded(
                        child: _buildFlowNode(
                          icon: Icons.router,
                          label: 'Internet\nTCP',
                          color: _isConnected ? Colors.blue : Colors.grey,
                        ),
                      ),
                      Icon(Icons.arrow_forward, color: Colors.grey[400]),
                      Expanded(
                        child: _buildFlowNode(
                          icon: Icons.cloud,
                          label: 'Servidor\nTraccar',
                          color: _isLoggedIn ? Colors.green : Colors.grey,
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:''${time.minute.toString().padLeft(2, '0')}:''${time.second.toString().padLeft(2, '0')}';
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
                  'Logs do Cliente GT06',
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
                      'Nenhum log disponível\nConecte ao servidor para ver os logs',
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
                      
                      if (log.contains('✓') || log.contains('ONLINE')) {
                        logColor = Colors.green;
                      } else if (log.contains('✗') || log.contains('ERRO')) {
                        logColor = Colors.red;
                      } else if (log.contains('⚠')) {
                        logColor = Colors.orange;
                      } else if (log.contains('→') || log.contains('→')) {
                        logColor = Colors.cyan;
                      } else if (log.contains('♥')) {
                        logColor = Colors.pink;
                      } else if (log.contains('📍')) {
                        logColor = Colors.yellow;
                      } else if (log.contains('📟') || log.contains('🎮')) {
                        logColor = Colors.purple;
                      } else if (log.contains('===')) {
                        logColor = Colors.blue;
                      }
                      
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

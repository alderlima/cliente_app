import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'arduino_tcp_service.dart';

/// Tela de controle do Arduino via TCP
/// Similar ao aplicativo Android TCPUART
/// Permite conectar, enviar comandos e visualizar respostas

class ArduinoScreen extends StatefulWidget {
  const ArduinoScreen({super.key});

  @override
  State<ArduinoScreen> createState() => _ArduinoScreenState();
}

class _ArduinoScreenState extends State<ArduinoScreen> {
  final ArduinoTCPService _arduinoService = ArduinoTCPService();
  final TextEditingController _hostController = TextEditingController(text: '192.168.1.100');
  final TextEditingController _portController = TextEditingController(text: '80');
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _hexController = TextEditingController();
  final ScrollController _receivedScrollController = ScrollController();
  final ScrollController _logScrollController = ScrollController();

  bool _isConnected = false;
  bool _isConnecting = false;
  String _connectionStatus = 'Desconectado';
  Color _statusColor = Colors.grey;
  
  final List<String> _receivedData = [];
  final List<String> _logs = [];
  
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _logSubscription;

  // Modo de entrada
  bool _isHexMode = false;
  bool _addNewline = true;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    // Stream de conexão
    _connectionSubscription = _arduinoService.connectionStream.listen((state) {
      setState(() {
        _isConnected = state.isConnected;
        _isConnecting = state.status == ConnectionStatus.connecting;
        _connectionStatus = state.message;
        
        switch (state.status) {
          case ConnectionStatus.connected:
            _statusColor = Colors.green;
            break;
          case ConnectionStatus.connecting:
            _statusColor = Colors.orange;
            break;
          case ConnectionStatus.disconnected:
            _statusColor = Colors.grey;
            break;
          case ConnectionStatus.error:
          case ConnectionStatus.timeout:
            _statusColor = Colors.red;
            break;
        }
      });
    });

    // Stream de dados recebidos
    _dataSubscription = _arduinoService.dataStream.listen((event) {
      setState(() {
        _receivedData.add(event.text);
        if (_receivedData.length > 100) {
          _receivedData.removeAt(0);
        }
      });
      _scrollToBottom(_receivedScrollController);
    });

    // Stream de logs
    _logSubscription = _arduinoService.logStream.listen((log) {
      setState(() {
        _logs.add(log);
        if (_logs.length > 200) {
          _logs.removeAt(0);
        }
      });
      _scrollToBottom(_logScrollController);
    });
  }

  void _scrollToBottom(ScrollController controller) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (controller.hasClients) {
        controller.animateTo(
          controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 80;

    if (host.isEmpty) {
      _showSnackBar('Digite o endereço IP do Arduino');
      return;
    }

    setState(() => _isConnecting = true);
    
    final success = await _arduinoService.connect(host, port);
    
    if (!success && mounted) {
      _showSnackBar('Falha ao conectar. Verifique o IP e porta.');
    }
  }

  Future<void> _disconnect() async {
    await _arduinoService.disconnect();
  }

  Future<void> _sendCommand() async {
    if (!_isConnected) {
      _showSnackBar('Conecte-se primeiro ao Arduino');
      return;
    }

    final command = _commandController.text.trim();
    if (command.isEmpty) return;

    bool success;
    if (_isHexMode) {
      success = await _arduinoService.sendHex(command);
    } else {
      success = await _arduinoService.sendText(command, addNewline: _addNewline);
    }

    if (success) {
      _commandController.clear();
    } else {
      _showSnackBar('Erro ao enviar comando');
    }
  }

  Future<void> _sendPredefinedCommand(String command) async {
    if (!_isConnected) {
      _showSnackBar('Conecte-se primeiro ao Arduino');
      return;
    }

    await _arduinoService.sendText(command, addNewline: _addNewline);
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  void _clearReceived() {
    setState(() => _receivedData.clear());
    _arduinoService.clearBuffer();
  }

  void _clearLogs() {
    setState(() => _logs.clear());
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    _logSubscription?.cancel();
    _hostController.dispose();
    _portController.dispose();
    _commandController.dispose();
    _hexController.dispose();
    _receivedScrollController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Controle Arduino (TCPUART)'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.settings_ethernet), text: 'Conexão'),
              Tab(icon: Icon(Icons.terminal), text: 'Terminal'),
              Tab(icon: Icon(Icons.receipt_long), text: 'Logs'),
            ],
          ),
          actions: [
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
                  Icon(Icons.circle, color: _statusColor, size: 10),
                  const SizedBox(width: 6),
                  Text(
                    _isConnected ? 'CONECTADO' : 'DESCONECTADO',
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
            _buildConnectionTab(),
            _buildTerminalTab(),
            _buildLogsTab(),
          ],
        ),
      ),
    );
  }

  /// Aba de conexão
  Widget _buildConnectionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card de configuração
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configuração TCP',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Host/IP
                  TextField(
                    controller: _hostController,
                    decoration: InputDecoration(
                      labelText: 'Endereço IP do Arduino',
                      hintText: '192.168.1.100',
                      prefixIcon: const Icon(Icons.computer),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !_isConnected,
                  ),
                  const SizedBox(height: 12),
                  
                  // Porta
                  TextField(
                    controller: _portController,
                    decoration: InputDecoration(
                      labelText: 'Porta',
                      hintText: '80',
                      prefixIcon: const Icon(Icons.settings_input_hdmi),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !_isConnected,
                  ),
                  const SizedBox(height: 20),
                  
                  // Botões de conexão
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isConnecting 
                          ? null 
                          : (_isConnected ? _disconnect : _connect),
                      icon: _isConnecting 
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_isConnected ? Icons.link_off : Icons.connect_without_contact),
                      label: Text(
                        _isConnecting 
                            ? 'CONECTANDO...' 
                            : (_isConnected ? 'DESCONECTAR' : 'CONECTAR'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isConnected ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Status da conexão
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatusRow('Conexão:', _connectionStatus),
                  _buildStatusRow('Endereço:', _arduinoService.host.isEmpty ? '-' : _arduinoService.host),
                  _buildStatusRow('Porta:', _arduinoService.port.toString()),
                  _buildStatusRow('Modo:', _isHexMode ? 'HEX' : 'ASCII'),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Comandos rápidos
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comandos Rápidos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ArduinoTCPService.predefinedCommands.entries.map((entry) {
                      return ActionChip(
                        avatar: const Icon(Icons.send, size: 16),
                        label: Text(entry.key),
                        onPressed: _isConnected ? () => _sendPredefinedCommand(entry.value) : null,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Aba do terminal
  Widget _buildTerminalTab() {
    return Column(
      children: [
        // Área de dados recebidos
        Expanded(
          flex: 3,
          child: Card(
            margin: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.download, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Dados Recebidos',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: _receivedData.isEmpty 
                            ? null 
                            : () => _copyToClipboard(_receivedData.join('\n')),
                        tooltip: 'Copiar tudo',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: _receivedData.isEmpty ? null : _clearReceived,
                        tooltip: 'Limpar',
                      ),
                    ],
                  ),
                ),
                // Conteúdo
                Expanded(
                  child: Container(
                    color: Colors.black87,
                    child: _receivedData.isEmpty
                        ? const Center(
                            child: Text(
                              'Aguardando dados...',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            controller: _receivedScrollController,
                            padding: const EdgeInsets.all(8),
                            itemCount: _receivedData.length,
                            itemBuilder: (context, index) {
                              return SelectableText(
                                _receivedData[index],
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Área de envio
        Expanded(
          flex: 2,
          child: Card(
            margin: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header com opções
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.upload, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Enviar Comando',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      // Toggle HEX/ASCII
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('ASCII'),
                          Switch(
                            value: _isHexMode,
                            onChanged: (value) => setState(() => _isHexMode = value),
                          ),
                          const Text('HEX'),
                        ],
                      ),
                      const SizedBox(width: 8),
                      // Checkbox newline
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _addNewline,
                            onChanged: (value) => setState(() => _addNewline = value ?? true),
                          ),
                          const Text('+\r\n'),
                        ],
                      ),
                    ],
                  ),
                ),
                // Input
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commandController,
                            decoration: InputDecoration(
                              hintText: _isHexMode 
                                  ? 'Digite em HEX (ex: 48 65 6C 6C 6F)' 
                                  : 'Digite o comando...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: Icon(_isHexMode ? Icons.code : Icons.text_fields),
                            ),
                            enabled: _isConnected,
                            onSubmitted: (_) => _sendCommand(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _isConnected ? _sendCommand : null,
                          icon: const Icon(Icons.send),
                          label: const Text('ENVIAR'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Aba de logs
  Widget _buildLogsTab() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[200],
          ),
          child: Row(
            children: [
              const Icon(Icons.receipt_long, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Logs de Comunicação',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text('${_logs.length} entradas'),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                onPressed: _logs.isEmpty ? null : () => _copyToClipboard(_logs.join('\n')),
                tooltip: 'Copiar logs',
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                onPressed: _logs.isEmpty ? null : _clearLogs,
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
                      'Nenhum log disponível',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      Color logColor = Colors.white;
                      
                      if (log.contains('→')) logColor = Colors.green;
                      else if (log.contains('←')) logColor = Colors.cyan;
                      else if (log.contains('✓')) logColor = Colors.lightGreen;
                      else if (log.contains('✗')) logColor = Colors.red;
                      else if (log.contains('Conectado')) logColor = Colors.yellow;
                      
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

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('Copiado para a área de transferência');
  }
}

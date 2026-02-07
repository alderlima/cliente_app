import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'command_log_service.dart';
import 'gt06_server_service.dart';

/// Tela de logs de comandos com suporte a tempo real
/// Exibe comandos recebidos do servidor GT06 na porta 5023

class CommandLogScreen extends StatefulWidget {
  const CommandLogScreen({super.key});

  @override
  State<CommandLogScreen> createState() => _CommandLogScreenState();
}

class _CommandLogScreenState extends State<CommandLogScreen> {
  final GT06ServerService _serverService = GT06ServerService();
  final ScrollController _scrollController = ScrollController();
  
  bool _isServerRunning = false;
  int _connectedClients = 0;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _commandSubscription;

  @override
  void initState() {
    super.initState();
    _initServer();
  }

  void _initServer() {
    // Inicia o servidor automaticamente se não estiver rodando
    if (!_serverService.isRunning) {
      _startServer();
    } else {
      setState(() {
        _isServerRunning = _serverService.isRunning;
        _connectedClients = _serverService.connectedClientsCount;
      });
    }

    // Escuta eventos de conexão
    _connectionSubscription = _serverService.connectionStream.listen((event) {
      setState(() {
        _isServerRunning = _serverService.isRunning;
        _connectedClients = _serverService.connectedClientsCount;
      });
    });

    // Escuta comandos recebidos
    _commandSubscription = _serverService.commandStream.listen((event) {
      // Scroll automático para o topo quando receber novo comando
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startServer() async {
    try {
      await _serverService.start(port: 5023);
      setState(() {
        _isServerRunning = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao iniciar servidor: $e')),
        );
      }
    }
  }

  Future<void> _stopServer() async {
    await _serverService.stop();
    setState(() {
      _isServerRunning = false;
      _connectedClients = 0;
    });
  }

  Future<void> _restartServer() async {
    await _serverService.restart(port: 5023);
    setState(() {
      _isServerRunning = _serverService.isRunning;
      _connectedClients = _serverService.connectedClientsCount;
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _commandSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs de Comandos em Tempo Real'),
        actions: [
          // Indicador do servidor
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isServerRunning ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isServerRunning ? Colors.green : Colors.red,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: _isServerRunning ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 6),
                Text(
                  _isServerRunning ? 'GT06 ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    color: _isServerRunning ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Menu de opções
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'start':
                  _startServer();
                  break;
                case 'stop':
                  _stopServer();
                  break;
                case 'restart':
                  _restartServer();
                  break;
                case 'clear':
                  _showClearDialog(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              if (!_isServerRunning)
                const PopupMenuItem(
                  value: 'start',
                  child: Row(
                    children: [
                      Icon(Icons.play_arrow, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Iniciar Servidor'),
                    ],
                  ),
                ),
              if (_isServerRunning)
                const PopupMenuItem(
                  value: 'stop',
                  child: Row(
                    children: [
                      Icon(Icons.stop, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Parar Servidor'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'restart',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Reiniciar Servidor'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Limpar Logs'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Painel de status do servidor
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatusCard(
                        icon: Icons.router,
                        title: 'Servidor GT06',
                        value: _isServerRunning ? 'ONLINE' : 'OFFLINE',
                        color: _isServerRunning ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatusCard(
                        icon: Icons.settings_ethernet,
                        title: 'Porta',
                        value: '5023',
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatusCard(
                        icon: Icons.devices,
                        title: 'Clientes',
                        value: '$_connectedClients',
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Botões de controle rápido
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isServerRunning ? _stopServer : _startServer,
                        icon: Icon(_isServerRunning ? Icons.stop : Icons.play_arrow),
                        label: Text(_isServerRunning ? 'PARAR' : 'INICIAR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isServerRunning ? Colors.red : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _restartServer,
                        icon: const Icon(Icons.refresh),
                        label: const Text('REINICIAR'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Lista de logs
          Expanded(
            child: StreamBuilder<List<CommandLog>>(
              stream: CommandLogService.logsStream,
              initialData: CommandLogService.currentLogs,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erro ao carregar logs: ${snapshot.error}'));
                }

                final logs = snapshot.data ?? [];
                
                if (logs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isServerRunning ? Icons.rss_feed : Icons.router_outlined,
                          size: 64,
                          color: _isServerRunning ? Colors.green.withOpacity(0.5) : Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isServerRunning 
                              ? 'Aguardando comandos na porta 5023...' 
                              : 'Servidor offline. Inicie para receber comandos.',
                          style: TextStyle(
                            color: _isServerRunning ? Colors.green : Colors.grey,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        if (_isServerRunning)
                          Text(
                            'Protocolo: GT06 | Aguardando conexões...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  controller: _scrollController,
                  itemCount: logs.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return _buildLogItem(log);
                  },
                );
              },
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(CommandLog log) {
    final timeStr = DateFormat('dd/MM HH:mm:ss').format(log.timestamp);
    
    // Determina o tipo de log e o ícone/cor apropriado
    Color iconColor = Colors.blue;
    IconData iconData = Icons.terminal;
    Color bgColor = Colors.white;
    
    final command = log.command.toUpperCase();
    
    if (command.contains('AÇÃO:')) {
      iconData = log.command.contains('BLOQUEADO') ? Icons.block : Icons.play_arrow;
      iconColor = log.command.contains('BLOQUEADO') ? Colors.red : Colors.green;
      bgColor = iconColor.withOpacity(0.05);
    } else if (command.contains('PACOTE GT06')) {
      iconData = Icons.gps_fixed;
      iconColor = Colors.purple;
      bgColor = iconColor.withOpacity(0.05);
    } else if (command.contains('SERVIDOR')) {
      iconData = Icons.router;
      iconColor = Colors.orange;
      bgColor = iconColor.withOpacity(0.05);
    } else if (command.contains('CONEXÃO') || command.contains('CLIENTE')) {
      iconData = Icons.devices;
      iconColor = Colors.teal;
      bgColor = iconColor.withOpacity(0.05);
    } else if (command.contains('ARDUINO')) {
      iconData = Icons.memory;
      iconColor = Colors.indigo;
      bgColor = iconColor.withOpacity(0.05);
    } else if (command.contains('ERRO')) {
      iconData = Icons.error;
      iconColor = Colors.red;
      bgColor = iconColor.withOpacity(0.1);
    }

    return Container(
      color: bgColor,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(iconData, color: iconColor, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                log.command,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                  fontSize: 14,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                timeStr,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
        subtitle: log.data != null && log.data!.isNotEmpty
            ? _buildDataPreview(log.data!)
            : null,
        onTap: log.data != null ? () => _showLogDetails(log) : null,
        trailing: log.data != null 
            ? const Icon(Icons.chevron_right, size: 20, color: Colors.grey)
            : null,
      ),
    );
  }

  Widget _buildDataPreview(Map<String, dynamic> data) {
    // Mostra preview resumido dos dados
    final previewData = <String, dynamic>{};
    
    // Filtra campos importantes
    if (data.containsKey('comando')) previewData['Comando'] = data['comando'];
    if (data.containsKey('acao')) previewData['Ação'] = data['acao'];
    if (data.containsKey('cliente')) previewData['Cliente'] = data['cliente'];
    if (data.containsKey('tipo')) previewData['Tipo'] = data['tipo'];
    if (data.containsKey('status')) previewData['Status'] = data['status'];
    if (data.containsKey('porta')) previewData['Porta'] = data['porta'];
    
    if (previewData.isEmpty && data.isNotEmpty) {
      // Pega o primeiro item se não encontrou campos específicos
      final firstKey = data.keys.first;
      previewData[firstKey] = data[firstKey];
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: previewData.entries.map((entry) {
          return Text(
            '${entry.key}: ${entry.value}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
              fontFamily: 'monospace',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }).toList(),
      ),
    );
  }

  void _showLogDetails(CommandLog log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Detalhes do Log',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        final text = '${log.command}\n${DateFormat('dd/MM/yyyy HH:mm:ss').format(log.timestamp)}\n\n${log.data?.toString() ?? ''}';
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copiado para a área de transferência')),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                
                // Informações básicas
                _buildDetailRow('Comando:', log.command),
                _buildDetailRow('Data/Hora:', DateFormat('dd/MM/yyyy HH:mm:ss').format(log.timestamp)),
                
                const SizedBox(height: 16),
                
                // Dados completos
                if (log.data != null) ...[
                  Text(
                    'Dados:',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: SelectableText(
                          _formatData(log.data!),
                          style: const TextStyle(
                            color: Colors.green,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
            child: SelectableText(
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

  String _formatData(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    data.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    return buffer.toString();
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar Logs'),
        content: const Text('Deseja remover todos os logs de comandos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              CommandLogService.clearLogs();
              Navigator.pop(context);
            },
            child: const Text('Limpar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

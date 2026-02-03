import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'command_log_service.dart';

class CommandLogScreen extends StatelessWidget {
  const CommandLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs de Comandos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _showClearDialog(context),
            tooltip: 'Limpar Logs',
          ),
        ],
      ),
      body: StreamBuilder<List<CommandLog>>(
        stream: CommandLogService.logsStream,
        initialData: CommandLogService.currentLogs,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar logs: ${snapshot.error}'));
          }

          final logs = snapshot.data ?? [];
          
          if (logs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.terminal, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Aguardando comandos em tempo real...', 
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: logs.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final log = logs[index];
              final timeStr = DateFormat('dd/MM HH:mm:ss').format(log.timestamp);
              
              Color iconColor = Colors.green;
              IconData iconData = Icons.terminal;
              bool isAction = log.command.startsWith('AÇÃO:');
              bool isBlocked = log.command.contains('BLOQUEADO');
              
              if (isAction) {
                iconData = isBlocked ? Icons.block : Icons.play_arrow;
                iconColor = isBlocked ? Colors.red : Colors.blue;
              }

              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(iconData, color: iconColor),
                ),
                title: Text(
                  log.command,
                  style: TextStyle(
                    fontWeight: isAction ? FontWeight.bold : FontWeight.w600,
                    color: isAction ? iconColor : Colors.black87,
                    fontFamily: 'monospace',
                    fontSize: 15,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(timeStr, style: const TextStyle(fontSize: 12)),
                    if (log.data != null && log.data!.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log.data.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[800],
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
                isThreeLine: log.data != null && log.data!.isNotEmpty,
              );
            },
          );
        },
      ),
    );
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

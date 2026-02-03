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
          final logs = snapshot.data ?? [];
          
          if (logs.isEmpty) {
            return const Center(
              child: Text('Nenhum comando recebido ainda.'),
            );
          }

          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final log = logs[index];
              final timeStr = DateFormat('dd/MM HH:mm:ss').format(log.timestamp);
              
              // Custom styling based on command content
              Color iconColor = Colors.green;
              IconData iconData = Icons.terminal;
              bool isAction = log.command.startsWith('AÇÃO:');
              bool isBlocked = log.command.contains('BLOQUEADO');
              
              if (isAction) {
                iconData = isBlocked ? Icons.block : Icons.play_arrow;
                iconColor = isBlocked ? Colors.red : Colors.blue;
              }

              return ListTile(
                leading: Icon(iconData, color: iconColor),
                title: Text(
                  log.command,
                  style: TextStyle(
                    fontWeight: isAction ? FontWeight.bold : FontWeight.normal,
                    color: isAction ? iconColor : null,
                    fontFamily: 'monospace'
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(timeStr),
                    if (log.data != null && log.data!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          log.data.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
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

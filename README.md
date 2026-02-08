# Rastreador GT06 - Simulador de Rastreador Real

Aplicativo Flutter que transforma seu celular em um **rastreador GT06 real**, conectando-se ao servidor Traccar e enviando a localização GPS do dispositivo em tempo real.

## ✨ Funcionalidades

### 🎯 Principal
- ✅ **Simula um rastreador GT06 real** no servidor Traccar
- ✅ **Gera IMEI aleatório** ao abrir (pode ser alterado)
- ✅ **Envia localização GPS** do celular em tempo real
- ✅ **Recebe comandos** do servidor Traccar
- ✅ **Conexão persistente** TCP com heartbeat
- ✅ **Reconexão automática** em caso de queda

### 📡 Protocolo GT06 Implementado
- ✅ **Login Packet (0x01)** - Autenticação com IMEI
- ✅ **Heartbeat (0x13)** - Keep-alive a cada 30s
- ✅ **Location Packet (0x12)** - Envio de coordenadas GPS
- ✅ **Alarm Packet (0x16)** - Alarmes SOS, excesso de velocidade, etc.
- ✅ **Command Response (0x21)** - Resposta a comandos do servidor

### 🔌 Integração Arduino
- ✅ **Comunicação USB-OTG** com Arduino
- ✅ **Passa comandos** do Traccar para o Arduino
- ✅ **Lista dispositivos USB** disponíveis
- ✅ **Auto-conexão** ao Arduino

### 📱 Interface
- ✅ **Dashboard** com status em tempo real
- ✅ **Configuração** de servidor, porta e IMEI
- ✅ **Logs detalhados** de comunicação
- ✅ **Estatísticas** de pacotes enviados/recebidos

## 🚀 Como Usar

### 1. Instalação

```bash
# Clone ou baixe o projeto
cd rastreador_gt06

# Instale as dependências
flutter pub get

# Execute no dispositivo
flutter run
```

### 2. Configuração

1. **Abra o aplicativo**
2. **Anote o IMEI gerado** (ou gere um novo)
3. **Vá em Configuração** e informe:
   - **Servidor**: IP ou domínio do seu Traccar
   - **Porta**: `5023` (protocolo GT06)
   - **IMEI**: 15 dígitos (use o gerado ou um específico)
4. **Salve as configurações**

### 3. Configurar no Traccar

1. Acesse seu painel Traccar
2. Cadastre um novo dispositivo:
   - **Identificador Único**: O mesmo IMEI do app
   - **Modelo**: Selecione "GT06" ou "Concox"
3. Salve e aguarde o dispositivo ficar **ONLINE**

### 4. Conectar

1. Volte à tela principal
2. Toque em **CONECTAR**
3. O status mudará para **ONLINE**
4. Sua posição GPS será enviada automaticamente

### 5. Conectar Arduino (Opcional)

1. Conecte o Arduino ao celular via cabo OTG
2. Vá em **Arduino** no menu inferior
3. Toque em **Auto Conectar** ou selecione o dispositivo
4. Comandos do Traccar serão passados automaticamente

## 📋 Estrutura do Projeto

```
lib/
├── main.dart                    # Ponto de entrada
├── models/
│   └── tracker_state.dart       # Modelos de dados
├── screens/
│   ├── main_screen.dart         # Tela principal (dashboard)
│   ├── config_screen.dart       # Configuração
│   ├── logs_screen.dart         # Logs de comunicação
│   └── arduino_screen.dart      # Controle do Arduino
├── services/
│   ├── gt06_protocol.dart       # Protocolo GT06
│   ├── gt06_client.dart         # Cliente TCP
│   ├── gps_service.dart         # Serviço de GPS
│   ├── arduino_service.dart     # Comunicação USB
│   └── tracker_provider.dart    # Gerenciamento de estado
└── pubspec.yaml
```

## 🔧 Configurações

### Servidor Traccar
- **Endereço**: IP ou domínio do servidor
- **Porta**: 5023 (padrão GT06)

### Intervalos
- **Heartbeat**: 30 segundos (mantém conexão ativa)
- **Envio de Posição**: 10 segundos (envia coordenadas GPS)

### IMEI
- Gerado automaticamente na primeira abertura
- Pode ser alterado manualmente
- Deve ter exatamente 15 dígitos
- Deve ser único no servidor Traccar

## 📡 Protocolo GT06

### Pacotes Enviados

#### Login (0x01)
```
[78 78] [0B] [01] [IMEI BCD 8bytes] [Serial 2bytes] [Checksum] [0D 0A]
```

#### Heartbeat (0x13)
```
[78 78] [08] [13] [TerminalInfo] [Voltage] [GSM] [AlarmLang 2bytes] [Serial] [Checksum] [0D 0A]
```

#### Location (0x12)
```
[78 78] [15] [12] [DateTime 6bytes] [Satellites] [Lat 4bytes] [Lon 4bytes] [Speed] [Course 2bytes] [Serial] [Checksum] [0D 0A]
```

### Pacotes Recebidos

#### Command (0x80)
Comandos enviados pelo servidor Traccar:
- `STOP` / `CUT` - Bloquear veículo
- `RESUME` / `RESTORE` - Desbloquear veículo
- `WHERE` / `LOCATE` - Solicitar posição
- `RESET` / `REBOOT` - Reiniciar
- `STATUS` - Solicitar status

## 🔌 Comunicação Arduino

### Comandos Enviados ao Arduino
```
CMD:BLOQUEAR
CMD:DESBLOQUEAR
CMD:POSICAO
CMD:STATUS
CMD:REINICIAR
```

### Baud Rates Suportados
- 9600 (padrão)
- 19200
- 38400
- 57600
- 115200

## 📱 Permissões Necessárias

O aplicativo requer as seguintes permissões:
- **Localização** - Para obter coordenadas GPS
- **USB** - Para comunicação com Arduino
- **Internet** - Para conexão TCP com servidor

## 🛠️ Dependências

```yaml
dependencies:
  flutter:
    sdk: flutter
  geolocator: ^10.1.0      # GPS
  usb_serial: ^0.5.1       # USB Serial
  provider: ^6.1.1         # Estado
  shared_preferences: ^2.2.2 # Persistência
  intl: ^0.19.0            # Formatação
```

## 🐛 Debug

### Logs do Aplicativo
Acesse a tela **Logs** para ver:
- Pacotes enviados (SENT)
- Pacotes recebidos (RECV)
- Comandos do servidor (CMD)
- Posições GPS (GPS)
- Mensagens do Arduino (ARDUINO)
- Erros (ERROR)

### Cores dos Logs
- 🟢 Verde - Sucesso / Enviado
- 🔴 Vermelho - Erro
- 🟠 Laranja - Aviso
- 🔵 Azul - Recebido
- 🟣 Roxo - Comando
- 🩵 Ciano - GPS
- 🟡 Amarelo - Arduino

## 📊 Fluxo de Comunicação

```
┌─────────────┐      TCP       ┌─────────────┐      USB       ┌─────────────┐
│  Celular    │ ◄────────────► │   Traccar   │                │             │
│  (GT06)     │   Porta 5023   │   Server    │                │             │
│             │                │             │                │             │
│ 1. Login    │ ─────────────► │ 2. Valida   │                │             │
│             │ ◄───────────── │ 3. ACK      │                │             │
│ 4. Heartbeat│ ─────────────► │ 5. ACK      │                │             │
│ 6. Location │ ─────────────► │ 7. ACK      │                │             │
│             │ ◄───────────── │ 8. Command  │ ─────────────► │  9. Arduino │
│ 10. CMD ACK │ ─────────────► │             │                │             │
└─────────────┘                └─────────────┘                └─────────────┘
```

## 📝 Notas

- O aplicativo mantém a conexão TCP aberta continuamente
- Heartbeat é enviado automaticamente para manter online
- GPS é atualizado em tempo real
- Reconexão automática em caso de queda de conexão
- Comandos do Traccar são passados imediatamente para o Arduino

## 🤝 Compatibilidade

### Servidores Traccar
- ✅ Traccar 4.x
- ✅ Traccar 5.x
- ✅ Traccar Cloud

### Protocolos
- ✅ GT06 (Concox)
- ✅ GT06N
- ✅ TK100/TK110

### Android
- ✅ Android 6.0+ (API 23+)
- ✅ USB-OTG necessário para Arduino

## 📄 Licença

MIT License - Livre para uso e modificação.

---

**Desenvolvido para simular rastreadores GT06 reais no Traccar**

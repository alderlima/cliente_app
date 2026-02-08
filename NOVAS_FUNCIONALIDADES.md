# Novas Funcionalidades - Cliente Traccar Mod (Gateway Edition)

Este documento descreve as novas funcionalidades do aplicativo Cliente Traccar Mod com Gateway Traccar-Arduino.

---

## 🔄 Gateway Traccar-Arduino

### Visão Geral
O aplicativo agora funciona como um **GATEWAY** entre o servidor Traccar e o Arduino Uno:

```
Servidor Traccar → Comando GT06 (Porta 5023) → App Android 
                                                        ↓
                                           Repassa via USB/OTG
                                                        ↓
                                                  Arduino Uno
```

### Funcionalidades

#### 1. Servidor GT06 (Porta 5023)
- ✅ Servidor TCP escutando na porta **5023**
- ✅ Protocolo **GT06** completo implementado
- ✅ Recebe comandos do servidor Traccar como se fosse um rastreador real
- ✅ Exibe comandos em **tempo real** na tela de logs

#### 2. Comunicação Serial com Arduino
- ✅ Conexão via **USB/OTG** (cabo USB OTG)
- ✅ **Baud rate configurável**: 9600, 19200, 38400, 57600, 115200, etc.
- ✅ Detecção automática de dispositivos Arduino
- ✅ Suporte a múltiplos conversores USB-Serial (CH340, FTDI, CP210x, etc.)

#### 3. Bridge Automático
- ✅ Comandos do Traccar são **automaticamente repassados** ao Arduino
- ✅ Mapeamento de comandos Traccar → Arduino
- ✅ Estatísticas de comandos recebidos/enviados
- ✅ Logs detalhados de toda a comunicação

---

## 📋 Comandos Suportados

### Comandos Traccar → Arduino

| Comando Traccar | Comando Arduino | Descrição |
|-----------------|-----------------|-----------|
| `STOP` / `BLOQUEAR` | `CMD_BLOQUEAR` | Bloqueia o veículo |
| `RESUME` / `DESBLOQUEAR` | `CMD_DESBLOQUEAR` | Desbloqueia o veículo |
| `WHERE` / `LOCALIZACAO` | `CMD_LOCALIZAR` | Solicita localização |
| `RESET` / `REINICIAR` | `CMD_REINICIAR` | Reinicia o sistema |
| `STATUS` | `CMD_STATUS` | Solicita status |
| `CORTE_COMBUSTIVEL` | `CMD_CORTE_COMBUSTIVEL` | Corta combustível |
| `RESTAURAR_COMBUSTIVEL` | `CMD_RESTAURAR_COMBUSTIVEL` | Restaura combustível |

---

## 📱 Telas do Aplicativo

### 1. Tela Principal
- Botão **"LOGS DE COMANDOS EM TEMPO REAL"** - Acessa logs do servidor
- Botão **"GATEWAY TRACCAR-ARDUINO"** - Acessa configuração do gateway

### 2. Gateway Traccar-Arduino (3 abas)

#### Aba Configuração
- Configuração do servidor (porta 5023)
- Seleção de baud rate
- Lista de dispositivos USB disponíveis
- Botões Conectar/Desconectar Arduino
- Instruções de uso

#### Aba Monitor
- Status do servidor (Online/Offline)
- Status do Arduino (Conectado/Desconectado)
- Estatísticas:
  - Comandos recebidos do Traccar
  - Comandos enviados ao Arduino
  - Respostas do Arduino
- Diagrama visual do fluxo de dados

#### Aba Logs
- Logs em tempo real do gateway
- Cores diferentes para cada tipo de evento
- Botão para limpar logs

### 3. Logs de Comandos em Tempo Real
- Painel de status do servidor GT06
- Lista de comandos recebidos
- Detalhes de cada comando (hex, ascii, timestamp)
- Controles para iniciar/parar/reiniciar servidor

---

## 🔧 Configuração do Arduino

### Hardware Necessário
- Arduino Uno (ou compatível)
- Cabo USB OTG para Android
- Cabo USB para Arduino

### Código Arduino Exemplo

```cpp
// Código básico para receber comandos do Gateway

String inputString = "";
boolean stringComplete = false;

void setup() {
  Serial.begin(9600);
  pinMode(LED_BUILTIN, OUTPUT);
  pinMode(13, OUTPUT); // Pino de bloqueio
  
  Serial.println("Arduino Gateway Ready");
}

void loop() {
  if (stringComplete) {
    processCommand(inputString);
    inputString = "";
    stringComplete = false;
  }
}

void serialEvent() {
  while (Serial.available()) {
    char inChar = (char)Serial.read();
    if (inChar == '\n') {
      stringComplete = true;
    } else {
      inputString += inChar;
    }
  }
}

void processCommand(String cmd) {
  cmd.trim();
  cmd.toUpperCase();
  
  if (cmd == "CMD_BLOQUEAR" || cmd == "CMD_PARAR") {
    digitalWrite(13, HIGH); // Ativa bloqueio
    Serial.println("OK: VEICULO BLOQUEADO");
  }
  else if (cmd == "CMD_DESBLOQUEAR" || cmd == "CMD_CONTINUAR") {
    digitalWrite(13, LOW); // Desativa bloqueio
    Serial.println("OK: VEICULO DESBLOQUEADO");
  }
  else if (cmd == "CMD_REINICIAR") {
    Serial.println("OK: REINICIANDO...");
    delay(1000);
    // Reinicia o Arduino
    asm volatile ("  jmp 0");
  }
  else if (cmd == "CMD_STATUS") {
    Serial.print("STATUS: LED=");
    Serial.print(digitalRead(LED_BUILTIN));
    Serial.print(" BLOQUEIO=");
    Serial.println(digitalRead(13));
  }
  else if (cmd == "CMD_LOCALIZAR") {
    // Aqui você pode ler GPS e enviar coordenadas
    Serial.println("LOC:-23.5505,-46.6333");
  }
  else {
    Serial.print("ERRO: COMANDO DESCONHECIDO: ");
    Serial.println(cmd);
  }
}
```

---

## 🔐 Permissões Necessárias

O aplicativo requer as seguintes permissões:
- `INTERNET` - Comunicação de rede
- `ACCESS_NETWORK_STATE` - Estado da rede
- `ACCESS_WIFI_STATE` - Estado do WiFi
- `FOREGROUND_SERVICE` - Servidor em background
- `WAKE_LOCK` - Manter servidor ativo
- `USB_PERMISSION` - Acesso a dispositivos USB
- `RECEIVE_BOOT_COMPLETED` - Iniciar com o sistema

---

## 📊 Fluxo de Dados

```
┌─────────────────┐     Comando GT06      ┌──────────────────┐
│                 │ ─────────────────────→│                  │
│  Servidor       │    Porta 5023         │  App Android     │
│  Traccar        │                       │  Gateway         │
│                 │←──────────────────────│                  │
└─────────────────┘    (Futuro: Resposta) └────────┬─────────┘
                                                   │
                                                   │ USB/OTG
                                                   │ Serial
                                                   ↓
                                            ┌──────────────┐
                                            │   Arduino    │
                                            │   Uno        │
                                            └──────────────┘
```

---

## 🛠️ Arquivos Modificados/Criados

### Novos Arquivos
| Arquivo | Descrição |
|---------|-----------|
| `lib/gt06_protocol.dart` | Parser do protocolo GT06 |
| `lib/gt06_server_service.dart` | Servidor TCP GT06 |
| `lib/arduino_serial_service.dart` | Comunicação USB Serial com Arduino |
| `lib/traccar_gateway_service.dart` | Integração Gateway (servidor + serial) |
| `lib/gateway_screen.dart` | Tela de configuração do Gateway |
| `android/app/src/main/res/xml/device_filter.xml` | Filtro de dispositivos USB |

### Arquivos Modificados
| Arquivo | Alteração |
|---------|-----------|
| `lib/main.dart` | Inicialização do Gateway |
| `lib/main_screen.dart` | Botão de acesso ao Gateway |
| `lib/command_log_screen.dart` | Melhorias nos logs |
| `android/app/src/main/AndroidManifest.xml` | Permissões USB |
| `pubspec.yaml` | Dependências usb_serial e permission_handler |

---

## 📝 Changelog

### Versão 9.7.5+119 (Gateway Edition)
- ✅ Gateway Traccar-Arduino completo
- ✅ Servidor GT06 na porta 5023
- ✅ Protocolo GT06 implementado
- ✅ Comunicação USB/OTG com Arduino
- ✅ Baud rate configurável
- ✅ Bridge automático de comandos
- ✅ Estatísticas de comunicação
- ✅ Logs em tempo real
- ✅ Detecção automática de Arduino
- ✅ Suporte a múltiplos conversores USB-Serial

---

## ⚠️ Notas Importantes

1. **USB OTG**: É necessário um cabo USB OTG para conectar o Arduino ao celular
2. **Porta 5023**: Certifique-se de que a porta 5023 esteja liberada no firewall
3. **Baud Rate**: O baud rate no app deve ser o mesmo configurado no Arduino (padrão: 9600)
4. **Permissão USB**: Ao conectar o Arduino, aceite a permissão de acesso USB
5. **Background**: O servidor pode ser encerrado pelo sistema em background

---

## 📞 Suporte

Para dúvidas ou problemas:
1. Verifique se o cabo USB OTG está funcionando
2. Confirme que o baud rate é o mesmo no app e no Arduino
3. Verifique os logs na aba "Logs" do Gateway
4. Certifique-se de que o Arduino está enviando dados corretamente

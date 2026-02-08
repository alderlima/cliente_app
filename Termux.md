comandos para instalar e da permissão no diretório:
git init
git config --global --add safe.directory /storage/emulated/0/cliente_app
git remote add origin https://github.com/alderlima/cliente_app
git pull origin main


Comando para atualizar e gerar apk:
git status
git add .
git commit -m "Compilar APK 2"
git push origin main


assinar apk
apksigner sign \
  --ks /root/keys/test.keystore \
  --ks-key-alias testkey \
  --ks-pass pass:123456 \
  --key-pass pass:123456 \
  --out app-release-signed.apk \
  app-release-unsigned.apk



# Objetivo
clonar o repositório https://github.com/alderlima/cliente_app fazer as melhorias e devolver o arquivo modificado.
Refatorar e simplificar o aplicativo Flutter existente sem remover funcionalidades.  
O app é um cliente de comunicação com dispositivos (Arduino / GT06 / Gateway) e integração com a plataforma Traccar.

A meta é reduzir complexidade, melhorar manutenção, corrigir falhas de comunicação e modernizar a arquitetura.

---

# Regras IMPORTANTES
- NÃO remover nenhuma funcionalidade existente.
- NÃO alterar protocolos de comunicação.
- NÃO quebrar compatibilidade com o backend.
- Melhorar organização, legibilidade e desacoplamento.
- Sempre preferir soluções escaláveis e fáceis de testar.

---

# Problemas atuais a corrigir

## 1) Comunicação com o Traccar
A conexão/login/envio de dados não está funcionando corretamente.

Verificar:
- autenticação
- cookies / tokens
- websocket ou REST
- reconexão automática
- tratamento de erro
- timeouts
- logs

Criar uma camada robusta de comunicação.

---

## 2) Notificação permanente de GPS
Ao conceder permissão de localização, aparece a notificação do sistema no topo (foreground service).

Revisar:
- necessidade real de execução contínua
- modo de economia de bateria
- possibilidade de usar atualização menos agressiva
- lifecycle do serviço
- parar quando não estiver em uso

Implementar a abordagem mais moderna recomendada pelo Android / Flutter.

---

## 3) Código muito espalhado
Há muitos services fazendo responsabilidades parecidas.

Criar:
- interfaces comuns
- herança ou composição
- padronização de conexão, envio e recebimento

Exemplo desejado:

abstract class DeviceConnection {
  Future connect();
  Future disconnect();
  Future sendCommand(String cmd);
  Stream messages;
}

Cada protocolo implementa essa base.

---

## 4) Telas falando direto com services
Criar camada de gerenciamento de estado.

Usar uma das opções:
- Riverpod (preferencial)
- Bloc
- Provider

As telas não devem mais acessar serviços diretamente.

---

## 5) Falta padronização de pastas
Reorganizar em algo como:

lib/
 ├── core/
 ├── data/
 ├── domain/
 ├── services/
 ├── controllers/
 ├── ui/
 ├── widgets/

---

## 6) Melhorar testabilidade
Facilitar criação de mocks e testes unitários.

---

---

# Melhorias obrigatórias

## Reconexão inteligente
- retry automático
- backoff exponencial
- status online/offline

## Logs centralizados
Criar sistema único de logs para debug.

## Fila offline
Se perder conexão, armazenar comandos e enviar depois.

## Segurança
Revisar armazenamento de:
- senhas
- tokens
- configs

---

---

# UI / UX
Sem mudar funcionalidades.

Melhorar:
- organização visual
- redução de cliques
- feedback de conexão
- indicadores de status em tempo real
- carregamentos
- mensagens de erro claras

Código mais limpo e reutilizável.

---

# Performance
- reduzir rebuilds
- evitar streams desnecessárias
- revisar listeners
- otimizar conexões simultâneas

---

# Entrega esperada da IA

1. Nova arquitetura proposta
2. Lista do que será alterado
3. Arquivos impactados
4. Estratégia de migração segura
5. Exemplos de código refatorado
6. Sugestões futuras de evolução

---

# Contexto importante
Este é um app de telemetria/rastreamento que conversa com:
- Traccar
- Arduino
- GT06
- TCP / Serial

A estabilidade da comunicação é prioridade máxima.

---

# Prioridade das tarefas
1 → estabilizar comunicação  
2 → remover acoplamento  
3 → simplificar estrutura  
4 → melhorar UI  
5 → preparar escala  


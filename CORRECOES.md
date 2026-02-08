# Correções Realizadas para Build no GitHub Actions

## Resumo das Correções

### 1. Criada pasta `assets/` (Faltando)
- **Problema:** A pasta `assets/` estava referenciada no `pubspec.yaml` mas não existia
- **Solução:** Criada pasta `assets/` com arquivo `.gitkeep`

### 2. Removida referência ao `flutter_background_geolocation` (Erro Crítico)
- **Problema:** O `android/app/build.gradle.kts` referenciava o plugin `flutter_background_geolocation` que não estava no `pubspec.yaml`
- **Solução:** Removidas as linhas:
  ```kotlin
  val backgroundGeolocation = project(":flutter_background_geolocation")
  apply { from("${backgroundGeolocation.projectDir}/background_geolocation.gradle") }
  ```

### 3. Removidos plugins Firebase (Erro Crítico)
- **Problema:** Os plugins do Firebase estavam configurados mas não estavam sendo usados corretamente
- **Solução:** Removidos do `android/app/build.gradle.kts`:
  - `id("com.google.gms.google-services")`
  - `id("com.google.firebase.crashlytics")`
- **Solução:** Removidos do `android/settings.gradle.kts`:
  - `id("com.google.gms.google-services") version("4.3.15") apply false`
  - `id("com.google.firebase.crashlytics") version("2.8.1") apply false`
- **Solução:** Removido arquivo `firebase.json`
- **Solução:** Removido arquivo `google-services.json`

### 4. Atualizada versão do Kotlin
- **Problema:** Versão `2.1.21` era muito recente e poderia causar incompatibilidades
- **Solução:** Downgrade para versão `1.9.22` no `android/settings.gradle.kts`

### 5. Adicionado import faltante no `tracker_provider.dart`
- **Problema:** Usava `jsonEncode` e `jsonDecode` sem importar `dart:convert`
- **Solução:** Adicionado `import 'dart:convert';`

### 6. Adicionado getter público para `arduinoService`
- **Problema:** A tela `arduino_screen.dart` tentava acessar `provider.arduinoService` mas o campo era privado
- **Solução:** Adicionado getter público:
  ```dart
  ArduinoService get arduinoService => _arduinoService;
  ```

### 7. Removida licença do flutter_background_geolocation do AndroidManifest.xml
- **Problema:** Licença desnecessária estava no manifesto
- **Solução:** Removido o meta-data da licença

### 8. Removido arquivo `l10n.yaml`
- **Problema:** Configuração de localização que não estava sendo usada corretamente
- **Solução:** Removido arquivo para simplificar o build

### 9. Comentado include do flutter_lints
- **Problema:** O arquivo `analysis_options.yaml` incluía `package:flutter_lints/flutter.yaml` mas o pacote não estava no `pubspec.yaml`
- **Solução:** Comentada a linha de include

### 10. Atualizado workflow do GitHub Actions
- **Melhorias:**
  - Adicionado `workflow_dispatch` para permitir execução manual
  - Simplificado o workflow
  - Removido modo verbose
  - Adicionado `flutter clean` antes do build

### 11. Removido `pubspec.lock`
- **Problema:** O arquivo tinha versões antigas de dependências travadas
- **Solução:** Removido para regenerar com versões compatíveis

### 12. Atualizadas dependências no `pubspec.yaml`
- **Problema:** Versões antigas de dependências podiam causar incompatibilidades
- **Solução:** Atualizadas para versões mais recentes:
  - `geolocator: ^13.0.2`
  - `usb_serial: ^0.5.2`
  - `provider: ^6.1.2`
  - `shared_preferences: ^2.5.2`
- **Removidas dependências não usadas:**
  - `location`
  - `flutter_bloc`
  - `equatable`
  - `flutter_animate`
  - `font_awesome_flutter`
  - `shimmer`
  - `intl`
  - `google_fonts`
  - `path_provider`
  - `permission_handler`
  - `device_info_plus`
  - `logger`

### 13. Atualizado `AndroidManifest.xml`
- **Problema:** Faltavam permissões de localização para o GPS
- **Solução:** Adicionadas permissões:
  - `ACCESS_FINE_LOCATION`
  - `ACCESS_COARSE_LOCATION`
  - `ACCESS_BACKGROUND_LOCATION`
- **Problema:** `tools:replace="android:label"` podia causar conflitos
- **Solução:** Removido
- **Problema:** `tools` namespace não era necessário
- **Solução:** Removido

### 14. Simplificado `MainApplication.kt`
- **Problema:** Usava SLF4J que foi removido
- **Solução:** Simplificado para não usar dependências externas

### 15. Removidas dependências do SLF4J
- **Problema:** Dependências não eram necessárias
- **Solução:** Removidas do `android/app/build.gradle.kts`:
  - `org.slf4j:slf4j-api:2.0.7`
  - `com.github.tony19:logback-android:3.0.0`

### 16. Simplificado `android/build.gradle.kts`
- **Problema:** Variáveis extras não eram necessárias
- **Solução:** Removidas as variáveis `appCompatVersion` e `playServicesLocationVersion`

### 17. Removida versão específica do NDK
- **Problema:** Versão específica podia causar problemas
- **Solução:** Removida a linha `ndkVersion = "27.0.12077973"`

## Como Testar o Build

1. Faça commit das alterações:
   ```bash
   git add .
   git commit -m "Correções para build no GitHub Actions"
   git push
   ```

2. Acesse a aba **Actions** no GitHub

3. Execute o workflow manualmente ou aguarde o push

4. Verifique se o build completa com sucesso

## Próximos Passos (Se o build falhar)

Se o build ainda falhar, verifique:

1. **Logs do GitHub Actions** - Procure por mensagens de erro específicas
2. **Versões de dependências** - Algumas versões podem ser incompatíveis
3. **Permissões** - Verifique se o workflow tem permissões suficientes

## Estrutura Final do Projeto

```
cliente_app/
├── .github/
│   └── workflows/
│       └── android-build.yml    # Workflow atualizado
├── android/
│   ├── app/
│   │   ├── build.gradle.kts     # Sem referências ao flutter_background_geolocation
│   │   └── src/...
│   ├── build.gradle.kts
│   └── settings.gradle.kts      # Versão Kotlin atualizada
├── assets/                      # Criada
│   └── .gitkeep
├── lib/
│   ├── main.dart
│   ├── models/
│   ├── screens/
│   └── services/
├── pubspec.yaml                 # Dependências atualizadas
└── ...
```

## Dependências Finais

```yaml
dependencies:
  flutter:
    sdk: flutter
  geolocator: ^13.0.2
  usb_serial: ^0.5.2
  provider: ^6.1.2
  shared_preferences: ^2.5.2
```

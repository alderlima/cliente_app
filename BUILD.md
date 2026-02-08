# Instruções de Build - Rastreador GT06

## 📋 Pré-requisitos

### Instalar Flutter
```bash
# Windows (usando chocolatey)
choco install flutter

# macOS (usando homebrew)
brew install flutter

# Linux
sudo snap install flutter --classic
```

### Verificar Instalação
```bash
flutter doctor
```

Deve mostrar:
- ✅ Flutter SDK
- ✅ Android toolchain
- ✅ Android Studio (opcional)

## 🚀 Build do Aplicativo

### 1. Navegar ao Projeto
```bash
cd rastreador_gt06
```

### 2. Instalar Dependências
```bash
flutter pub get
```

### 3. Build APK (Android)

#### Debug (para testes)
```bash
flutter build apk --debug
```
Saída: `build/app/outputs/flutter-apk/app-debug.apk`

#### Release (para distribuição)
```bash
flutter build apk --release
```
Saída: `build/app/outputs/flutter-apk/app-release.apk`

#### App Bundle (para Play Store)
```bash
flutter build appbundle
```
Saída: `build/app/outputs/bundle/release/app-release.aab`

### 4. Instalar no Dispositivo

#### Via USB (modo desenvolvedor)
```bash
flutter install
```

#### Via arquivo APK
1. Transfira o APK para o celular
2. Abra o arquivo no celular
3. Permita instalação de fontes desconhecidas
4. Instale

## 🔧 Configuração de Assinatura (Release)

### Criar Keystore
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### Configurar gradle
Crie o arquivo `android/key.properties`:
```properties
storePassword=<sua-senha>
keyPassword=<sua-senha>
keyAlias=upload
storeFile=<caminho>/upload-keystore.jks
```

## 📱 Permissões no Android

O aplicativo precisa das seguintes permissões (já configuradas):

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.USB_PERMISSION" />
<uses-feature android:name="android.hardware.usb.host" />
```

## 🐛 Debug

### Rodar em modo debug
```bash
flutter run
```

### Ver logs
```bash
flutter logs
```

### Hot reload (durante desenvolvimento)
Pressione `r` no terminal

## 📦 Estrutura do APK

Após build, o APK contém:
- ✅ Código Flutter compilado
- ✅ Dependências nativas (GPS, USB)
- ✅ Assets e recursos

## 🔍 Solução de Problemas

### Erro: "Flutter SDK not found"
```bash
export PATH="$PATH:`pwd`/flutter/bin"
```

### Erro: "Android license status unknown"
```bash
flutter doctor --android-licenses
```

### Erro: "USB device not found"
- Ative "Depuração USB" no celular
- Conecte via cabo USB
- Aceite a permissão de debug no celular

### Erro: "Permissão de localização negada"
- Vá em Configurações > Aplicativos > Rastreador GT06
- Permissões > Localização > Permitir sempre

## 📊 Tamanho do APK

- Debug: ~30-40 MB
- Release: ~15-25 MB

## 🚀 Distribuição

### Instalação Direta
1. Envie o APK para o celular
2. Instale diretamente

### Play Store
1. Gere App Bundle: `flutter build appbundle`
2. Faça upload no Google Play Console

### Outros
- Firebase App Distribution
- TestFlight (iOS)
- APK direto

---

**Pronto para usar!** 🎉

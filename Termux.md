comandos para instalar e da permissão no diretório:
git init
git config --global --add safe.directory /storage/emulated/0/cliente_app
git remote add origin https://github.com/alderlima/cliente_app
git pull origin main


Comando para atualizar e gerar apk:
git status
git add .
git commit -m "Compilar APK 1"
git push origin main


assinar apk
apksigner sign \
  --ks /root/keys/test.keystore \
  --ks-key-alias testkey \
  --ks-pass pass:123456 \
  --key-pass pass:123456 \
  --out app-release-signed.apk \
  app-release-unsigned.apk

@echo off
setlocal

:: ==========================================
:: CONFIGURAÇÃO (AJUSTE AQUI O CAMINHO DA EXTENSÃO)
:: ==========================================
:: Cole aqui o caminho da pasta da extensão instalada (aquela que tem o package.json)
set "DESTINO=C:\Users\copal\AppData\Local\Programs\Antigravity\resources\app\extensions\roblox-ide-icons\theme.json"

echo ==========================================
echo 🚀 INICIANDO PROCESSO COMPLETO
echo ==========================================

echo.
echo 1. Exportando jogo do Roblox (Lune)...
lune run RbxExport

echo.
echo 2. Gerando novo theme.json...
node gerar_tema.js

echo.
echo 3. Substituindo arquivo na Extensao...
copy /Y "theme.json" "%DESTINO%"

if %errorlevel% equ 0 (
    echo.
    echo ✅ SUCESSO! Arquivo substituido.
    echo ⚠️  Agora de um "Reload Window" no VS Code (Ctrl+R).
) else (
    echo.
    echo ❌ ERRO: Nao foi possivel copiar o arquivo.
    echo Verifique se o caminho em DESTINO esta correto no script.
)

echo ==========================================
pause
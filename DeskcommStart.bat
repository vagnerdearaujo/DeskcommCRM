@echo off
setlocal
title DeskcommCRM - Inicializador
cd /d "D:\qwenProjects\DeskcommCRM"

echo ============================================
echo   DeskcommCRM - Inicializador manual
echo ============================================
echo.

rem [1/5] Docker
echo [1/5] Verificando Docker...
docker info >NUL 2>&1
if errorlevel 1 (
    echo.
    echo   ERRO: Docker nao esta rodando. Abra o Docker Desktop e tente de novo.
    pause
    exit /b 1
)
echo   OK - Docker ativo.
echo.

rem [2/5] Junction do supabase\.temp - o Docker Desktop so faz bind de ARQUIVOS
rem a partir da unidade C:. Sem o junction, o postgres nao sobe com a chave
rem pgsodium (bind de arquivo vira diretorio). O junction aponta .temp para
rem uma pasta no C:.
echo [2/5] Verificando junction supabase\.temp...
if not exist "supabase\.temp" (
    echo   Criando junction .temp -^> C:...
    if not exist "C:\Users\vagne\.qwen\supabase-temp\deskcommcrm" mkdir "C:\Users\vagne\.qwen\supabase-temp\deskcommcrm"
    mklink /J "supabase\.temp" "C:\Users\vagne\.qwen\supabase-temp\deskcommcrm"
) else (
    dir /a:l "supabase" | findstr /C:".temp" >NUL
    if errorlevel 1 (
        echo.
        echo   ATENCAO: supabase\.temp existe mas NAO e um junction.
        echo   O start do Supabase vai falhar no pgsodium. Mova a pasta
        echo   supabase\.temp para outro lugar e execute este script de novo.
        pause
        exit /b 1
    )
)
echo   OK - junction ativo.
echo.

rem [3/5] Servicos auxiliares (WAHA, Redis, SRH, Worker) - idempotente
echo [3/5] Iniciando servicos auxiliares - WAHA, Redis, SRH, Worker...
docker compose --env-file .env.local up -d
if errorlevel 1 (
    echo.
    echo   ERRO ao iniciar os servicos auxiliares. Veja a saida acima.
    pause
    exit /b 1
)
echo   OK - servicos auxiliares no ar.
echo.

rem [4/5] Supabase local (idempotente: se ja estiver rodando, apenas reporta)
echo [4/5] Iniciando Supabase local - API :54321, Studio :54323...
call supabase start
if errorlevel 1 (
    echo.
    echo   ERRO ao iniciar o Supabase. Veja a saida acima.
    pause
    exit /b 1
)
echo   OK - Supabase no ar.
echo.

rem [5/5] Aplicacao web
echo [5/5] Iniciando aplicacao web em http://localhost:3000 ...
netstat -ano | findstr /R /C:":3000 .*LISTENING" >NUL
if not errorlevel 1 (
    echo   App ja esta rodando na porta 3000.
) else (
    start "DeskcommCRM App" cmd /k "cd /d D:\qwenProjects\DeskcommCRM && pnpm dev"
)
echo.

echo ============================================
echo   DeskcommCRM iniciado:
echo     App       http://localhost:3000
echo     Supabase  http://localhost:54321
echo     Studio    http://localhost:54323
echo     WAHA      http://localhost:3030
echo ============================================
endlocal

@echo off
REM =============================================================================
REM rollback.bat — Rollback de dados e aplicação DeskcommCRM (Windows)
REM =============================================================================
REM Uso:
REM   scripts\rollback.bat db [YYYY-MM-DD]    Restaura DB do backup mais recente
REM   scripts\rollback.bat app                Reverte docker-compose ao git anterior
REM   scripts\rollback.bat full [YYYY-MM-DD]  DB + app
REM =============================================================================

setlocal enabledelayedexpansion
cd /d "%~dp0.."

if /i "%~1"=="" (
  echo Uso: %~n0 db [data] ^| app ^| full [data]
  exit /b 1
)

if /i "%~1"=="db" goto :rollback_db
if /i "%~1"=="app" goto :rollback_app
if /i "%~1"=="full" goto :rollback_full

echo Modo invalido: %~1
exit /b 1

:rollback_full
  call :rollback_db %2
  call :rollback_app
  exit /b %ERRORLEVEL%

:rollback_db
  echo === Rollback DB ===

  REM Encontrar backup mais recente
  set "BACKUP_DIR=data\backups\%~1"
  if "%~1"=="" (
    REM Pega o diretorio mais recente
    for /f "delims=" %%d in ('dir data\backups\????-??-?? /b /ad /o-n 2^>nul') do (
      set "BACKUP_DIR=data\backups\%%d"
      goto :found_dir
    )
    echo Nenhum backup encontrado em data\backups\
    exit /b 1
  )
  :found_dir

  REM Encontrar o dump mais recente
  set "DUMP_FILE="
  for /f "delims=" %%f in ('dir "!BACKUP_DIR!\supabase_*.dump" /b /o-n 2^>nul') do (
    set "DUMP_FILE=!BACKUP_DIR!\%%f"
    goto :found_dump
  )
  if "!DUMP_FILE!"=="" (
    echo Nenhum supabase dump encontrado em !BACKUP_DIR!
    exit /b 1
  )
  :found_dump

  echo Restaurando de: !DUMP_FILE!

  REM Validar dump
  echo [1/3] Validando dump...
  docker exec supabase_db_deskcomm-crm pg_restore --list /tmp/validate.dump >nul 2>&1 || (
    echo Copiando dump para validacao...
    docker cp "!DUMP_FILE!" supabase_db_deskcomm-crm:/tmp/validate.dump
    docker exec supabase_db_deskcomm-crm pg_restore --list /tmp/validate.dump >nul 2>&1 || (
      echo ERRO: Dump invalido ou corrompido
      exit /b 1
    )
  )

  REM Parar worker (evita escritas)
  echo [2/3] Parando worker...
  docker stop deskcomm-srh deskcomm-worker 2>nul

  REM Restaurar
  echo [3/3] Restaurando DB...
  docker cp "!DUMP_FILE!" supabase_db_deskcomm-crm:/tmp/rollback.dump
  docker exec supabase_db_deskcomm-crm psql -U postgres -d postgres -c "DROP OWNED BY current_user CASCADE;" >nul 2>&1
  docker exec supabase_db_deskcomm-crm pg_restore -U postgres -d postgres --clean --if-exists /tmp/rollback.dump
  docker exec supabase_db_deskcomm-crm rm /tmp/rollback.dump

  echo === DB rollback concluido ===
  echo Reinicie: docker compose --env-file .env.local up -d
  exit /b 0

:rollback_app
  echo === Rollback App ===

  REM Verificar se ha commit anterior dos composes
  for %%f in (docker-compose.yml docker-compose.override.yml docker-compose.prod.yml) do (
    if exist "%%f" (
      for /f "usebackq tokens=1" %%c in (`git log -1 --format="%%H" -- "%%f" 2^>nul`) do (
        for /f "usebackq tokens=*" %%p in (`git rev-list --parents -1 %%c 2^>nul ^| findstr /V "^$"`) do set PARENT=%%p
      )
    )
  )

  REM Restaurar do commit anterior
  echo Revertendo composes...
  for %%f in (docker-compose.yml docker-compose.override.yml docker-compose.prod.yml) do (
    for /f "tokens=1" %%p in ('git log --oneline -2 -- "%%f" ^| findstr /V "^$" ^| tail -1') do (
      git show %%p:"%%f" > "%%f" 2>nul && echo  - %%f restaurado
    )
  )

  REM Subir com versao anterior
  docker compose --env-file .env.local up -d

  echo === App rollback concluido ===
  exit /b 0

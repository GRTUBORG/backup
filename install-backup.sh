#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="node-backup-watcher"
WATCHER_SCRIPT_PATH="/usr/local/bin/${SERVICE_NAME}.sh"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

REMOTE_PORT="${REMOTE_PORT:-22}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"

log() {
  printf "\033[1;34m[INFO]\033[0m %s\n" "$1"
}

success() {
  printf "\033[1;32m[OK]\033[0m %s\n" "$1"
}

error() {
  printf "\033[1;31m[ERROR]\033[0m %s\n" "$1" >&2
}

load_env() {
  if [[ -f ".env" ]]; then
    log "Загружаю конфигурацию из .env"
    # shellcheck disable=SC1091
    source .env
  else
    log ".env не найден, использую переменные окружения"
  fi
}

require_var() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    error "Не задана обязательная переменная: ${var_name}"
    exit 1
  fi
}

install_dependencies() {
  log "Устанавливаю зависимости"
  apt update -y
  apt install -y inotify-tools zip openssh-client
  success "Зависимости установлены"
}

build_ssh_options() {
  SSH_OPTIONS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -p "${REMOTE_PORT}")

  if [[ -n "${SSH_KEY_PATH}" ]]; then
    SSH_OPTIONS+=(-i "${SSH_KEY_PATH}")
  fi
}

print_ssh_setup_hint() {
  local ssh_user_host="${REMOTE_USER}@${REMOTE_HOST}"
  local private_key_path="${SSH_KEY_PATH}"
  local public_key_path=""

  if [[ -z "${private_key_path}" ]]; then
    for candidate in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ecdsa"; do
      if [[ -f "${candidate}" ]]; then
        private_key_path="${candidate}"
        break
      fi
    done
  fi

  if [[ -n "${private_key_path}" ]]; then
    public_key_path="${private_key_path}.pub"

    if [[ ! -f "${private_key_path}" ]]; then
      error "Приватный ключ не найден: ${private_key_path}"
      error "Создайте ключ: ssh-keygen -t ed25519 -f ${private_key_path} -N \"\""
      error "После этого загрузите ключ: ssh-copy-id -i ${public_key_path} -p ${REMOTE_PORT} ${ssh_user_host}"
      return
    fi

    if [[ ! -f "${public_key_path}" ]]; then
      error "Публичный ключ не найден: ${public_key_path}"
      error "Сгенерируйте public key из приватного: ssh-keygen -y -f ${private_key_path} > ${public_key_path}"
      error "После этого загрузите ключ: ssh-copy-id -i ${public_key_path} -p ${REMOTE_PORT} ${ssh_user_host}"
      return
    fi

    error "Найден локальный ключ: ${private_key_path}"
    error "Добавьте ключ на удалённый сервер: ssh-copy-id -i ${public_key_path} -p ${REMOTE_PORT} ${ssh_user_host}"
    return
  fi

  error "Локальные SSH-ключи не найдены (возможна ошибка ssh-copy-id: No identities found)."
  error "Создайте ключ: ssh-keygen -t ed25519 -f $HOME/.ssh/id_ed25519 -N \"\""
  error "Загрузите его на удалённый сервер: ssh-copy-id -i $HOME/.ssh/id_ed25519.pub -p ${REMOTE_PORT} ${ssh_user_host}"
}

verify_ssh_access() {
  log "Проверяю SSH-доступ к ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}"

  if ! ssh -o BatchMode=yes "${SSH_OPTIONS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "true"; then
    error "Не удалось подключиться по SSH без пароля."
    error "Для автозагрузки бэкапов нужен key-based доступ (без ввода пароля)."
    print_ssh_setup_hint
    exit 1
  fi

  success "SSH-доступ подтверждён"
}

prepare_directories() {
  log "Создаю локальную директорию бэкапов: ${LOCAL_BACKUP_DIR}"
  mkdir -p "${LOCAL_BACKUP_DIR}"

  log "Создаю директорию на резервном сервере: ${REMOTE_DIR}"
  ssh "${SSH_OPTIONS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p '${REMOTE_DIR}'"
  success "Локальная и удалённая директории готовы"
}

create_watcher_script() {
  log "Создаю watcher-скрипт: ${WATCHER_SCRIPT_PATH}"
  cat > "${WATCHER_SCRIPT_PATH}" <<WATCHER
#!/usr/bin/env bash

set -euo pipefail

WATCH_DIR="${WATCH_DIR}"
LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR}"
REMOTE_USER="${REMOTE_USER}"
REMOTE_HOST="${REMOTE_HOST}"
REMOTE_PORT="${REMOTE_PORT}"
REMOTE_DIR="${REMOTE_DIR}"
SSH_KEY_PATH="${SSH_KEY_PATH}"

SCP_OPTIONS=(-P "\${REMOTE_PORT}" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

if [[ -n "\${SSH_KEY_PATH}" ]]; then
  SCP_OPTIONS+=( -i "\${SSH_KEY_PATH}" )
fi

mkdir -p "\${LOCAL_BACKUP_DIR}"

inotifywait -m -r -e modify,create,delete,move "\${WATCH_DIR}" | while read -r _ _ _
do
  sleep 5

  timestamp=\$(date +"%Y-%m-%d_%H-%M-%S")
  archive_name="node_backup_\${timestamp}.zip"
  archive_path="\${LOCAL_BACKUP_DIR}/\${archive_name}"

  zip -r -q "\${archive_path}" "\${WATCH_DIR}"
  scp "\${SCP_OPTIONS[@]}" "\${archive_path}" "\${REMOTE_USER}@\${REMOTE_HOST}:\${REMOTE_DIR}/"

  ls -tp "\${LOCAL_BACKUP_DIR}" | grep -v '/$' | tail -n +4 | xargs -r -I {} rm -- "\${LOCAL_BACKUP_DIR}/{}"
done
WATCHER

  chmod +x "${WATCHER_SCRIPT_PATH}"
  success "Watcher-скрипт создан"
}

create_systemd_service() {
  log "Создаю systemd-сервис: ${SERVICE_NAME}"
  cat > "${SERVICE_PATH}" <<SERVICE
[Unit]
Description=Node Folder Backup Watcher
After=network.target

[Service]
ExecStart=${WATCHER_SCRIPT_PATH}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}"
  systemctl restart "${SERVICE_NAME}"
  success "Сервис запущен"
}

print_summary() {
  success "Установка завершена"
  printf "\nСводка:\n"
  printf "  WATCH_DIR:        %s\n" "${WATCH_DIR}"
  printf "  LOCAL_BACKUP_DIR: %s\n" "${LOCAL_BACKUP_DIR}"
  printf "  REMOTE_TARGET:    %s@%s:%s\n" "${REMOTE_USER}" "${REMOTE_HOST}" "${REMOTE_DIR}"
  printf "  REMOTE_PORT:      %s\n\n" "${REMOTE_PORT}"
  systemctl status "${SERVICE_NAME}" --no-pager
}

main() {
  load_env

  require_var "REMOTE_USER"
  require_var "REMOTE_HOST"
  require_var "WATCH_DIR"
  require_var "LOCAL_BACKUP_DIR"
  require_var "REMOTE_DIR"

  install_dependencies
  build_ssh_options
  verify_ssh_access
  prepare_directories
  create_watcher_script
  create_systemd_service
  print_summary
}

main "$@"

#!/usr/bin/env bash

set -euo pipefail

SOURCE_PORT="${SOURCE_PORT:-22}"
DEST_PORT="${DEST_PORT:-22}"
SOURCE_SSH_KEY_PATH="${SOURCE_SSH_KEY_PATH:-${SSH_KEY_PATH:-}}"
DEST_SSH_KEY_PATH="${DEST_SSH_KEY_PATH:-${SSH_KEY_PATH:-}}"
LOCAL_TMP_DIR="${LOCAL_TMP_DIR:-/tmp/backup-transfer}"
EXTRACT_SUBDIR="${EXTRACT_SUBDIR:-}"
KEEP_REMOTE_ARCHIVE="${KEEP_REMOTE_ARCHIVE:-true}"

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

build_ssh_opts() {
  SOURCE_SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -P "${SOURCE_PORT}")
  DEST_SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -P "${DEST_PORT}")

  SOURCE_EXEC_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -p "${SOURCE_PORT}")
  DEST_EXEC_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -p "${DEST_PORT}")

  if [[ -n "${SOURCE_SSH_KEY_PATH}" ]]; then
    SOURCE_SSH_OPTS+=( -i "${SOURCE_SSH_KEY_PATH}" )
    SOURCE_EXEC_OPTS+=( -i "${SOURCE_SSH_KEY_PATH}" )
  fi

  if [[ -n "${DEST_SSH_KEY_PATH}" ]]; then
    DEST_SSH_OPTS+=( -i "${DEST_SSH_KEY_PATH}" )
    DEST_EXEC_OPTS+=( -i "${DEST_SSH_KEY_PATH}" )
  fi
}

ensure_dependencies() {
  for cmd in scp ssh basename mktemp; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      error "Не найдена обязательная утилита: ${cmd}"
      exit 1
    fi
  done
}

download_archive() {
  local filename
  filename="$(basename "${SOURCE_ARCHIVE_PATH}")"

  mkdir -p "${LOCAL_TMP_DIR}"
  LOCAL_ARCHIVE_PATH="$(mktemp "${LOCAL_TMP_DIR}/incoming_XXXXXX_${filename}")"

  log "Скачиваю архив с бэкап-сервера: ${SOURCE_USER}@${SOURCE_HOST}:${SOURCE_ARCHIVE_PATH}"
  scp "${SOURCE_SSH_OPTS[@]}" "${SOURCE_USER}@${SOURCE_HOST}:${SOURCE_ARCHIVE_PATH}" "${LOCAL_ARCHIVE_PATH}"
  success "Архив скачан локально: ${LOCAL_ARCHIVE_PATH}"
}

upload_archive() {
  REMOTE_ARCHIVE_NAME="$(basename "${SOURCE_ARCHIVE_PATH}")"
  REMOTE_ARCHIVE_PATH="${DEST_DIR%/}/${REMOTE_ARCHIVE_NAME}"

  log "Создаю директорию на резервном сервере: ${DEST_DIR}"
  ssh "${DEST_EXEC_OPTS[@]}" "${DEST_USER}@${DEST_HOST}" "mkdir -p '${DEST_DIR}'"

  log "Загружаю архив на резервный сервер: ${DEST_USER}@${DEST_HOST}:${REMOTE_ARCHIVE_PATH}"
  scp "${DEST_SSH_OPTS[@]}" "${LOCAL_ARCHIVE_PATH}" "${DEST_USER}@${DEST_HOST}:${REMOTE_ARCHIVE_PATH}"
  success "Архив загружен на резервный сервер"
}

extract_archive() {
  local extract_to
  extract_to="${DEST_DIR}"

  if [[ -n "${EXTRACT_SUBDIR}" ]]; then
    extract_to="${DEST_DIR%/}/${EXTRACT_SUBDIR}"
    ssh "${DEST_EXEC_OPTS[@]}" "${DEST_USER}@${DEST_HOST}" "mkdir -p '${extract_to}'"
  fi

  log "Распаковываю архив на резервном сервере в: ${extract_to}"

  case "${REMOTE_ARCHIVE_NAME}" in
    *.zip)
      ssh "${DEST_EXEC_OPTS[@]}" "${DEST_USER}@${DEST_HOST}" "command -v unzip >/dev/null 2>&1 || { echo 'unzip не установлен на резервном сервере' >&2; exit 1; }; unzip -o '${REMOTE_ARCHIVE_PATH}' -d '${extract_to}'"
      ;;
    *.tar.gz|*.tgz)
      ssh "${DEST_EXEC_OPTS[@]}" "${DEST_USER}@${DEST_HOST}" "tar -xzf '${REMOTE_ARCHIVE_PATH}' -C '${extract_to}'"
      ;;
    *.tar)
      ssh "${DEST_EXEC_OPTS[@]}" "${DEST_USER}@${DEST_HOST}" "tar -xf '${REMOTE_ARCHIVE_PATH}' -C '${extract_to}'"
      ;;
    *)
      error "Неподдерживаемый формат архива: ${REMOTE_ARCHIVE_NAME}"
      error "Поддерживаются: .zip, .tar.gz, .tgz, .tar"
      exit 1
      ;;
  esac

  success "Архив распакован на резервном сервере"
}

cleanup() {
  if [[ -n "${LOCAL_ARCHIVE_PATH:-}" && -f "${LOCAL_ARCHIVE_PATH}" ]]; then
    rm -f "${LOCAL_ARCHIVE_PATH}"
    log "Удалён временный локальный файл: ${LOCAL_ARCHIVE_PATH}"
  fi

  if [[ "${KEEP_REMOTE_ARCHIVE}" != "true" ]]; then
    log "Удаляю архив с резервного сервера: ${REMOTE_ARCHIVE_PATH}"
    ssh "${DEST_EXEC_OPTS[@]}" "${DEST_USER}@${DEST_HOST}" "rm -f '${REMOTE_ARCHIVE_PATH}'"
    success "Архив удалён с резервного сервера"
  fi
}

main() {
  load_env

  require_var "SOURCE_USER"
  require_var "SOURCE_HOST"
  require_var "SOURCE_ARCHIVE_PATH"
  require_var "DEST_USER"
  require_var "DEST_HOST"
  require_var "DEST_DIR"

  ensure_dependencies
  build_ssh_opts

  download_archive
  upload_archive
  extract_archive
  cleanup

  success "Готово: архив перенесён и распакован"
}

main "$@"

#!/usr/bin/env bash

set -euo pipefail

SOURCE_PORT="${SOURCE_PORT:-22}"
SOURCE_SSH_KEY_PATH="${SOURCE_SSH_KEY_PATH:-${SSH_KEY_PATH:-}}"
LOCAL_ARCHIVE_DIR="${LOCAL_ARCHIVE_DIR:-/tmp/backup-transfer}"
EXTRACT_SUBDIR="${EXTRACT_SUBDIR:-}"
KEEP_LOCAL_ARCHIVE="${KEEP_LOCAL_ARCHIVE:-true}"

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
  if ! command -v apt-get >/dev/null 2>&1; then
    error "apt-get не найден. Установите вручную: openssh-client zip unzip tar"
    exit 1
  fi

  log "Обновляю индекс пакетов (apt-get update)"
  apt-get update -y

  log "Устанавливаю зависимости: openssh-client zip unzip tar"
  DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-client zip unzip tar
  success "Зависимости установлены"
}

build_ssh_opts() {
  SOURCE_SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -P "${SOURCE_PORT}")

  if [[ -n "${SOURCE_SSH_KEY_PATH}" ]]; then
    SOURCE_SSH_OPTS+=( -i "${SOURCE_SSH_KEY_PATH}" )
  fi
}

ensure_dependencies() {
  for cmd in scp basename mkdir; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      error "Не найдена обязательная утилита: ${cmd}"
      exit 1
    fi
  done
}

download_archive() {
  ARCHIVE_NAME="$(basename "${SOURCE_ARCHIVE_PATH}")"
  LOCAL_ARCHIVE_PATH="${LOCAL_ARCHIVE_DIR%/}/${ARCHIVE_NAME}"

  mkdir -p "${LOCAL_ARCHIVE_DIR}"

  log "Скачиваю архив с бэкап-сервера: ${SOURCE_USER}@${SOURCE_HOST}:${SOURCE_ARCHIVE_PATH}"
  scp "${SOURCE_SSH_OPTS[@]}" "${SOURCE_USER}@${SOURCE_HOST}:${SOURCE_ARCHIVE_PATH}" "${LOCAL_ARCHIVE_PATH}"
  success "Архив скачан на резервный сервер: ${LOCAL_ARCHIVE_PATH}"
}

extract_archive() {
  local extract_to
  extract_to="${DEST_DIR}"

  mkdir -p "${DEST_DIR}"

  if [[ -n "${EXTRACT_SUBDIR}" ]]; then
    extract_to="${DEST_DIR%/}/${EXTRACT_SUBDIR}"
    mkdir -p "${extract_to}"
  fi

  log "Распаковываю архив локально в: ${extract_to}"

  case "${ARCHIVE_NAME}" in
    *.zip)
      command -v unzip >/dev/null 2>&1 || {
        error "unzip не установлен на резервном сервере"
        exit 1
      }
      unzip -o "${LOCAL_ARCHIVE_PATH}" -d "${extract_to}"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "${LOCAL_ARCHIVE_PATH}" -C "${extract_to}"
      ;;
    *.tar)
      tar -xf "${LOCAL_ARCHIVE_PATH}" -C "${extract_to}"
      ;;
    *)
      error "Неподдерживаемый формат архива: ${ARCHIVE_NAME}"
      error "Поддерживаются: .zip, .tar.gz, .tgz, .tar"
      exit 1
      ;;
  esac

  success "Архив распакован"
}

cleanup() {
  if [[ "${KEEP_LOCAL_ARCHIVE}" != "true" && -f "${LOCAL_ARCHIVE_PATH}" ]]; then
    rm -f "${LOCAL_ARCHIVE_PATH}"
    log "Удалён локальный архив: ${LOCAL_ARCHIVE_PATH}"
  fi
}

main() {
  load_env

  require_var "SOURCE_USER"
  require_var "SOURCE_HOST"
  require_var "SOURCE_ARCHIVE_PATH"
  require_var "DEST_DIR"

  install_dependencies
  ensure_dependencies
  build_ssh_opts

  download_archive
  extract_archive
  cleanup

  success "Готово: архив скачан на резервный сервер и распакован"
}

main "$@"

# Node Backup Installer

Скрипт для быстрой настройки автоматического резервного копирования директории `/root/node` на удалённый сервер.

Система отслеживает изменения в папке, автоматически создаёт архив и отправляет его на резервный сервер по SSH.
Процесс работает как системный сервис и запускается вместе с сервером.

---

## Как это работает

1. Система отслеживает изменения в директории `/root/node`.
2. При любом изменении создаётся архив всей папки.
3. Архив отправляется на резервный сервер через `scp`.
4. Локально хранятся только **3 последних архива**.
5. Если папки на резервном сервере нет — установщик создаёт её автоматически.

Скрипт запускается как `systemd`-сервис и работает постоянно.

---

## Установка в одну команду (рекомендуется)

> Подходит, если хотите «красиво и быстро» без ручного редактирования файлов.

```bash
curl -fsSL https://raw.githubusercontent.com/GRTUBORG/backup/refs/heads/master/install-backup.sh | \
sudo REMOTE_USER=root \
REMOTE_HOST=1.2.3.4 \
WATCH_DIR=/root/node \
LOCAL_BACKUP_DIR=/root/node_backups \
REMOTE_DIR=/root/backup_node/node-1 \
REMOTE_PORT=22 \
bash
```

Если нужен нестандартный ключ, добавьте перед `bash` параметр:

```bash
SSH_KEY_PATH=/root/.ssh/id_ed25519
```

Скрипт:

* установит зависимости
* создаст локальную папку для архивов
* создаст удалённую папку на резервном сервере через SSH
* проверит, что SSH-авторизация настроена без пароля (по ключу)
* создаст и запустит `systemd` сервис

---


## Быстрый перенос готового архива между серверами

Если архив уже лежит на одном сервере, можно в **одну команду** скачать его, отправить на резервный сервер и распаковать:

```bash
curl -fsSL https://raw.githubusercontent.com/GRTUBORG/backup/refs/heads/master/transfer-backup.sh | \
sudo SOURCE_USER=root \
SOURCE_HOST=10.10.10.10 \
SOURCE_ARCHIVE_PATH=/root/node_backups/node_backup_2026-03-12_01-00-00.zip \
DEST_USER=root \
DEST_HOST=20.20.20.20 \
DEST_DIR=/root/restore/node-1 \
SOURCE_PORT=22 \
DEST_PORT=22 \
bash
```

Опциональные параметры:

* `SOURCE_SSH_KEY_PATH` — приватный ключ для доступа к серверу-источнику.
* `DEST_SSH_KEY_PATH` — приватный ключ для доступа к резервному серверу.
* `EXTRACT_SUBDIR` — подпапка внутри `DEST_DIR`, куда распаковывать архив.
* `KEEP_REMOTE_ARCHIVE` — оставить архив на резервном сервере (`true`, по умолчанию) или удалить после распаковки (`false`).
* `LOCAL_TMP_DIR` — локальная временная папка для промежуточной загрузки.

Поддерживаемые форматы архива: `.zip`, `.tar.gz`, `.tgz`, `.tar`.

---

## Классическая установка через `.env`

Клонируйте репозиторий:

```bash
git clone https://github.com/GRTUBORG/backup
cd backup
```

Создайте конфигурационный файл:

```bash
cp env.example .env
nano .env
```

После этого запустите установку:

```bash
chmod +x install-backup.sh
sudo ./install-backup.sh
```

---

## Структура репозитория

```text
backup
│
├── install-backup.sh
├── env.example
└── README.md
```

---

## Конфигурация

Файл `.env` (или переменные окружения) содержит параметры системы.

Пример:

```env
REMOTE_USER=root
REMOTE_HOST=1.2.3.4
WATCH_DIR=/root/node
LOCAL_BACKUP_DIR=/root/node_backups
REMOTE_DIR=/root/backup_node/node-1
REMOTE_PORT=22
# SSH_KEY_PATH=/root/.ssh/id_ed25519
```

Описание параметров:

* **REMOTE_USER** — пользователь на резервном сервере.
* **REMOTE_HOST** — IP или домен резервного сервера.
* **WATCH_DIR** — директория, за которой следит система.
* **LOCAL_BACKUP_DIR** — папка для локального хранения архивов.
* **REMOTE_DIR** — директория на резервном сервере.
* **REMOTE_PORT** *(опционально)* — SSH-порт (по умолчанию `22`).
* **SSH_KEY_PATH** *(опционально)* — путь до приватного SSH-ключа.

---


## Важно про SSH-доступ

Установщик и `systemd`-watcher работают без интерактивного ввода пароля.
Поэтому на резервном сервере должен быть настроен вход по SSH-ключу для `REMOTE_USER`.

Пример подготовки ключа:

```bash
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""
ssh-copy-id -i /root/.ssh/id_ed25519.pub -p 22 root@1.2.3.4
```

Если key-based доступ ещё не настроен, установщик сам попытается:

1. сделать `apt update -y` перед SSH-настройкой,
2. создать локальный ключ (если его нет),
3. создать `.pub` из приватного ключа (если `.pub` отсутствует),
4. выполнить `ssh-copy-id` на удалённый сервер.

Если видите ошибку `ssh-copy-id: ERROR: No identities found`, это значит, что локальные SSH-ключи отсутствуют.
Создайте ключ через `ssh-keygen`, затем повторите `ssh-copy-id` с `-i /path/to/key.pub`.

Если приватный ключ уже есть, но нет `.pub`, сгенерируйте публичный ключ:

```bash
ssh-keygen -y -f /root/.ssh/id_ed25519 > /root/.ssh/id_ed25519.pub
```

Если видите ошибку `ssh-copy-id: ERROR: No identities found`, это значит, что локальные SSH-ключи отсутствуют.
Создайте ключ через `ssh-keygen`, затем повторите `ssh-copy-id` с `-i /path/to/key.pub`.

Если приватный ключ уже есть, но нет `.pub`, сгенерируйте публичный ключ:

```bash
ssh-keygen -y -f /root/.ssh/id_ed25519 > /root/.ssh/id_ed25519.pub
```

Если видите ошибку `ssh-copy-id: ERROR: No identities found`, это значит, что публичный ключ ещё не создан.
Сначала выполните `ssh-keygen`, затем повторите `ssh-copy-id` с `-i /path/to/key.pub`.

## Проверка работы

Проверьте статус сервиса:

```bash
systemctl status node-backup-watcher
```

Если всё настроено правильно, статус будет:

```text
active (running)
```

---

## Тестирование

Создайте тестовый файл:

```bash
touch /root/node/testfile.txt
```

Через несколько секунд:

* появится архив в `/root/node_backups`
* архив будет отправлен на резервный сервер

---

## Управление сервисом

Перезапуск:

```bash
systemctl restart node-backup-watcher
```

Остановка:

```bash
systemctl stop node-backup-watcher
```

Просмотр логов:

```bash
journalctl -u node-backup-watcher -f
```

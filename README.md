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
bash
```

Скрипт:

* установит зависимости
* создаст локальную папку для архивов
* создаст удалённую папку на резервном сервере через SSH
* создаст и запустит `systemd` сервис

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
```

Описание параметров:

* **REMOTE_USER** — пользователь на резервном сервере.
* **REMOTE_HOST** — IP или домен резервного сервера.
* **WATCH_DIR** — директория, за которой следит система.
* **LOCAL_BACKUP_DIR** — папка для локального хранения архивов.
* **REMOTE_DIR** — директория на резервном сервере.

---

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

#!/bin/bash

set -e

echo "Loading configuration..."

if [ ! -f ".env" ]; then
    echo ".env file not found"
    exit 1
fi

source .env

echo "Installing dependencies..."

apt update -y
apt install -y inotify-tools zip openssh-client

echo "Creating local backup directory..."

mkdir -p $LOCAL_BACKUP_DIR

echo "Creating watcher script..."

cat << EOF > /usr/local/bin/node-backup-watcher.sh
#!/bin/bash

WATCH_DIR="$WATCH_DIR"
LOCAL_BACKUP_DIR="$LOCAL_BACKUP_DIR"
REMOTE_USER="$REMOTE_USER"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_DIR="$REMOTE_DIR"

mkdir -p "\$LOCAL_BACKUP_DIR"

inotifywait -m -r -e modify,create,delete,move "\$WATCH_DIR" | while read path action file
do
    sleep 5

    TIMESTAMP=\$(date +"%Y-%m-%d_%H-%M-%S")
    ARCHIVE_NAME="node_backup_\$TIMESTAMP.zip"
    ARCHIVE_PATH="\$LOCAL_BACKUP_DIR/\$ARCHIVE_NAME"

    zip -r -q "\$ARCHIVE_PATH" "\$WATCH_DIR"

    scp "\$ARCHIVE_PATH" \${REMOTE_USER}@\${REMOTE_HOST}:\${REMOTE_DIR}/

    ls -tp \$LOCAL_BACKUP_DIR | grep -v '/$' | tail -n +4 | xargs -I {} rm -- "\$LOCAL_BACKUP_DIR/{}"
done
EOF

chmod +x /usr/local/bin/node-backup-watcher.sh

echo "Creating systemd service..."

cat << EOF > /etc/systemd/system/node-backup-watcher.service
[Unit]
Description=Node Folder Backup Watcher
After=network.target

[Service]
ExecStart=/usr/local/bin/node-backup-watcher.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "Starting service..."

systemctl daemon-reload
systemctl enable node-backup-watcher
systemctl start node-backup-watcher

echo "Backup watcher installed successfully"

systemctl status node-backup-watcher --no-pager
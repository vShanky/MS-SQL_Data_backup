#!/bin/bash
set -e

# -----------------------------
# Load environment variables
# -----------------------------
source "$(dirname "$0")/mssql_backup.env"

# Tools
SQLCMD="/opt/mssql-tools/bin/sqlcmd"
AWSCLI="/snap/bin/aws"  # Update if different

# Paths
SQL_BACKUP_DIR="/var/opt/mssql/backups/MDM_DB"
LOCAL_BACKUP_BASE="$(dirname "$0")/backups"
LOGFILE="$(dirname "$0")/logs/mssql-backup.log"

# Timestamp and folder
TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")
DATE_FOLDER=$(date "+%Y-%m-%d")
LOCAL_BACKUP_DIR="${LOCAL_BACKUP_BASE}/${DATE_FOLDER}"

mkdir -p "$SQL_BACKUP_DIR" "$LOCAL_BACKUP_DIR"

echo "[$(date)] === MSSQL daily backup started ===" | tee -a "$LOGFILE"

# Get list of user databases
DATABASES=$($SQLCMD -S "$DB_HOST" -U "$DB_USER" -P "$DB_PASS" \
    -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4" -h -1)

if [ -z "$DATABASES" ]; then
    echo "❌ No user databases found — exiting" | tee -a "$LOGFILE"
    exit 1
fi

echo "📦 Will back up: $DATABASES" | tee -a "$LOGFILE"

for DB in $DATABASES; do
    FILE="${DB}_${TIMESTAMP}.bak"
    SQL_PATH="${SQL_BACKUP_DIR}/${FILE}"
    LOCAL_PATH="${LOCAL_BACKUP_DIR}/${FILE}"
    S3_PATH="${S3_BUCKET}/${DATE_FOLDER}/${FILE}"

    echo "[$(date)] Backing up [${DB}] → ${SQL_PATH}" | tee -a "$LOGFILE"

    # Run backup
    $SQLCMD -S "$DB_HOST" -U "$DB_USER" -P "$DB_PASS" \
        -Q "BACKUP DATABASE [${DB}] TO DISK = N'${SQL_PATH}' WITH NOFORMAT, INIT, NAME = '${DB}-full', SKIP, NOREWIND, NOUNLOAD, STATS = 10" \
        > /tmp/sql_backup_${DB}.log 2>&1

    # Copy to organized folder
    cp "$SQL_PATH" "$LOCAL_PATH"

    if [ ! -f "$LOCAL_PATH" ]; then
        echo "[$(date)] ❌ Backup failed for $DB" | tee -a "$LOGFILE"
        continue
    fi

    echo "[$(date)] Uploading ${FILE} to S3…" | tee -a "$LOGFILE"
    $AWSCLI s3 cp "$LOCAL_PATH" "$S3_PATH" --storage-class STANDARD_IA

    if [ $? -eq 0 ]; then
        echo "[$(date)] ✅ Upload SUCCESS for ${FILE}" | tee -a "$LOGFILE"
    else
        echo "[$(date)] ❌ Upload FAILED for ${FILE}" | tee -a "$LOGFILE"
    fi
done

echo "[$(date)] ✅ Backup job finished" | tee -a "$LOGFILE"

# -----------------------------
# Cleanup local backups > 7 days
# -----------------------------
echo "[$(date)] 🧹 Cleaning up local backups (>7 days) in $LOCAL_BACKUP_BASE" | tee -a "$LOGFILE"
find "$LOCAL_BACKUP_BASE" -type f -name "*.bak" -mtime +7 -exec rm -f {} \;
echo "[$(date)] 🗑️ Local backup cleanup complete" | tee -a "$LOGFILE"

# -----------------------------
# Cleanup S3 backups > 7 days
# -----------------------------
echo "[$(date)] ☁️ Cleaning up S3 backups older than 7 days..." | tee -a "$LOGFILE"
$AWSCLI s3 ls "$S3_BUCKET/" | while read -r line; do
    createDate=$(echo $line | awk '{print $1}')
    fileName=$(echo $line | awk '{print $4}')
    if [ -z "$fileName" ]; then
        continue
    fi
    createDateSec=$(date -d $createDate +%s)
    olderThan=$(date -d '-7 days' +%s)
    if [ $createDateSec -lt $olderThan ]; then
        echo "[$(date)] Deleting S3 object: $fileName" | tee -a "$LOGFILE"
        $AWSCLI s3 rm "$S3_BUCKET/$fileName"
    fi
done
echo "[$(date)] ✅ S3 backup cleanup complete" | tee -a "$LOGFILE"

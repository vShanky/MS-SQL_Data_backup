# MSSQL Daily Backup Template

This repository provides a reusable template to backup MSSQL databases from a server to local folders and AWS S3, with automatic cleanup.

## Features

* Daily backup of all user databases
* Local storage organized by date
* Upload to AWS S3 organized by date
* Cleanup of local and S3 backups older than 7 days
* Fully configurable via `mssql_backup.env`

## Folder Structure

```
backups/                # Local backups (date-based subfolders)
logs/                   # Logs
mssql_daily_backup.sh    # Main backup script
mssql_backup.env.example # Example environment file
```

## Setup Instructions

1. Clone this repository (or use as GitHub template):

```bash
git clone https://github.com/<username>/mssql-backup-template.git
cd mssql-backup-template
```

2. Copy the example env and edit:

```bash
cp mssql_backup.env.example mssql_backup.env
# Edit DB_HOST, DB_USER, DB_PASS, S3_BUCKET
```

3. Make the script executable:

```bash
chmod +x mssql_daily_backup.sh
```

4. Test the script:

```bash
./mssql_daily_backup.sh
```

5. Setup cron job for daily backups:

```bash
0 2 * * * /path/to/mssql_daily_backup.sh >> /path/to/logs/cron.log 2>&1
```

## Notes

* Ensure AWS CLI is installed and configured (`aws configure`)
* `.env` file contains sensitive credentials — do not commit to GitHub
* The script automatically creates date-based subfolders for organization

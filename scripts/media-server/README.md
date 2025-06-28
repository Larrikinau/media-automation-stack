# Media Server Scripts

These scripts handle post-import cleanup on the **LOCAL** media server after Sonarr/Radarr have processed files.

## cleanup-sonarr.sh

**Purpose**: Removes source files from staging directories after Sonarr successfully imports TV shows.

**Trigger**: Executed by Sonarr as a custom script on:
- Download completion
- Import completion
- Upgrade completion

**Function**:
- Monitors Sonarr environment variables to determine source paths
- Only acts on qBittorrent downloads (ignores other clients like NZBGet)
- Safely removes files only from designated staging areas
- Logs all operations for auditing

**Safety Features**:
- Only deletes from `/tank/IncomingTV/` and `/tank/IncomingMovies/` paths
- Uses `--one-file-system` flag to prevent accidental cross-filesystem deletion
- Extensive logging of all operations
- Handles both Sonarr v3 and v4 variable formats

**Configuration in Sonarr**:
```
Settings → Connect → Custom Script
Name: Cleanup Script
Path: /home/username/cleanup-sonarr.sh
Arguments: (leave empty)
Triggers: On Download, On Import, On Upgrade
```

## cleanup-radarr.sh

**Purpose**: Removes source files from staging directories after Radarr successfully imports movies.

**Trigger**: Executed by Radarr as a custom script on:
- Download completion
- Import completion  
- Upgrade completion

**Function**:
- Monitors Radarr environment variables to determine source paths
- Only acts on qBittorrent downloads (ignores other clients)
- Safely removes files only from designated staging areas
- Logs all operations for auditing

**Safety Features**:
- Only deletes from `/tank/incomingmovies/` paths (case-insensitive)
- Uses `--one-file-system` flag to prevent accidental cross-filesystem deletion
- Extensive logging of all operations
- Warns if attempting to delete from outside staging areas

**Configuration in Radarr**:
```
Settings → Connect → Custom Script
Name: Cleanup Script
Path: /home/username/cleanup-radarr.sh
Arguments: (leave empty)
Triggers: On Download, On Import, On Upgrade
```

## Common Features

Both scripts share these characteristics:

**Logging**: All operations are logged to `~/cleanup-sonarr.log` and `~/cleanup-radarr.log` respectively, including:
- Timestamp of each operation
- Event type and download client
- Source path being processed
- Success/failure status
- Warning messages for edge cases

**Environment Variables**: The scripts read standard Sonarr/Radarr environment variables:
- Event type (Download, DownloadFolderImported, etc.)
- Download client name
- Source file/folder paths
- Other metadata provided by the applications

**Error Handling**: 
- Graceful handling of missing or invalid paths
- Skip operations for non-qBittorrent downloads
- Warning logs for unexpected conditions
- Fail-safe approach (won't delete if unsure)

**Security**: 
- Path validation to ensure deletions only occur in staging areas
- Protection against directory traversal attacks
- Conservative approach to file removal

## Troubleshooting

**Check if scripts are being called**:
```bash
tail -f ~/cleanup-sonarr.log
tail -f ~/cleanup-radarr.log
```

**Common issues**:
1. **Scripts not executing**: Check Sonarr/Radarr custom script configuration
2. **Permission errors**: Ensure scripts have execute permissions (`chmod +x`)
3. **Path mismatches**: Verify staging directory paths match your setup
4. **Not cleaning up**: Check that downloads are properly labeled as qBittorrent source

**Manual testing**:
You can test the scripts by setting the environment variables manually:
```bash
export sonarr_eventtype="Download"
export sonarr_download_client="qBittorrent"
export sonarr_sourcepath="/tank/IncomingTV/test-show"
./cleanup-sonarr.sh
```

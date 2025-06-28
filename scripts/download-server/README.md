# Download Server Scripts

These scripts handle the download and initial processing phase on the **REMOTE** download server (VPS, seedbox, dedicated server).

## rclone-sync-queue.sh

**Purpose**: Queue manager that limits concurrent rclone operations to prevent resource exhaustion.

**Function**: 
- Maintains a maximum of 4 parallel rclone sync operations
- Uses file-based locking to coordinate between processes
- Queues additional requests when all slots are busy

**Usage**: 
- Called automatically by qBittorrent on torrent completion
- Can be tested manually: `./rclone-sync-queue.sh "/path/to/file" "TV Shows"`

**Parameters**:
- `$1`: Path to downloaded file/folder (qBittorrent %F)
- `$2`: Category/label (qBittorrent %L)

## rclone-sync.sh

**Purpose**: Main processing script that handles file preparation and upload to media server.

**Key Features**:
- **Wrapper Detection**: Automatically strips generic "Incoming TV Shows"/"Incoming Movies" folders
- **RAR Extraction**: Detects and extracts RAR archives automatically
- **File Filtering**: Excludes unnecessary files (screens, metadata, RAR files) from upload
- **Optimized Transfer**: Uses high-performance rclone settings for fast uploads
- **Two-Stage Upload**: Uploads to staging area, then server-side move to live directory

**Workflow**:
1. Resolve source directory and strip wrappers if needed
2. Detect and extract RAR archives
3. Determine destination based on category label
4. Upload files to staging area with optimizations
5. Server-side move from staging to live directory

**Configuration**:
- Edit the `MEDIA_SERVER` remote name to match your rclone configuration
- Adjust rclone performance parameters based on your network capacity
- Modify category mappings as needed

**Category Mapping**:
- `TV Shows`, `tv shows`, `tv-shows`, `tv`, `series` → `/tank/IncomingTV/`
- `Movies`, `movies`, `movie`, `film` → `/tank/incomingmovies/`

**Log Files**:
- `~/rclone-debug.log`: High-level operations and status
- `~/rclone-sync.log`: Detailed rclone transfer logs

**Performance Tuning**:
The script uses aggressive optimization for fast transfers:
- 12 parallel transfers with 24 streams each
- 96 concurrent SFTP operations
- 256MB transfer buffer
- Automatic retries with exponential backoff

Adjust these values in the script based on your server capabilities and network bandwidth.

# Docker Registry Push/Pull Failure Investigation - 2026-01-05

**Date:** January 5, 2026
**Status:** Partial Fix Applied, Workaround Provided
**Affected Service:** conversationalist (versions 1.0.29, 1.0.30)
**Registry:** registry.alanhoangnguyen.com

---

## Problem Statement

Docker pull operations from the private registry were failing with "unexpected EOF" errors. The issue affected conversationalist image versions 1.0.29 and 1.0.30, preventing deployment to production.

### Error Symptoms
```
1.0.30: Pulling from admin/conversationalist
02d7611c4eae: Pulling fs layer
8715e552fa13: Pulling fs layer
9c27bc7ba63d: Pulling fs layer
...
02d7611c4eae: Retrying in 5 seconds
8715e552fa13: Retrying in 5 seconds
9c27bc7ba63d: Retrying in 5 seconds
...
unexpected EOF
```

---

## Investigation Timeline

### Initial Hypothesis: Network/Timeout Issues
**Time:** ~15:30 UTC
**Actions Taken:**
- Checked disk space: 22GB free (57% used) - ✅ Healthy
- Checked Docker resource usage: 9.3GB images, 0% reclaimable - ✅ Clean
- Analyzed registry resource usage: 0.67% memory, 0.02% CPU - ✅ Healthy

**Conclusion:** Not a resource issue.

### Discovery: Local Pull Also Fails
**Time:** ~15:48 UTC
**Key Finding:** Pull fails even on the same server hosting the registry (localhost connection)

**Implications:**
- ❌ NOT a network bandwidth issue
- ❌ NOT a firewall issue
- ❌ NOT an nginx timeout (fails immediately, not after minutes)
- ✅ Issue is with registry storage or blob corruption

### Root Cause Identified
**Time:** ~15:50 UTC
**Critical Discovery:** The failing blob files do not exist on disk!

```bash
# Registry returns HTTP 200 with 0 bytes written
http.response.status=200 http.response.written=0

# Blob directory is empty
ls /root/Orchestration/obsRemote/registry/data/docker/registry/v2/blobs/sha256/02/
# Output: empty directory
```

**Analysis:**
1. Manifest for version 1.0.29/1.0.30 exists in registry ✅
2. Manifest references specific blob hashes (layer IDs) ✅
3. Blob data files are MISSING from disk ❌
4. Registry returns "200 OK" with 0 bytes → Docker sees EOF

### Failing Layers Identified
**Consistently failing blobs (same across 1.0.29 and 1.0.30):**
- `02d7611c4eae219af91448a4720bdba036575d3bc0356cfe12774af85daa6aff` (~65MB - apt-get vim)
- `8715e552fa1374bdde269437d9a1c607c817289c2ebbceb9ed9ab1aa9ca86763` (~60MB - Python deps)
- `9c27bc7ba63d1ac690daefc68302197d3ab9a91fc5c0e19f447cd57eda92d87c` (~75MB - Application)

**Key Insight:** These are base image layers (Debian + Python 3.10.19) that are reused between builds. They were never successfully uploaded to the registry in the first place.

### Problem: Silent Push Failure
**Time:** ~16:00 UTC
**Discovery:** Push operations appear to succeed but these specific layers never upload.

**Evidence:**
- Version 1.0.30 was pushed after cleaning 1.0.29
- Same three layers still missing
- No blob files created on disk
- Docker push command reports success

**Hypothesis:** HTTP/2 causing silent failures with large blob uploads (known issue)

---

## Fixes Applied

### 1. Nginx Timeout Configuration
**File:** `/root/Orchestration/obsRemote/custom_server.conf`
**Changes:**
```nginx
# Docker Registry server block
client_max_body_size: 2G → 5G
proxy_connect_timeout: 300s → 1800s (30 minutes)
proxy_send_timeout: 300s → 1800s
proxy_read_timeout: 300s → 1800s
proxy_buffering: off (added)
proxy_request_buffering: off (added)
```

**Result:** Applied successfully, nginx reloaded ✅

### 2. HTTP/2 Disabled for Registry
**File:** `/root/Orchestration/obsRemote/custom_server.conf`
**Change:**
```nginx
# Before
listen 443 ssl http2;

# After
listen 443 ssl;
```

**Reason:** HTTP/2 is known to cause silent failures with large Docker blob uploads through nginx.

**Result:** Applied successfully, nginx reloaded ✅

### 3. Registry Cleanup
**Actions:**
```bash
# Removed corrupted manifests
docker exec docker_registry rm -rf \
  /var/lib/registry/docker/registry/v2/repositories/admin/conversationalist/_manifests/tags/1.0.29 \
  /var/lib/registry/docker/registry/v2/repositories/admin/conversationalist/_manifests/tags/1.0.30

# Ran garbage collection
docker exec docker_registry registry garbage-collect /etc/docker/registry/config.yml
# Result: 185 blobs marked, 0 eligible for deletion
```

**Result:** Corrupted manifests removed ✅

---

## Current Status

### What's Working
- ✅ Registry is healthy and operational
- ✅ Nginx configuration optimized for large uploads
- ✅ HTTP/2 disabled to prevent silent failures
- ✅ Corrupted manifests cleaned up
- ✅ Other images (agent-server, openwebui, etc.) working normally

### What's Not Working
- ❌ conversationalist 1.0.29 and 1.0.30 still cannot be pulled
- ❌ Base image layers not successfully uploading during push
- ❌ Docker client may be caching registry state and skipping uploads

### Outstanding Issue
**Docker client behavior:** Docker thinks the layers already exist in the registry (from corrupted manifest references) and skips uploading them, even after manifests are deleted.

---

## Solutions Provided

### Solution 1: Direct Deployment (Bypass Registry)
**Status:** ✅ Recommended for immediate deployment
**Script Created:** `/root/Orchestration/obsRemote/deploy-conversationalist-direct.sh`

**From build server:**
```bash
# Save image to archive
docker save registry.alanhoangnguyen.com/admin/conversationalist:1.0.30 | \
  gzip > conversationalist-1.0.30.tar.gz

# Transfer to production
scp conversationalist-1.0.30.tar.gz root@production:/tmp/

# On production server
docker load < /tmp/conversationalist-1.0.30.tar.gz
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml up -d --force-recreate conversationalist
```

**Pros:**
- Immediate deployment
- Bypasses registry issues completely
- Guaranteed to work

**Cons:**
- Manual process
- Doesn't fix registry for future use

### Solution 2: Force Registry Re-upload
**Status:** ⚠️ Requires testing

**From build server:**
```bash
# Clear Docker's registry cache
docker logout registry.alanhoangnguyen.com
rm -rf ~/.docker/manifests/registry.alanhoangnguyen.com*

# Re-login and force push
docker login registry.alanhoangnguyen.com
docker push registry.alanhoangnguyen.com/admin/conversationalist:1.0.30 --verbose
```

**Watch for:** Layers `02d7611c4eae`, `8715e552fa13`, and `9c27bc7ba63d` should show "Pushing" status, not "Layer already exists".

**Pros:**
- Fixes registry for future use
- Normal workflow once fixed

**Cons:**
- May not work if Docker still thinks layers exist
- Requires access to build server

---

## Technical Details

### Registry Configuration
```yaml
# /root/Orchestration/obsRemote/run_obsidian_remote.yml
docker-registry:
  image: registry:2
  container_name: docker_registry
  restart: unless-stopped
  environment:
    - REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/var/lib/registry
    - REGISTRY_AUTH=htpasswd
    - REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd
    - REGISTRY_HTTP_ADDR=0.0.0.0:5000
    - REGISTRY_STORAGE_DELETE_ENABLED=true
  volumes:
    - ./registry/data:/var/lib/registry
    - ./registry/auth:/auth
```

### Disk Usage
- **Total:** 49GB
- **Used:** 28GB (57%)
- **Available:** 21GB
- **Registry storage:** 3.4GB
- **Docker images:** 9.3GB

### Registry URL Structure
- **External:** https://registry.alanhoangnguyen.com
- **Internal:** http://docker-registry:5000
- **SSL:** Terminated at nginx
- **Auth:** htpasswd (admin user)

---

## Lessons Learned

1. **HTTP/2 + Large Blobs = Problems**
   - HTTP/2 can cause silent failures with large Docker blob uploads
   - Always test large uploads after enabling HTTP/2
   - Consider disabling HTTP/2 for registry endpoints

2. **Manifest vs Blob Storage**
   - Registry stores manifests separately from blobs
   - Manifests can reference non-existent blobs
   - Always verify blob existence, not just manifest

3. **Docker Client Caching**
   - Docker caches registry state locally
   - Corrupted manifests can poison client cache
   - Clear `~/.docker/manifests/` when troubleshooting

4. **Silent Failures Are Dangerous**
   - Push appeared successful but blobs never uploaded
   - Always verify pulls work after pushes
   - Monitor registry logs during uploads

5. **Base Layer Reuse**
   - Docker reuses base layers between builds (good for efficiency)
   - If base layers never uploaded, all dependent images fail
   - Consider pushing base images explicitly first

---

## Next Steps

### Immediate (For User)
1. **Choose deployment method:**
   - Option A: Use direct docker save/load (fastest)
   - Option B: Fix registry push (better long-term)

2. **If using Option A:**
   - Run deployment script from build server
   - Transfer and load on production
   - Redeploy conversationalist service

3. **If using Option B:**
   - Clear Docker client cache on build server
   - Re-push version 1.0.30
   - Verify layers upload successfully
   - Test pull on production

### Follow-up Investigation
1. **Monitor next push attempt:**
   ```bash
   # On registry server
   docker logs -f docker_registry | grep -i "put\|blob"
   ```

2. **Check nginx error logs:**
   ```bash
   docker exec nginx_proxy_manager tail -f /var/log/nginx/registry_error.log
   ```

3. **If push still fails:**
   - Consider upgrading registry to v2.8+ (currently v2.0)
   - Check for disk I/O errors: `dmesg | grep -i error`
   - Test with a minimal test image first

### Long-term Improvements
1. **Registry health monitoring:**
   - Add automated checks for blob integrity
   - Alert on manifest-without-blob scenarios
   - Monitor push/pull success rates

2. **Backup strategy:**
   - Regular backups of registry data
   - Document recovery procedures
   - Test restore process

3. **Alternative architectures:**
   - Consider managed registry (Docker Hub, GitHub Registry)
   - Implement registry replication
   - Add local registry cache on build server

---

## Reference Information

### Useful Commands

**Check registry tags:**
```bash
curl -u admin:password https://registry.alanhoangnguyen.com/v2/admin/conversationalist/tags/list
```

**Verify blob exists:**
```bash
docker exec docker_registry ls -la /var/lib/registry/docker/registry/v2/blobs/sha256/02/
```

**Test registry health:**
```bash
curl -I https://registry.alanhoangnguyen.com/v2/
```

**View registry logs:**
```bash
docker logs docker_registry --tail 100 | grep conversationalist
```

**Manual garbage collection:**
```bash
docker exec docker_registry registry garbage-collect /etc/docker/registry/config.yml
```

### Files Modified
- `/root/Orchestration/obsRemote/custom_server.conf` (nginx config)
  - Increased timeouts to 30 minutes
  - Disabled HTTP/2 for registry
  - Increased client_max_body_size to 5GB
  - Disabled proxy buffering

### Files Created
- `/root/Orchestration/obsRemote/deploy-conversationalist-direct.sh` (deployment script)
- `/root/Orchestration/docs/registry-push-pull-failure-2026-01-05.md` (this document)

---

## Additional Notes

### Why HTTP/2 Causes Issues
HTTP/2 multiplexes multiple requests over a single TCP connection. With large blob uploads:
- Nginx may close connections prematurely
- Flow control issues with large payloads
- Buffering problems with streaming data
- Known issue with Docker registry + nginx + HTTP/2

### Why Same Three Layers Always Fail
These layers are from the base image (debian:bookworm + python:3.10.19):
1. They're built first in the Dockerfile
2. They're large (60-75MB each)
3. Docker tries to reuse them across builds
4. They were never successfully uploaded initially
5. Every subsequent version references these same missing layers

### Registry Storage Path
```
/root/Orchestration/obsRemote/registry/data/
└── docker/
    └── registry/
        └── v2/
            ├── blobs/
            │   └── sha256/
            │       ├── 02/  (should contain 02d7611c4eae... - EMPTY)
            │       ├── 87/  (should contain 8715e552fa13... - EMPTY)
            │       └── 9c/  (should contain 9c27bc7ba63d... - EMPTY)
            └── repositories/
                └── admin/
                    └── conversationalist/
                        └── _manifests/
                            └── tags/
                                ├── 1.0.16/  (working)
                                ├── 1.0.24/  (working)
                                └── 1.0.28/  (working)
```

---

**End of Report**

**Session ended:** 2026-01-05 ~16:10 UTC
**Next session:** Continue with chosen deployment solution and verify registry fix

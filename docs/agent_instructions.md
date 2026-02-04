# Agent Instructions - Fix Docker Pull Issue

## Current Problem
The deployment is stuck because Docker cannot pull the image from the private registry. The production server's Docker daemon keeps getting "unexpected EOF" errors.

## What You Need to Do

1. **Investigate the Docker pull failure**
   - Check why `docker pull registry.alanhoangnguyen.com/admin/conversationalist:1.0.29` fails
   - Look at Docker daemon logs: `journalctl -u docker.service -f`
   - Try different approaches to pull the image

2. **Test registry connectivity**
   - Verify authentication works: `docker login registry.alanhoangnguyen.com`
   - Check if you can list repositories
   - Try pulling with verbose logging

3. **Alternative Solutions to Try**
   - Pull with `--platform linux/amd64` flag
   - Use `docker buildx` to create and push a multi-platform image
   - Try pulling individual layers manually
   - Check if there's a proxy or network issue

4. **Once Pull Works**
   - Complete the deployment using the existing deployment script
   - Verify the container starts with version 1.0.29
   - Run health check to confirm it's working

## Success Criteria
- Docker image pulls successfully from registry.alanhoangnguyen.com
- Container starts with conversationalist version 1.0.29
- Health endpoint returns version 1.0.29
- Service is accessible at https://conversationalist.alanhoangnguyen.com/health

## Files to Reference
- `/root/Orchestration/docs/deployment_issue_2026-01-05.md` - Detailed problem description
- The deployment scripts in the build directory
- Docker compose file: `run_obsidian_remote.yml`

The image is already built and pushed successfully - the issue is purely with pulling it to the production server.
#!/bin/bash
# Direct deployment script - bypasses registry
# Run this on the build server and transfer to production

IMAGE_NAME="conversationalist"
VERSION="1.0.30"
ARCHIVE_NAME="${IMAGE_NAME}-${VERSION}.tar.gz"

echo "=== Saving Docker image to archive ==="
docker save registry.alanhoangnguyen.com/admin/${IMAGE_NAME}:${VERSION} | gzip > ${ARCHIVE_NAME}

echo "=== Archive created: ${ARCHIVE_NAME} ==="
ls -lh ${ARCHIVE_NAME}

echo ""
echo "=== Next steps ==="
echo "1. Transfer to production:"
echo "   scp ${ARCHIVE_NAME} production-server:/tmp/"
echo ""
echo "2. On production server, run:"
echo "   cd /root/Orchestration/obsRemote"
echo "   docker load < /tmp/${ARCHIVE_NAME}"
echo "   source script/sourceEnv.sh"
echo "   docker compose -f run_obsidian_remote.yml up -d --force-recreate conversationalist"
echo "   rm /tmp/${ARCHIVE_NAME}"

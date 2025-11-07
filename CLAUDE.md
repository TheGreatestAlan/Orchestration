# Claude Code Project Instructions - Orchestration Repository

## Project Overview

This is the **Orchestration** repository on production. It contains Docker Compose configurations for managing containerized services across multiple environments.

## Repository Structure

```
Orchestration/
├── .claude/
│   └── settings.local.json    # Claude Code configuration
├── obsRemote/                  # Main production Docker Compose system
│   ├── run_obsidian_remote.yml # Primary compose file (11 services)
│   ├── custom_server.conf      # Nginx reverse proxy configuration
│   ├── script/                 # Management scripts
│   ├── dev/                    # Production environment variables
│   │   └── docker-compose.env  # CRITICAL: Source of truth for all env vars
│   ├── agent-server/           # Agent server data
│   ├── npm/                    # Nginx Proxy Manager data
│   ├── registry/               # Docker registry storage
│   ├── certbot-scripts/        # SSL certificate renewal
│   └── docs/                   # Documentation
├── docker-compose.yml          # Root level compose (legacy/simple setup)
├── CLAUDE.md                   # This file
└── README.md                   # Project overview
```

## Key Documentation

- **`obsRemote/README.md`** - Comprehensive production system documentation (300+ lines)
- **`obsRemote/CLAUDE.md`** - Detailed technical guide for working with the production system
- **`README.md`** - High-level project description
- **`obsRemote/docs/task-log/`** - Task completion logs and session handoffs

## Working with This Repository

### Primary System: obsRemote

The main production system is in the `obsRemote/` directory. It manages 11 containerized services with SSL, VPN, private registries, and AI agents.

**Always work from the obsRemote directory:**
```bash
cd /root/Orchestration/obsRemote
```

**Environment variables are MANDATORY:**
```bash
# Source environment before any docker compose command
source script/sourceEnv.sh
```

**Common operations:**
```bash
# Start services
./script/setEnvAndRun.sh

# View logs
./script/see-logs.sh <service-name>
./script/see-logs.sh -t <service-name>  # tail mode

# Shell into container
./script/shell-into.sh <service-name> [shell]

# Update images
./script/pullNewImages.sh

# Stop services
./script/down.sh
```

### Root Level docker-compose.yml

A simpler setup with 3 services:
- web
- organizerserver
- updater

This appears to be a legacy or alternative configuration.

## Development Best Practices

### Context Management

- Use `/clear` between different tasks to maintain focus
- This CLAUDE.md file is automatically loaded for context
- Refer to `obsRemote/README.md` and `obsRemote/CLAUDE.md` for detailed operational guidance

### Git Integration

Standard git workflow:

```bash
# Standard commit messages
git commit -m "feat: implement feature"
git commit -m "fix: resolve issue"
git commit -m "refactor: improve code structure"

# Create PR for feature (if using gh CLI)
gh pr create --title "Feature: Description" --body "Implementation details"
```

Current git status shows:
- Modified: `obsRemote/run_obsidian_remote.yml`
- Untracked: Various new documentation and configuration files

## Production Services Overview

The `obsRemote/` system runs 11 containerized services:

### Core Services
- **agent-server** - Multi-model LLM support (Fireworks, OpenAI), REST + WebSocket
- **organizerserver** - Git repository and Obsidian vault management
- **updater** - Obsidian vault synchronization
- **translator** - Fireworks AI translation service
- **open-webui** - Web UI for LLM interaction

### Infrastructure
- **nginx_proxy_manager** - Reverse proxy with SSL termination
- **certbot** - Automated SSL certificate renewal (every 12 hours)
- **wireguard** - VPN server for secure remote access
- **scheduler** - Task scheduling and automation
- **n8n** - Workflow automation platform

### Registry Services
- **docker-registry** - Private Docker image registry at registry.alanhoangnguyen.com
- **pypi-server** - Private Python package repository at helper.alanhoangnguyen.com/pypi/

### Domains Served
- alanhoangnguyen.com
- openwebui.alanhoangnguyen.com
- helper.alanhoangnguyen.com
- n8n.alanhoangnguyen.com
- registry.alanhoangnguyen.com
- flofluent.com

## Task Documentation Standards

When completing tasks, create documentation in `obsRemote/docs/task-log/` following these formats:

#### Task Completion Documents (`task-XX-completion.md`)

Structure for completed task documentation:

```markdown
# Task XX – [Task Title] — COMPLETED

## Overview
[Brief description of what was accomplished and why it matters]

## What Changed

### [Section 1: e.g., Server-Side Changes]
**`file_path/file.py`**
- **[Change Type]**: [Description of what changed]
- **[Change Type]**: [Another change with details]

### [Section 2: e.g., Client-Side Changes] 
**`another_file.py`**
- **[Change Type]**: [Description]

## Architecture Achievement
### [Feature Name] ✅
- **Before**: [Previous state]
- **After**: [New state with code examples if relevant]

## Test Results
### Manual Testing
- ✅ [Test scenario] works
- ✅ [Another test] functions correctly

## Key Technical Improvements
### Code Quality
- **[Improvement Type]**: [Description]

### Performance  
- **[Improvement Type]**: [Description]

### Maintainability
- **[Improvement Type]**: [Description]

## What's Next
[Describe what this unblocks or enables]

## Status
✅ **COMPLETED** — [Summary of completion]
```

#### Bridge to Tomorrow Documents (`task-XX-bridge-to-tomorrow-YYYY-MM-DD.md`)

Structure for end-of-session handoff documentation:

```markdown
# Task XX – Bridge to Tomorrow

## Where we are
- [Current state bullet points]
- [What's implemented and working]
- [What's partially complete]

## What's left in Task XX
- [Remaining work items]
- [Known issues to address]
- [Testing gaps to fill]

## Likely root causes to verify
- [Hypotheses about current issues]
- [Areas that need investigation]

## Concrete next steps (tomorrow)
1. [Specific actionable step]
2. [Another specific step with details]
3. [Continue numbered list]

## Out of scope (deferred to next tasks)
- [Items intentionally not included]
- [Future task references]

## Notes
- [Important context for future work]
- [Technical decisions made]
- [Temporary measures in place]
```

#### Naming Convention
- Completion: `task-XX-completion.md`
- Bridge: `task-XX-bridge-to-tomorrow-YYYY-MM-DD.md` (use `date +%Y-%m-%d`)
- Use actual task numbers when available, or descriptive names for ad-hoc tasks

## Important Notes

### Configuration Safety

**ALWAYS backup before modifying critical files:**
```bash
# Backup docker compose file
cp obsRemote/run_obsidian_remote.yml obsRemote/run_obsidian_remote.yml.backup-$(date +%Y%m%d_%H%M%S)

# Backup environment variables
cp obsRemote/dev/docker-compose.env obsRemote/dev/docker-compose.env.backup-$(date +%Y%m%d_%H%M%S)

# Backup nginx configuration
cp obsRemote/custom_server.conf obsRemote/custom_server.conf.backup-$(date +%Y%m%d_%H%M%S)
```

### Service Restart Protocol

When updating services:
1. Pull new images if needed
2. Test configuration: `docker compose -f run_obsidian_remote.yml config`
3. Update single service: `docker compose -f run_obsidian_remote.yml up -d --force-recreate --no-deps <service>`
4. Check logs immediately: `./script/see-logs.sh <service>`

### SSL Certificate Management

- ALL certificates managed automatically by certbot container
- Certificates shared between certbot and nginx via `npm/letsencrypt/` volume
- Renewal happens every 12 hours automatically
- Manual intervention rarely needed

## Quick Reference

**For detailed operational instructions, always refer to:**
- `obsRemote/README.md` - System architecture and operations
- `obsRemote/CLAUDE.md` - Technical deep dive and troubleshooting

**Key directories:**
- `obsRemote/dev/docker-compose.env` - Environment variables (source of truth)
- `obsRemote/script/` - Helper scripts for all operations
- `obsRemote/docs/task-log/` - Task documentation and session handoffs

---

_This CLAUDE.md is specific to the Orchestration repository and its production Docker Compose system._
# pyMC UI Release Guide

Complete guide for developers to create and publish new releases of the pyMC UI.

## Table of Contents
- [Quick Release Steps](#quick-release-steps)
- [Understanding the Release Process](#understanding-the-release-process)
- [Manual Build Process](#manual-build-process)
- [Troubleshooting](#troubleshooting)
- [Version Numbering](#version-numbering)

---

## Quick Release Steps

For experienced developers, here's the TL;DR:

```bash
cd pymc_console/frontend

# 1. Update version (creates git tag automatically if configured)
npm version patch

# 2. Push changes and tag
git push origin main
git push origin --tags

# Done! Check GitHub Actions for build status
```

---

## Understanding the Release Process

### What Happens Automatically

This project uses **GitHub Actions** for continuous integration and deployment:

#### On Every Push to `main` or `dev`:
- ✅ Installs dependencies
- ✅ Builds static files (`npm run build:static`)
- ✅ Creates versioned `.tar.gz` and `.zip` archives
- ✅ Uploads build artifacts to GitHub (available for 30 days)
- ❌ Does NOT create a GitHub Release

#### On Version Tag Push (e.g., `v0.1.1`):
- ✅ Everything above, PLUS
- ✅ Creates a GitHub Release
- ✅ Attaches downloadable archives to the release
- ✅ Generates automatic release notes from commits

### The Workflow File

Located at: `.github/workflows/build-ui.yml`

This workflow has two jobs:
1. **build** - Runs on all pushes and PRs
2. **release** - Only runs when a tag starting with `v` is pushed

---

## Detailed Release Steps

### Step 1: Make Your Changes

Work on your feature branch as normal:
```bash
git checkout -b feature/my-new-feature
# ... make changes ...
git add .
git commit -m "feat: add awesome new feature"
git push origin feature/my-new-feature
```

Create a PR, get it reviewed, and merge to `main`.

### Step 2: Decide on Version Number

Use [Semantic Versioning](https://semver.org/):
- **MAJOR** (`1.0.0` → `2.0.0`) - Breaking changes
- **MINOR** (`0.1.0` → `0.2.0`) - New features, backwards compatible
- **PATCH** (`0.1.1` → `0.1.2`) - Bug fixes only

### Step 3: Update Version

Navigate to the frontend directory:
```bash
cd pymc_console/frontend
```

Run the appropriate npm version command:
```bash
# For bug fixes
npm version patch

# For new features
npm version minor

# For breaking changes
npm version major

# For pre-releases
npm version prerelease --preid=beta
```

**What this does:**
- Updates `version` in `package.json` and `package-lock.json`
- Creates a git commit with message like "0.1.2"
- Creates a git tag like `v0.1.2` (if git is configured properly)

### Step 4: Push Changes and Tags

Push your version commit:
```bash
git push origin main
```

Push the tag to trigger the release:
```bash
git push origin --tags
```

Or push a specific tag:
```bash
git push origin v0.1.2
```

### Step 5: Monitor the Release

1. Go to your repository on GitHub
2. Click the **Actions** tab
3. You should see a workflow running for your tag
4. Wait for both jobs (build and release) to complete

### Step 6: Verify the Release

Once the workflow completes:

1. Go to the **Releases** section of your GitHub repo
2. You should see your new release (e.g., `v0.1.2`)
3. It should have two attached files:
   - `pymc-ui-v0.1.2.tar.gz`
   - `pymc-ui-v0.1.2.zip`
4. Release notes are auto-generated from commit messages

---

## Manual Build Process

If you need to build locally without creating a release:

```bash
cd pymc_console/frontend

# Install dependencies (first time only)
npm install

# Build static files
npm run build:static
```

The output will be in `frontend/dist/` directory.

### What the Build Does

1. `vite build` - Compiles React app to static HTML/CSS/JS
2. Outputs to `frontend/out/`
3. Copies `out/` contents to `frontend/dist/`

---

## Troubleshooting

### "Release job was skipped"

**Problem:** You pushed code but no GitHub Release was created.

**Solution:** The release job only runs for version tags. Make sure you:
1. Created a tag with `npm version` or `git tag v0.1.x`
2. Pushed the tag with `git push origin --tags`
3. The tag name starts with `v` (e.g., `v0.1.2`, not `0.1.2`)

### "Build failed: npm ERR! code ELIFECYCLE"

**Problem:** The build process failed.

**Solution:** 
1. Pull the latest code: `git pull origin main`
2. Clean install locally: `cd frontend && rm -rf node_modules package-lock.json && npm install`
3. Test build locally: `npm run build:static`
4. Fix any errors before pushing

### "Tag already exists"

**Problem:** You tried to create a tag that already exists.

**Solution:**
```bash
# Delete local tag
git tag -d v0.1.2

# Delete remote tag (if already pushed)
git push origin :refs/tags/v0.1.2

# Create new tag
npm version patch
git push origin --tags
```

### "Permission denied" when creating release

**Problem:** GitHub Actions doesn't have permission to create releases.

**Solution:** The workflow already has `permissions: contents: write` set. Check your repository settings:
1. Go to Settings → Actions → General
2. Under "Workflow permissions", ensure "Read and write permissions" is selected

---

## Version Numbering

### Semantic Versioning Format

`MAJOR.MINOR.PATCH` (e.g., `0.1.2`)

### When to Increment Each Part

| Change Type | Example | Command | Version Change |
|-------------|---------|---------|----------------|
| Bug fix | Fix broken map display | `npm version patch` | `0.1.1` → `0.1.2` |
| New feature | Add dark mode | `npm version minor` | `0.1.2` → `0.2.0` |
| Breaking change | Require new API version | `npm version major` | `0.2.0` → `1.0.0` |
| Pre-release | Beta testing | `npm version prerelease --preid=beta` | `0.1.2` → `0.1.3-beta.0` |

### Pre-release Tags

For alpha, beta, or release candidate versions:

```bash
# First beta
npm version 0.2.0-beta.1

# Subsequent betas
npm version prerelease --preid=beta  # 0.2.0-beta.2

# Release candidate
npm version 0.2.0-rc.1

# Final release
npm version 0.2.0
```

Pre-releases are automatically marked as "Pre-release" on GitHub.

---

## End User Deployment

Once a release is published, end users can deploy it:

### Download and Extract

```bash
# Download latest release
wget https://github.com/dmduran12/pymc_console/releases/download/v0.2.0/pymc-ui-v0.2.0.tar.gz

# Extract to pyMC_Repeater's web directory
tar -xzf pymc-ui-v0.2.0.tar.gz -C /opt/pymc_repeater/repeater/web/html/

# Or use zip
unzip pymc-ui-v0.2.0.zip -d /opt/pymc_repeater/repeater/web/html/
```

### Configure Backend

The backend (pyMC_API) should be configured to serve these static files. Users control where they deploy the UI files.

---

## Quick Reference Commands

```bash
# View current version
cat frontend/package.json | grep version

# List all tags
git tag --list

# View latest tag
git describe --tags --abbrev=0

# Delete local tag
git tag -d v0.1.2

# Delete remote tag
git push origin :refs/tags/v0.1.2

# Create tag manually (if npm version didn't work)
git tag v0.1.2
git push origin v0.1.2

# Check GitHub Actions status
# Visit: https://github.com/dmduran12/pymc_console/actions
```

---

## Need Help?

- Check GitHub Actions logs for detailed error messages
- Review commit messages to ensure they follow conventions
- Test builds locally before pushing tags
- Ask in the project's discussion forum or issues section

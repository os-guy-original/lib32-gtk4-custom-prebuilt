# GitHub Actions Token Setup

## Default GITHUB_TOKEN Limitations

The default `GITHUB_TOKEN` provided by GitHub Actions has restricted permissions by default:
- It can read repositories
- It can write to releases and tags
- It **cannot** push directly to branches (like `main`)

## Options for Enabling Push

### Option 1: Use Workflow Permissions (Recommended for Releases)

The workflow already includes:
```yaml
permissions:
  contents: write
```

This is sufficient for:
- Creating and uploading releases
- Pushing tags
- The release job should work

### Option 2: Use a Personal Access Token (PAT)

If you need to push directly to the `main` branch:

1. **Create a PAT:**
   - Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Click "Generate new token (classic)"
   - Give it a name like "CI Push Token"
   - Select scope: `repo` (full control)
   - Copy the generated token

2. **Add as Repository Secret:**
   - Go to Repository Settings → Secrets and variables → Actions
   - Click "New repository secret"
   - Name: `PAT`
   - Value: Paste your PAT

3. **Update the workflow:**
   Find the push step and change:
   ```yaml
   env:
     GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
   ```
   to:
   ```yaml
   env:
     GITHUB_TOKEN: ${{ secrets.PAT }}
   ```

### Option 3: Grant Workflow Repository Permissions

1. Go to Repository Settings → Actions → General
2. Under "Workflow permissions", select "Read and write"
3. Save

This allows the default `GITHUB_TOKEN` to push to branches.

## Security Note

Never commit a PAT directly in the workflow file. Always use GitHub secrets.

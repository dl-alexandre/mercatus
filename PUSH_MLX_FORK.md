# Push MLX Fork to GitHub

The fix has been committed locally in `/tmp/mlx-swift-fork`.

## Steps to Push:

1. **Fork MLX Swift on GitHub** (if not already done):
   - Go to https://github.com/ml-explore/mlx-swift
   - Click "Fork"

2. **Push the branch**:
   ```bash
   cd /tmp/mlx-swift-fork
   git remote set-url origin https://github.com/dl-alexandre/mlx-swift.git
   git push -u origin fix/macos26-m3pro-sigill
   ```

3. **After pushing, test in mercatus**:
   ```bash
   cd /Users/developer/mercatus
   swift package resolve
   swift build -c release
   swift run -c release SmartVestorCLI coins --limit 1
   ```

4. **Look for the diagnostic message**:
   ```
   [MLX] Applied M3 Pro SIGILL mitigation
   ```

If you see this message and the app runs without SIGILL, the fix is working!

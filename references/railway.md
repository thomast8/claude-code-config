# Railway deployment

Main rules: prefer Railpack (zero-config, 38-77% smaller images). Fall back to Dockerfile for multi-language monorepos or custom system deps. Railway sets `PORT` dynamically — use shell-form CMD.

## CLI commands

```bash
railway init --name "project-name"    # Create project
railway up -d                          # Deploy from current dir (detached)
railway service link <name>            # Link to the created service
railway domain                         # Generate public URL
railway volume add -m /app/data        # Add persistent volume
railway service status                 # Check deployment status
railway logs --build                   # View build logs
railway logs                           # View runtime logs
```

## Dockerfile PORT example

```dockerfile
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT}
```

Shell-form CMD is required — exec-form `CMD ["uvicorn", ..., "--port", "${PORT}"]` doesn't expand the variable.

## When to use Dockerfile over Railpack

- Monorepo single-service with multi-language build stages
- Custom system dependencies (apt packages, etc.) that Railpack auto-detection doesn't cover
- Existing image that already works on other platforms

Otherwise start with Railpack — the auto-detection for FastAPI, Vite, Next.js, etc. is good.

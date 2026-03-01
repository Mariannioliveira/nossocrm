# ===================================================================
# NossoCRM — Dockerfile para Coolify / Docker
# ===================================================================
# Build em 3 estágios:
#   deps     → instala dependências npm
#   builder  → compila o Next.js (produção)
#   runner   → imagem final mínima com o servidor standalone
# ===================================================================

# ── Estágio 1: Dependências ─────────────────────────────────────────
FROM node:20-alpine AS deps

# libc6-compat necessário para algumas dependências nativas no Alpine
RUN apk add --no-cache libc6-compat

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

# ── Estágio 2: Build ────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Variáveis NEXT_PUBLIC_* são embutidas no bundle durante o build.
# Devem ser passadas como build args pelo Coolify (Settings → Build Variables).
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY

ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL
ENV NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=$NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

RUN npm run build

# ── Estágio 3: Runner (imagem de produção) ──────────────────────────
FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Cria usuário sem privilégios para rodar a aplicação
RUN addgroup --system --gid 1001 nodejs \
 && adduser  --system --uid 1001 nextjs

# Copia os assets públicos
COPY --from=builder /app/public ./public

# Cria a pasta .next com permissão correta para o cache do Next.js
RUN mkdir .next && chown nextjs:nodejs .next

# O output 'standalone' já inclui node_modules otimizados
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static    ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# server.js é gerado automaticamente pelo next build com output: 'standalone'
CMD ["node", "server.js"]

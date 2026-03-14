-- Per-service roles (no superuser)
-- Note: Replace password variables with secure ones via environment injection during deployment
-- (These will be populated automatically by docker-compose)
CREATE ROLE chat_app LOGIN PASSWORD '${CHAT_DB_PASSWORD}';
CREATE ROLE rag_app  LOGIN PASSWORD '${RAG_DB_PASSWORD}';

-- Grant CREATEDB so applications can manage their own schemas and migrations
ALTER ROLE chat_app CREATEDB;
ALTER ROLE rag_app CREATEDB;

-- Install pgvector in the public schema for shared use
-- Requires the pgvector/pgvector image
CREATE EXTENSION IF NOT EXISTS vector;

-- Initialize zendb
CREATE DATABASE zendb;
\c zendb;
CREATE EXTENSION IF NOT EXISTS vector;

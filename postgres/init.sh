#!/bin/bash
set -euo pipefail

# This script runs as the postgres superuser inside the container.
# The PostgreSQL Docker entrypoint executes .sh files as bash, so env vars
# are properly interpolated — unlike .sql files which are passed raw to psql.

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    -- =========================================================
    -- chat-api: role + database + schema isolation
    -- =========================================================
    CREATE ROLE chat_app LOGIN PASSWORD '${CHAT_DB_PASSWORD}';
    CREATE DATABASE chatdb OWNER chat_app;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "chatdb" <<-SQL
    CREATE SCHEMA chat AUTHORIZATION chat_app;
    GRANT USAGE ON SCHEMA chat TO chat_app;
    GRANT ALL ON ALL TABLES IN SCHEMA chat TO chat_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA chat GRANT ALL ON TABLES TO chat_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA chat GRANT ALL ON SEQUENCES TO chat_app;
    CREATE EXTENSION IF NOT EXISTS vector;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    -- =========================================================
    -- rag-service: role + database + schema isolation
    -- =========================================================
    CREATE ROLE rag_app LOGIN PASSWORD '${RAG_DB_PASSWORD}';
    CREATE DATABASE ragdb OWNER rag_app;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "ragdb" <<-SQL
    CREATE SCHEMA rag AUTHORIZATION rag_app;
    GRANT USAGE ON SCHEMA rag TO rag_app;
    GRANT ALL ON ALL TABLES IN SCHEMA rag TO rag_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA rag GRANT ALL ON TABLES TO rag_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA rag GRANT ALL ON SEQUENCES TO rag_app;
    CREATE EXTENSION IF NOT EXISTS vector;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    -- =========================================================
    -- zendesk-agent-api: role + database + schema isolation
    -- =========================================================
    CREATE ROLE zendesk_app LOGIN PASSWORD '${ZENDESK_DB_PASSWORD}';
    CREATE DATABASE zendb OWNER zendesk_app;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "zendb" <<-SQL
    CREATE SCHEMA zendesk AUTHORIZATION zendesk_app;
    GRANT USAGE ON SCHEMA zendesk TO zendesk_app;
    GRANT ALL ON ALL TABLES IN SCHEMA zendesk TO zendesk_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA zendesk GRANT ALL ON TABLES TO zendesk_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA zendesk GRANT ALL ON SEQUENCES TO zendesk_app;
    CREATE EXTENSION IF NOT EXISTS vector;
SQL

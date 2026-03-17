#!/bin/bash
set -euo pipefail

# This script runs as the postgres superuser inside the container.
# The PostgreSQL Docker entrypoint executes .sh files as bash, so env vars
# are properly interpolated — unlike .sql files which are passed raw to psql.

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    CREATE DATABASE meowdb;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "meowdb" <<-SQL
    -- Extensions
    CREATE EXTENSION IF NOT EXISTS vector;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

    -- =========================================================
    -- zenconnect_app (zendesk-agent-api)
    -- =========================================================
    CREATE ROLE zenconnect_app LOGIN PASSWORD '${ZENCONNECT_DB_PASSWORD}';
    CREATE SCHEMA zenconnect AUTHORIZATION zenconnect_app;
    GRANT CONNECT ON DATABASE meowdb TO zenconnect_app;
    GRANT USAGE ON SCHEMA zenconnect TO zenconnect_app;
    GRANT ALL ON ALL TABLES IN SCHEMA zenconnect TO zenconnect_app;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA zenconnect TO zenconnect_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA zenconnect GRANT ALL ON TABLES TO zenconnect_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA zenconnect GRANT ALL ON SEQUENCES TO zenconnect_app;
    ALTER ROLE zenconnect_app SET search_path TO zenconnect;

    -- =========================================================
    -- meowrag_app (rag-api / meowRAG)
    -- =========================================================
    CREATE ROLE meowrag_app LOGIN PASSWORD '${MEOWRAG_DB_PASSWORD}';
    CREATE SCHEMA meowrag AUTHORIZATION meowrag_app;
    GRANT CONNECT ON DATABASE meowdb TO meowrag_app;
    GRANT USAGE ON SCHEMA meowrag TO meowrag_app;
    GRANT ALL ON ALL TABLES IN SCHEMA meowrag TO meowrag_app;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA meowrag TO meowrag_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA meowrag GRANT ALL ON TABLES TO meowrag_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA meowrag GRANT ALL ON SEQUENCES TO meowrag_app;
    ALTER ROLE meowrag_app SET search_path TO meowrag;

    -- Lock down public schema
    REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SQL

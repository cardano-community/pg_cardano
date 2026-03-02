-- Initialize pg_cardano extension for local development
-- This script runs automatically when PostgreSQL starts

\echo 'Creating pg_cardano extension...'

-- Create the extension
CREATE EXTENSION IF NOT EXISTS pg_cardano;

-- Create a test schema
CREATE SCHEMA IF NOT EXISTS cardano_dev;

-- Grant usage on the cardano schema to postgres user
GRANT USAGE ON SCHEMA cardano TO postgres;
GRANT USAGE ON SCHEMA cardano_dev TO postgres;

-- Test basic functionality
\echo 'Testing basic extension functionality...'

-- Test Base58 encoding
SELECT 'Base58 Test:' as test, cardano.base58_encode('Hello Cardano'::bytea) as result;

-- Test Blake2b hashing
SELECT 'Blake2b Test:' as test, encode(cardano.blake2b_hash('test message'::bytea, 32), 'hex') as result;

-- Test Bech32 encoding
SELECT 'Bech32 Test:' as test, cardano.bech32_encode('addr', 'test data'::bytea) as result;

\echo 'pg_cardano extension initialized successfully!'
\echo 'You can now connect and use all cardano.* functions.'
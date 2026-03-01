\echo 'Starting pg_cardano extension test suite...'

SELECT 'Extension Status' as test_category,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END as result
FROM pg_extension 
WHERE extname = 'pg_cardano';

\echo 'Testing Base58 functions...'
SELECT 'Base58 Encode' as test_name,
       CASE WHEN cardano.base58_encode('Cardano'::bytea) = '3Z6ioYHE3x' 
            THEN 'PASS' ELSE 'FAIL' END as result;

SELECT 'Base58 Decode' as test_name,
       CASE WHEN cardano.base58_decode('3Z6ioYHE3x') = 'Cardano'::bytea 
            THEN 'PASS' ELSE 'FAIL' END as result;

\echo 'Testing Bech32 functions...'
SELECT 'Bech32 Encode' as test_name,
       CASE WHEN cardano.bech32_encode('ada', 'is amazing'::bytea) = 'ada1d9ejqctdv9axjmn8dypl4d'
            THEN 'PASS' ELSE 'FAIL' END as result;

SELECT 'Bech32 Decode Prefix' as test_name,
       CASE WHEN cardano.bech32_decode_prefix('ada1d9ejqctdv9axjmn8dypl4d') = 'ada'
            THEN 'PASS' ELSE 'FAIL' END as result;

\echo 'Testing Blake2b hashing...'
SELECT 'Blake2b Hash' as test_name,
       CASE WHEN length(cardano.blake2b_hash('test'::bytea, 32)) = 32
            THEN 'PASS' ELSE 'FAIL' END as result;

\echo 'Testing CBOR functions...'
SELECT 'CBOR Simple Decode' as test_name,
       CASE WHEN cardano.cbor_decode_jsonb('\xa1636b6579655f616c7565') IS NOT NULL
            THEN 'PASS' ELSE 'FAIL' END as result;

\echo 'Testing Ed25519 functions...'
SELECT 'Ed25519 Sign' as test_name,
       CASE WHEN length(cardano.ed25519_sign_message(
               '\x43D68AECFA7B492F648CE90133D10A97E4300FB3C08B5D843F05BDA7EF53B3E3'::bytea,
               'test message'::bytea)) = 64
            THEN 'PASS' ELSE 'FAIL' END as result;

\echo 'Testing utility functions...'
SELECT 'Asset Name Conversion' as test_name,
       CASE WHEN cardano.tools_read_asset_name('hello'::bytea) = 'hello'
            THEN 'PASS' ELSE 'FAIL' END as result;

\echo 'Running performance test...'
SELECT 'Performance Test' as test_name,
       CASE WHEN (SELECT COUNT(*) FROM (
           SELECT cardano.blake2b_hash(('test' || generate_series(1,1000))::bytea, 32)
       ) t) = 1000
            THEN 'PASS' ELSE 'FAIL' END as result;

\echo 'Checking function availability...'
SELECT 'Function Count' as test_name,
       CASE WHEN COUNT(*) >= 20 THEN 'PASS' ELSE 'FAIL' END as result
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'cardano';

\echo 'Available cardano functions:'
SELECT proname as function_name
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'cardano'
ORDER BY proname;

\echo 'pg_cardano extension test suite completed!'
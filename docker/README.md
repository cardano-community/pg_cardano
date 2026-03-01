# Docker Setup for pg_cardano Extension

Docker configuration for building and deploying the pg_cardano PostgreSQL extension  
as a container compatible with CloudNativePG (CNPG).

## Overview

The Docker setup creates a container that packages the pg_cardano extension in a format that can be mounted  
as a K8s ImageVolume in CloudNativePG clusters. This follows the [postgres-extensions-containers](https://github.com/cloudnative-pg/postgres-extensions-containers) pattern.

## Building the Extension Container

### Prerequisites

- Docker or Podman
- Access to pull Ubuntu 22.04 base images

### Build Command

```bash
# From the project root directory
# Build for PostgreSQL 18.1 (default)
docker build -f docker/Dockerfile -t pg_cardano-extension:pg18.1 .

# Build for PostgreSQL 17.9
docker build -f docker/Dockerfile \
  --build-arg PG_VERSION=17 \
  --build-arg PG_VERSION_FULL=17.9 \
  -t pg_cardano-extension:pg17.9 .

# Build for PostgreSQL 16.13
docker build -f docker/Dockerfile \
  --build-arg PG_VERSION=16 \
  --build-arg PG_VERSION_FULL=16.13 \
  -t pg_cardano-extension:pg16.13 .

# Build all supported versions at once
cd docker && ./build-all.sh
```

### Build Process

The Dockerfile uses a multi-stage build:

1. **Builder Stage**: Compiles the Rust extension using cargo-pgrx on Ubuntu 22.04
2. **Extractor Stage**: Organizes extension files into the correct directory structure
3. **Final Stage**: Creates a minimal scratch container with only the extension files

The final container contains:
- Extension shared libraries (`*.so`) in `/usr/lib/postgresql/{VERSION}/lib/`
- SQL files (`*.sql`) in `/usr/share/postgresql/{VERSION}/extension/`
- Control files (`*.control`) in `/usr/share/postgresql/{VERSION}/extension/`

### Supported PostgreSQL Versions

This container supports PostgreSQL versions:
- **16.13** (pg16)
- **17.9** (pg17) 
- **18.1** (pg18) - Default

Each version is built as a separate container image with their respective tags.

## Using with CloudNativePG

### 1. Push to Registry

First, push your built image to a container registry:

```bash
# Tag for your registry
docker tag pg_cardano-extension:pg18.1 cardano-community/pg_cardano-extension:pg18.1

# Push to registry
docker push cardano-community/pg_cardano-extension:pg18.1
```

### 2. Configure CNPG Cluster

Create a CloudNativePG cluster with the pg_cardano extension using the recommended ImageVolume approach:

```yaml
# cluster-with-pg-cardano.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-with-cardano
  namespace: default
spec:
  instances: 3
  
  postgresql:
    parameters:
      shared_preload_libraries: "pg_cardano"
    
  imageName: postgres:18.1
  
  # Extension container using ImageVolume (recommended)
  imageVolume:
    - name: pg-cardano-extension
      image: cardano-community/pg_cardano-extension:pg18.1

  storage:
    size: 10Gi
    storageClass: fast-ssd
```

### 3. Apply the Configuration

```bash
kubectl apply -f cluster-with-pg-cardano.yaml
```

### 4. Create the Extension in Database

Once the cluster is running, create a database and enable the extension:

```yaml
# database-with-cardano.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: cardano-db
  namespace: default
spec:
  name: cardano_test
  owner: postgres
  cluster:
    name: postgres-with-cardano
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cardano-init-script
  namespace: default
data:
  init.sql: |
    -- Create the pg_cardano extension
    CREATE EXTENSION IF NOT EXISTS pg_cardano;
    
    -- Test the extension
    SELECT cardano.base58_encode('Hello Cardano'::bytea);
```

Apply the database configuration:

```bash
kubectl apply -f database-with-cardano.yaml
```

### 5. Initialize the Extension

Connect to your database and run:

```sql
-- Enable the extension
CREATE EXTENSION pg_cardano;

-- Test basic functionality
SELECT cardano.base58_encode('Cardano'::bytea);
-- Should return: 3Z6ioYHE3x

-- Test Blake2b hashing
SELECT cardano.blake2b_hash('Cardano is amazing!'::bytea, 32);
```

## Alternative PostgreSQL Versions

For different PostgreSQL versions, specify the appropriate image tag:

```yaml
# PostgreSQL 17.9
imageName: postgres:17.9
imageVolume:
  - name: pg-cardano-extension
    image: cardano-community/pg_cardano-extension:pg17.9

# PostgreSQL 16.13  
imageName: postgres:16.13
imageVolume:
  - name: pg-cardano-extension
    image: cardano-community/pg_cardano-extension:pg16.13
```


## Using Prebuilt Registry Images

> ⚠️ **Warning**: The registry.2lovelaces.io registry should not be relied upon for production workloads as it is sometimes offline for regular maintenance.

For convenience, prebuilt pg_cardano extension images are available at `registry.2lovelaces.io`. These can be used directly without building the extension locally:

```yaml
# cluster-with-prebuilt-cardano.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-with-cardano
  namespace: default
spec:
  instances: 3
  
  postgresql:
    parameters:
      shared_preload_libraries: "pg_cardano"
    
  imageName: postgres:18.1
  
  # Using prebuilt extension from registry.2lovelaces.io
  imageVolume:
    - name: pg-cardano-extension
      image: registry.2lovelaces.io/pg_cardano-extension:pg18.1

  storage:
    size: 10Gi
    storageClass: fast-ssd
```

### Available Prebuilt Images

The following prebuilt images are available:

- `registry.2lovelaces.io/pg_cardano-extension:pg18.1` - PostgreSQL 18.1
- `registry.2lovelaces.io/pg_cardano-extension:pg17.9` - PostgreSQL 17.9
- `registry.2lovelaces.io/pg_cardano-extension:pg16.13` - PostgreSQL 16.13

## Verification

### Check Extension Availability

Connect to your PostgreSQL database and verify the extension:

```sql
-- List available extensions
SELECT * FROM pg_available_extensions WHERE name = 'pg_cardano';

-- Check if extension is installed
SELECT * FROM pg_extension WHERE extname = 'pg_cardano';

-- List all cardano functions
SELECT proname, prosrc 
FROM pg_proc 
WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'cardano');
```

### Test Extension Functions

```sql
-- Base58 encoding/decoding
SELECT cardano.base58_encode('test'::bytea);
SELECT cardano.base58_decode('3yZe7d');

-- Bech32 encoding/decoding  
SELECT cardano.bech32_encode('addr', 'test data'::bytea);

-- Blake2b hashing
SELECT cardano.blake2b_hash('test message'::bytea, 32);

-- CBOR operations
SELECT cardano.cbor_decode_jsonb('\xa1636b6579655f616c7565');
```

## Troubleshooting

### Common Issues

1. **Extension not found**: Verify the ImageVolume container was pulled and mounted correctly
2. **Permission denied**: Check that the extension files have correct permissions
3. **Version mismatch**: Ensure PostgreSQL and extension container versions match
4. **Image pull errors**: Confirm the extension container image exists in the registry

### Debug Commands

```bash
# Check if extension files are present
kubectl exec -it postgres-with-cardano-1 -- ls -la /usr/share/postgresql/18/extension/ | grep cardano
kubectl exec -it postgres-with-cardano-1 -- ls -la /usr/lib/postgresql/18/lib/ | grep cardano

# Check pod events for ImageVolume issues
kubectl describe pod postgres-with-cardano-1

# Check cluster status
kubectl get cluster postgres-with-cardano -o yaml

# Connect to database for testing
kubectl exec -it postgres-with-cardano-1 -- psql -U postgres
```

### Log Analysis

Check CNPG operator logs for extension loading issues:

```bash
kubectl logs -n cnpg-system deployment/cnpg-controller-manager
```

## Local Development

For local development and testing, use Docker Compose:

```bash
# Default PostgreSQL 18.1
cd docker && docker-compose up -d

# Different PostgreSQL versions
PG_VERSION=17 PG_VERSION_FULL=17.9 docker-compose up -d
PG_VERSION=16 PG_VERSION_FULL=16.13 docker-compose up -d

# With pgAdmin web interface
docker-compose --profile admin up -d  # Access at http://localhost:8080

# Run extension tests
docker-compose --profile test up test_runner

# Connect to database
psql -h localhost -U postgres -d cardano_test
```

The setup includes automatic extension building, multi-version PostgreSQL support (16, 17, 18), 
integrated test suite, and pgAdmin for database management.

## Security Considerations

- The extension container runs with minimal privileges
- Extension files are copied during initialization, not at runtime
- Consider using signed container images for production deployments
- The final container is built from scratch with no shell or package manager for minimal attack surface
- Regularly update the base Ubuntu image used in build stages for security patches

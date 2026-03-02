# Docker Setup for pg_cardano Extension

Docker configuration for building and deploying the pg_cardano PostgreSQL extension  
as an ImageVolume compatible with CloudNativePG (CNPG). This follows the [postgres-extensions-containers](https://github.com/cloudnative-pg/postgres-extensions-containers) pattern.

## Building the Extension Container

### Prerequisites

- Docker or Podman
- Access to pull Ubuntu 22.04 base images
- If you're deploying to kubernetes at least 1.33 with the ImageVolume featured flagged turned on.

### Architecture-Specific Builds (Recommended)

The build system creates separate images for different architectures (AMD64 and ARM64) to provide better compatibility and fix issues where native extension files (.so) are not executable in certain environments:

```bash
# From the project root directory
# Build for AMD64 architecture (default)
docker build -f docker/Dockerfile \
  --build-arg TARGETARCH=amd64 \
  -t pgcardano:1.2.0-pg18.1-linux-amd64-scratch .

# Build for ARM64 architecture
docker build -f docker/Dockerfile \
  --platform linux/arm64 \
  --build-arg TARGETARCH=arm64 \
  -t pgcardano:1.2.0-pg18.1-linux-arm64-scratch .

# Using the build script (recommended)
cd docker && ARCH=amd64 ./build.sh
cd docker && ARCH=arm64 PLATFORM=linux/arm64 ./build.sh

# Build all supported versions and architectures at once
cd docker && ./build-all.sh

# Build with legacy multi-arch approach (not recommended)
cd docker && BUILD_MULTI_ARCH=true ./build-all.sh
```

### Multi-Arch Build Command (Not Recommended)

```bash
# Multi-arch build (creates manifest pointing to multiple architectures)
docker buildx build -f docker/Dockerfile \
  --platform linux/amd64,linux/arm64 \
  -t pgcardano:1.2.0-pg18.1-scratch .
```

### Build Process

The Dockerfile uses a multi-stage build:

1. **Builder Stage**: Compiles the Rust extension using cargo-pgrx on Ubuntu 22.04
2. **Extractor Stage**: Organizes extension files into the correct directory structure
3. **Final Stage**: Creates a minimal scratch container with only the extension files

The final container contains:
- Extension shared libraries (`*.so`) in `/lib/`
- SQL files (`*.sql`) in `/share/extension/`
- Control files (`*.control`) in `/share/extension/`

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
# Tag platform-specific images for your registry 
docker tag pgcardano:1.2.0-pg18.1-linux-amd64-scratch cardano-community/pgcardano:1.2.0-pg18.1-linux-amd64-scratch
docker tag pgcardano:1.2.0-pg18.1-linux-arm64-scratch cardano-community/pgcardano:1.2.0-pg18.1-linux-arm64-scratch

# Push to registry
docker push cardano-community/pgcardano:1.2.0-pg18.1-linux-amd64-scratch
docker push cardano-community/pgcardano:1.2.0-pg18.1-linux-arm64-scratch

# For compatibility tags (platform-specific)
docker tag pgcardano-extension:pg18.1-linux-amd64 cardano-community/pgcardano-extension:pg18.1-linux-amd64
docker tag pgcardano-extension:pg18.1-linux-arm64 cardano-community/pgcardano-extension:pg18.1-linux-arm64
docker push cardano-community/pgcardano-extension:pg18.1-linux-amd64
docker push cardano-community/pgcardano-extension:pg18.1-linux-arm64

# Or use build script with push
cd docker && REGISTRY=cardano-community PUSH=true ./build-all.sh
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
    extensions:
      - name: pgvector
        image:
          reference: ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie
      - name: pgcardano
        image:
          reference: cardano-community/pgcardano:1.2.0-pg18.1-linux-amd64-scratch
          # reference: cardano-community/pgcardano:1.2.0-pg18.1-linux-arm64-scratch  # For ARM64 nodes

    parameters:
      shared_buffers: "2Gi"
    
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie
  imagePullPolicy: IfNotPresent

  storage:
    size: 10Gi
    storageClass: fast-ssd
```

### 3. Apply the Configuration

```bash
kubectl apply -f cluster-with-pg-cardano.yaml
```

### 4. Create the Extension in Database

This tells CloudNativePG to install and create the extension when the db is ready.

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
  extensions:
    - name: vector
      version: '0.8.1'
    - name: pg_cardano
      version: '1.2.0'
```

Apply the database configuration:

```bash
kubectl apply -f database-with-cardano.yaml
```

### 5. Initialize the Extension (Skip if you're using CloudNativePG)

If you are using CloudNativePG, you're done.   
You can start using cardano.* features in your app.  
The stanza on Database.extensions in CloudNativePG automagically installs and create the extension for you.
```sql
-- Enable the extension
CREATE EXTENSION pg_cardano;
```  


### 6. Test the extension
Connect to your database and run:

```sql
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
imageName: ghcr.io/cloudnative-pg/postgresql:17.9-system-trixie
extensions:
  - name: pgcardano
    image:
      reference: cardano-community/pgcardano:1.2.0-pg17.9-linux-amd64-scratch

# PostgreSQL 16.13
imageName: ghcr.io/cloudnative-pg/postgresql:16.13-system-trixie
extensions:
  - name: pgcardano
    image:
      reference: cardano-community/pgcardano:1.2.0-pg16.3-linux-amd64-scratch
```

## Using Prebuilt Registry Images

> ⚠️ **Warning**: The registry.2lovelaces.io registry should not be relied upon for production workloads  
> as it is sometimes offline for regular maintenance.

For convenience, prebuilt pg_cardano extension images are available at `registry.2lovelaces.io`.   
These can be used directly without building the extension yourself:

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
    extensions:
      - name: pgcardano
        image:
          reference: registry.2lovelaces.io/2lovelaces/cardano/pgcardano:1.2.0-pg18.1-linux-amd64-scratch
          # reference: registry.2lovelaces.io/2lovelaces/cardano/pgcardano:1.2.0-pg18.1-linux-arm64-scratch  # For ARM64 nodes
```

### Available Prebuilt Images

The following prebuilt images are available (may use compatibility naming):
- `registry.2lovelaces.io/2lovelaces/cardano/pgcardano:1.2.0-pg18.1-linux-amd64-scratch` 
- `registry.2lovelaces.io/2lovelaces/cardano/pgcardano:1.2.0-pg17.9-linux-amd64-scratch`
- `registry.2lovelaces.io/2lovelaces/cardano/pgcardano:1.2.0-pg16.13-linux-amd64-scratch`

Full list of images are published at https://gitlab.2lovelaces.io/2lovelaces/cardano/pgcardano/container_registry/65

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
5. **.so file not executable**: Use platform-specific images (`-linux-amd64` or `-linux-arm64`) instead of multi-arch manifests
6. **Platform mismatch**: Ensure the image platform matches your Kubernetes nodes (check with `kubectl get nodes -o wide`)



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
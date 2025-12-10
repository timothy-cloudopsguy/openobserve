# OpenObserve Infrastructure Stack

This Terraform stack deploys OpenObserve, a high-performance observability platform, on AWS infrastructure using ECS Fargate instead of Kubernetes (EKS). Built specifically to avoid the operational overhead and complexity of running OpenObserve in EKS, this stack provides a simpler, serverless deployment model while maintaining enterprise-grade features.

## Why Not EKS?

OpenObserve is typically deployed in Kubernetes clusters, but this introduces significant operational complexity:
- Managing Kubernetes control plane and worker nodes
- Dealing with cluster upgrades, scaling, and maintenance
- Complex networking and service mesh requirements
- Higher operational costs for small to medium deployments

This stack was created as an alternative that leverages AWS-managed services (ECS Fargate, Aurora, ALB) to provide a production-ready OpenObserve deployment with minimal operational overhead.

## Infrastructure Overview

The Terraform stack creates a complete observability platform with the following AWS resources:

### Core Infrastructure
- **VPC**: Multi-AZ VPC with public and private subnets
- **Application Load Balancer**: Public-facing ALB with SSL termination
- **ECS Cluster**: Fargate-based container orchestration with auto-scaling
- **Aurora PostgreSQL**: Serverless database for metadata storage
- **NATS**: Distributed messaging system for cluster coordination
- **S3**: Object storage for log data persistence

### OpenObserve Services
The stack deploys multiple OpenObserve services as ECS tasks:

#### Ingester Service
- **Role**: `ingester,querier,compactor`
- **Responsibilities**:
  - Ingests log data via HTTP/gRPC APIs
  - Compacts and optimizes stored data
  - Serves query requests
- **Storage**: Uses S3 for data persistence and Aurora for metadata

#### Frontend Service
- **Role**: `all`
- **Responsibilities**:
  - Provides web UI interface
  - Handles user authentication and authorization
  - Routes API requests to appropriate services
  - Since it's Role is All, it will query over S3 to help ease the load on the ingester
  - Since it's Role is All, it can ingest, but isn't behind the ALB
- **Features**: Full OpenObserve web interface with dashboards and alerts

#### Additional Services
- **NATS Cluster**: 2-node NATS cluster for distributed coordination
- **Database Service Accounts**: Automated creation of PostgreSQL users with specific permissions

## Container Architecture

### Custom Dockerfile

The included Dockerfile creates a production-ready OpenObserve container:

```dockerfile
FROM public.ecr.aws/zinclabs/openobserve-enterprise:v0.20.3 AS builder
FROM public.ecr.aws/debian/debian:trixie-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends curl iproute2

COPY --from=builder /openobserve /openobserve
COPY entrypoint.sh /entrypoint.sh

RUN ["/openobserve", "init-dir", "-p", "/data/"]
RUN ["chmod", "+x", "/entrypoint.sh"]

EXPOSE 5080

CMD ["/entrypoint.sh"]
```

**Note**: The Enterprise edition (`openobserve-enterprise`) is required because the graceful shutdown script relies on the `/node/drain_status` endpoint, which returns a 404 error in non-enterprise editions. This endpoint is essential for monitoring drain status during container termination.

### Why a Custom Dockerfile?

This custom Dockerfile is required for several critical reasons:

#### Graceful Shutdown Requirements
The official OpenObserve distroless image doesn't include `/bin/sh`, which prevents ECS from executing pre-stop lifecycle hooks. These hooks are essential for:
- Gracefully removing the node from the cluster before shutdown
- Ensuring all in-flight data is safely copied to S3
- Preventing data loss during container termination

#### IP Address Resolution Issues
ECS Fargate containers receive two IP addresses:
- A `169.x.x.x` link-local address (first in the resolution order)
- The actual private IP address needed for cluster communication

OpenObserve selects the first resolved IP, causing cluster join failures. The entrypoint script explicitly sets:
- `ZO_HTTP_ADDR`: Forces the correct private IP for HTTP communication
- `ZO_GRPC_ADDR`: Forces the correct private IP for gRPC cluster coordination

#### Entrypoint Script Injection
Since the entrypoint script is required anyway for IP resolution and graceful shutdown, using a custom Dockerfile allows us to inject this critical functionality while maintaining compatibility with the official OpenObserve binary.

### Graceful Shutdown Handling

The `entrypoint.sh` script provides enterprise-grade shutdown handling for ECS Fargate:

- **Pre-stop Hook**: Implements drain mode before container termination
- **Data Safety**: Ensures all in-flight data is flushed to S3 before shutdown
- **Health Monitoring**: Polls drain status to confirm safe termination
- **Timeout Protection**: Prevents indefinite waiting with configurable timeouts

Key features:
- Disables new ingestion requests during shutdown
- Monitors pending parquet file uploads to S3
- Ensures memory is flushed before termination
- Provides detailed logging for troubleshooting

## Configuration

### Environment Variables

The stack supports extensive configuration through environment variables:

#### Core Configuration
- `ZO_APP_NAME`: Application identifier
- `ZO_CLUSTER_NAME`: Cluster coordination name
- `ZO_NODE_ROLE`: Service role (ingester, querier, compactor, frontend)

#### Networking
- `ZO_HTTP_PORT`: HTTP service port (default: 5080)
- `ZO_GRPC_PORT`: gRPC service port (default: 5081)
- Dynamic IP assignment for ECS task networking

#### Storage Configuration
- **Database**: Aurora PostgreSQL with connection pooling
- **Object Storage**: S3 with organization-level access controls
- **Local Storage**: Ephemeral storage for active data processing

#### Security
- `ZO_ROOT_USER_EMAIL`: Admin user email
- `ZO_ROOT_USER_PASSWORD`: Admin password (stored in SSM)
- Database service accounts with granular permissions

## Deployment Process

### Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Docker for building custom container images

### Deployment Steps

1. **Configure Properties**
   ```bash
   # Edit properties.dev.json or properties.prod.json
   # Set domain name, VPC configuration, and service settings
   ```

2. **Initialize Terraform**
   ```bash
   terraform init
   ```

3. **Plan Deployment**
   ```bash
   terraform plan -var="environment=dev"
   ```

4. **Apply Infrastructure**
   ```bash
   terraform apply -var="environment=dev"
   ```

### Important Configuration Prerequisites

Before deploying, review and update the following settings in your `properties.X.json` file:

#### Infrastructure Dependencies
- **`iac_core_name`**: Only set if VPC and ALB are pre-created in another stack. Leave as default otherwise.
- **`vpc.create`**: Set to `true` if you don't have existing VPC with public and support subnets.
- **`alb.create`**: Set to `true` if you don't have an existing ALB using public and support subnets.

#### DNS Configuration
- **`route53.domain_name`**: **Pre-create this hosted zone in Route53** before deployment. The domain must exist in your AWS account.

#### Container Images
- **ECR Repository**: Pre-create a repository named `openobserve/slim` in your ECR account and push the custom Docker image to it before deployment.

### Post-Deployment

1. **DNS Configuration**: Route53 records are automatically created. Ensure your `properties.X.json` file contains a valid Route53 domain that exists in your AWS account.
2. **Database Credentials**: Automatically generated and stored in SSM Parameter Store, then securely passed to containers.
3. **Configure Authentication**: Set up user accounts and permissions via the OpenObserve web interface. The root/admin password will be created and stored for you in SSM params.
4. **Test Ingestion**: Use the provided Python test scripts to verify functionality.

## Monitoring and Operations

### Health Checks
- ALB health checks on `/health` endpoint
- Container health monitoring via ECS
- Aurora database connection monitoring

### Scaling
- **Horizontal Scaling**: ECS service auto-scaling based on CPU/memory
- **Off-hours Scaling**: Automatic scaling down for non-production environments
- **Database Scaling**: Aurora Serverless v2 with ACU-based scaling

### Logging
- All OpenObserve logs are ingested into the platform itself
- ECS task logs available in CloudWatch
- Application metrics exposed via `/metrics` endpoint

## Testing and Development

The repository includes Python test utilities for development and validation:

### Log Ingestion Testing
```bash
cd ../
python test_pushing_log.py 100 --host https://your-domain.com --delay 0.1
```

### Features Tested
- Bulk log ingestion with realistic Kubernetes log formats
- Authentication and authorization
- High-throughput scenarios with delays
- Error handling and retry logic

## Cost Optimization

### Estimated Monthly Costs

The base cost of running this OpenObserve stack (excluding ALB) is approximately **$58/month**:

#### Compute Costs (Fargate SPOT ARM)
- **Frontend & Ingester Services**: Fargate SPOT ARM instances optimized for cost
- **NATS Cluster**: 2 regular Fargate ARM instances (0.256 vCPU, 512MB each) = **$14/month**

#### Storage Costs
- **Aurora Serverless**: Scales to zero when idle, minimal cost for metadata storage
- **S3**: Pay-per-use for log data storage with intelligent tiering

**Optional ALB**: Add **$32/month** for public load balancer with SSL termination.

#### NATS Redundancy Options
- **Current Setup**: 2 regular Fargate ARM instances = $14/month
- **Spot ARM Alternative**: 3 NATS instances on Fargate SPOT ARM for better redundancy = **$8/month**
  - Better handles spot instance interruptions
  - Improved fault tolerance with 3-node cluster

### Serverless Benefits
- **ECS Fargate**: Pay only for actual compute usage
- **Aurora Serverless**: Database scales to zero when idle
- **No EKS Costs**: Eliminates control plane and worker node costs

### Storage Efficiency
- S3 storage with intelligent tiering
- Compressed parquet file storage
- Configurable data retention policies

## Security Considerations

### Network Security
- Private subnets for application containers
- Security groups with minimal required access
- ALB with SSL/TLS termination

### Data Protection
- Encrypted S3 buckets with organization-level access
- Aurora encryption at rest and in transit
- Database service accounts with principle of least privilege

### Access Control
- SSM Parameter Store for secrets management
- IAM roles with minimal required permissions
- Route53 integration for domain-based access control

## Troubleshooting

### Common Issues

1. **Container Startup Failures**
   - Check ECS task logs in CloudWatch
   - Verify environment variable configuration
   - Ensure database connectivity

2. **ALB Health Check Failures**
   - Verify service is responding on port 5080
   - Check `/health` endpoint accessibility
   - Review security group configurations

3. **Data Ingestion Issues**
   - Verify NATS cluster connectivity
   - Check S3 bucket permissions
   - Review Aurora database connections

### Logs and Monitoring
- ECS task logs: `/aws/ecs/openobserve-{environment}`
- Application logs: Ingested into OpenObserve itself
- Infrastructure logs: CloudTrail and VPC Flow Logs

## Future Enhancements

- Multi-region deployment support
- Automated backup and disaster recovery
- Integration with AWS X-Ray for tracing
- Custom alerting and notification systems
- Advanced data lifecycle management

---

This stack provides a production-ready, cost-effective alternative to EKS-based OpenObserve deployments while maintaining full feature compatibility and enterprise-grade reliability.

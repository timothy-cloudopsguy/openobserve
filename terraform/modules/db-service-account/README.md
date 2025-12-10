# Database Service Account Provisioning

This Terraform module automatically provisions database service accounts with fine-grained permissions in your Aurora PostgreSQL cluster. Each service account gets its own credentials stored securely in AWS Systems Manager (SSM) Parameter Store.

## Features

- 🔐 **Secure Credentials**: Service account passwords are auto-generated and stored in SSM Parameter Store
- 🎯 **Fine-grained Permissions**: Configure specific SQL permissions (SELECT, INSERT, UPDATE, DELETE) per account
- 📊 **Table-specific Access**: Grant permissions on specific tables or all tables in schema
- 🔄 **Truly Idempotent**: Lambda function checks SSM parameter existence first - if credentials exist, it does nothing
- 🔧 **Smart Recovery**: If database user exists but SSM doesn't, it updates the password and takes over management
- 🛡️ **Automatic Cleanup**: Handles orphaned database users by bringing them under Terraform management
- 🔧 **Permission Management**: Optionally updates permissions for existing users to match configuration
- 🏷️ **Tagged Resources**: All resources are properly tagged for cost tracking and management

## Architecture

```
Terraform Module
    ↓
Lambda Function (Python)
    ↓
Aurora PostgreSQL
    ↓
SSM Parameter Store
```

## Usage

### 1. Configure Service Accounts

Add service account configurations to your `properties.dev.json` (or `properties.prod.json`):

**Note:** The Lambda automatically handles existing database users by updating their passwords and bringing them under Terraform management.

```json
{
  "database_service_accounts": [
    {
      "name": "myapp_readonly",
      "permissions": ["SELECT"],
      "tables": ["users", "sessions"],
      "update_permissions": false
    },
    {
      "name": "myapp_readwrite",
      "permissions": ["SELECT", "INSERT", "UPDATE"],
      "tables": ["users", "user_preferences"],
      "update_permissions": true
    },
    {
      "name": "admin_service",
      "permissions": ["SELECT", "INSERT", "UPDATE", "DELETE"],
      "tables": [],
      "update_permissions": false
    }
  ]
}
```

### 2. Terraform Integration

The service accounts are automatically created when you apply the Terraform configuration. The module:

1. **Deploys a Lambda function** that connects to your Aurora cluster
2. **Creates service accounts** with the specified permissions
3. **Stores credentials** in SSM Parameter Store
4. **Provides outputs** with SSM parameter paths

### 3. Access Credentials in Your Application

#### Option A: Direct SSM Access (Recommended)

```python
import boto3
import json

def get_db_credentials(service_account_name, environment):
    ssm = boto3.client('ssm')
    parameter_name = f"/cmpCore/db-service-accounts/{service_account_name}/{environment}"

    response = ssm.get_parameter(
        Name=parameter_name,
        WithDecryption=True
    )

    return json.loads(response['Parameter']['Value'])

# Usage
creds = get_db_credentials('myapp_readonly', 'dev')
# Returns: {'username': 'myapp_readonly', 'password': '...', 'database': 'cmpcore', 'host': '...', 'port': 5432}
```

#### Option B: Environment Variables

```bash
# Get credentials and export as environment variables
CREDS=$(aws ssm get-parameter --name "/cmpCore/db-service-accounts/myapp_readonly/dev" --with-decryption --query Parameter.Value --output text)
DB_USER=$(echo $CREDS | jq -r .username)
DB_PASSWORD=$(echo $CREDS | jq -r .password)
DB_HOST=$(echo $CREDS | jq -r .host)
DB_PORT=$(echo $CREDS | jq -r .port)
DB_NAME=$(echo $CREDS | jq -r .database)
```

## Configuration Options

### Service Account Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `name` | string | ✅ | Unique name for the service account |
| `permissions` | array | ✅ | SQL permissions: `["SELECT"]`, `["SELECT", "INSERT", "UPDATE"]`, etc. |
| `tables` | array | ❌ | Specific tables to grant permissions on. Empty array = all tables |
| `update_permissions` | boolean | ❌ | Whether to update permissions for existing users (default: false) |

### Permission Examples

```json
{
  "name": "readonly_user",
  "permissions": ["SELECT"],
  "tables": ["users", "products"]
}
```

```json
{
  "name": "api_user",
  "permissions": ["SELECT", "INSERT", "UPDATE"],
  "tables": ["orders", "order_items"]
}
```

```json
{
  "name": "admin_user",
  "permissions": ["SELECT", "INSERT", "UPDATE", "DELETE"],
  "tables": []
}
```

## Security Considerations

- 🔐 **Password Rotation**: Service account passwords are generated once and stored securely
- 👤 **Principle of Least Privilege**: Only grant necessary permissions
- 📋 **Audit Trail**: All database operations are logged
- 🔒 **Encryption**: Credentials are encrypted in SSM Parameter Store

## Monitoring and Troubleshooting

### Check Lambda Logs

```bash
aws logs tail /aws/lambda/cmpCore-db-service-account-{account_name}-dev --follow
```

### Verify SSM Parameters

```bash
aws ssm describe-parameters --parameter-filters "Key=Name,Option=BeginsWith,Values=/cmpCore/db-service-accounts/"
```

### Check Database Users

Connect to your Aurora cluster and run:

```sql
SELECT rolname FROM pg_roles WHERE rolname LIKE 'myapp_%';
```

## Terraform Outputs

The module provides these outputs:

```hcl
output "database_service_accounts" {
  description = "Database service account configurations"
  value = {
    "myapp_readonly" = {
      ssm_parameter_name = "/cmpCore/db-service-accounts/myapp_readonly/dev"
      lambda_function    = "cmpCore-db-service-account-myapp_readonly-dev"
      service_account    = "myapp_readonly"
    }
  }
}
```

## Cost Considerations

- **Lambda Invocations**: One-time cost per service account creation
- **SSM Parameters**: Minimal storage cost for encrypted parameters
- **Aurora Connections**: Temporary connections during user creation

## Best Practices

1. **Use Specific Permissions**: Avoid granting unnecessary privileges
2. **Regular Audits**: Review service account permissions periodically
3. **Environment Separation**: Use different accounts for dev/staging/prod
4. **Naming Conventions**: Use descriptive names (e.g., `{app}_{permission_level}`)
5. **Documentation**: Document what each service account is used for

## Troubleshooting

### Lambda Function Fails

Check CloudWatch logs for the specific Lambda function. Common issues:
- Aurora cluster not accessible (security groups, VPC configuration)
- Master credentials secret not found
- Database connection timeouts

### Permission Errors

Verify that the Aurora master user has sufficient privileges to create users and grant permissions.

### SSM Parameter Not Created

Check that the Lambda has the correct IAM permissions for SSM operations.

### Handling Existing Database Users

The Lambda automatically handles existing database users by:

1. **Taking over management**: Updates the user's password to a known value
2. **Creating SSM credentials**: Stores the new credentials in SSM Parameter Store
3. **Maintaining permissions**: Leaves existing permissions unchanged to avoid conflicts

This allows you to bring manually created users under Terraform management.

### Permission Updates for Existing Users

When `update_permissions` is set to `true`, the Lambda will:

1. **Analyze current permissions** on the database user
2. **Compare with desired permissions** from configuration
3. **Revoke excess permissions** that shouldn't be granted
4. **Grant missing permissions** that should be granted
5. **Handle schema-level permissions** for "all tables" configurations

**⚠️ Warning:** Enabling `update_permissions` can be destructive. It will revoke permissions that are not in your configuration. Use carefully in production environments.

**Recommended approach:**
- Set `update_permissions: false` for production service accounts
- Use schema migrations or manual updates for permission changes
- Only enable for development or when explicitly updating permissions

## Support

For issues or questions:
1. Check the Lambda function logs
2. Verify your Aurora cluster is accessible
3. Ensure master credentials are correct
4. Review the service account configuration in `properties.dev.json`

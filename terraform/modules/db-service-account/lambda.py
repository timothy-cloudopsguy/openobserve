import json
import boto3
import psycopg2
import os
from botocore.exceptions import ClientError

def grant_permissions(cursor, username, permissions, tables, schema_permissions, database_privileges):
    """Revoke all permissions first, then grant only the desired permissions"""

    # Verify user exists before attempting to revoke permissions
    cursor.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (username,))
    if not cursor.fetchone():
        raise Exception(f"User {username} does not exist - cannot revoke/grant permissions")

    # First, revoke all permissions to ensure clean slate
    print(f"Revoking all permissions for {username}...")

    # Revoke all table permissions
    cursor.execute(f"REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{username}\"")
    cursor.execute(f"ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL PRIVILEGES ON TABLES FROM \"{username}\"")
    print(f"Revoked all table permissions for {username}")

    # Revoke schema permissions (only revoke ones that might exist)
    for perm in ['USAGE', 'CREATE', 'ALTER', 'DROP']:
        try:
            cursor.execute(f'REVOKE {perm} ON SCHEMA public FROM "{username}"')
            print(f"Revoked {perm} on schema public from {username}")
        except Exception as e:
            # Ignore errors if permission wasn't granted
            pass

    # Revoke database privileges by setting the opposite where possible
    for privilege in ['CREATEDB', 'CREATEROLE', 'CREATEUSER', 'SUPERUSER', 'INHERIT', 'LOGIN']:
        try:
            if privilege in ['CREATEDB', 'CREATEROLE', 'CREATEUSER', 'SUPERUSER']:
                cursor.execute(f"ALTER USER \"{username}\" NO{privilege}")
                print(f"Revoked database privilege {privilege} from {username}")
            elif privilege == 'INHERIT':
                cursor.execute(f"ALTER USER \"{username}\" NOINHERIT")
                print(f"Revoked database privilege {privilege} from {username}")
            # LOGIN is required for users, so we don't revoke it
        except Exception as e:
            # Ignore errors if privilege wasn't set
            pass

    # Now grant the desired permissions
    print(f"Granting desired permissions for {username}...")

    # Grant database-level privileges
    for privilege in database_privileges:
        cursor.execute(f"ALTER USER \"{username}\" {privilege}")
        print(f"Granted database privilege {privilege} to {username}")

    # Grant schema permissions
    for perm in schema_permissions:
        cursor.execute(f'GRANT {perm} ON SCHEMA public TO "{username}"')
        print(f"Granted {perm} on schema public to {username}")

    # Grant table permissions
    for permission in permissions:
        if tables and "*" not in tables:
            # Grant on specific tables
            for table in tables:
                cursor.execute(f"GRANT {permission} ON \"{table}\" TO \"{username}\"")
                print(f"Granted {permission} on {table} to {username}")
        else:
            # Grant on all tables (current and future)
            cursor.execute(f"GRANT {permission} ON ALL TABLES IN SCHEMA public TO \"{username}\"")
            cursor.execute(f"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT {permission} ON TABLES TO \"{username}\"")
            print(f"Granted {permission} on all tables (current and future) to {username}")

def lambda_handler(event, context):
    """
    Lambda function to create or update database service accounts with specific permissions.

    When update_permissions is true, it will always generate a new password and update SSM.
    Otherwise, it's idempotent - it will only create/update credentials once.

    Event structure:
    {
        "service_account_name": "myapp",
        "database_name": "cmpcore",
        "permissions": ["SELECT", "INSERT", "UPDATE"],
        "tables": ["users", "sessions"],
        "schema_permissions": ["USAGE", "CREATE", "ALTER", "DROP"],
        "database_privileges": ["CREATEDB", "CREATEROLE"],
        "update_permissions": false,
        "aurora_endpoint": "cluster-endpoint",
        "aurora_port": 5432,
        "master_secret_arn": "arn:aws:secretsmanager:...",
        "ssm_parameter_name": "/app/service-account/myapp"
    }
    """

    # Extract parameters
    service_account_name = event['service_account_name']
    database_name = event['database_name']
    permissions = event.get('permissions', [])
    tables = event.get('tables', [])
    schema_permissions = event.get('schema_permissions', [])
    database_privileges = event.get('database_privileges', [])
    update_permissions = event.get('update_permissions', False)
    aurora_endpoint = event['aurora_endpoint']
    aurora_port = event.get('aurora_port', 5432)
    master_secret_arn = event['master_secret_arn']
    ssm_parameter_name = event['ssm_parameter_name']

    # Get master credentials from Secrets Manager
    secrets_client = boto3.client('secretsmanager')
    secret_value = secrets_client.get_secret_value(SecretId=master_secret_arn)
    master_creds = json.loads(secret_value['SecretString'])
    master_username = master_creds['username']
    master_password = master_creds['password']

    # Check if SSM parameter already exists
    ssm_client = boto3.client('ssm')
    ssm_exists = False
    try:
        ssm_client.get_parameter(Name=ssm_parameter_name)
        ssm_exists = True
        print(f"SSM parameter '{ssm_parameter_name}' already exists")
    except ssm_client.exceptions.ParameterNotFound:
        print(f"SSM parameter '{ssm_parameter_name}' does not exist")

    # If SSM exists and we're not updating permissions, return early
    if ssm_exists and not update_permissions:
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Service account {service_account_name} already provisioned',
                'ssm_parameter': ssm_parameter_name
            })
        }

    # Connect to database
    conn = psycopg2.connect(
        host=aurora_endpoint,
        port=aurora_port,
        database=database_name,
        user=master_username,
        password=master_password
    )
    conn.autocommit = True
    cursor = conn.cursor()

    try:
        # Check if user exists
        cursor.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (service_account_name,))
        user_exists = cursor.fetchone() is not None

        # Generate password (always when update_permissions is true, or when creating new user/SSM)
        should_generate_password = update_permissions or not user_exists or not ssm_exists
        service_password = None

        if should_generate_password:
            import secrets
            import string
            special_characters = "_"
            alphabet = string.ascii_letters + string.digits + special_characters
            service_password = ''.join(secrets.choice(alphabet) for i in range(32))

            if user_exists:
                cursor.execute(f"ALTER USER \"{service_account_name}\" PASSWORD %s", (service_password,))
                print(f"Updated password for service account '{service_account_name}'")
            else:
                cursor.execute(f"CREATE USER \"{service_account_name}\" WITH PASSWORD %s", (service_password,))
                print(f"Created service account '{service_account_name}'")

        # Always grant permissions when creating user or when update_permissions is true
        if not user_exists or update_permissions:
            grant_permissions(cursor, service_account_name, permissions, tables, schema_permissions, database_privileges)

        # Update SSM parameter (always when password changed or when update_permissions is true and SSM exists)
        if service_password or (update_permissions and ssm_exists):
            connection_string = f"postgres://{service_account_name}:{service_password}@{aurora_endpoint}:{aurora_port}/{database_name}"

            # Prepare the put_parameter call
            put_params = {
                'Name': ssm_parameter_name,
                'Description': f"Database service account credentials for {service_account_name}",
                'Value': connection_string,
                'Type': 'SecureString',
                'Overwrite': True if ssm_exists else False # Allow overwriting when updating
            }

            # Only include Tags when creating a new parameter (not overwriting)
            # AWS SSM doesn't allow Tags and Overwrite=True together
            if not ssm_exists:
                put_params['Tags'] = [
                    {'Key': 'ServiceAccount', 'Value': service_account_name},
                    {'Key': 'ManagedBy', 'Value': 'terraform'},
                    {'Key': 'Environment', 'Value': os.environ.get('ENVIRONMENT', 'unknown')}
                ]

            ssm_client.put_parameter(**put_params)
            print(f"Stored/updated credentials for '{service_account_name}' in SSM")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Service account {service_account_name} provisioned/updated successfully',
                'ssm_parameter': ssm_parameter_name,
                'user_created': not user_exists,
                'password_updated': service_password is not None,
                'permissions_updated': not user_exists or update_permissions
            })
        }

    finally:
        conn.close()

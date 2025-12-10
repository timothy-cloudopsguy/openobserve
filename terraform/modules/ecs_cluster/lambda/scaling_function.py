import boto3
import json
import os
from typing import Dict, List

def lambda_handler(event, context):
    """
    Lambda function to scale ECS services up or down during off-hours.
    """

    # Initialize AWS clients
    ecs_client = boto3.client('ecs')
    ssm_client = boto3.client('ssm')

    # Get environment variables
    cluster_name = os.environ['ECS_CLUSTER_NAME']
    app_name = os.environ['APP_NAME']
    environment = os.environ['ENVIRONMENT']

    # Get action from event payload (sent by EventBridge)
    action = event.get('action')
    if not action:
        raise ValueError("Missing 'action' in event payload. Expected 'scale_down' or 'scale_up'.")

    print(f"Starting {action} operation for cluster: {cluster_name}")

    try:
        # List all services in the cluster
        services_response = ecs_client.list_services(
            cluster=cluster_name,
            maxResults=100
        )

        service_arns = services_response['serviceArns']

        if not service_arns:
            print("No services found in cluster")
            return {
                'statusCode': 200,
                'body': json.dumps('No services to scale')
            }

        # We can only describe up to 10 services at a time, so we need to split out the list into chunks of 10
        service_chunks = [service_arns[i:i+10] for i in range(0, len(service_arns), 10)]

        services_details = {}
        services_details['services'] = []
        for chunk in service_chunks:
            # Get detailed service information
            service_details_chunk = ecs_client.describe_services(
                cluster=cluster_name,
                services=chunk,
                include=['TAGS'])
            services_details['services'].extend(service_details_chunk['services'])

        services_to_scale = []

        # Filter services that should be scaled (exclude scheduled tasks)
        for service in services_details['services']:
            # Skip services that are not deployed as ECS services (they're scheduled tasks)
            if not service.get('serviceName'):
                continue

            # Check if service has off-hours scaling enabled via tags
            tags = service.get('tags', [])
            enable_scaling = False

            for tag in tags:
                if tag['key'] == 'OffHoursScaling' and tag['value'].lower() == 'true':
                    enable_scaling = True
                    break

            if enable_scaling:
                services_to_scale.append({
                    'service_name': service['serviceName'],
                    'current_desired_count': service['desiredCount'],
                    'service_arn': service['serviceArn']
                })

        print(f"Found {len(services_to_scale)} services to scale")

        if action == 'scale_down':
            return scale_down_services(ecs_client, ssm_client, cluster_name, services_to_scale, app_name, environment)
        elif action == 'scale_up':
            return scale_up_services(ecs_client, ssm_client, cluster_name, services_to_scale, app_name, environment)
        else:
            raise ValueError(f"Invalid action: {action}")

    except Exception as e:
        print(f"Error during scaling operation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def scale_down_services(ecs_client, ssm_client, cluster_name: str, services: List[Dict], app_name: str, environment: str):
    """Scale down services to zero and store original desired counts."""

    print("Scaling down services to zero...")

    for service in services:
        service_name = service['service_name']
        current_desired_count = service['current_desired_count']

        if current_desired_count == 0:
            print(f"Service {service_name} is already scaled down to zero, skipping")
            continue

        # Store original desired count in SSM parameter
        ssm_param_name = f"/{app_name}/ecs/{service_name}/original_desired_count"
        try:
            ssm_client.put_parameter(
                Name=ssm_param_name,
                Value=str(current_desired_count),
                Type='String',
                Overwrite=True,
                Description=f'Original desired count for {service_name} before off-hours scaling'
            )
            print(f"Stored original desired count {current_desired_count} for service {service_name}")
        except Exception as e:
            print(f"Error storing original count for {service_name}: {str(e)}")
            continue

        # Scale down to zero
        try:
            ecs_client.update_service(
                cluster=cluster_name,
                service=service_name,
                desiredCount=0
            )
            print(f"Scaled down service {service_name} to 0")
        except Exception as e:
            print(f"Error scaling down service {service_name}: {str(e)}")

    return {
        'statusCode': 200,
        'body': json.dumps('Scale down operation completed')
    }

def scale_up_services(ecs_client, ssm_client, cluster_name: str, services: List[Dict], app_name: str, environment: str):
    """Scale up services to their original desired counts."""

    print("Scaling up services to original counts...")

    for service in services:
        service_name = service['service_name']

        # Get original desired count from SSM parameter
        ssm_param_name = f"/{app_name}/ecs/{service_name}/original_desired_count"
        try:
            response = ssm_client.get_parameter(Name=ssm_param_name)
            original_desired_count = int(response['Parameter']['Value'])
            print(f"Retrieved original desired count {original_desired_count} for service {service_name}")
        except ssm_client.exceptions.ParameterNotFound:
            print(f"No stored desired count found for service {service_name}, leaving at zero")
            original_desired_count = 0
        except Exception as e:
            print(f"Error retrieving original count for {service_name}: {str(e)}")
            original_desired_count = 0

        try:
            if original_desired_count > 0:
                ecs_client.update_service(
                    cluster=cluster_name,
                    service=service_name,
                    desiredCount=original_desired_count
                )
                print(f"Scaled up service {service_name} to {original_desired_count}")

            # Delete SSM Paramater
            try:
                ssm_client.delete_parameter(Name=ssm_param_name)
                print(f"Deleted SSM parameter {ssm_param_name} for service {service_name}")
            except Exception as e:
                print(f"Error deleting SSM parameter {ssm_param_name} for service {service_name}: {str(e)}")

        except Exception as e:
            print(f"Error scaling up service {service_name}: {str(e)}")

    return {
        'statusCode': 200,
        'body': json.dumps('Scale up operation completed')
    }

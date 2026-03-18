import boto3
from botocore.exceptions import ClientError

def create_dynamodb_table():
    """
    Create DynamoDB table 'finopsagentlogs' with session_id as hash key
    Region: London (eu-west-2)
    """

    # Initialize DynamoDB client for London region
    dynamodb = boto3.client('dynamodb', region_name='eu-west-2')

    table_name = 'finopsagentlogs'

    try:
        # Create the DynamoDB table
        response = dynamodb.create_table(
            TableName=table_name,
            KeySchema=[
                {
                    'AttributeName': 'session_id',
                    'KeyType': 'HASH'  # Partition key
                }
            ],
            AttributeDefinitions=[
                {
                    'AttributeName': 'session_id',
                    'AttributeType': 'S'  # String type
                }
            ],
            BillingMode='PAY_PER_REQUEST',  # On-demand pricing
            Tags=[
                {
                    'Key': 'Project',
                    'Value': 'FinOpsAgent'
                },
                {
                    'Key': 'Environment',
                    'Value': 'Development'
                }
            ]
        )

        print(f"Creating table '{table_name}'...")
        print(f"Table ARN: {response['TableDescription']['TableArn']}")
        print(f"Table Status: {response['TableDescription']['TableStatus']}")

        # Wait for table to be created
        waiter = dynamodb.get_waiter('table_exists')
        waiter.wait(TableName=table_name)

        print(f"Table '{table_name}' created successfully!")

        return response

    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceInUseException':
            print(f"Table '{table_name}' already exists.")
        else:
            print(f"Error creating table: {e.response['Error']['Message']}")
            raise
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        raise


if __name__ == '__main__':
    create_dynamodb_table()

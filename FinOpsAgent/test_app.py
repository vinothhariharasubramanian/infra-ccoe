import pytest
import boto3
from moto import mock_aws
from botocore.exceptions import ClientError
from app import create_dynamodb_table


@mock_aws
def test_create_dynamodb_table_success():
    """Test successful creation of DynamoDB table"""

    # Create the table
    response = create_dynamodb_table()

    # Verify the response
    assert response is not None
    assert 'TableDescription' in response
    assert response['TableDescription']['TableName'] == 'finopsagentlogs'
    assert response['TableDescription']['TableStatus'] in ['CREATING', 'ACTIVE']

    # Verify the table exists and has correct configuration
    dynamodb = boto3.client('dynamodb', region_name='eu-west-2')
    table_description = dynamodb.describe_table(TableName='finopsagentlogs')

    # Check table name
    assert table_description['Table']['TableName'] == 'finopsagentlogs'

    # Check key schema
    key_schema = table_description['Table']['KeySchema']
    assert len(key_schema) == 1
    assert key_schema[0]['AttributeName'] == 'session_id'
    assert key_schema[0]['KeyType'] == 'HASH'

    # Check attribute definitions
    attributes = table_description['Table']['AttributeDefinitions']
    assert len(attributes) == 1
    assert attributes[0]['AttributeName'] == 'session_id'
    assert attributes[0]['AttributeType'] == 'S'

    # Check billing mode
    assert table_description['Table']['BillingModeSummary']['BillingMode'] == 'PAY_PER_REQUEST'


@mock_aws
def test_create_dynamodb_table_already_exists():
    """Test handling when table already exists"""

    # Create the table first time
    response1 = create_dynamodb_table()
    assert response1 is not None

    # Try to create it again - should handle gracefully
    response2 = create_dynamodb_table()
    # Should return None or handle the ResourceInUseException


@mock_aws
def test_table_can_store_and_retrieve_data():
    """Test that the created table can store and retrieve data"""

    # Create the table
    create_dynamodb_table()

    # Use boto3 resource for easier data manipulation
    dynamodb = boto3.resource('dynamodb', region_name='eu-west-2')
    table = dynamodb.Table('finopsagentlogs')

    # Put an item
    test_item = {
        'session_id': 'test-session-123',
        'timestamp': '2026-03-18T10:00:00Z',
        'event': 'test_event',
        'data': {'key': 'value'}
    }
    table.put_item(Item=test_item)

    # Get the item
    response = table.get_item(Key={'session_id': 'test-session-123'})

    # Verify
    assert 'Item' in response
    assert response['Item']['session_id'] == 'test-session-123'
    assert response['Item']['event'] == 'test_event'


@mock_aws
def test_table_region_is_london():
    """Test that the table is created in the correct region"""

    # Create the table
    create_dynamodb_table()

    # Verify it exists in eu-west-2 (London)
    dynamodb = boto3.client('dynamodb', region_name='eu-west-2')
    tables = dynamodb.list_tables()

    assert 'finopsagentlogs' in tables['TableNames']

    # Verify it doesn't exist in other regions (e.g., us-east-1)
    dynamodb_us = boto3.client('dynamodb', region_name='us-east-1')
    tables_us = dynamodb_us.list_tables()

    assert 'finopsagentlogs' not in tables_us['TableNames']


@mock_aws
def test_table_has_correct_tags():
    """Test that the table has the correct tags"""

    # Create the table
    create_dynamodb_table()

    # Get table ARN and check tags
    dynamodb = boto3.client('dynamodb', region_name='eu-west-2')
    table_description = dynamodb.describe_table(TableName='finopsagentlogs')
    table_arn = table_description['Table']['TableArn']

    tags = dynamodb.list_tags_of_resource(ResourceArn=table_arn)

    # Convert tags list to dict for easier checking
    tags_dict = {tag['Key']: tag['Value'] for tag in tags['Tags']}

    assert 'Project' in tags_dict
    assert tags_dict['Project'] == 'FinOpsAgent'
    assert 'Environment' in tags_dict
    assert tags_dict['Environment'] == 'Development'


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--cov=app', '--cov-report=term-missing'])

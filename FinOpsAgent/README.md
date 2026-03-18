# FinOpsAgent

Python application for FinOps operations using AWS services and AI agents.

## Overview
FinOpsAgent manages financial operations logging and analytics using AWS DynamoDB and Strands AI agents.

## Features
- DynamoDB table management for session logs
- AWS Bedrock integration via boto3
- Strands AI agent framework
- Comprehensive test coverage

## Setup

### Prerequisites
- Python 3.12+
- AWS credentials configured
- Virtual environment support

### Installation

1. **Create and activate virtual environment:**
   ```bash
   python -m venv venv
   source venv/Scripts/activate  # Windows Git Bash
   # or
   .\venv\Scripts\activate  # Windows PowerShell
   ```

2. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

## Usage

### Create DynamoDB Table
```bash
python app.py
```

This creates the `finopsagentlogs` table in the London (eu-west-2) region with:
- Hash key: `session_id` (String)
- Billing mode: PAY_PER_REQUEST
- Tags: Project=FinOpsAgent, Environment=Development

## Testing

### Run all tests:
```bash
pytest test_app.py -v
```

### Run tests with coverage:
```bash
pytest test_app.py -v --cov=app --cov-report=term-missing
```

### Run tests with HTML coverage report:
```bash
pytest test_app.py --cov=app --cov-report=html
```

## Project Structure
```
FinOpsAgent/
├── app.py              # Main application - DynamoDB table creation
├── test_app.py         # Test suite with moto mocking
├── requirements.txt    # Python dependencies
├── .gitignore         # Git ignore patterns
├── README.md          # This file
└── venv/              # Virtual environment (not committed)
```

## Dependencies
- **boto3**: AWS SDK for Python
- **strands-agents**: AI agent framework
- **strands-agents-tools**: Agent tooling
- **pytest**: Testing framework
- **pytest-cov**: Coverage reporting
- **moto[dynamodb]**: AWS service mocking

## AWS Configuration

Ensure AWS credentials are configured via:
- AWS CLI (`aws configure`)
- Environment variables
- IAM role (if running on EC2/Lambda)

Required permissions:
- `dynamodb:CreateTable`
- `dynamodb:DescribeTable`
- `dynamodb:ListTables`
- `dynamodb:TagResource`

## Test Coverage
Current coverage: **75%**

All tests use moto to mock AWS services - no actual AWS resources are created during testing.

import json
import boto3
import os
from datetime import datetime, timedelta

dynamodb = boto3.resource('dynamodb')
TOKEN_TABLE = os.environ.get('DYNAMODB_TOKEN_TABLE')

def lambda_handler(event, context):
    """Clean up expired tokens from DynamoDB"""
    try:
        table = dynamodb.Table(TOKEN_TABLE)
        
        # Scan for expired items (TTL automatically handles cleanup,
        # but this is a manual backup cleaner)
        response = table.scan()
        expired_count = 0
        
        for item in response.get('Items', []):
            expires_at = item.get('expires_at')
            if expires_at and expires_at < int(datetime.utcnow().timestamp()):
                table.delete_item(Key={'finding_id': item['finding_id']})
                expired_count += 1
        
        print(f"Cleaned up {expired_count} expired tokens")
        
        return {
            "statusCode": 200,
            "cleaned": expired_count
        }
        
    except Exception as e:
        print(f"Error cleaning tokens: {str(e)}")
        return {
            "statusCode": 500,
            "error": str(e)
        }
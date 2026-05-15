import json
import boto3
import os
from datetime import datetime, timedelta
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('DYNAMODB_HISTORY_TABLE')
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    """Check historical precedent for similar incidents"""
    try:
        finding_type = event.get('finding_type')
        target_id = event.get('target_id')
        finding_id = event.get('finding_id')
        
        if not finding_type or not target_id:
            return {
                "has_precedent": False,
                "notes": "Missing finding_type or target_id for precedent check",
                "previous_actions": []
            }
        
        # Query for incidents of same type on same target in last 90 days
        ninety_days_ago = (datetime.utcnow() - timedelta(days=90)).isoformat()
        
        response = table.query(
            KeyConditionExpression='finding_type = :ft AND target_id = :tid',
            ExpressionAttributeValues={
                ':ft': finding_type,
                ':tid': target_id
            },
            ScanIndexForward=False,
            Limit=10
        )
        
        items = response.get('Items', [])
        
        if items:
            # Filter by timestamp (simplified - in production use filter expression)
            recent_items = [
                item for item in items 
                if item.get('timestamp', '').startswith(datetime.utcnow().strftime('%Y'))
            ]
            
            if recent_items:
                latest = recent_items[0]
                
                result = {
                    "has_precedent": True,
                    "finding_type": finding_type,
                    "target_id": target_id,
                    "count": len(recent_items),
                    "last_occurrence": latest.get('timestamp'),
                    "previous_action": latest.get('action_taken', 'None'),
                    "previous_outcome": latest.get('outcome', 'Unknown'),
                    "notes": f"Found {len(recent_items)} similar incidents in last 90 days",
                    "previous_actions": [
                        {
                            "timestamp": item.get('timestamp'),
                            "action": item.get('action_taken'),
                            "outcome": item.get('outcome')
                        }
                        for item in recent_items[:5]
                    ]
                }
                
                print(f"Precedent found: {len(recent_items)} incidents for {target_id}")
                return result
        
        return {
            "has_precedent": False,
            "finding_type": finding_type,
            "target_id": target_id,
            "notes": "No similar incidents found for this resource",
            "previous_actions": []
        }
        
    except ClientError as e:
        print(f"DynamoDB error: {e}")
        return {
            "has_precedent": False,
            "notes": f"Database error: {e.response['Error']['Message']}",
            "previous_actions": []
        }
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            "has_precedent": False,
            "notes": f"Error checking precedent: {str(e)}",
            "previous_actions": []
        }
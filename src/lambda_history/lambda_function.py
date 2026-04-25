import json
import boto3
import os
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    table_name = os.environ.get('DYNAMODB_TABLE_NAME')
    table = dynamodb.Table(table_name)
    
    params = {p['name']: p['value'] for p in event.get('inputParameters', [])}
    finding_type = params.get('finding_type')
    target_id = params.get('target_id')
    
    try:
        response = table.get_item(
            Key={
                'finding_type': finding_type,
                'target_id': target_id
            }
        )
        
        if 'Item' in response:
            item = response['Item']
            result = {
                "has_precedent": True,
                "last_occurrence": item.get('timestamp'),
                "previous_action": item.get('action_taken'),
                "previous_outcome": item.get('outcome'),
                "previous_severity": int(item.get('severity', 0)),
                "notes": "Phát hiện tiền lệ: Tài nguyên này từng gặp sự cố tương tự."
            }
        else:
            result = {
                "has_precedent": False,
                "notes": "Không tìm thấy tiền lệ lịch sử cho lỗi này trên tài nguyên."
            }
            
        return {
            "messageVersion": "1.0",
            "response": {
                "actionGroup": event['actionGroup'],
                "function": event['function'],
                "functionResponse": {
                    "responseBody": {
                        "TEXT": {"body": json.dumps(result)}
                    }
                }
            }
        }
    except ClientError as e:
        return {"error": e.response['Error']['Message']}
    except Exception as e:
        return {"error": str(e)}
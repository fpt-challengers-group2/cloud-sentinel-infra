import json
import requests
import boto3
import os
from botocore.exceptions import ClientError

TELEGRAM_TOKEN = os.environ.get('TELEGRAM_TOKEN')
DYNAMODB_TOKEN_TABLE = os.environ.get('DYNAMODB_TOKEN_TABLE')
COGNITO_USER_POOL_ID = os.environ.get('COGNITO_USER_POOL_ID')
cognito = boto3.client('cognito-idp')
stepfunctions = boto3.client('stepfunctions')
dynamodb = boto3.resource('dynamodb')
token_table = dynamodb.Table(DYNAMODB_TOKEN_TABLE)

def verify_admin(telegram_id):
    """Verify if Telegram user is admin in Cognito"""
    try:
        # Lấy toàn bộ user về và tự filter bằng Python vì AWS không hỗ trợ filter custom attribute
        paginator = cognito.get_paginator('list_users')
        for page in paginator.paginate(UserPoolId=COGNITO_USER_POOL_ID):
            for user in page.get('Users', []):
                for attr in user.get('Attributes', []):
                    if attr['Name'] == 'custom:telegram_id' and attr['Value'] == str(telegram_id):
                        return True
        return False
    except Exception as e:
        print(f"Cognito error: {e}")
        return False

def lambda_handler(event, context):
    """Handle Telegram callback queries"""
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Handle callback query (button press)
        if 'callback_query' in body:
            callback = body['callback_query']
            telegram_id = str(callback['from']['id'])
            admin_name = callback['from'].get('first_name', 'Admin')
            callback_data = callback['data']
            
            # Extract finding_id and action
            parts = callback_data.split('_', 1)
            if len(parts) != 2:
                return respond_error(callback, "Invalid callback data")
            
            action, finding_id = parts[0], parts[1]
            
            # Verify admin
            if not verify_admin(telegram_id):
                answer_callback(callback['id'], "❌ Unauthorized! Admin access required.", True)
                return respond_unauthorized()
            
            # Get task token from DynamoDB
            try:
                response = token_table.get_item(Key={'finding_id': finding_id})
                if 'Item' not in response:
                    answer_callback(callback['id'], "⚠️ Request expired or already processed.", True)
                    return respond_success()
                
                task_token = response['Item']['task_token']
                
                # Delete token to prevent reuse
                token_table.delete_item(Key={'finding_id': finding_id})
                
            except ClientError as e:
                print(f"DynamoDB error: {e}")
                answer_callback(callback['id'], "❌ System error. Please contact administrator.", True)
                return respond_error_response()
            
            # Process action and send to Step Functions
            if action == 'approve':
                # Send success to Step Function
                stepfunctions.send_task_success(
                    taskToken=task_token,
                    output=json.dumps({
                        "approved_action": "approve",
                        "approved_by": admin_name,
                        "approved_by_id": telegram_id,
                        "timestamp": str(callback.get('message', {}).get('date', ''))
                    })
                )
                answer_callback(callback['id'], f"✅ Approved by {admin_name}. Executing remediation...", False)
                
                # Update Telegram message
                update_telegram_message(
                    callback['message']['chat']['id'],
                    callback['message']['message_id'],
                    f"✅ *APPROVED* by {admin_name}\n\nRemediation is being executed..."
                )
                
            elif action == 'reject':
                # Send failure to Step Function
                stepfunctions.send_task_failure(
                    taskToken=task_token,
                    error="UserRejected",
                    cause=f"Rejected by {admin_name} (ID: {telegram_id})"
                )
                answer_callback(callback['id'], f"❌ Rejected by {admin_name}. No action taken.", False)
                
                # Update Telegram message
                update_telegram_message(
                    callback['message']['chat']['id'],
                    callback['message']['message_id'],
                    f"❌ *REJECTED* by {admin_name}\n\nNo remediation action was taken."
                )
            
            return respond_success()
        
        # Handle regular message (not implemented)
        return {
            "statusCode": 200,
            "body": json.dumps({"status": "ok"})
        }
        
    except Exception as e:
        print(f"Error in approval handler: {str(e)}")
        return respond_error_response()

def answer_callback(callback_id, text, show_alert=False):
    """Answer Telegram callback query"""
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/answerCallbackQuery"
    payload = {
        "callback_query_id": callback_id,
        "text": text,
        "show_alert": show_alert
    }
    try:
        requests.post(url, json=payload, timeout=5)
    except Exception as e:
        print(f"Error answering callback: {e}")

def update_telegram_message(chat_id, message_id, text):
    """Update existing Telegram message"""
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/editMessageText"
    payload = {
        "chat_id": chat_id,
        "message_id": message_id,
        "text": text,
        "parse_mode": "Markdown"
    }
    try:
        requests.post(url, json=payload, timeout=5)
    except Exception as e:
        print(f"Error updating message: {e}")

def respond_success():
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"status": "success"})
    }

def respond_unauthorized():
    return {
        "statusCode": 403,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"status": "unauthorized"})
    }

def respond_error_response():
    return {
        "statusCode": 500,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"status": "error"})
    }
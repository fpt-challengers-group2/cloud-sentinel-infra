import json
import boto3
import os
import requests
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
TOKEN_TABLE = os.environ.get('DYNAMODB_TOKEN_TABLE')
TELEGRAM_TOKEN = os.environ.get('TELEGRAM_TOKEN')
TELEGRAM_CHAT_ID = os.environ.get('TELEGRAM_CHAT_ID')

def lambda_handler(event, context):
    """Send alert to Telegram and save Step Functions Task Token"""
    try:
        finding = event.get('finding', {})
        remediation_plan = event.get('remediation_plan', 'No plan generated.')
        finding_id = event.get('finding_id')
        task_token = event.get('task_token')
        
        # 1. Lưu Task Token vào DynamoDB để Webhook xử lý duyệt sau
        table = dynamodb.Table(TOKEN_TABLE)
        table.put_item(
            Item={
                'finding_id': finding_id,
                'task_token': task_token,
                'expires_at': int(datetime.utcnow().timestamp()) + 86400 # Token hết hạn sau 24h
            }
        )
        
        # 2. Xây dựng nội dung tin nhắn Telegram
        severity_emoji = "🔴" if finding.get('severity') == "HIGH" else "🟡"
        
        message = (
            f"{severity_emoji} *SECURITY ALERT: {finding.get('finding_type')}*\n\n"
            f"*Resource:* `{finding.get('target_id')}`\n"
            f"*IP:* `{finding.get('attacker_ip')}`\n"
            f"*Location:* {finding.get('attacker_location')}\n\n"
            f"*Proposed Remediation Plan:*\n"
            f"{remediation_plan[:3000]}..." # Cắt bớt nếu plan vượt giới hạn ký tự của Telegram
        )
        
        # 3. Tạo nút bấm Inline Keyboard
        keyboard = {
            "inline_keyboard": [[
                {"text": "✅ Approve", "callback_data": f"approve_{finding_id}"},
                {"text": "❌ Reject", "callback_data": f"reject_{finding_id}"}
            ]]
        }
        
        # 4. Gửi qua API Telegram
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        payload = {
            "chat_id": TELEGRAM_CHAT_ID,
            "text": message,
            "parse_mode": "Markdown",
            "reply_markup": json.dumps(keyboard)
        }
        
        response = requests.post(url, json=payload)
        response.raise_for_status()
        
        print(f"Successfully sent Telegram alert for {finding_id}")
        
        # Lưu ý: Return ở đây không làm State Machine đi tiếp, 
        # vì Step Function đang sử dụng .waitForTaskToken để chờ duyệt.
        return {"status": "message_sent_waiting_for_approval"}
        
    except Exception as e:
        print(f"Error sending Telegram message: {str(e)}")
        # Báo Failed về cho Step Function để quy trình không bị treo vĩnh viễn
        client = boto3.client('stepfunctions')
        if event.get('task_token'):
            client.send_task_failure(
                taskToken=event.get('task_token'),
                error="TelegramSendError",
                cause=str(e)
            )
        raise e
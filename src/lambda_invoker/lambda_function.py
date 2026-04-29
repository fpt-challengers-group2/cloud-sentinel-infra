import json
import boto3
import re

bedrock_agent_runtime = boto3.client('bedrock-agent-runtime')

def lambda_handler(event, context):
    agent_id = event.get('AgentId')
    agent_alias_id = event.get('AgentAliasId')
    session_id = event.get('SessionId', 'default-session')
    input_text = event.get('InputText')
    
    response = bedrock_agent_runtime.invoke_agent(
        agentId=agent_id,
        agentAliasId=agent_alias_id,
        sessionId=session_id,
        inputText=input_text
    )
    
    raw_completion = ""
    for event_stream in response.get('completion', []):
        if 'chunk' in event_stream:
            raw_completion += event_stream['chunk'].get('bytes', b'').decode('utf-8')
            
    # --- ĐOẠN CODE SỬA LỖI: Dùng Regex để tách riêng JSON ---
    try:
        # Tìm nội dung nằm giữa dấu { và } đầu tiên/cuối cùng
        json_match = re.search(r'(\{.*\})', raw_completion, re.DOTALL)
        if json_match:
            clean_json = json_match.group(1)
            # Kiểm tra thử xem có đúng là JSON không
            json.loads(clean_json) 
            return {"Completion": clean_json}
        else:
            raise ValueError("Không tìm thấy JSON trong phản hồi của Agent")
    except Exception:
        # Nếu không tách được, trả về toàn bộ để gỡ lỗi nhưng Step Functions có thể vẫn lỗi
        return {"Completion": raw_completion}
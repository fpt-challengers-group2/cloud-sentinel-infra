import json
import boto3

bedrock_agent_runtime = boto3.client('bedrock-agent-runtime')

def lambda_handler(event, context):
    agent_id = event.get('AgentId')
    agent_alias_id = event.get('AgentAliasId')
    session_id = event.get('SessionId', 'default-session')
    input_text = event.get('InputText')
    
    try:
        response = bedrock_agent_runtime.invoke_agent(
            agentId=agent_id,
            agentAliasId=agent_alias_id,
            sessionId=session_id,
            inputText=input_text
        )
        
        completion_text = ""
        # Hứng từng cục dữ liệu (chunk) từ Event Stream của Bedrock Agent
        for event_stream in response.get('completion', []):
            if 'chunk' in event_stream:
                chunk = event_stream['chunk']
                completion_text += chunk.get('bytes', b'').decode('utf-8')
                
        return {"Completion": completion_text}
        
    except Exception as e:
        return {"error": str(e)}
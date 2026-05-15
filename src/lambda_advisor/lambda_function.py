import json
import boto3
import os

bedrock_agent_runtime = boto3.client('bedrock-agent-runtime')
SUPERVISOR_AGENT_ID = os.environ.get('SUPERVISOR_AGENT_ID')
SUPERVISOR_AGENT_ALIAS_ID = os.environ.get('SUPERVISOR_AGENT_ALIAS_ID')
ADVISOR_AGENT_ID = os.environ.get('ADVISOR_AGENT_ID')
ADVISOR_AGENT_ALIAS_ID = os.environ.get('ADVISOR_AGENT_ALIAS_ID')

def invoke_agent(agent_id, alias_id, session_id, input_text):
    response = bedrock_agent_runtime.invoke_agent(
        agentId=agent_id,
        agentAliasId=alias_id,
        sessionId=session_id,
        inputText=input_text,
        enableTrace=False
    )
    completion_text = ""
    for event_stream in response.get('completion', []):
        if 'chunk' in event_stream:
            chunk = event_stream['chunk']
            completion_text += chunk.get('bytes', b'').decode('utf-8')
    return completion_text.strip()

def lambda_handler(event, context):
    try:
        intelligence_package = event.get('intelligence_package', {})
        finding_id = event.get('finding_id', 'default-session')
        
        # BƯỚC 1: Gọi Supervisor Agent để phân tích và lấy cấu trúc JSON
        print(f"Invoking Supervisor Agent for {finding_id}...")
        supervisor_input = json.dumps(intelligence_package, default=str)
        supervisor_output = invoke_agent(
            SUPERVISOR_AGENT_ID, SUPERVISOR_AGENT_ALIAS_ID, finding_id, supervisor_input
        )
        
        # Dọn dẹp JSON output từ Supervisor (bỏ tag markdown nếu có)
        if supervisor_output.startswith('```json'): 
            supervisor_output = supervisor_output[7:]
        if supervisor_output.startswith('```'): 
            supervisor_output = supervisor_output[3:]
        if supervisor_output.endswith('```'): 
            supervisor_output = supervisor_output[:-3]
        supervisor_output = supervisor_output.strip()

        # BƯỚC 2: Gọi Advisor Agent truyền JSON vào để tạo Markdown Report
        print(f"Invoking Advisor Agent to generate report for {finding_id}...")
        advisor_output = invoke_agent(
            ADVISOR_AGENT_ID, ADVISOR_AGENT_ALIAS_ID, finding_id, supervisor_output
        )
        
        return {
            "remediation_plan": advisor_output,
            "intelligence_json": supervisor_output,
            "finding_id": finding_id,
            "error": False
        }
        
    except Exception as e:
        print(f"Error in Agent Pipeline: {str(e)}")
        return {
            "remediation_plan": f"Error generating intelligence package: {str(e)}",
            "finding_id": event.get('finding_id'),
            "error": True
        }
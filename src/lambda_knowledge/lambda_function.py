import json
import os
import boto3
from pinecone import Pinecone

bedrock_runtime = boto3.client('bedrock-runtime')

def get_embedding(text):
    body = json.dumps({"inputText": text})
    response = bedrock_runtime.invoke_model(
        body=body,
        modelId='amazon.titan-embed-text-v1',
        accept='application/json',
        contentType='application/json'
    )
    response_body = json.loads(response.get('body').read())
    return response_body.get('embedding')

def lambda_handler(event, context):
    # Khởi tạo bằng API_KEY và HOST
    pc = Pinecone(api_key=os.environ.get('PINECONE_API_KEY'))
    index = pc.Index(host=os.environ.get('PINECONE_HOST'))
    
    params = {p['name']: p['value'] for p in event.get('inputParameters', [])}
    
    finding_type = params.get("finding_type", "")
    resource_type = params.get("resource_type", "")
    
    filters = {"finding_type": {"$eq": finding_type}}
    if resource_type:
        filters["resource_type"] = {"$eq": resource_type}
    
    query_text = f"{finding_type} {resource_type}".strip()
    
    try:
        vector = get_embedding(query_text)
        query_response = index.query(
            vector=vector, 
            filter=filters, 
            top_k=1, 
            include_metadata=True
        )
        
        guideline = "No specific guidelines found in knowledge base."
        source = "Internal Database"
        
        if query_response['matches']:
            match = query_response['matches'][0]
            guideline = match['metadata'].get('text', guideline)
            source = match['metadata'].get('source_url', source)
            
        result = {"guidelines": guideline, "source": source}
        
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
    except Exception as e:
        return {"error": str(e)}
import json
import os
import boto3
from pinecone import Pinecone

bedrock_runtime = boto3.client('bedrock-runtime')

def get_embedding(text):
    """Generate embedding using Amazon Titan"""
    try:
        body = json.dumps({"inputText": text[:2000]})  # Limit text length
        
        response = bedrock_runtime.invoke_model(
            body=body,
            modelId='amazon.titan-embed-text-v2:0',
            accept='application/json',
            contentType='application/json'
        )
        
        response_body = json.loads(response.get('body').read())
        return response_body.get('embedding')
    except Exception as e:
        print(f"Error generating embedding: {e}")
        return None

def lambda_handler(event, context):
    """Retrieve remediation guidelines from Pinecone knowledge base"""
    try:
        # Initialize Pinecone
        pc = Pinecone(api_key=os.environ.get('PINECONE_API_KEY'))
        index = pc.Index(host=os.environ.get('PINECONE_HOST'))
        
        finding_type = event.get("finding_type", "")
        resource_type = event.get("resource_type", "")
        
        if not finding_type:
            return {
                "guidelines": "No finding type provided for knowledge retrieval",
                "source": "Error",
                "matches": []
            }
        
        # Build query text
        query_text = f"{finding_type} {resource_type}".strip()
        
        # Build filter
        filters = {"finding_type": {"$eq": finding_type}}
        if resource_type and resource_type != "Unknown":
            filters["resource_type"] = {"$eq": resource_type}
        
        # Get embedding and search
        vector = get_embedding(query_text)
        if not vector:
            return {
                "guidelines": "Unable to generate embedding for query",
                "source": "Error",
                "matches": []
            }
        
        query_response = index.query(
            vector=vector,
            filter=filters,
            top_k=3,
            include_metadata=True
        )
        
        guidelines = "No specific guidelines found in knowledge base."
        source = "Knowledge Base"
        all_matches = []
        
        if query_response.get('matches'):
            # Combine top matches
            guidelines_parts = []
            for i, match in enumerate(query_response['matches'][:2], 1):
                metadata = match.get('metadata', {})
                text = metadata.get('text', '') or metadata.get('text_to_embed', '')
                if text:
                    guidelines_parts.append(f"{i}. {text[:500]}...")
                    all_matches.append({
                        "id": match.get('id'),
                        "score": match.get('score'),
                        "source": metadata.get('source', 'Unknown')
                    })
            
            if guidelines_parts:
                guidelines = "\n\n".join(guidelines_parts)
                source = query_response['matches'][0].get('metadata', {}).get('source', 'Knowledge Base')
        
        # Add general guidelines if no specific matches
        if not guidelines_parts:
            guidelines = f"For {finding_type} on {resource_type}, follow standard incident response: isolate affected resource, investigate root cause, apply patches, and verify remediation."
        
        result = {
            "guidelines": guidelines,
            "source": source,
            "matches": all_matches,
            "finding_type": finding_type,
            "resource_type": resource_type
        }
        
        print(f"Retrieved {len(all_matches)} knowledge matches for {finding_type}")
        return result
        
    except Exception as e:
        print(f"Error retrieving knowledge: {str(e)}")
        return {
            "guidelines": "Error retrieving guidelines from knowledge base. Please refer to AWS Security Hub for manual remediation.",
            "source": "Error",
            "matches": [],
            "error": str(e)
        }
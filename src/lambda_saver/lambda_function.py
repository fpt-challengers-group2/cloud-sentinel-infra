import json
import boto3
import os

s3 = boto3.client('s3')

def lambda_handler(event, context):
    bucket_name = os.environ.get('REPORT_BUCKET_NAME')
    finding_id = event.get('finding_id', 'unknown_id')
    report_content = event.get('report_content', 'Empty report')
    
    final_data = {
        "incident_id": finding_id,
        "remediation_plan": report_content,
        "status": "AWAITING_REVIEW",
        "generated_at": event.get('metadata', {}).get('timestamp')
    }
    
    file_name = f"remediations/{finding_id}.json"
    
    try:
        s3.put_object(
            Bucket=bucket_name,
            Key=file_name,
            Body=json.dumps(final_data, indent=4, ensure_ascii=False),
            ContentType='application/json'
        )
        return {"status": "SUCCESS", "s3_path": f"s3://{bucket_name}/{file_name}"}
    except Exception as e:
        return {"status": "FAILED", "error": str(e)}
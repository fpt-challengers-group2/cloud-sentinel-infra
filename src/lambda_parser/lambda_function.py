import json
import re

def get_target_id(resource_type, resource_data):
    mapping = {
        "Instance": lambda d: d.get("instanceDetails", {}).get("instanceId"),
        "AccessKey": lambda d: d.get("accessKeyDetails", {}).get("accessKeyId"),
        "LambdaFunction": lambda d: d.get("lambdaDetails", {}).get("functionName"),
        "S3Bucket": lambda d: d.get("s3BucketDetails", {}).get("name"),
        "EKSCluster": lambda d: d.get("eksClusterDetails", {}).get("name"),
        "RDSDbInstance": lambda d: d.get("rdsDbInstanceDetails", {}).get("dbInstanceIdentifier"),
        "ECSCluster": lambda d: d.get("ecsClusterDetails", {}).get("clusterArn"),
        "Container": lambda d: d.get("containerDetails", {}).get("id"),
        "DBInstance": lambda d: d.get("rdsDbInstanceDetails", {}).get("dbInstanceIdentifier"),
        "EBSSnapshot": lambda d: d.get("ebsVolumeDetails", {}).get("snapshotId"),
        "IAMUser": lambda d: d.get("accessKeyDetails", {}).get("userName")
    }
    return mapping.get(resource_type, lambda d: "UNKNOWN")(resource_data)

def lambda_handler(event, context):
    try:
        params = {p['name']: p['value'] for p in event.get('inputParameters', [])}
        input_text = params.get('raw_finding', '') 
        
        if not input_text and event.get('inputText'):
            input_text = event['inputText']
            
        match = re.search(r"FINDING_DETAIL:\s*(\{.*\})", input_text)
        if not match:
            try:
                raw_detail = json.loads(input_text)
            except:
                raise ValueError("Không tìm thấy dữ liệu Finding hợp lệ.")
        else:
            raw_detail = json.loads(match.group(1))
            
        res_type = raw_detail.get('resource', {}).get('resourceType')
        
        parsed_result = {
            "finding_id": raw_detail.get('id'),
            "finding_type": raw_detail.get('type'),
            "severity": raw_detail.get('severity'),
            "resource_type": res_type,
            "target_id": get_target_id(res_type, raw_detail.get('resource', {})),
            "description": raw_detail.get('description'),
            "title": raw_detail.get('title', 'Unknown Title'),
            "region": raw_detail.get('region', 'Unknown Region')
        }
        
        return {
            "messageVersion": "1.0",
            "response": {
                "actionGroup": event['actionGroup'],
                "function": event['function'],
                "functionResponse": {
                    "mapping_status": "SUCCESS",
                    "responseBody": {
                        "TEXT": {"body": json.dumps(parsed_result)}
                    }
                }
            }
        }
    except Exception as e:
        return {"error": str(e)}
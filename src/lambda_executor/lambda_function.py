import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
HISTORY_TABLE = os.environ.get('DYNAMODB_HISTORY_TABLE')
REPORT_BUCKET = os.environ.get('REPORT_BUCKET_NAME')
table = dynamodb.Table(HISTORY_TABLE)

def block_ip_nacl(ip_address, region, finding_id):
    """Simulate blocking IP via Network ACL"""
    print(f"[SIMULATION] Blocking IP {ip_address} in {region}")
    # In production, implement actual NACL modification
    return {
        "action": "block_ip",
        "ip": ip_address,
        "status": "simulated_success"
    }

def isolate_instance(instance_id, region, finding_id):
    """Simulate isolating EC2 instance"""
    print(f"[SIMULATION] Isolating instance {instance_id} in {region}")
    # In production, implement security group modification
    return {
        "action": "isolate_instance",
        "instance_id": instance_id,
        "status": "simulated_success"
    }

def revoke_iam_keys(access_key_id, finding_id):
    """Simulate revoking IAM access keys"""
    print(f"[SIMULATION] Revoking access key {access_key_id}")
    return {
        "action": "revoke_keys",
        "access_key": access_key_id,
        "status": "simulated_success"
    }

def determine_action(finding, remediation_plan):
    """Determine which action to take based on finding type and plan"""
    finding_type = finding.get('finding_type', '')
    resource_type = finding.get('resource_type', '')
    severity = finding.get('severity', 'MEDIUM')
    
    # Rule-based action mapping (for demo purposes)
    if 'UnauthorizedAccess' in finding_type and 'EC2' in resource_type:
        return {
            "name": "isolate_instance",
            "func": isolate_instance,
            "params": {
                "instance_id": finding.get('target_id'),
                "region": finding.get('region')
            }
        }
    elif 'Backdoor' in finding_type and 'EC2' in resource_type:
        return {
            "name": "isolate_instance",
            "func": isolate_instance,
            "params": {
                "instance_id": finding.get('target_id'),
                "region": finding.get('region')
            }
        }
    elif 'Recon' in finding_type and 'EC2' in resource_type:
        return {
            "name": "block_ip",
            "func": block_ip_nacl,
            "params": {
                "ip_address": finding.get('attacker_ip'),
                "region": finding.get('region')
            }
        }
    elif 'IAM' in resource_type or 'CredentialAccess' in finding_type:
        return {
            "name": "revoke_keys",
            "func": revoke_iam_keys,
            "params": {
                "access_key_id": finding.get('target_id')
            }
        }
    else:
        # Default action: block IP if available
        if finding.get('attacker_ip') and finding.get('attacker_ip') != 'N/A':
            return {
                "name": "block_ip",
                "func": block_ip_nacl,
                "params": {
                    "ip_address": finding.get('attacker_ip'),
                    "region": finding.get('region')
                }
            }
        else:
            return {
                "name": "manual_review",
                "func": None,
                "params": {},
                "message": "No automated action available. Manual review required."
            }

def lambda_handler(event, context):
    """Execute remediation based on approved action"""
    try:
        finding = event.get('finding', {})
        approved_action = event.get('approved_action', {})
        remediation_plan = event.get('remediation_plan', '')
        finding_id = finding.get('finding_id')
        
        # Determine which action to execute
        action_config = determine_action(finding, remediation_plan)
        
        execution_result = {
            "finding_id": finding_id,
            "action_taken": action_config.get('name'),
            "status": "pending",
            "timestamp": datetime.utcnow().isoformat(),
            "details": {}
        }
        
        # Execute action if available
        if action_config.get('func'):
            try:
                result = action_config['func'](**action_config['params'], finding_id=finding_id)
                execution_result['status'] = 'success'
                execution_result['details'] = result
                print(f"Action {action_config['name']} executed successfully")
            except Exception as e:
                execution_result['status'] = 'failed'
                execution_result['error'] = str(e)
                print(f"Action failed: {str(e)}")
        else:
            execution_result['status'] = 'manual_required'
            execution_result['message'] = action_config.get('message', 'Manual review required')
        
        # Save to DynamoDB history
        history_item = {
            'finding_type': finding.get('finding_type', 'Unknown'),
            'target_id': finding.get('target_id', 'Unknown'),
            'finding_id': finding_id,
            'action_taken': execution_result['action_taken'],
            'outcome': execution_result['status'],
            'timestamp': execution_result['timestamp'],
            'severity': finding.get('severity', 'MEDIUM'),
            'attacker_ip': finding.get('attacker_ip', 'N/A'),
            'execution_details': json.dumps(execution_result.get('details', {})),
            'ttl': int((datetime.utcnow().timestamp() + 7776000))  # 90 days TTL
        }
        
        table.put_item(Item=history_item)
        
        # Save report to S3
        report_key = f"remediations/{finding_id}.json"
        report_content = {
            "finding_id": finding_id,
            "finding_type": finding.get('finding_type'),
            "action_taken": execution_result['action_taken'],
            "status": execution_result['status'],
            "remediation_plan": remediation_plan,
            "execution_details": execution_result.get('details', {}),
            "executed_at": execution_result['timestamp']
        }
        
        s3.put_object(
            Bucket=REPORT_BUCKET,
            Key=report_key,
            Body=json.dumps(report_content, indent=2, default=str),
            ContentType='application/json'
        )
        
        print(f"Remediation completed for {finding_id}: {execution_result['status']}")
        
        return {
            "statusCode": 200,
            "finding_id": finding_id,
            "action_taken": execution_result['action_taken'],
            "outcome": execution_result['status'],
            "s3_report": f"s3://{REPORT_BUCKET}/{report_key}"
        }
        
    except Exception as e:
        print(f"Error executing remediation: {str(e)}")
        raise e
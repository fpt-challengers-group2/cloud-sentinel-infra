import json
import re
from datetime import datetime

def get_target_id(resource_type, resource_data):
    """Extract target ID based on resource type"""
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
        "IAMUser": lambda d: d.get("accessKeyDetails", {}).get("userName") or 
                              d.get("userIdentity", {}).get("userName", "UNKNOWN")
    }
    return mapping.get(resource_type, lambda d: "UNKNOWN")(resource_data)

def get_attacker_info(resource_data):
    """Extract attacker IP and location from finding"""
    service = resource_data.get('service', {})
    
    # Try networkConnectionAction
    action = service.get('action', {})
    network_action = action.get('networkConnectionAction', {})
    dns_action = action.get('dnsRequestAction', {})
    
    remote_ip = "N/A"
    location = "Unknown"
    
    if network_action:
        remote_ip = network_action.get('remoteIpDetails', {}).get('ipAddressV4', 'N/A')
        location = network_action.get('remoteIpDetails', {}).get('country', {}).get('countryName', 'Unknown')
    elif dns_action:
        remote_ip = dns_action.get('remoteIpDetails', {}).get('ipAddressV4', 'N/A')
        location = dns_action.get('remoteIpDetails', {}).get('country', {}).get('countryName', 'Unknown')
    else:
        # Try finding directly
        remote_ip = service.get('resourceRole', 'N/A')
    
    return remote_ip, location

def lambda_handler(event, context):
    """Parse GuardDuty finding into structured format"""
    try:
        raw_detail = event.get('detail', {})
        
        # Extract core fields
        resource = raw_detail.get('resource', {})
        resource_type = resource.get('resourceType', 'Unknown')
        
        attacker_ip, location = get_attacker_info(raw_detail)
        
        severity_map = {
            'HIGH': 7,
            'MEDIUM': 4,
            'LOW': 1
        }
        
        # Parse severity
        severity_str = raw_detail.get('severity', 'Low')
        if isinstance(severity_str, (int, float)):
            if severity_str >= 7:
                severity = 'HIGH'
            elif severity_str >= 4:
                severity = 'MEDIUM'
            else:
                severity = 'LOW'
        else:
            severity = 'MEDIUM'
        
        # Build result
        result = {
            "finding_id": raw_detail.get('id'),
            "finding_type": raw_detail.get('type', 'Unknown'),
            "severity": severity,
            "resource_type": resource_type,
            "target_id": get_target_id(resource_type, resource),
            "attacker_ip": attacker_ip,
            "attacker_location": location,
            "region": raw_detail.get('region', 'Unknown'),
            "description": raw_detail.get('description', 'No description provided'),
            "title": raw_detail.get('title', 'Untitled Finding'),
            "timestamp": raw_detail.get('createdAt', datetime.utcnow().isoformat()),
            "raw_json": json.dumps(raw_detail, default=str)
        }
        
        print(f"Parsed finding: {result['finding_id']} - {result['finding_type']}")
        
        return {
            "statusCode": 200,
            "finding_id": result['finding_id'],
            "finding_type": result['finding_type'],
            "target_id": result['target_id'],
            "severity": result['severity'],
            "resource_type": result['resource_type'],
            "attacker_ip": result['attacker_ip'],
            "attacker_location": result['attacker_location'],
            "region": result['region'],
            "description": result['description'],
            "title": result['title'],
            "timestamp": result['timestamp'],
            "raw_json": result['raw_json']
        }
        
    except Exception as e:
        print(f"Error parsing finding: {str(e)}")
        raise e
# ============================================================================
# SUPERVISOR AGENT - Phân tích và tổng hợp thông tin từ GuardDuty
# ============================================================================

resource "aws_bedrockagent_agent" "supervisor" {
  agent_name                  = "${var.project_name}-supervisor"
  agent_resource_role_arn     = aws_iam_role.agent_role.arn
  foundation_model            = "anthropic.claude-3-5-sonnet-20240620-v1:0"
  idle_session_ttl_in_seconds = 600
  description                 = "Senior Cloud Security Orchestrator - Analyzes GuardDuty findings and creates intelligence packages"

  instruction = <<-EOT
    You are the Supervisor-CloudSentinel-Agent, a Senior Cloud Security Orchestrator.
    
    ## MISSION
    Your absolute goal is to analyze raw AWS GuardDuty logs and synthesize a high-fidelity "Intelligence Package" (JSON) for the Advisor Agent.
    
    ## INPUT FORMAT
    You will receive a JSON object with these fields:
    - finding_details: Raw GuardDuty finding data
    - historical_context: Previous incidents for this resource (if any)
    - remediation_guidelines: RAG results from knowledge base
    
    ## WORKFLOW (STRICT ORDER - DO NOT SKIP)
    
    ### PHASE 1 - CORE EXTRACTION
    1. Extract from finding_details:
       - finding_id: The unique identifier of the finding
       - finding_type: The type of finding (e.g., "UnauthorizedAccess:EC2/SSHBruteForce")
       - severity: Convert numeric severity (0.1-8.9) to HIGH/MEDIUM/LOW
         * HIGH: >= 7.0
         * MEDIUM: 4.0 - 6.9
         * LOW: < 4.0
       - region: AWS region where finding occurred
       - resource_type: Type of resource (EC2, IAM, S3, RDS, etc.)
       - title: Finding title
       - description: Detailed description
       - target_id: The affected resource identifier
    
    ### PHASE 2 - ATTACKER & NETWORK ANALYSIS
    Parse the finding_details to extract:
    - attacker_ip: Source IP address (look in service.action.networkConnectionAction.remoteIpDetails.ipAddressV4)
    - location: Country or Region of the source IP (look in service.action.networkConnectionAction.remoteIpDetails.country.countryName)
    - action_protocol: Port and Protocol used (look in service.action.networkConnectionAction.protocol and localPortDetails.port)
    
    ### PHASE 3 - HISTORICAL CONTEXT
    Use the "historical_context" provided to determine:
    - is_recurring: true if has_precedent is true
    - previous_action: action_taken from historical_context
    - recurrence_count: count from historical_context
    - notes: Additional historical notes
    
    ### PHASE 4 - KNOWLEDGE INTEGRATION
    Use the "remediation_guidelines" provided to include:
    - suggested_actions: Key remediation steps from guidelines
    - mitre_mapping: MITRE ATT&CK tactics if available
    - source: Source of the guidelines
    
    ## OUTPUT REQUIREMENT (STRICT)
    Your response MUST be a single, valid JSON object with the following structure:
    
    {
      "executive_summary": "Brief 1-sentence summary of the threat",
      "finding_id": "unique_id",
      "finding_type": "Finding.Type.Here",
      "severity": "HIGH/MEDIUM/LOW",
      "target": {
        "type": "EC2/IAM/S3/RDS/etc",
        "id": "resource_identifier",
        "region": "aws_region"
      },
      "attacker": {
        "ip": "x.x.x.x or N/A",
        "location": "Country or Unknown",
        "protocol_port": "TCP/22 or N/A"
      },
      "historical_analysis": {
        "is_recurring": true/false,
        "previous_action": "action or None",
        "recurrence_count": 0,
        "notes": "Historical context notes"
      },
      "remediation_guidelines": {
        "suggested_actions": "Key remediation steps",
        "mitre_mapping": "Tactic/Technique if available",
        "source": "Knowledge base source"
      },
      "raw_details": {
        "title": "Finding title",
        "description": "Full description",
        "timestamp": "ISO timestamp"
      }
    }
    
    ## RULES
    - Output ONLY valid JSON, no other text
    - NO markdown formatting (DO NOT use ```json blocks)
    - The response must start with "{" and end with "}"
    - Use "N/A" for missing values
    - Do not make up information not present in the input
  EOT
}

# ----------------------------------------------------------------------------
# Action Group 1: Finding Parser
# ----------------------------------------------------------------------------
resource "aws_bedrockagent_agent_action_group" "ag_parser" {
  action_group_name          = "FindingParserActionGroup"
  agent_id                   = aws_bedrockagent_agent.supervisor.id
  agent_version              = "DRAFT"
  skip_resource_in_use_check = true
  description                = "Extracts and parses raw GuardDuty finding logs into structured format"

  action_group_executor {
    lambda = aws_lambda_function.sentinel_lambdas["lambda_parser"].arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "parse_guardduty_finding"
        description = "Parse raw GuardDuty finding JSON and extract key fields including finding_id, finding_type, severity, resource_type, target_id, region, title, and description"

        parameters {
          map_block_key = "raw_finding_json"
          type          = "string"
          description   = "The raw GuardDuty finding JSON string from the event detail"
          required      = true
        }
      }
    }
  }
}

# ----------------------------------------------------------------------------
# Action Group 2: Precedent Check (DynamoDB History)
# ----------------------------------------------------------------------------
resource "aws_bedrockagent_agent_action_group" "ag_history" {
  action_group_name          = "PrecedentCheckActionGroup"
  agent_id                   = aws_bedrockagent_agent.supervisor.id
  agent_version              = "DRAFT"
  skip_resource_in_use_check = true
  description                = "Checks DynamoDB for historical incidents on the same resource"

  action_group_executor {
    lambda = aws_lambda_function.sentinel_lambdas["lambda_history"].arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "check_historical_precedent"
        description = "Query DynamoDB to check if this resource has experienced similar incidents in the past 90 days"

        parameters {
          map_block_key = "finding_type"
          type          = "string"
          description   = "The type of finding (e.g., UnauthorizedAccess:EC2/SSHBruteForce)"
          required      = true
        }

        parameters {
          map_block_key = "target_id"
          type          = "string"
          description   = "The unique identifier of the affected resource (instance ID, user ARN, bucket name, etc.)"
          required      = true
        }
      }
    }
  }
}

# ----------------------------------------------------------------------------
# Action Group 3: Knowledge Retrieval (Pinecone RAG)
# ----------------------------------------------------------------------------
resource "aws_bedrockagent_agent_action_group" "ag_knowledge" {
  action_group_name          = "KnowledgeRetrievalActionGroup"
  agent_id                   = aws_bedrockagent_agent.supervisor.id
  agent_version              = "DRAFT"
  skip_resource_in_use_check = true
  description                = "Retrieves remediation guidelines from Pinecone vector database using RAG"

  action_group_executor {
    lambda = aws_lambda_function.sentinel_lambdas["lambda_knowledge"].arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "retrieve_remediation_guidelines"
        description = "Search Pinecone knowledge base for remediation guidelines, MITRE ATT&CK mappings, and CIS benchmarks based on finding type and resource type"

        parameters {
          map_block_key = "finding_type"
          type          = "string"
          description   = "The type of finding to search for"
          required      = true
        }

        parameters {
          map_block_key = "resource_type"
          type          = "string"
          description   = "The type of AWS resource affected (EC2, IAM, S3, RDS, etc.)"
          required      = false
        }
      }
    }
  }
}


# ============================================================================
# ADVISOR AGENT - Tạo kế hoạch khắc phục chi tiết
# ============================================================================

resource "aws_bedrockagent_agent" "advisor" {
  agent_name                  = "${var.project_name}-advisor"
  agent_resource_role_arn     = aws_iam_role.agent_role.arn
  foundation_model            = "anthropic.claude-3-5-sonnet-20240620-v1:0"
  idle_session_ttl_in_seconds = 600
  description                 = "Senior Cloud Security Consultant - Creates detailed remediation plans from intelligence packages"

  instruction = <<-EOT
    You are the CloudSentinel-Advisor-Agent, a Senior Cloud Security Consultant.
    
    ## MISSION
    Transform the "intelligence_package" (JSON) received from the Supervisor Agent into a professional, high-priority Security Remediation Plan.
    
    ## INPUT STRUCTURE
    You will receive a JSON object with these fields:
    - finding_details: Parsed finding information
    - historical_context: Previous incident data (if any)
    - remediation_guidelines: RAG results from knowledge base
    
    ## YOUR TASK
    Create a comprehensive remediation plan with the following sections:
    
    ### 1. EXECUTIVE SUMMARY
    - Brief overview (2-3 sentences) of the threat
    - Severity level and urgency
    - Potential business impact
    
    ### 2. THREAT DETAILS
    - Finding type and ID
    - Affected resource (type, ID, region)
    - Attacker information (IP, location, method)
    - Timeline of events
    
    ### 3. HISTORICAL CONTEXT (if applicable)
    - Whether this is a recurring issue
    - Previous actions taken
    - Effectiveness of previous remediation
    
    ### 4. IMMEDIATE REMEDIATION STEPS (Priority 1 - Do NOW)
    Provide clear, numbered, actionable steps:
    - Step 1: [Action] - [Command/Console location] - [Expected result]
    - Step 2: [Action] - [Command/Console location] - [Expected result]
    - Step 3: [Action] - [Command/Console location] - [Expected result]
    
    ### 5. INVESTIGATION STEPS (Priority 2)
    Steps to determine root cause and scope:
    - Check CloudTrail logs for related activity
    - Review VPC Flow Logs for unusual traffic patterns
    - Examine resource access patterns
    
    ### 6. LONG-TERM RECOMMENDATIONS (Priority 3)
    Preventive measures to avoid recurrence:
    - Security group or NACL updates
    - IAM policy refinements
    - Monitoring and alerting improvements
    - Patch management
    
    ### 7. VERIFICATION
    How to confirm remediation was successful:
    - Commands to run
    - Logs to check
    - Metrics to monitor
    
    ### 8. ROLLBACK PLAN (if applicable)
    Steps to revert changes if remediation causes issues
    
    ## FORMATTING REQUIREMENTS
    - Use Markdown for clarity
    - Use bold for section headers: **Section Name**
    - Use bullet points for lists
    - Use code blocks for commands: `command here`
    - Keep paragraphs concise (3-4 sentences max)
    
    ## TONE
    - Professional, urgent, but not alarmist
    - Assume the reader is a security engineer with AWS knowledge
    - Be specific with AWS service names and console paths
    
    ## STRICT RULES
    - Do NOT make up information not present in the input
    - If a field is "N/A" or "Unknown", state that investigation is required
    - Do NOT include conversational text like "Here is your report"
    - Output ONLY the remediation plan, no extra text
    - Maximum length: 2000 words
  EOT
}

# Note: Advisor Agent has NO action groups - it works purely on the input JSON


# ============================================================================
# AGENT ALIASES (Production endpoints)
# ============================================================================

resource "aws_bedrockagent_agent_alias" "supervisor_prod" {
  agent_alias_name = "PROD"
  agent_id         = aws_bedrockagent_agent.supervisor.id
  description      = "Production alias for Supervisor Agent"

  depends_on = [
    aws_bedrockagent_agent_action_group.ag_parser,
    aws_bedrockagent_agent_action_group.ag_history,
    aws_bedrockagent_agent_action_group.ag_knowledge
  ]
}

resource "aws_bedrockagent_agent_alias" "advisor_prod" {
  agent_alias_name = "PROD"
  agent_id         = aws_bedrockagent_agent.advisor.id
  description      = "Production alias for Advisor Agent"
}


# ============================================================================
# OPTIONAL: Knowledge Base for Bedrock (Alternative to Pinecone)
# Nếu bạn muốn dùng Bedrock Knowledge Base thay vì Pinecone
# ============================================================================

# resource "aws_bedrockagent_data_source" "security_knowledge_base" {
#   knowledge_base_id = aws_bedrockagent_knowledge_base.security_kb.knowledge_base_id
#   name              = "security-docs"
#   data_source_configuration {
#     type = "S3"
#     s3_configuration {
#       bucket_arn = aws_s3_bucket.knowledge_base.arn
#     }
#   }
# }

# resource "aws_bedrockagent_knowledge_base" "security_kb" {
#   name     = "${var.project_name}-security-knowledge-base"
#   role_arn = aws_iam_role.agent_role.arn
#   knowledge_base_configuration {
#     type = "VECTOR"
#     vector_knowledge_base_configuration {
#       embedding_model_arn = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0"
#     }
#   }
#   storage_configuration {
#     type = "OPENSEARCH_SERVERLESS"
#     opensearch_serverless_configuration {
#       collection_arn = aws_opensearchserverless_collection.vector_store.arn
#       vector_index_name = "security_vectors"
#       field_mapping {
#         metadata_field = "metadata"
#         text_field     = "text"
#       }
#     }
#   }
# }


# ============================================================================
# OUTPUTS
# ============================================================================

output "supervisor_agent_id" {
  description = "ID of the Supervisor Agent"
  value       = aws_bedrockagent_agent.supervisor.id
}

output "supervisor_agent_alias_id" {
  description = "Alias ID of the Supervisor Agent"
  value       = aws_bedrockagent_agent_alias.supervisor_prod.agent_alias_id
}

output "advisor_agent_id" {
  description = "ID of the Advisor Agent"
  value       = aws_bedrockagent_agent.advisor.id
}

output "advisor_agent_alias_id" {
  description = "Alias ID of the Advisor Agent"
  value       = aws_bedrockagent_agent_alias.advisor_prod.agent_alias_id
}
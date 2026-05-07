# --- 2. Supervisor Agent ---
resource "aws_bedrockagent_agent" "supervisor" {
  agent_name                  = "${var.project_name}-supervisor"
  agent_resource_role_arn     = aws_iam_role.agent_role.arn
  foundation_model            = "anthropic.claude-3-5-sonnet-20240620-v1:0"
  idle_session_ttl_in_seconds = 600

  instruction = <<EOT
You are the Supervisor-CloudSentinel-Agent, a Senior Cloud Security Orchestrator. 
MISSION: 
Your absolute goal is to analyze raw AWS GuardDuty logs and synthesize a high-fidelity "Intelligence Package" (JSON) for the Advisor Agent.
CONTEXT:
Input format: "REGION: [Region]. EVENT_ID: [ID]. FINDING_DETAIL: [Raw JSON Log]".
WORKFLOW (STRICT ORDER - DO NOT SKIP):
PHASE 1 - CORE EXTRACTION:
1. Call "Finding_Parser_Tool" immediately. Pass the entire input string to the "raw_finding" parameter.
2. Retrieve 7 core fields: finding_id, finding_type, region, severity, resource_type, title, description, and target_id.
3. CRITICAL: If "target_id" is returned as "UNKNOWN", you MUST manually inspect the "resource" block in the "FINDING_DETAIL" to identify the victim's ID (e.g., InstanceId, FunctionName, or ClusterArn). If still not found, use "UNKNOWN_RESOURCE".
PHASE 2 - HISTORICAL CONTEXT:
1. Use the "finding_type" and "target_id" from Phase 1 to call "Precedent_Check".
2. This determines if the specific resource has a history of this incident type in DynamoDB.
PHASE 3 - KNOWLEDGE RETRIEVAL (RAG):
1. Use "finding_type" and "resource_type" as filters to call "Knowledge_Retrieval".
2. Obtain standardized remediation guidelines (MITRE ATT&CK / CIS Benchmarks) from the vector database.
PHASE 4 - ATTACKER & NETWORK ANALYSIS:
1. Manually parse the "FINDING_DETAIL" log to extract:
   - "attacker_ip": Source IP address (usually under service.action.networkConnectionAction).
   - "location": Country or Region of the source IP.
   - "action_protocol": Port and Protocol (TCP/UDP) used in the connection.
OUTPUT REQUIREMENT (STRICT):
- Your response MUST be a single, valid JSON object.
- NO conversational text, NO "Here is your report", NO markdown formatting (DO NOT use ```json blocks).
- The response must start with "{" and end with "}".
EOT
}

# --- Action Groups của Supervisor ---
resource "aws_bedrockagent_agent_action_group" "ag_parser" {
  action_group_name          = "Finding_Parser_Group"
  agent_id                   = aws_bedrockagent_agent.supervisor.id
  agent_version              = "DRAFT"
  skip_resource_in_use_check = true

  action_group_executor { lambda = aws_lambda_function.sentinel_lambdas["lambda_parser"].arn }

  function_schema {
    member_functions {
      functions {
        name        = "Finding_Parser_Tool"
        description = "Bóc tách thông tin từ log thô của GuardDuty"
        parameters {
          # Đã sửa thành map_block_key
          map_block_key = "raw_finding"
          type          = "string"
          description   = "Chuỗi log JSON thô"
          required      = true
        }
      }
    }
  }
}

resource "aws_bedrockagent_agent_action_group" "ag_history" {
  action_group_name          = "Precedent_Check_Group"
  agent_id                   = aws_bedrockagent_agent.supervisor.id
  agent_version              = "DRAFT"
  skip_resource_in_use_check = true

  action_group_executor { lambda = aws_lambda_function.sentinel_lambdas["lambda_history"].arn }

  function_schema {
    member_functions {
      functions {
        name        = "Precedent_Check"
        description = "Kiểm tra tiền lệ sự cố trong DynamoDB"
        parameters { 
          # Đã sửa thành map_block_key
          map_block_key = "finding_type" 
          type          = "string" 
          description   = "Loại sự cố"
          required      = true 
        }
        parameters { 
          # Đã sửa thành map_block_key
          map_block_key = "target_id" 
          type          = "string" 
          description   = "ID tài nguyên"
          required      = true 
        }
      }
    }
  }
}

resource "aws_bedrockagent_agent_action_group" "ag_knowledge" {
  action_group_name          = "Knowledge_Retrieval_Group"
  agent_id                   = aws_bedrockagent_agent.supervisor.id
  agent_version              = "DRAFT"
  skip_resource_in_use_check = true

  action_group_executor { lambda = aws_lambda_function.sentinel_lambdas["lambda_knowledge"].arn }

  function_schema {
    member_functions {
      functions {
        name        = "Knowledge_Retrieval"
        description = "Lấy hướng dẫn xử lý từ Pinecone"
        parameters { 
          # Đã sửa thành map_block_key
          map_block_key = "finding_type" 
          type          = "string" 
          description   = "Loại sự cố"
          required      = true 
        }
        parameters { 
          # Đã sửa thành map_block_key
          map_block_key = "resource_type" 
          type          = "string" 
          description   = "Loại tài nguyên"
          required      = false 
        }
      }
    }
  }
}

# --- 3. Advisor Agent ---
resource "aws_bedrockagent_agent" "advisor" {
  agent_name                  = "${var.project_name}-advisor"
  agent_resource_role_arn     = aws_iam_role.agent_role.arn
  foundation_model            = "anthropic.claude-3-5-sonnet-20240620-v1:0"
  idle_session_ttl_in_seconds = 600

  instruction = <<EOT
You are the CloudSentinel-Advisor-Agent, a Senior Cloud Security Consultant.
MISSION:
Your mission is to transform the "intelligence_package" (JSON) received from the Supervisor Agent into a professional, high-priority Security Remediation Plan.
CONTEXT:
You do not have tools. You rely entirely on the structured data provided in the input JSON to draft your advice.
INSTRUCTIONS:
1. Parse the incoming JSON "intelligence_package".
2. Create a report with the following mandatory sections:
   - EXECUTIVE SUMMARY: Brief overview of the threat and severity.
   - TARGET INFO: ID and type of the affected resource.
   - ATTACKER PROFILE: IP address, location, and the protocol/action used.
   - HISTORICAL ANALYSIS: Indicate if this is a recurring issue or a new threat.
   - STEP-BY-STEP REMEDIATION: Clear, actionable steps based on the "guidelines" provided in the JSON.
3. TONE: Professional, concise, and urgent.
4. FORMAT: Use Markdown for clarity (bolding, lists, headers).
STRICT RULE:
- Do not make up information. If a field in the JSON is "UNKNOWN", state that further investigation is required for that specific detail.
- Your response should be the text of the report ONLY.
EOT
}

# --- 4. Tạo Alias cho Agents ---
resource "aws_bedrockagent_agent_alias" "supervisor_prod" {
  agent_alias_name = "PROD"
  agent_id         = aws_bedrockagent_agent.supervisor.id
  
  depends_on = [
    aws_bedrockagent_agent_action_group.ag_parser,
    aws_bedrockagent_agent_action_group.ag_history,
    aws_bedrockagent_agent_action_group.ag_knowledge
  ]
}

resource "aws_bedrockagent_agent_alias" "advisor_prod" {
  agent_alias_name = "PROD"
  agent_id         = aws_bedrockagent_agent.advisor.id
}
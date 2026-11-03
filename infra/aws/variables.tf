variable "aws_region" {
  description = "AWS region for EC2, S3, and Bedrock. Confirm Bedrock model availability in this region."
  type        = string
  default     = "ap-south-1"
}

variable "budget_email" {
  description = "Email address for monthly AWS budget notifications."
  type        = string
}

variable "acme_email" {
  description = "Contact email for Let's Encrypt HTTPS origin certificates."
  type        = string
}

variable "instance_type" {
  description = "ARM64 EC2 instance size; t4g.small is a low-cost, low-capacity demo default."
  type        = string
  default     = "t4g.small"
}

variable "chat_model" {
  description = "Amazon Bedrock Converse model ID available in aws_region."
  type        = string
  default     = "amazon.nova-micro-v1:0"
}

variable "embedding_model" {
  description = "Bedrock Titan embedding model. This model change requires re-indexing all documents."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "monthly_budget_usd" {
  description = "AWS monthly budget alert threshold. Alerts do not stop usage."
  type        = number
  default     = 25
}

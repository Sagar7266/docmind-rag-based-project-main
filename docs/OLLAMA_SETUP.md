# Local Ollama models

DocMind defaults to the `dev` profile for local runs, using locally installed Ollama models for chat and document embeddings:

- Chat: `qwen3.5:9b`
- Embeddings: `qwen3-embedding:0.6b` (1024 dimensions)

Pull both models before starting the backend:

```shell
ollama pull qwen3.5:9b
ollama pull qwen3-embedding:0.6b
```

Ollama must be running and reachable at `http://localhost:11434`. Set `OLLAMA_BASE_URL` if Ollama is hosted elsewhere. If the backend itself runs in a container while Ollama runs on the host, use the host address reachable from that container (for example, `http://host.docker.internal:11434` on Docker Desktop).

For a backend launched directly from the IDE, PostgreSQL must be reachable on the host-published port `localhost:5434`; set `DB_USER` and `DB_PASSWORD` to match that database. Container deployments use the database service address; the AWS Compose deployment uses `postgres:5432`, which is only resolvable inside its Docker network.

The `dev` profile supplies a development-only default for `JWT_SECRET`. Production deployments must explicitly activate `prod` and supply a strong `JWT_SECRET`; AWS deployment generates and provides one at runtime.

Model names can be changed with `OLLAMA_CHAT_MODEL` and `OLLAMA_EMBEDDING_MODEL`. Pull any overridden models into Ollama before launching the backend; model pulling at application startup is disabled. An alternate embedding model must return 1024-dimensional vectors unless the pgvector dimension and table are migrated to match it.

The dev profile disables Qwen's thinking mode by default. Streaming logs report generated-token throughput and duration. Production uses Amazon Bedrock; see [AWS deployment](AWS_DEPLOYMENT.md). Changing embedding providers requires a fresh vector index and document re-upload.

## Local Amazon Bedrock profile

To run locally with Bedrock instead of Ollama, start the backend with the `bedrock-local` Spring profile. It uses the host PostgreSQL database at `localhost:5434`, Amazon Nova Micro for chat, and Titan Text Embeddings V2 at 1024 dimensions. Ensure the local PostgreSQL Compose service is running and that your AWS identity has Bedrock model access and invoke permissions in the selected region.

The AWS SDK uses its standard credential provider chain; no AWS keys are stored in the application configuration. Configure AWS CLI credentials (for example, with an SSO profile), then select the profile and start the backend:

```shell
aws configure sso --profile docmind
aws sso login --profile docmind
aws sts get-caller-identity --profile docmind
aws bedrock list-inference-profiles \
  --region ap-south-1 \
  --type-equals SYSTEM_DEFINED \
  --query "inferenceProfileSummaries[].{Name:inferenceProfileName,Id:inferenceProfileId,Arn:inferenceProfileArn}" \
  --output table
export AWS_PROFILE=docmind
export AWS_REGION=ap-south-1
export SPRING_PROFILES_ACTIVE=bedrock-local
# Replace this value with an inference profile ID or ARN from the list that includes Nova Micro.
export BEDROCK_CHAT_MODEL="YOUR_INFERENCE_PROFILE_ID_OR_ARN"
./mvnw spring-boot:run
```

In IntelliJ, set `SPRING_PROFILES_ACTIVE=bedrock-local`, `AWS_PROFILE=docmind`, `BEDROCK_CHAT_MODEL` to the selected inference profile ID or ARN, and optionally `AWS_REGION` in the run configuration. The profile defaults to `ap-south-1`; override the embedding model with `BEDROCK_EMBEDDING_MODEL`. The configured AWS identity must be allowed to invoke the inference profile and its underlying model. `BEDROCK_CHAT_MODEL` is required because direct Nova Micro on-demand invocation is not available in every account or region. The normal `dev`/Ollama profile remains the default. Bedrock requests can incur AWS charges.

## Vector table

Ollama uses the existing `vector_store` table with 1024-dimensional vectors. It must be empty before switching from a different embedding model; embeddings from different models or dimensions cannot be mixed. DocMind does not keep copies of uploaded files, so upload documents again to index them with Ollama.

If `vector_store` already exists with a different embedding dimension, first verify it is empty, then change its embedding column to 1024 dimensions:

```sql
SELECT COUNT(*) FROM vector_store;
ALTER TABLE vector_store ALTER COLUMN embedding TYPE vector(1024);
```

Skip the `ALTER TABLE` if `vector_store` does not exist yet; Spring AI will initialize it with the configured 1024-dimensional schema. Do not run the alteration if the table contains rows.

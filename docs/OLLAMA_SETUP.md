# Local Ollama models

DocMind's default `dev` profile uses the locally installed Ollama model for both chat and document embeddings:

- Chat: `llama3.2:latest`
- Embeddings: `qwen3-embedding:0.6b` (1024 dimensions)

Pull the embedding model before starting the backend; the chat model is already installed in the current Ollama instance:

```shell
ollama pull qwen3-embedding:0.6b
```

Ollama must be running and reachable at `http://localhost:11434`. The installed `llama3.2:latest` model is used for chat only; Ollama needs a dedicated embedding model for `/api/embed`. Set `OLLAMA_BASE_URL` if Ollama is hosted elsewhere. If the backend itself runs in a container while Ollama runs on the host, use the host address reachable from that container (for example, `http://host.docker.internal:11434` on Docker Desktop).

Model names can be changed with `OLLAMA_CHAT_MODEL` and `OLLAMA_EMBEDDING_MODEL`. Pull any overridden models into Ollama before launching the backend; model pulling at application startup is disabled. An alternate embedding model must return 1024-dimensional vectors unless the pgvector dimension and table are migrated to match it.

The dev profile disables Qwen's thinking mode by default and limits generated answers to 256 tokens to reduce completion time. Set `OLLAMA_CHAT_THINK=TRUE` to re-enable thinking, or increase `OLLAMA_CHAT_MAX_TOKENS` for longer answers. Streaming logs report generated-token throughput and duration so you can measure the effect.

## Vector table

Ollama uses the existing `vector_store` table with 1024-dimensional vectors. It must be empty before switching from a different embedding model; embeddings from different models or dimensions cannot be mixed. DocMind does not keep copies of uploaded files, so upload documents again to index them with Ollama.

If `vector_store` already exists with a different embedding dimension, first verify it is empty, then change its embedding column to 1024 dimensions:

```sql
SELECT COUNT(*) FROM vector_store;
ALTER TABLE vector_store ALTER COLUMN embedding TYPE vector(1024);
```

Skip the `ALTER TABLE` if `vector_store` does not exist yet; Spring AI will initialize it with the configured 1024-dimensional schema. Do not run the alteration if the table contains rows.

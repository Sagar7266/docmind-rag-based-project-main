package com.substring.docmind.config;


import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import lombok.extern.slf4j.Slf4j;
import org.modelmapper.ModelMapper;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Slf4j
@Configuration
public class ProjectConfig {


    @Bean
    public ChatClient chatClient(ChatClient.Builder builder, ChatMemory memory) {


        log.info("Chatmemory class name {} ", memory.getClass().getName());
        return builder
                .defaultSystem("""
                        You are DocMind. Answer clearly, helpfully, and concisely in Markdown.
                        For document questions, prioritize the provided context and cite filenames and page numbers when available. If it is incomplete, supplement with general knowledge. Answer general questions normally.

                        Document context:
                        {doc_context}
                        """)
                .defaultAdvisors(MessageChatMemoryAdvisor.builder(memory).build())
                .build();
    }


    @Bean
    public OpenAPI openAPI() {

        String securitySchemeName = "bearerAuth";

        return new OpenAPI()
                .info(
                        new Info()
                                .title("DocMind — AI Document Intelligence & RAG backend")
                                .description("REST API for DocMind: Multi-format document ingestion, vector embeddings with PostgreSQL pgvector, and hybrid conversational Q&A with configurable AI providers.")

                                .version("1.0.0")
                                .contact(new Contact()
                                        .name("Substring Technologies")
                                        .email("support@substringtechnolgoies.com")
                                        .url("https://substringtechnologies.com")
                                )

                ).components(new Components()
                        .addSecuritySchemes(
                                securitySchemeName,
                                new SecurityScheme()
                                        .name(securitySchemeName)
                                        .type(SecurityScheme.Type.HTTP)
                                        .scheme("bearer")
                                        .bearerFormat("JWT")
                        ))

                .addSecurityItem(
                        new SecurityRequirement()
                                .addList(securitySchemeName)
                );


    }

    @Bean
    public ModelMapper modelMapper() {
        return new ModelMapper();
    }
}

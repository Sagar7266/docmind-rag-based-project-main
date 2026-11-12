package com.substring.docmind.service;

import com.substring.docmind.entity.DocumentMetadata;
import com.substring.docmind.repository.DocumentMetadataRepo;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.modelmapper.ModelMapper;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Optional;
import java.util.UUID;

import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class DocumentMetadataServiceTest {

    @Test
    void deletesVectorsFromVectorStoreBeforeDeletingMetadata() {
        UUID documentId = UUID.randomUUID();
        DocumentMetadata metadata = DocumentMetadata.builder().id(documentId).build();
        DocumentMetadataRepo repository = mock(DocumentMetadataRepo.class);
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        String deleteQuery = String.format(
                "DELETE FROM %s.%s WHERE metadata->>'documentId' = ?",
                "\"public\"",
                "\"vector_store_gemini_prod\""
        );
        when(repository.findById(documentId)).thenReturn(Optional.of(metadata));
        when(jdbcTemplate.update(
                deleteQuery,
                documentId.toString()
        )).thenReturn(2);

        service(repository, jdbcTemplate, "vector_store_gemini_prod", "public").deleteDocument(documentId);

        var order = inOrder(jdbcTemplate, repository);
        order.verify(jdbcTemplate).update(
                deleteQuery,
                documentId.toString()
        );
        order.verify(repository).delete(metadata);
    }

    @Test
    void rejectsUnsafeVectorStoreIdentifiers() {
        Assertions.assertThrows(IllegalArgumentException.class,
                () -> service(mock(DocumentMetadataRepo.class), mock(JdbcTemplate.class), "vector_store; DROP TABLE users", "public"));
    }

    private DocumentMetadataService service(
            DocumentMetadataRepo repository,
            JdbcTemplate jdbcTemplate,
            String tableName,
            String schemaName
    ) {
        return new DocumentMetadataService(
                repository,
                mock(DocumentParserService.class),
                mock(DocumentIngestionService.class),
                mock(ModelMapper.class),
                jdbcTemplate,
                tableName,
                schemaName
        );
    }
}

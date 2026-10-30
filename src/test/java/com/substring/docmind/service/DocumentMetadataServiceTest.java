package com.substring.docmind.service;

import com.substring.docmind.entity.DocumentMetadata;
import com.substring.docmind.repository.DocumentMetadataRepo;
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
        when(repository.findById(documentId)).thenReturn(Optional.of(metadata));
        when(jdbcTemplate.update(
                "DELETE FROM vector_store WHERE metadata->>'documentId' = ?",
                documentId.toString()
        )).thenReturn(2);

        service(repository, jdbcTemplate).deleteDocument(documentId);

        var order = inOrder(jdbcTemplate, repository);
        order.verify(jdbcTemplate).update(
                "DELETE FROM vector_store WHERE metadata->>'documentId' = ?",
                documentId.toString()
        );
        order.verify(repository).delete(metadata);
    }

    private DocumentMetadataService service(
            DocumentMetadataRepo repository,
            JdbcTemplate jdbcTemplate
    ) {
        return new DocumentMetadataService(
                repository,
                mock(DocumentParserService.class),
                mock(DocumentIngestionService.class),
                mock(ModelMapper.class),
                jdbcTemplate
        );
    }
}

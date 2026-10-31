/** Private attachments are reachable only through the VK session and transaction visibility rules. */
public without sharing class ReceiptService {
    public static final Integer MAX_BYTES = 350000;
    private static final String FIELDS = 'Transaction__c, Member__c, File_Name__c, Mime_Type__c, Bytes__c, Attachment_Id__c, Content_Version_Id__c, Content_Document_Id__c, CreatedDate';

    public static List<Map<String, Object>> listReceipts(UserContext ctx, Id transactionId) {
        EnhancementService.requireFeature(ctx, 'RECEIPTS', 'READ');
        TransactionService.getTransaction(ctx, transactionId);
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Transaction_Receipt__c r : (List<Transaction_Receipt__c>) Database.queryWithBinds('SELECT ' + FIELDS +
            ' FROM Transaction_Receipt__c WHERE Family__c = :fid AND Transaction__c = :tid ORDER BY CreatedDate DESC LIMIT 5',
            new Map<String, Object>{ 'fid' => ctx.familyId, 'tid' => transactionId }, AccessLevel.SYSTEM_MODE)) result.add(dto(r));
        return result;
    }

    public static Map<String, Object> upload(UserContext ctx, Id transactionId, Map<String, Object> body) {
        EnhancementService.requireFeature(ctx, 'RECEIPTS', 'CREATE');
        FinanceDtos.Txn txn = TransactionService.getTransaction(ctx, transactionId);
        if (!txn.canEdit) throw new PortalException('NOT_AUTHORIZED').withError('You can only attach receipts to an entry you can edit.');
        String encoded = LedgerUtil.text(body, 'data');
        if (String.isBlank(encoded) || encoded.length() > 470000) throw EnhancementService.invalid('Use an image smaller than 350 KB after compression.');
        Blob content;
        try { content = EncodingUtil.base64Decode(encoded); } catch (Exception e) { throw EnhancementService.invalid('The receipt image is invalid.'); }
        if (content.size() > MAX_BYTES || content.size() < 12) throw EnhancementService.invalid('Choose a valid receipt image up to 350 KB.');
        String signature = EncodingUtil.convertToHex(content).left(24).toLowerCase();
        String mime = LedgerUtil.text(body, 'mimeType');
        Boolean valid = (mime == 'image/jpeg' && signature.startsWith('ffd8ff')) ||
            (mime == 'image/png' && signature.startsWith('89504e470d0a1a0a')) ||
            (mime == 'image/webp' && signature.startsWith('52494646') && signature.endsWith('57454250'));
        if (!valid) throw EnhancementService.invalid('Choose a JPEG, PNG or WebP photo.');
        String fileName = EnhancementService.title(body, 'fileName', 120).replaceAll('[^a-zA-Z0-9 ._-]', '_');
        String key = TokenService.hash(String.valueOf(transactionId) + ':' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', content)));
        // Serialize per transaction so two uploads cannot bypass the five-image cap.
        List<Transaction__c> locked = [SELECT Id FROM Transaction__c WHERE Id = :transactionId AND Family__c = :ctx.familyId WITH SYSTEM_MODE FOR UPDATE];
        List<Transaction_Receipt__c> existing = [SELECT Id FROM Transaction_Receipt__c WHERE Family__c = :ctx.familyId AND Dedupe_Key__c = :key WITH SYSTEM_MODE LIMIT 1];
        if (!existing.isEmpty()) return dto((Transaction_Receipt__c) EnhancementService.record(ctx, 'Transaction_Receipt__c', FIELDS, existing[0].Id, false));
        if ([SELECT COUNT() FROM Transaction_Receipt__c WHERE Family__c = :ctx.familyId AND Transaction__c = :transactionId WITH SYSTEM_MODE] >= 5)
            throw EnhancementService.invalid('An entry can have up to five receipt photos.');
        Family__c family = [SELECT OwnerId FROM Family__c WHERE Id = :ctx.familyId WITH SYSTEM_MODE];
        Transaction_Receipt__c receipt = new Transaction_Receipt__c(Family__c = ctx.familyId, Member__c = ctx.userId,
            Transaction__c = transactionId, File_Name__c = fileName, Mime_Type__c = mime, Bytes__c = content.size(),
            Dedupe_Key__c = key);
        insert as system receipt;
        // ContentVersion queries are platform-blocked for the site guest even in
        // system mode. A private Attachment on the private mapping avoids that
        // restriction without granting guest file or record access.
        Attachment attachment = new Attachment(ParentId = receipt.Id, Name = fileName, ContentType = mime,
            Body = content, OwnerId = family.OwnerId, IsPrivate = true);
        insert as system attachment;
        update as system new Transaction_Receipt__c(Id = receipt.Id, Attachment_Id__c = attachment.Id);
        AuditService.log(ctx, 'RECEIPT_UPLOADED', 'Transaction_Receipt__c', receipt.Id, String.valueOf(content.size()) + ' bytes');
        return dto(receipt);
    }

    public static Map<String, Object> download(UserContext ctx, Id receiptId) {
        EnhancementService.requireFeature(ctx, 'RECEIPTS', 'READ');
        Transaction_Receipt__c receipt = (Transaction_Receipt__c) EnhancementService.record(ctx, 'Transaction_Receipt__c', FIELDS, receiptId, false);
        TransactionService.getTransaction(ctx, receipt.Transaction__c);
        Map<String, Object> result = dto(receipt);
        if (receipt.Attachment_Id__c != null) {
            Id attachmentId = (Id) receipt.Attachment_Id__c;
            List<Attachment> images = [SELECT Body FROM Attachment WHERE Id = :attachmentId AND ParentId = :receiptId WITH SYSTEM_MODE LIMIT 1];
            if (images.isEmpty()) throw new PortalException('NOT_FOUND');
            result.put('data', EncodingUtil.base64Encode(images[0].Body));
        } else {
            // Preserve access for any older internally-created Files receipts.
            Id versionId = (Id) receipt.Content_Version_Id__c;
            List<ContentVersion> images = [SELECT VersionData FROM ContentVersion WHERE Id = :versionId WITH SYSTEM_MODE LIMIT 1];
            if (images.isEmpty()) throw new PortalException('NOT_FOUND');
            result.put('data', EncodingUtil.base64Encode(images[0].VersionData));
        }
        return result;
    }

    public static void remove(UserContext ctx, Id receiptId) {
        EnhancementService.requireFeature(ctx, 'RECEIPTS', 'DELETE');
        Transaction_Receipt__c receipt = (Transaction_Receipt__c) EnhancementService.record(ctx, 'Transaction_Receipt__c', FIELDS, receiptId, true);
        FinanceDtos.Txn txn = TransactionService.getTransaction(ctx, receipt.Transaction__c);
        if (!txn.canEdit) throw new PortalException('NOT_AUTHORIZED');
        Id documentId = (Id) receipt.Content_Document_Id__c;
        if (receipt.Attachment_Id__c != null) {
            Id attachmentId = (Id) receipt.Attachment_Id__c;
            delete as system [SELECT Id FROM Attachment WHERE Id = :attachmentId AND ParentId = :receiptId WITH SYSTEM_MODE];
        }
        delete as system receipt;
        if (documentId != null) delete as system [SELECT Id FROM ContentDocument WHERE Id = :documentId WITH SYSTEM_MODE];
        AuditService.log(ctx, 'RECEIPT_REMOVED', 'Transaction_Receipt__c', receiptId, null);
    }

    private static Map<String, Object> dto(Transaction_Receipt__c r) {
        return new Map<String, Object>{ 'id' => r.Id, 'fileName' => r.File_Name__c, 'mimeType' => r.Mime_Type__c,
            'bytes' => r.Bytes__c, 'transactionId' => r.Transaction__c, 'createdAt' => r.CreatedDate };
    }
}
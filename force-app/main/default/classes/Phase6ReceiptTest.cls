@IsTest
private class Phase6ReceiptTest {
    @TestSetup static void setup() {
        VkfTestData.twoFamilies(); List<Family__c> families=[SELECT Id FROM Family__c WITH SYSTEM_MODE];
        for(Family__c f:families) f.Enhancements__c='RECEIPTS'; update as system families;
    }
    @IsTest static void photoIsPrivateDeduplicatedAndRemovedWithItsFile() {
        VkfTestData.fastPolicy(); UserContext admin=VkfTestData.ctx('admina');
        Id account=LedgerTestData.account(admin,'Bank','Savings',1000).id;
        Id txn=LedgerTestData.entry(admin,'Expense',50,account,LedgerTestData.categoryId(admin,'Groceries')).id;
        String data='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aOioAAAAASUVORK5CYII=';
        Map<String,Object> body=new Map<String,Object>{'fileName'=>'receipt.png','mimeType'=>'image/png','data'=>data};
        Id receipt=(Id) ReceiptService.upload(admin,txn,body).get('id');
        Assert.areEqual(receipt,ReceiptService.upload(admin,txn,body).get('id'));
        Assert.areEqual(1,ReceiptService.listReceipts(admin,txn).size());
        Id attachmentId = (Id) [SELECT Attachment_Id__c FROM Transaction_Receipt__c WHERE Id = :receipt WITH SYSTEM_MODE].Attachment_Id__c;
        Attachment image = [SELECT ParentId, IsPrivate, OwnerId FROM Attachment WHERE Id = :attachmentId WITH SYSTEM_MODE];
        Assert.areEqual(receipt, image.ParentId);
        Assert.isTrue(image.IsPrivate, 'Receipts must never become public attachments.');
        Assert.areEqual([SELECT OwnerId FROM Family__c WHERE Id = :admin.familyId WITH SYSTEM_MODE].OwnerId, image.OwnerId);
        Map<String,Object> downloaded=ReceiptService.download(admin,receipt);
        Assert.areEqual(data,downloaded.get('data'));
        Assert.isFalse(downloaded.containsKey('Content_Document_Id__c'));
        try { ReceiptService.download(VkfTestData.ctx('adminb'),receipt); Assert.fail(); } catch(PortalException e) { Assert.areEqual('NOT_FOUND',e.code()); }
        ReceiptService.remove(admin,receipt);
        Assert.areEqual(0,ReceiptService.listReceipts(admin,txn).size());
        Assert.areEqual(0, [SELECT COUNT() FROM Attachment WHERE Id = :attachmentId WITH SYSTEM_MODE]);
        Assert.areEqual(950,LedgerTestData.balance(account));
    }
    @IsTest static void mismatchedImageSignatureIsRejected() {
        VkfTestData.fastPolicy(); UserContext admin=VkfTestData.ctx('admina');
        Id account=LedgerTestData.account(admin,'Bank','Savings',1000).id;
        Id txn=LedgerTestData.entry(admin,'Expense',50,account,LedgerTestData.categoryId(admin,'Groceries')).id;
        try { ReceiptService.upload(admin,txn,new Map<String,Object>{'fileName'=>'bad.jpg','mimeType'=>'image/jpeg','data'=>EncodingUtil.base64Encode(Blob.valueOf('<script>bad image</script>'))}); Assert.fail(); }
        catch(PortalException e) { Assert.areEqual('VALIDATION',e.code()); }
        Assert.areEqual(0,[SELECT COUNT() FROM Transaction_Receipt__c WITH SYSTEM_MODE]);
    }
}

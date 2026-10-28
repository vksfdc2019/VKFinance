@IsTest
private class Phase6ResourceTest {
    @TestSetup static void setup() { VkfTestData.twoFamilies(); }
    @IsTest static void newRoutesRequireSessionAndKeepDisabledFeaturesClosed() {
        VkfTestData.fastPolicy();
        RestResponse res=VkfTestData.call('GET','/services/apexrest/vkf/v1/enhancements/settings',null,null);
        VkfEnhancementsResource.get(); Assert.areEqual(401,res.statusCode);
        String token=VkfTestData.login('admina');
        res=VkfTestData.call('GET','/services/apexrest/vkf/v1/enhancements/settings',null,token);
        VkfEnhancementsResource.get(); Assert.areEqual(200,res.statusCode);
        Assert.areEqual(0,((List<Object>)VkfTestData.json(res).get('enabled')).size());
        res=VkfTestData.call('GET','/services/apexrest/vkf/v1/enhancements/goals',null,token);
        VkfEnhancementsResource.get(); Assert.areEqual(403,res.statusCode);
        res=VkfTestData.call('POST','/services/apexrest/vkf/v1/enhancements/goals','[]',token);
        VkfEnhancementsResource.post(); Assert.areEqual(400,res.statusCode);
        res=VkfTestData.call('GET','/services/apexrest/vkf/v1/enhancements/unknown',null,token);
        VkfEnhancementsResource.get(); Assert.areEqual(404,res.statusCode);
    }

    private static RestResponse invoke(String method, String path, String body, String token) {
        RestResponse response = VkfTestData.call(method, '/services/apexrest/vkf/v1/enhancements/' + path, body, token);
        if (method == 'GET') VkfEnhancementsResource.get();
        if (method == 'POST') VkfEnhancementsResource.post();
        if (method == 'PATCH') VkfEnhancementsResource.patch();
        if (method == 'DELETE') VkfEnhancementsResource.remove();
        return response;
    }

    @IsTest static void settingsGoalsAndImportRoutesRoundTrip() {
        VkfTestData.fastPolicy(); String token = VkfTestData.login('admina');
        UserContext admin = SessionService.require(token, VkfTestData.UA);
        RestResponse response = invoke('PATCH','settings',JSON.serialize(new Map<String,Object>{ 'enabled'=>new List<String>{'GOALS','IMPORTS','RECEIPTS','REQUESTS','INSIGHTS'},'currentPassword'=>VkfTestData.PASSWORD }),token);
        Assert.areEqual(200,response.statusCode,response.responseBody.toString());
        Id account = LedgerTestData.account(admin,'Savings','Savings',1000).id;
        response = invoke('POST','goals',JSON.serialize(new Map<String,Object>{'title'=>'Holiday','target'=>2000,'accountId'=>account,'includeExisting'=>true}),token);
        Assert.areEqual(201,response.statusCode,response.responseBody.toString());
        String goalId = String.valueOf(VkfTestData.json(response).get('id'));
        Assert.areEqual(200,invoke('GET','goals',null,token).statusCode);
        Assert.areEqual(200,invoke('PATCH','goals/'+goalId,JSON.serialize(new Map<String,Object>{'title'=>'Holiday updated','target'=>2500}),token).statusCode);
        Assert.areEqual(204,invoke('DELETE','goals/'+goalId,null,token).statusCode);
        Map<String,Object> entry = new Map<String,Object>{'type'=>'Expense','amount'=>10,'date'=>String.valueOf(Date.today()),'categoryId'=>LedgerTestData.categoryId(admin,'Groceries')};
        response = invoke('POST','imports',JSON.serialize(new Map<String,Object>{'fileName'=>'test.csv','accountId'=>account,'rows'=>new List<Object>{entry}}),token);
        Assert.areEqual(201,response.statusCode,response.responseBody.toString());
        String importId = String.valueOf(VkfTestData.json(response).get('id'));
        Assert.areEqual(200,invoke('GET','imports',null,token).statusCode);
        Assert.areEqual(200,invoke('GET','imports/'+importId,null,token).statusCode);
        Assert.areEqual(200,invoke('POST','imports/'+importId+'/cancel','{}',token).statusCode);
        Assert.areEqual(200,invoke('GET','insights',null,token).statusCode);
    }

    @IsTest static void requestsAndReceiptsUseTheSameSessionBoundary() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina'), child = VkfTestData.ctx('childa');
        update as system new Family__c(Id=admin.familyId,Enhancements__c='REQUESTS,RECEIPTS,INSIGHTS');
        String adminToken=VkfTestData.login('admina'), childToken=VkfTestData.login('childa');
        Id account=AccountService.createAccount(admin,new Map<String,Object>{'name'=>'Pocket','type'=>'Cash','openingBalance'=>500,'ownerId'=>child.userId}).id;
        RestResponse response=invoke('POST','requests',JSON.serialize(new Map<String,Object>{'title'=>'School','amount'=>50,'accountId'=>account,'categoryId'=>LedgerTestData.categoryId(admin,'Groceries')}),childToken);
        Assert.areEqual(201,response.statusCode,response.responseBody.toString());
        String requestId=String.valueOf(VkfTestData.json(response).get('id'));
        Assert.areEqual(200,invoke('GET','requests',null,adminToken).statusCode);
        Assert.areEqual(200,invoke('POST','requests/'+requestId+'/approve','{}',adminToken).statusCode);
        response=invoke('POST','requests/'+requestId+'/record','{}',childToken);
        Assert.areEqual(200,response.statusCode,response.responseBody.toString());
        String txn=String.valueOf(VkfTestData.json(response).get('transactionId'));
        String data='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aOioAAAAASUVORK5CYII=';
        response=invoke('POST','transactions/'+txn+'/receipts',JSON.serialize(new Map<String,Object>{'fileName'=>'receipt.png','mimeType'=>'image/png','data'=>data}),childToken);
        Assert.areEqual(201,response.statusCode,response.responseBody.toString());
        String receipt=String.valueOf(VkfTestData.json(response).get('id'));
        Assert.areEqual(200,invoke('GET','transactions/'+txn+'/receipts',null,childToken).statusCode);
        Assert.areEqual(200,invoke('GET','receipts/'+receipt,null,childToken).statusCode);
        Assert.areEqual(204,invoke('DELETE','receipts/'+receipt,null,childToken).statusCode);
        Assert.areEqual(404,invoke('PATCH','unknown','{}',childToken).statusCode);
        Assert.areEqual(404,invoke('DELETE','unknown',null,childToken).statusCode);
    }
}

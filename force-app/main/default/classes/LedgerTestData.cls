@IsTest
public class LedgerTestData {
    public static FinanceDtos.Account account(UserContext ctx, String name, String type, Decimal opening) {
        Map<String, Object> body = new Map<String, Object>{ 'name' => name, 'type' => type, 'openingBalance' => opening };
        if (type == 'Credit Card') {
            body.put('creditLimit', 50000);
            body.put('statementDay', 15);
        }
        return AccountService.createAccount(ctx, body);
    }

    public static Id categoryId(UserContext ctx, String name) {
        for (Category__c c : CategoryService.ensureSeeded(ctx).all()) {
            if (c.Name == name) {
                return c.Id;
            }
        }
        return null;
    }

    public static FinanceDtos.Txn entry(UserContext ctx, String type, Decimal amount, Id accountId, Id categoryId) {
        return entry(ctx, type, amount, accountId, categoryId, Date.today(), null);
    }

    public static FinanceDtos.Txn entry(UserContext ctx, String type, Decimal amount, Id accountId, Id categoryId, Date d, String payee) {
        return TransactionService.createTransaction(
            ctx,
            new Map<String, Object>{
                'type' => type,
                'amount' => amount,
                'accountId' => accountId,
                'categoryId' => categoryId,
                'date' => String.valueOf(d),
                'payee' => payee
            }
        );
    }

    public static FinanceDtos.Transfer transfer(UserContext ctx, Id fromId, Id toId, Decimal amount) {
        return TransferService.createTransfer(
            ctx,
            new Map<String, Object>{ 'fromAccountId' => fromId, 'toAccountId' => toId, 'amount' => amount, 'date' => String.valueOf(Date.today()) }
        );
    }

    public static Decimal balance(Id accountId) {
        return [SELECT Current_Balance__c FROM Financial_Account__c WHERE Id = :accountId WITH SYSTEM_MODE].Current_Balance__c;
    }

    public static String code(Exception e) {
        return e instanceof PortalException ? ((PortalException) e).code() : e.getTypeName() + ': ' + e.getMessage();
    }

    public static Map<String, String> params(String query) {
        Map<String, String> result = new Map<String, String>();
        for (String pair : query.split('&')) {
            if (pair.contains('=')) {
                result.put(pair.substringBefore('='), EncodingUtil.urlDecode(pair.substringAfter('='), 'UTF-8'));
            }
        }
        return result;
    }
}

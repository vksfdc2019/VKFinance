/**
 * Owner Workspace (VK Finance Console, desktop and the Salesforce mobile app): the platform
 * owner picks a family and works inside it through the same services the portal uses.
 *
 * - Every method requires the VKF_Platform_Admin custom permission (via OwnerContext).
 * - The family's admin context comes from the database, never from the client, and every
 *   audit event is tagged with the owner's Salesforce user.
 * - Responses are JSON strings in exactly the portal REST shape, so the screens reuse the
 *   service DTOs without duplicating them as @AuraEnabled classes.
 * - Not cacheable: some reads (dashboard, dues) may seed categories or generate card statements.
 */
public with sharing class VkfOwnerController {
  private static final Integer MAX_DUE_DAYS = 90;
  private static final String GENERIC_ERROR = 'Something went wrong. Please try again.';
  private static final Map<String, String> CODE_MESSAGES = new Map<String, String>{
    'NOT_AUTHORIZED' => 'You don\'t have access to do that.',
    'NOT_FOUND' => 'That record no longer exists.',
    'CONFLICT' => 'That record was changed. Refresh and try again.',
    'VALIDATION' => 'Check the details and try again.',
    'BAD_REQUEST' => 'The request was not valid.'
  };

  /** @return JSON list of OwnerContext.FamilySummary */
  @AuraEnabled
  public static String getFamilies() {
    try {
      return JSON.serialize(OwnerContext.families(), true);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  /**
   * @param familyId family to read
   * @param month 'YYYY-MM'; blank for the current month
   * @return JSON FinanceDtos.Dashboard
   */
  @AuraEnabled
  public static String getOverview(Id familyId, String month) {
    try {
      UserContext ctx = OwnerContext.forFamily(familyId, false);
      return JSON.serialize(
        DashboardService.build(
          ctx,
          new Map<String, String>{ 'month' => month }
        ),
        true
      );
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  /**
   * @param familyId family to read
   * @param filtersJson JSON object of the portal list filters (month, q, type, accountId, categoryId, cursor, limit)
   * @return JSON FinanceDtos.TxnPage
   */
  @AuraEnabled
  public static String getTransactions(Id familyId, String filtersJson) {
    try {
      UserContext ctx = OwnerContext.forFamily(familyId, false);
      return JSON.serialize(
        TransactionService.listTransactions(ctx, stringParams(filtersJson)),
        true
      );
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  /** @return JSON { accounts, categories, members, paymentModes } for the entry form */
  @AuraEnabled
  public static String getEntryOptions(Id familyId) {
    try {
      UserContext ctx = OwnerContext.forFamily(familyId, false);
      List<Map<String, Object>> members = new List<Map<String, Object>>();
      for (PortalDtos.Member m : MemberService.listMembers(ctx)) {
        if (m.status == 'Active' || m.status == 'Invited') {
          members.add(
            new Map<String, Object>{
              'id' => m.id,
              'name' => FinanceDtos.personName(m.firstName, m.lastName),
              'role' => m.role
            }
          );
        }
      }
      List<String> modes = new List<String>(LedgerUtil.PAYMENT_MODES);
      modes.sort();
      return JSON.serialize(
        new Map<String, Object>{
          'accounts' => AccountService.listAccounts(ctx, false),
          'categories' => CategoryService.listCategories(ctx),
          'members' => members,
          'paymentModes' => modes
        },
        true
      );
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  /**
   * Records an income, expense, refund or (type 'Transfer') a transfer.
   * @param familyId family to write to
   * @param entryJson portal request body (type, amount, date, accountId, categoryId, payee, notes,
   *        paymentMode, memberId; for transfers fromAccountId and toAccountId)
   * @return JSON FinanceDtos.Txn, or FinanceDtos.Transfer for a transfer
   */
  @AuraEnabled
  public static String saveEntry(Id familyId, String entryJson) {
    try {
      UserContext ctx = OwnerContext.forFamily(familyId, true);
      Map<String, Object> body = bodyOf(entryJson);
      Object saved = LedgerUtil.text(body, 'type') == 'Transfer'
        ? (Object) TransferService.createTransfer(ctx, body)
        : (Object) TransactionService.createTransaction(ctx, body);
      return JSON.serialize(saved, true);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  /** Voids a transaction (both legs of a transfer); a voided payment re-opens what it paid. */
  @AuraEnabled
  public static void voidTransaction(Id familyId, Id transactionId) {
    try {
      TransactionService.voidTransaction(
        OwnerContext.forFamily(familyId, true),
        transactionId
      );
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  /**
   * @param days look-ahead window, 1-90 (default 30)
   * @return JSON list of CommitmentDtos.DueItem (bills, EMIs, card bills), soonest first
   */
  @AuraEnabled
  public static String getDues(Id familyId, Integer days) {
    try {
      Integer window = days == null ||
        days < 1
        ? 30
        : Math.min(days, MAX_DUE_DAYS);
      return JSON.serialize(
        DuesService.upcoming(OwnerContext.forFamily(familyId, false), window),
        true
      );
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  /**
   * Pays a bill instance or the next EMI. Card bills are settled as a transfer to the card.
   * @param kind 'bill' or 'emi' (DueItem.kind)
   * @param recordId DueItem.id (the bill instance or EMI instalment)
   * @param parentId DueItem.parentId (the bill or loan)
   * @param paymentJson optional { amount, accountId, date }; defaults pay the full amount from the usual account
   * @return JSON of the updated bill instance or loan
   */
  @AuraEnabled
  public static String payDue(
    Id familyId,
    String kind,
    Id recordId,
    Id parentId,
    String paymentJson
  ) {
    try {
      UserContext ctx = OwnerContext.forFamily(familyId, true);
      Map<String, Object> body = bodyOf(paymentJson);
      Object result;
      if (kind == 'bill') {
        result = BillService.payInstance(ctx, recordId, body);
      } else if (kind == 'emi') {
        result = LoanService.payEmi(ctx, parentId, body);
      } else {
        throw new PortalException('VALIDATION')
          .withError(
            'Card bills are paid as a transfer from a bank account to the card.'
          );
      }
      return JSON.serialize(result, true);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  /** @return JSON FinanceDtos.BudgetView for 'YYYY-MM' (blank = current month) */
  @AuraEnabled
  public static String getBudget(Id familyId, String month) {
    try {
      return JSON.serialize(
        BudgetService.getBudget(OwnerContext.forFamily(familyId, false), month),
        true
      );
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  /** @return JSON list of PortalDtos.Member */
  @AuraEnabled
  public static String getMembers(Id familyId) {
    try {
      return JSON.serialize(
        MemberService.listMembers(OwnerContext.forFamily(familyId, false)),
        true
      );
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  private static Map<String, Object> bodyOf(String payload) {
    if (String.isBlank(payload)) {
      return new Map<String, Object>();
    }
    try {
      Object parsed = JSON.deserializeUntyped(payload);
      if (parsed instanceof Map<String, Object>) {
        return (Map<String, Object>) parsed;
      }
    } catch (JSONException e) {
      throw new PortalException('BAD_REQUEST', e)
        .withError('The request was not valid JSON.');
    }
    throw new PortalException('BAD_REQUEST')
      .withError('The request must be a JSON object.');
  }

  private static Map<String, String> stringParams(String payload) {
    Map<String, String> params = new Map<String, String>();
    Map<String, Object> raw = bodyOf(payload);
    for (String key : raw.keySet()) {
      Object value = raw.get(key);
      if (value != null) {
        params.put(key, String.valueOf(value));
      }
    }
    return params;
  }

  /** User-facing message only: the service's own wording when it gave one, never internals. */
  @TestVisible
  private static AuraHandledException auraError(Exception e) {
    String message;
    if (e instanceof PortalException) {
      PortalException pe = (PortalException) e;
      message = pe.errors.isEmpty()
        ? (CODE_MESSAGES.containsKey(pe.code())
            ? CODE_MESSAGES.get(pe.code())
            : GENERIC_ERROR)
        : String.join(pe.errors, ' ');
    } else if (e instanceof AuraHandledException) {
      return (AuraHandledException) e;
    } else {
      System.debug(
        LoggingLevel.ERROR,
        'Owner Workspace error: ' +
          e.getTypeName() +
          ': ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );
      message = GENERIC_ERROR;
    }
    AuraHandledException wrapped = new AuraHandledException(message);
    wrapped.setMessage(message);
    return wrapped;
  }
}

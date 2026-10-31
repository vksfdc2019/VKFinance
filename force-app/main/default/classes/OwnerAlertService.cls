/**
 * Delivers owner alerts on three channels - Salesforce push (custom notification), email and
 * Telegram - as configured in the VKF_Owner_Alerts__c hierarchy setting (org default).
 *
 * Recipients are the active users holding the VKF_Platform_Admin permission set. Each channel
 * is isolated: one failing never stops the others, and every result comes back to the caller.
 * Telegram is called first so the callout happens before any other work in the transaction.
 *
 * without sharing + SYSTEM_MODE: reads setup data (permission set assignments, notification
 * types) for a server-side job; nothing here is reachable from a client without the
 * VKF_Platform_Admin check in VkfOwnerController.
 */
public without sharing class OwnerAlertService {
  public static final String CHANNEL_PUSH = 'Push';
  public static final String CHANNEL_EMAIL = 'Email';
  public static final String CHANNEL_TELEGRAM = 'Telegram';
  public static final String STATUS_SENT = 'sent';
  public static final String STATUS_SKIPPED = 'skipped';
  public static final String STATUS_FAILED = 'failed';
  public static final String TELEGRAM_ENDPOINT = 'callout:VKF_Telegram/sendMessage';
  private static final String NOTIFICATION_TYPE = 'VKF_Owner_Alert';
  private static final String WORKSPACE_PAGE = '{"type":"standard__navItemPage","attributes":{"apiName":"VKF_Owner_Workspace"}}';
  private static final Integer PUSH_TITLE_MAX = 250;
  private static final Integer PUSH_BODY_MAX = 750;
  private static final Integer TELEGRAM_MAX = 4000;

  /** One alert in three lengths: push (short), email and Telegram (full text). */
  public class Alert {
    public String title;
    public String pushBody;
    public String text;

    public Alert(String title, String pushBody, String text) {
      this.title = title;
      this.pushBody = pushBody;
      this.text = text;
    }
  }

  /** What happened on one channel; returned to the Owner Workspace test button. */
  public class ChannelResult {
    public String channel;
    public String status;
    public String detail;

    public ChannelResult(String channel, String status, String detail) {
      this.channel = channel;
      this.status = status;
      this.detail = detail;
    }
  }

  @TestVisible
  private static List<ChannelResult> lastResults;

  /** The org-default settings; defaults (on, push + email, 3 days) apply when no row exists. */
  public static VKF_Owner_Alerts__c settings() {
    VKF_Owner_Alerts__c cfg = VKF_Owner_Alerts__c.getOrgDefaults();
    if (cfg.Id == null) {
      // With no saved row, getOrgDefaults() returns an empty row without the field defaults.
      cfg = new VKF_Owner_Alerts__c(
        Enabled__c = true,
        Push__c = true,
        Email__c = true,
        Telegram__c = false,
        Due_Within_Days__c = 3,
        Overdue_Repeat_Days__c = 1,
        Portal_Summary_Off__c = false
      );
    }
    return cfg;
  }

  /** @return days ahead to warn about dues, between 0 and 30 */
  public static Integer dueWithinDays() {
    Decimal days = settings().Due_Within_Days__c;
    return days == null ? 3 : Math.max(0, Math.min(30, days.intValue()));
  }

  /**
   * Portal bell: how often an overdue reminder repeats, 0-30 days; 0 means once only.
   * Blank (rows saved before the field existed) means daily.
   */
  public static Integer overdueRepeatDays() {
    Decimal days = settings().Overdue_Repeat_Days__c;
    return days == null ? 1 : Math.max(0, Math.min(30, days.intValue()));
  }

  /** Portal bell: whether the family admins get the daily dues summary. */
  public static Boolean portalSummaryOn() {
    return settings().Portal_Summary_Off__c != true;
  }

  /** Active users holding VKF_Platform_Admin. */
  public static Set<Id> recipients() {
    Set<Id> ids = new Set<Id>();
    for (PermissionSetAssignment a : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE
        PermissionSet.Name = :OwnerContext.PERMISSION
        AND Assignee.IsActive = TRUE
      WITH SYSTEM_MODE
      LIMIT 50
    ]) {
      ids.add(a.AssigneeId);
    }
    return ids;
  }

  /**
   * Sends the alert on every enabled channel.
   * @return one result per channel, in the order Telegram, Email, Push
   */
  public static List<ChannelResult> deliver(Alert alert) {
    VKF_Owner_Alerts__c cfg = settings();
    List<ChannelResult> results = new List<ChannelResult>();
    if (cfg.Enabled__c != true) {
      for (
        String channel : new List<String>{
          CHANNEL_TELEGRAM,
          CHANNEL_EMAIL,
          CHANNEL_PUSH
        }
      ) {
        results.add(
          new ChannelResult(
            channel,
            STATUS_SKIPPED,
            'Alerts are switched off (VKF Owner Alerts > Alerts On).'
          )
        );
      }
      lastResults = results;
      return results;
    }
    Set<Id> users = recipients();
    results.add(
      cfg.Telegram__c == true
        ? sendTelegram(cfg.Telegram_Chat_Id__c, alert)
        : skipped(CHANNEL_TELEGRAM)
    );
    results.add(
      cfg.Email__c == true ? sendEmail(users, alert) : skipped(CHANNEL_EMAIL)
    );
    results.add(
      cfg.Push__c == true ? sendPush(users, alert) : skipped(CHANNEL_PUSH)
    );
    recordFailures(results);
    lastResults = results;
    return results;
  }

  private static ChannelResult skipped(String channel) {
    return new ChannelResult(
      channel,
      STATUS_SKIPPED,
      'Turned off in VKF Owner Alerts.'
    );
  }

  @TestVisible
  private static ChannelResult sendTelegram(String chatId, Alert alert) {
    if (String.isBlank(chatId)) {
      return new ChannelResult(
        CHANNEL_TELEGRAM,
        STATUS_FAILED,
        'Add your Telegram chat ID in VKF Owner Alerts.'
      );
    }
    HttpRequest req = new HttpRequest();
    req.setEndpoint(TELEGRAM_ENDPOINT);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setTimeout(20000);
    req.setBody(
      JSON.serialize(
        new Map<String, Object>{
          'chat_id' => chatId.trim(),
          'text' => alert.text.left(TELEGRAM_MAX),
          'disable_web_page_preview' => true
        }
      )
    );
    try {
      HttpResponse res = new Http().send(req);
      if (res.getStatusCode() == 200) {
        return new ChannelResult(CHANNEL_TELEGRAM, STATUS_SENT, null);
      }
      return new ChannelResult(
        CHANNEL_TELEGRAM,
        STATUS_FAILED,
        telegramError(res)
      );
    } catch (CalloutException e) {
      return new ChannelResult(
        CHANNEL_TELEGRAM,
        STATUS_FAILED,
        'Could not reach Telegram. Check the VKF_Telegram named credential and the VKF Telegram Alerts permission set. (' +
          e.getMessage().left(200) +
          ')'
      );
    }
  }

  /** Telegram's own description ("Bad Request: chat not found", "Unauthorized"), never the token. */
  private static String telegramError(HttpResponse res) {
    String reason = 'HTTP ' + res.getStatusCode();
    try {
      Object parsed = JSON.deserializeUntyped(res.getBody());
      if (parsed instanceof Map<String, Object>) {
        Object description = ((Map<String, Object>) parsed).get('description');
        if (description != null) {
          reason += ': ' + String.valueOf(description).left(200);
        }
      }
    } catch (JSONException e) {
      // keep the status code only
    }
    if (res.getStatusCode() == 401 || res.getStatusCode() == 404) {
      reason += ' - check the bot token in the VKF_Telegram named credential URL.';
    }
    return reason;
  }

  @TestVisible
  private static ChannelResult sendEmail(Set<Id> users, Alert alert) {
    if (users.isEmpty()) {
      return new ChannelResult(
        CHANNEL_EMAIL,
        STATUS_FAILED,
        'Nobody has the VKF Platform Admin permission set.'
      );
    }
    List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    for (Id userId : users) {
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      // Email to an internal user by Id doesn't use the org's daily single-email allowance.
      mail.setTargetObjectId(userId);
      mail.setSaveAsActivity(false);
      mail.setSubject(alert.title);
      mail.setPlainTextBody(alert.text);
      mails.add(mail);
    }
    try {
      Integer failed = 0;
      for (Messaging.SendEmailResult r : Messaging.sendEmail(mails, false)) {
        if (!r.isSuccess()) {
          failed++;
        }
      }
      return failed == 0
        ? new ChannelResult(
            CHANNEL_EMAIL,
            STATUS_SENT,
            mails.size() + ' recipient(s)'
          )
        : new ChannelResult(
            CHANNEL_EMAIL,
            STATUS_FAILED,
            failed + ' of ' + mails.size() + ' emails failed.'
          );
    } catch (EmailException e) {
      return new ChannelResult(
        CHANNEL_EMAIL,
        STATUS_FAILED,
        'Email is blocked - check Setup > Deliverability. (' +
          e.getMessage().left(200) +
          ')'
      );
    }
  }

  @TestVisible
  private static ChannelResult sendPush(Set<Id> users, Alert alert) {
    if (users.isEmpty()) {
      return new ChannelResult(
        CHANNEL_PUSH,
        STATUS_FAILED,
        'Nobody has the VKF Platform Admin permission set.'
      );
    }
    List<CustomNotificationType> types = [
      SELECT Id
      FROM CustomNotificationType
      WHERE DeveloperName = :NOTIFICATION_TYPE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (types.isEmpty()) {
      return new ChannelResult(
        CHANNEL_PUSH,
        STATUS_FAILED,
        'The VKF Owner Alert notification type is not deployed.'
      );
    }
    Messaging.CustomNotification n = new Messaging.CustomNotification();
    n.setNotificationTypeId(types[0].Id);
    n.setTitle(alert.title.left(PUSH_TITLE_MAX));
    n.setBody(
      (String.isBlank(alert.pushBody) ? alert.text : alert.pushBody)
        .left(PUSH_BODY_MAX)
    );
    n.setTargetPageRef(WORKSPACE_PAGE);
    Set<String> targets = new Set<String>();
    for (Id userId : users) {
      targets.add(userId);
    }
    try {
      n.send(targets);
      return new ChannelResult(
        CHANNEL_PUSH,
        STATUS_SENT,
        targets.size() + ' recipient(s)'
      );
    } catch (Exception e) {
      return new ChannelResult(
        CHANNEL_PUSH,
        STATUS_FAILED,
        e.getMessage().left(250)
      );
    }
  }

  /** Failed channels go to the audit trail (platform level), so the weekly digest can show them. */
  private static void recordFailures(List<ChannelResult> results) {
    for (ChannelResult r : results) {
      if (r.status == STATUS_FAILED) {
        AuditService.log(
          (Id) null,
          null,
          'OWNER_ALERT_FAILED',
          null,
          null,
          r.channel + ': ' + r.detail
        );
      }
    }
  }
}

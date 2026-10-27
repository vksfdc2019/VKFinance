/**
 * Hourly: expires idle sessions and deletes old sessions and spent tokens.
 * Schedule with: System.schedule('VKF Session Cleanup', '0 0 * * * ?', new SessionCleanupJob());
 */
public without sharing class SessionCleanupJob implements Schedulable {
    public void execute(SchedulableContext context) {
        SessionService.cleanup();
    }
}

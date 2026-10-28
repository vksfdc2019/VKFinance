/**
 * 01:30 daily ("VKF Archive"): starts ArchiveWorker, which copies old records to the big object
 * and Google Sheets and then removes what is safely archived.
 */
public without sharing class ArchiveJob implements Schedulable {
    public void execute(SchedulableContext sc) {
        ArchiveWorker.start();
    }
}

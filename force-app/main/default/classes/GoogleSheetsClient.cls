/**
 * Minimal Google Drive + Sheets client for the archive copy. Authentication is a Salesforce
 * Named Credential pair (VKF_Google_Drive, VKF_Google_Sheets) sharing the VKF_Google external
 * credential, authorised once by the platform owner with the drive.file scope - the app sees
 * only the folders and spreadsheets it created.
 */
public without sharing class GoogleSheetsClient {
    public static final String DRIVE = 'callout:VKF_Google_Drive';
    public static final String SHEETS = 'callout:VKF_Google_Sheets';
    private static final String FOLDER_MIME = 'application/vnd.google-apps.folder';
    private static final String SHEET_MIME = 'application/vnd.google-apps.spreadsheet';

    public class GoogleException extends Exception {
    }

    public static String sheetUrl(String spreadsheetId) {
        return 'https://docs.google.com/spreadsheets/d/' + spreadsheetId + '/edit';
    }

    /** The folder with this name under the parent ('root' = My Drive), created when missing. */
    public String folder(String name, String parentId) {
        String q = 'name = \'' + escape(name) + '\' and mimeType = \'' + FOLDER_MIME + '\' and \'' + escape(parentId) + '\' in parents and trashed = false';
        Map<String, Object> found = call('GET', DRIVE + '/drive/v3/files?fields=files(id)&spaces=drive&q=' + EncodingUtil.urlEncode(q, 'UTF-8'), null, 200);
        List<Object> files = (List<Object>) found.get('files');
        if (files != null && !files.isEmpty()) {
            return (String) ((Map<String, Object>) files[0]).get('id');
        }
        Map<String, Object> created = call('POST', DRIVE + '/drive/v3/files?fields=id', new Map<String, Object>{
            'name' => name, 'mimeType' => FOLDER_MIME, 'parents' => new List<String>{ parentId }
        }, 200);
        return (String) created.get('id');
    }

    public String createSpreadsheet(String name, String folderId) {
        Map<String, Object> created = call('POST', DRIVE + '/drive/v3/files?fields=id', new Map<String, Object>{
            'name' => name, 'mimeType' => SHEET_MIME, 'parents' => new List<String>{ folderId }
        }, 200);
        return (String) created.get('id');
    }

    /** Tab title -> sheet id, or null when the spreadsheet no longer exists (deleted in Drive). */
    public Map<String, Integer> tabs(String spreadsheetId) {
        HttpResponse res = send('GET', SHEETS + '/v4/spreadsheets/' + spreadsheetId + '?fields=sheets.properties(sheetId,title)', null);
        if (res.getStatusCode() == 404) {
            return null;
        }
        Map<String, Object> body = parse(res, 200);
        Map<String, Integer> result = new Map<String, Integer>();
        for (Object s : (List<Object>) body.get('sheets')) {
            Map<String, Object> props = (Map<String, Object>) ((Map<String, Object>) s).get('properties');
            result.put((String) props.get('title'), (Integer) props.get('sheetId'));
        }
        return result;
    }

    /**
     * Makes the spreadsheet hold exactly these tabs' rows: adds missing tabs (header row frozen),
     * drops the blank default tab, clears and rewrites each tab. Returns the rows Google wrote.
     */
    public Integer replace(String spreadsheetId, Map<String, Integer> existing, Map<String, List<List<Object>>> data) {
        List<Object> requests = new List<Object>();
        for (String title : data.keySet()) {
            if (!existing.containsKey(title)) {
                requests.add(new Map<String, Object>{
                    'addSheet' => new Map<String, Object>{
                        'properties' => new Map<String, Object>{
                            'title' => title, 'gridProperties' => new Map<String, Object>{ 'frozenRowCount' => 1 }
                        }
                    }
                });
            }
        }
        for (String title : existing.keySet()) {
            if (!data.containsKey(title) && (title == 'Sheet1' || title == 'Blad1')) {
                requests.add(new Map<String, Object>{ 'deleteSheet' => new Map<String, Object>{ 'sheetId' => existing.get(title) } });
            }
        }
        if (!requests.isEmpty()) {
            call('POST', SHEETS + '/v4/spreadsheets/' + spreadsheetId + ':batchUpdate', new Map<String, Object>{ 'requests' => requests }, 200);
        }
        List<String> ranges = new List<String>();
        List<Object> values = new List<Object>();
        for (String title : data.keySet()) {
            String tab = '\'' + title.replace('\'', '\'\'') + '\'';
            ranges.add(tab + '!A:ZZ');
            values.add(new Map<String, Object>{ 'range' => tab + '!A1', 'majorDimension' => 'ROWS', 'values' => data.get(title) });
        }
        call('POST', SHEETS + '/v4/spreadsheets/' + spreadsheetId + '/values:batchClear', new Map<String, Object>{ 'ranges' => ranges }, 200);
        Map<String, Object> written = call('POST', SHEETS + '/v4/spreadsheets/' + spreadsheetId + '/values:batchUpdate', new Map<String, Object>{
            'valueInputOption' => 'RAW', 'data' => values
        }, 200);
        Object rows = written.get('totalUpdatedRows');
        return rows == null ? 0 : Integer.valueOf(rows);
    }

    private Map<String, Object> call(String method, String url, Object body, Integer expected) {
        return parse(send(method, url, body), expected);
    }

    private HttpResponse send(String method, String url, Object body) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(url);
        req.setTimeout(60000);
        if (body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(body));
        }
        return new Http().send(req);
    }

    private Map<String, Object> parse(HttpResponse res, Integer expected) {
        if (res.getStatusCode() != expected) {
            String detail = res.getBody() == null ? '' : res.getBody().left(300);
            throw new GoogleException('Google returned ' + res.getStatusCode() + ': ' + detail);
        }
        String body = res.getBody();
        return String.isBlank(body) ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    private static String escape(String value) {
        return value == null ? '' : value.replace('\\', '\\\\').replace('\'', '\\\'');
    }
}

"""Source-based, code-native diagrams for the VK Finance implementation guide.

ReportLab drawings stay vector in PDF. SVG originals and 3x PNGs are exported
for editing and for Word. Uses ReportLab and PyMuPDF; no online renderer.
"""
from pathlib import Path
import math

from reportlab.graphics.shapes import Drawing, Rect, Line, String, Polygon, Circle, Ellipse
from reportlab.graphics import renderSVG
from reportlab.lib.colors import HexColor
from reportlab.pdfbase.pdfmetrics import stringWidth

NAVY = '#12334B'
TEAL = '#157D8B'
BLUE = '#EAF3F9'
GREEN = '#E6F3EF'
AMBER = '#FFF4DE'
RED = '#FCEDEC'
GRAY = '#536878'
LIGHT = '#D3E0E8'
WHITE = '#FFFFFF'


class Diagram:
    def __init__(self, height=440):
        self.width, self.height = 720, height
        self.drawing = Drawing(self.width, self.height)

    def text(self, x, y, text, size=12, color=NAVY, bold=False, anchor='middle'):
        font = 'Helvetica-Bold' if bold else 'Helvetica'
        lines = text.split('\n')
        for i, line in enumerate(lines):
            self.drawing.add(String(x, self.height-y-i*size*1.3, line,
                                    fontName=font, fontSize=size,
                                    fillColor=HexColor(color), textAnchor=anchor))

    def wrap(self, text, width, size=12, bold=False):
        font = 'Helvetica-Bold' if bold else 'Helvetica'
        lines = []
        for part in text.split('\n'):
            line = ''
            for word in part.split():
                candidate = (line + ' ' + word).strip()
                if line and stringWidth(candidate, font, size) > width:
                    lines.append(line)
                    line = word
                else:
                    line = candidate
            lines.append(line)
        return lines

    def box(self, x, y, w, h, title, detail='', fill=BLUE, size=12):
        self.drawing.add(Rect(x, self.height-y-h, w, h, rx=9, ry=9,
                              fillColor=HexColor(fill), strokeColor=HexColor(TEAL), strokeWidth=1.2))
        titles = self.wrap(title, w-18, size, True)
        details = self.wrap(detail, w-18, size-1) if detail else []
        gap = 7 if details else 0
        total = len(titles)*size*1.3 + len(details)*(size-1)*1.3 + gap
        top = y + (h-total)/2 + size
        self.text(x+w/2, top, '\n'.join(titles), size=size, bold=True)
        if details:
            self.text(x+w/2, top+len(titles)*size*1.3+gap, '\n'.join(details), size=size-1, color=GRAY)

    def panel(self, x, y, w, h, title, fill='#F7FAFC'):
        self.drawing.add(Rect(x, self.height-y-h, w, h, rx=10, ry=10,
                              fillColor=HexColor(fill), strokeColor=HexColor(LIGHT), strokeWidth=1,
                              strokeDashArray=[5, 4]))
        self.text(x+12, y+20, title, size=11, bold=True, color=GRAY, anchor='start')

    def diamond(self, x, y, w, h, text):
        self.drawing.add(Polygon([x+w/2,self.height-y, x+w,self.height-y-h/2,
                                  x+w/2,self.height-y-h, x,self.height-y-h/2],
                                 fillColor=HexColor(AMBER), strokeColor=HexColor(TEAL), strokeWidth=1.2))
        lines = self.wrap(text, w*.65, 12, True)
        self.text(x+w/2, y+h/2-(len(lines)-1)*7+4, '\n'.join(lines), bold=True)

    def usecase(self, x, y, w, h, text):
        self.drawing.add(Ellipse(x+w/2, self.height-y-h/2, w/2, h/2,
                                fillColor=HexColor(BLUE), strokeColor=HexColor(TEAL), strokeWidth=1.2))
        lines = self.wrap(text, w*.80, 12)
        self.text(x+w/2, y+h/2-(len(lines)-1)*7+4, '\n'.join(lines))

    def actor(self, x, y, name):
        # x/y is center of the actor's head; labels stay below the figure.
        self.drawing.add(Circle(x,self.height-y,10,fillColor=HexColor(WHITE),strokeColor=HexColor(NAVY),strokeWidth=1.5))
        for a,b in [((x,y+10),(x,y+39)), ((x-19,y+21),(x+19,y+21)),
                    ((x,y+39),(x-16,y+57)), ((x,y+39),(x+16,y+57))]:
            self.line([a,b], color=NAVY)
        self.text(x,y+76,name,size=11,bold=True)

    def line(self, points, color=GRAY, dashed=False):
        for a,b in zip(points,points[1:]):
            self.drawing.add(Line(a[0],self.height-a[1],b[0],self.height-b[1],
                                  strokeColor=HexColor(color),strokeWidth=1.25,
                                  strokeDashArray=[5,3] if dashed else None))

    def arrow(self, points, label='', at=None, dashed=False, color=TEAL):
        self.line(points,color=color,dashed=dashed)
        a,b = points[-2:]
        angle = math.atan2(b[1]-a[1],b[0]-a[0])
        wing = 7
        pts = [b]
        pts += [(b[0]-wing*math.cos(angle+delta),b[1]-wing*math.sin(angle+delta)) for delta in [-.45,.45]]
        self.drawing.add(Polygon([coord for x,y in pts for coord in (x,self.height-y)],
                                 fillColor=HexColor(color),strokeColor=HexColor(color)))
        if label:
            x,y = at or ((a[0]+b[0])/2,(a[1]+b[1])/2-7)
            self.label(x,y,label)

    def label(self, x, y, text, size=10):
        lines = text.split('\n')
        w = max(stringWidth(t,'Helvetica',size) for t in lines)+8
        self.drawing.add(Rect(x-w/2,self.height-y-4-(len(lines)-1)*size*1.3,w,len(lines)*size*1.3+3,
                              fillColor=HexColor(WHITE),strokeColor=None))
        self.text(x,y,text,size=size,color=GRAY)

    def note(self, text, y=None):
        self.text(16,y or self.height-15,text,size=10,color=GRAY,anchor='start')


def system_architecture():
    d=Diagram(470)
    d.panel(200,30,500,394,'SALESFORCE / EXPERIENCE CLOUD')
    d.box(15,67,155,65,'Family member','Browser / React UI')
    d.box(230,67,210,65,'VKFinancePortal','Experience Cloud UI bundle')
    d.box(490,67,180,65,'Custom Apex REST','/vkf/v1/*')
    d.box(490,178,180,65,'Application guards','Session + role + family scope',GREEN)
    d.box(230,178,210,65,'Service layer','Ledger / commitments / insights')
    d.box(230,290,210,65,'Salesforce records','Family-scoped custom objects')
    d.box(490,290,180,65,'Audit pipeline','Event -> trigger -> big object',GREEN)
    d.box(15,290,155,65,'Platform owner','Internal VK Finance Console')
    d.arrow([(170,99),(230,99)],'HTTPS',at=(199,88))
    d.arrow([(440,99),(490,99)])
    d.arrow([(580,132),(580,178)],'VK session',at=(624,157))
    d.arrow([(490,210),(440,210)])
    d.arrow([(335,243),(335,290)],'system mode',at=(382,269))
    d.arrow([(440,322),(490,322)],dashed=True)
    d.arrow([(170,322),(200,322),(200,211),(230,211)],'console calls',at=(188,263))
    d.note('Solid arrows: request/data access. Dashed arrow: audit publication (also emitted by guards).',450)
    return d


def usecases_portal():
    d=Diagram(470)
    d.panel(170,20,350,420,'VK FINANCE PORTAL - USER USE CASES')
    d.actor(75,190,'Portal member')
    cases=[(65,'Sign in and manage security','All roles; MFA optional'),
           (140,'View eligible balances and activity','Role and row scope apply'),
           (215,'Record transactions and transfers','Requires create permission'),
           (290,'Pay bills / manage recurring entries','Eligible grants and scope'),
           (365,'Run reports and export results','Admin-only types restricted')]
    for y,title,note in cases:
        d.usecase(220,y,250,55,title)
        d.line([(95,211),(150,211),(150,y+27),(220,y+27)])
        d.text(537,y+22,'\n'.join(d.wrap(note,165,11)),size=11,color=GRAY,anchor='start')
    d.note('Associations show available use cases; the role/action matrix determines which members may execute them.')
    return d


def usecases_admin():
    d=Diagram(455)
    d.panel(185,20,350,400,'VK FINANCE - ADMINISTRATIVE USE CASES')
    d.actor(75,65,'Platform owner')
    d.actor(638,225,'Family Admin /\nCo-Admin')
    entries=[(60,'Onboard a family and first admin'),(135,'Reset portal password (owner)'),
             (225,'Manage family members and resets'),(300,'Configure budgets and commitments')]
    for y,title in entries: d.usecase(218,y,285,55,title)
    for y in [87,162]: d.line([(94,86),(153,86),(153,y),(218,y)])
    for y in [252,327]: d.line([(619,246),(566,246),(566,y),(503,y)])
    d.text(358,389,'Sensitive changes require step-up verification.',size=11,color=GRAY)
    d.note('Platform owner uses an internal Salesforce permission. Co-Admin actions retain Family Admin protections.')
    return d


def core_relationships():
    d=Diagram(500)
    # Read as a selected dependency diagram, not a full physical ERD.
    d.box(15,45,155,55,'Portal User','Portal_User__c')
    d.box(280,45,160,55,'Family','Family__c',GREEN)
    d.box(545,45,160,55,'Session','Portal_Session__c')
    d.box(15,195,180,60,'Account','Financial_Account__c')
    d.box(270,195,180,60,'Transaction','Transaction__c',GREEN)
    d.box(525,195,180,60,'Category','Category__c')
    d.box(15,355,180,60,'Loan / installment','Loan__c / EMI_Installment__c')
    d.box(270,355,180,60,'Bill / instance','Bill__c / Bill_Instance__c')
    d.box(525,355,180,60,'Budget / line','Budget__c / Budget_Line__c')
    d.arrow([(280,72),(170,72)],'1 : many',at=(225,62))
    d.arrow([(440,72),(545,72)],'1 : many',at=(493,62))
    d.arrow([(360,100),(360,195)],'tenant boundary',at=(360,153))
    d.arrow([(195,225),(270,225)],'1 : many',at=(233,214))
    d.arrow([(525,225),(450,225)],'1 : many',at=(487,214))
    d.arrow([(105,100),(105,195)],'owner',at=(128,150))
    d.arrow([(105,355),(105,255)],'loan account',at=(105,315))
    d.arrow([(360,355),(360,255)],'payment link',at=(360,315))
    d.arrow([(615,355),(615,255)],'category link',at=(615,315))
    d.note('Selected logical relationships. Arrows follow the named relation, not a complete foreign-key or cascade map.',460)
    d.note('Family predicates also apply to the operational entities; see Appendix A for exact lookup definitions.',478)
    return d


def authentication():
    d=Diagram(610)
    d.box(215,15,250,48,'Submit username + password')
    d.box(215,95,250,58,'Check identity and password','Throttle, status, lockout, temp expiry')
    d.arrow([(340,63),(340,95)])
    d.box(15,100,165,70,'Reject / throttle','Audit; preserve security counters',RED)
    d.arrow([(215,125),(180,125)],'fail',at=(198,114))
    d.diamond(250,185,180,75,'MFA enabled?')
    d.arrow([(340,153),(340,185)])
    d.box(480,190,220,65,'Challenge + code','Expiring challenge; TOTP or recovery')
    d.arrow([(430,222),(480,222)],'yes',at=(455,211))
    d.box(480,300,220,65,'Verify second factor','Replay / attempts / lockout')
    d.arrow([(590,255),(590,300)])
    d.box(480,405,220,65,'Reject / expire / lockout','No session issued',RED)
    d.arrow([(650,365),(650,405)],'invalid',at=(680,389))
    d.arrow([(480,332),(340,332),(340,350)],'valid',at=(449,319))
    d.diamond(250,350,180,80,'Password change required?')
    d.arrow([(340,260),(340,350)],'no MFA',at=(340,300))
    d.box(15,495,250,65,'Restricted session','CHANGE_PASSWORD -> set password')
    d.box(480,495,220,65,'Full session','FULL -> authenticated portal')
    d.arrow([(250,390),(140,390),(140,495)],'yes',at=(199,378))
    d.arrow([(430,390),(455,390),(455,527),(480,527)],'no',at=(446,380))
    d.arrow([(265,527),(480,527)],'password set',at=(365,515))
    d.note('Simplified decision flow; failed MFA never issues a session. Both login paths can require a password change.',590)
    return d


def protected_sequence():
    d=Diagram(560)
    xs=[73,216,360,504,648]
    labels=['Portal','REST resource','SessionService','Service + guards','Salesforce data']
    for x,label in zip(xs,labels):
        d.box(x-65,20,130,48,label,size=11)
        d.line([(x,68),(x,515)],dashed=True,color=LIGHT)
    def message(i,j,y,text,ret=False):
        d.arrow([(xs[i],y),(xs[j],y)],text,at=((xs[i]+xs[j])/2,y-8),dashed=ret)
    message(0,1,108,'1. JSON + X-VKF-Session')
    message(1,2,162,'2. require(token, agent)')
    message(2,4,213,'3. Read current user / session / family')
    message(4,2,247,'4. Identity state',True)
    message(2,1,285,'5. UserContext',True)
    message(1,3,325,'6. Permission + business checks')
    message(3,4,366,'7. Scoped query / write')
    message(4,3,409,'8. Scoped data / write result',True)
    message(3,1,453,'9. Approved DTO',True)
    message(1,0,501,'10. Flush activity; JSON / no-store',True)
    d.note('Write handlers normally use a savepoint. Rejected checks stop before business data access.')
    return d


def ledger_lifecycle():
    d=Diagram(500)
    d.box(245,20,230,52,'Create or edit movement','Validate permissions and references')
    d.box(245,113,230,55,'Persist transaction row(s)','Transfers use linked legs')
    d.box(245,210,230,65,'Trigger -> LedgerBalances','Apply new effect minus old effect')
    d.box(245,322,230,65,'Lock and update accounts','FOR UPDATE; asset / liability math',GREEN)
    d.box(15,210,175,65,'Void existing entry','Status = Void; effect becomes 0',AMBER)
    d.box(515,322,190,65,'Reopen commitment','Bill / EMI state; loan window',AMBER)
    for a,b in [(72,113),(168,210),(275,322)]: d.arrow([(360,a),(360,b)])
    d.arrow([(190,242),(245,242)])
    d.arrow([(475,355),(515,355)],'if payment',at=(505,309))
    d.note('Credit = +amount; Debit = -amount; Void = 0. Transfer edits and voids keep linked legs consistent.',445)
    d.note('Reconciliation posts an Adjustment; nightly recalculation provides a full-ledger safety check.',464)
    return d


def emi_accounting():
    d=Diagram(435)
    d.box(235,25,250,60,'EMI = INR 20,758.36','P = 1,000,000; 9%; 60 months',GREEN)
    d.box(35,160,280,65,'Principal = INR 13,258.36','Linked EMI Payment transfer legs')
    d.box(405,160,280,65,'Interest = INR 7,500.00','Expense in Loan Interest category')
    d.arrow([(360,85),(360,120),(175,120),(175,160)])
    d.arrow([(360,120),(545,120),(545,160)])
    d.box(20,300,180,65,'Bank debit','Principal reduces cash')
    d.box(235,300,180,65,'Loan credit','Reduces amount owed')
    d.box(500,300,200,65,'Bank debit','Interest reduces cash',AMBER)
    d.arrow([(175,225),(175,260),(110,260),(110,300)])
    d.arrow([(175,260),(325,260),(325,300)])
    d.arrow([(545,225),(545,265),(600,265),(600,300)])
    d.note('First-installment example. Principal is debt reduction; only interest is expense. The bank loses the full EMI.')
    return d


def daily_automation():
    d=Diagram(520)
    d.panel(15,15,205,458,'SCHEDULER / BATCH')
    d.panel(240,15,460,458,'ONE FAMILY PER PRODUCTION EXECUTION')
    d.box(33,70,168,65,'DailyDuesBatch','Select active families')
    d.box(33,215,168,65,'Batch size = 1','Family savepoint')
    d.arrow([(117,135),(117,215)])
    d.box(263,60,190,65,'1. Ensure snapshot','Previous month')
    d.box(488,60,190,65,'2. Refresh dues','Bills + loan windows')
    d.box(488,190,190,65,'3. Generate / post','Card cycles + recurring')
    d.box(263,190,190,65,'4. Attempt auto-pay','Reuse scoped services')
    d.box(263,320,190,65,'5. Notify / alert','Dues + 80% / 100% budget')
    d.box(488,320,190,65,'6. Finish batch','Purge old read notifications')
    d.arrow([(201,247),(230,247),(230,92),(263,92)])
    d.arrow([(453,92),(488,92)])
    d.arrow([(583,125),(583,190)])
    d.arrow([(488,222),(453,222)])
    d.arrow([(358,255),(358,320)])
    d.arrow([(453,352),(488,352)],'after all families',at=(475,305))
    d.text(470,430,'Failure: rollback family -> DAILY_DUES_FAILED audit -> continue',size=11,color=GRAY)
    d.note('Unique cycle keys, rule advancement and recipient dedupe keys support reruns; review concurrency separately.')
    return d


def report_scope():
    d=Diagram(480)
    d.box(20,30,215,65,'Run report or saved view','Type + dates + filter IDs')
    d.box(280,30,205,65,'Check REPORTS:READ','Admin-only type guard',GREEN)
    d.arrow([(235,62),(280,62)])
    d.box(280,155,205,65,'Rebuild viewer scope','Current family / role / visibility',GREEN)
    d.arrow([(382,95),(382,155)])
    d.box(20,155,215,65,'Saved report record','Filters only; no owner data snapshot',AMBER)
    d.arrow([(235,187),(280,187)],'revalidate IDs',at=(255,146))
    d.box(280,280,205,65,'Read permitted data','Ledger aggregates / older snapshots')
    d.arrow([(382,220),(382,280)])
    d.box(530,280,170,65,'Shared response','KPIs + chart + tables')
    d.arrow([(485,312),(530,312)])
    d.box(530,385,170,50,'Render / CSV / print')
    d.arrow([(615,345),(615,385)])
    d.note('Sharing a saved view shares the filter configuration. Each execution uses the current viewer\'s access.')
    return d


def onboarding():
    d=Diagram(450)
    d.box(20,35,200,60,'Platform owner','VK Finance Console')
    d.box(265,35,200,60,'Custom permission','VKF_Platform_Admin',GREEN)
    d.box(510,35,190,60,'Create family','Defaults + category templates')
    d.arrow([(220,65),(265,65)])
    d.arrow([(465,65),(510,65)])
    d.box(510,165,190,65,'Create first admin','Temporary password shown once')
    d.arrow([(605,95),(605,165)])
    d.box(265,165,200,65,'Private handover','Username + temporary password')
    d.arrow([(510,197),(465,197)])
    d.box(20,165,200,65,'First portal sign-in','Restricted password-change scope')
    d.arrow([(265,197),(220,197)])
    d.box(20,305,200,65,'Set personal password','Activate user; issue FULL session')
    d.box(265,305,200,65,'Secure and configure','MFA, accounts, budgets, members')
    d.arrow([(120,230),(120,305)])
    d.arrow([(220,337),(265,337)])
    d.note('Member invitations use the same temporary-password principle. Credentials are handed over privately.')
    return d


def deployment():
    d=Diagram(465)
    d.box(20,35,200,65,'Review environment','Org alias, portal URL, scheduler')
    d.box(265,35,200,65,'Build portal','npm ci -> npm run build')
    d.box(510,35,190,65,'Unschedule VKF jobs','When required by deploy settings',AMBER)
    d.arrow([(220,67),(265,67)])
    d.arrow([(465,67),(510,67)])
    d.box(510,180,190,65,'Deploy source','sf project deploy start')
    d.arrow([(605,100),(605,180)])
    d.box(265,180,200,65,'Restore schedules','Inspect NextFireTime')
    d.arrow([(510,212),(465,212)])
    d.box(20,180,200,65,'Publish portal','sf community publish')
    d.arrow([(265,212),(220,212)])
    d.box(20,325,200,65,'Run release checks','Apex / UI / isolation / security',GREEN)
    d.arrow([(120,245),(120,325)])
    d.box(310,325,370,65,'If deploy fails after unscheduling','Inspect deployed state; restore appropriate jobs',RED)
    d.arrow([(605,245),(605,325)],'failure',at=(632,285),color='#AB4B48',dashed=True)
    d.note('Source rollback does not undo financial data. The document runbook provides exact commands.')
    return d


SPECS = [
    ('portal-use-cases', '2. Business capabilities and boundaries', usecases_portal,
     'Portal use-case diagram', 'The portal actor represents authorized family roles. Each use case remains subject to the action grants and row scope described in section 7.',
     'routes.tsx; endpoints.ts; Role_Permission metadata; LedgerScope.cls.'),
    ('administration-use-cases', '2. Business capabilities and boundaries', usecases_admin,
     'Administration use-case diagram', 'The platform owner operates through an internal Salesforce permission. Family administrators operate within one family and retain step-up and Co-Admin restrictions.',
     'VkfConsoleController.cls; FamilyOnboardingService.cls; MemberService.cls.'),
    ('system-architecture', '3. Architecture and request lifecycle', system_architecture,
     'System architecture and execution boundaries', 'Portal REST requests execute as the site guest user. VK identity and application guards authorize the scoped service access; internal console access has a separate Salesforce permission check.',
     'vkfClient.ts; VkfRest.cls; SessionService.cls; AuditService.cls.'),
    ('core-data-relationships', '5. Data model and relationships', core_relationships,
     'Core data relationship diagram', 'This selected logical view highlights identity, account ownership and ledger links. It omits many tenant links for readability; the field dictionary remains the physical metadata reference.',
     'objects/**/fields/*.field-meta.xml; FamilyScopedSelector.cls.'),
    ('authentication-flow', '6. Authentication, sessions and account security', authentication,
     'Sign-in, MFA and first-password flowchart', 'MFA verification precedes session creation when enabled. Both password-only and MFA sign-ins can produce a restricted password-change session; setting the personal password issues full access.',
     'AuthService.login, completeMfa, completeLogin and firstLogin; MfaService.cls.'),
    ('protected-request-sequence', '7. Authorization and family isolation', protected_sequence,
     'Protected API request sequence', 'The current user and family are resolved before business access. Service permissions and family-scoped selectors determine authorization; safe response construction and deferred activity updates complete the request.',
     'Vkf*Resource.cls; SessionService.require; AccessGuard.cls; VkfRest.respond.'),
    ('ledger-post-and-void', '8. Ledger and planning implementation', ledger_lifecycle,
     'Ledger posting, balance update and void flowchart', 'Posting and voiding pass through the transaction trigger. Delta math updates locked accounts; payment reversals also restore the corresponding commitment state.',
     'TransactionService.cls; TransactionTrigger.trigger; LedgerBalances.cls; LoanService.afterVoid.'),
    ('emi-accounting', '9. Bills, loans, cards and recurring commitments', emi_accounting,
     'EMI payment accounting diagram', 'One installment becomes a principal pair plus an interest expense when interest is positive. This preserves debt reduction separately from family spending.',
     'EmiCalculator.cls; LoanService.payEmi and principalLegs.'),
    ('daily-automation', '9.2 Daily processing and reruns', daily_automation,
     'Daily automation activity diagram', 'Batch execution isolates each family. The finish-stage notification purge runs after the batch; a family failure is rolled back and audited without cancelling other families.',
     'DailyDuesBatch.cls; DuesProcessor.run; NotificationService.cls.'),
    ('report-scope', '10. Reports, snapshots and export', report_scope,
     'Report execution and saved-filter data flow', 'A shared report definition never grants the owner\'s data access. Filters are resolved again and the report is read using the current viewer\'s family and visibility.',
     'ReportService.cls; InsightService.cls; ReportView.tsx.'),
    ('family-onboarding', '13.3 Onboarding and demo preparation', onboarding,
     'Family onboarding and first-access workflow', 'The platform owner creates the first administrator. Private credential handover leads to a restricted first sign-in, a new password and normal family setup.',
     'VkfConsoleController.onboardFamily; FamilyOnboardingService.cls; AuthService.firstLogin.'),
    ('deployment-lifecycle', '13.2 Build and deploy commands', deployment,
     'Deployment and schedule-recovery flowchart', 'Build the bundle before source deployment, restore required jobs and publish the portal. If deployment fails after unscheduling, inspect the actual org state before restoring jobs.',
     'README.md; schedule-jobs.apex; unschedule-jobs.apex.'),
]


def build_assets(directory):
    import pymupdf
    directory=Path(directory)
    directory.mkdir(parents=True,exist_ok=True)
    result={}
    for number,(slug,section,factory,title,explanation,source) in enumerate(SPECS,1):
        diagram=factory()
        svg=directory/(slug+'.svg')
        png=directory/(slug+'.png')
        renderSVG.drawToFile(diagram.drawing,str(svg))
        with pymupdf.open(str(svg)) as svg_doc:
            svg_doc[0].get_pixmap(matrix=pymupdf.Matrix(3,3)).save(str(png))
        result[slug]={'slug':slug,'section':section,'drawing':diagram.drawing,
                      'svg':svg,'png':png,'title':f'Figure {number}. {title}',
                      'explanation':explanation,'source':source}
    return result

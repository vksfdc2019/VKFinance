/**
 * Family member management for Family Admins and Co-Admins. Every target member is
 * loaded through PortalUserSelector, so another family's member is always NOT_FOUND.
 */
public without sharing class MemberService {
    public static final Set<String> ROLES = new Set<String>{ 'Family Admin', 'Co-Admin', 'Member', 'Child', 'Viewer' };
    public static final Set<String> RELATIONSHIPS = new Set<String>{
        'Self', 'Spouse', 'Son', 'Daughter', 'Father', 'Mother', 'Brother', 'Sister', 'Grandparent', 'Other'
    };
    private static final Pattern USERNAME_PATTERN = Pattern.compile('^[a-z0-9._-]{4,40}$');
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$');

    public class MemberInput {
        public String firstName;
        public String lastName;
        public String username;
        public String email;
        public String mobile;
        public String relationship;
        public String role;
        public String viewerScope;

        public MemberInput() {
        }

        public MemberInput(Map<String, Object> body) {
            firstName = trimmed(body, 'firstName');
            lastName = trimmed(body, 'lastName');
            username = AuthService.normalizeUsername(VkfRest.str(body, 'username'));
            email = trimmed(body, 'email');
            mobile = trimmed(body, 'mobile');
            relationship = trimmed(body, 'relationship');
            role = trimmed(body, 'role');
            viewerScope = trimmed(body, 'viewerScope');
        }
    }

    public class Created {
        public PortalDtos.Member member;
        public String temporaryPassword;
    }

    public static List<PortalDtos.Member> listMembers(UserContext ctx) {
        AccessGuard.require(ctx, 'MEMBERS', 'READ');
        PortalUserSelector selector = new PortalUserSelector(ctx);
        List<Portal_User__c> users = selector.visibleMembers();
        Map<Id, Integer> sessions = selector.activeSessionCounts(new Map<Id, Portal_User__c>(users).keySet());
        List<PortalDtos.Member> result = new List<PortalDtos.Member>();
        for (Portal_User__c u : users) {
            result.add(PortalDtos.member(u, sessions.get(u.Id), ctx.userId));
        }
        return result;
    }

    public static Created createMember(UserContext ctx, MemberInput input) {
        AccessGuard.require(ctx, 'MEMBERS', 'CREATE');
        if (input.role == 'Family Admin' && !ctx.isFamilyAdmin()) {
            throw new PortalException('NOT_AUTHORIZED').withError('Only a Family Admin can add another Family Admin.');
        }
        PortalUserSelector selector = new PortalUserSelector(ctx);
        Decimal max = selector.maxMembers();
        if (selector.countMembers() >= max) {
            throw new PortalException('CONFLICT').withError('Your family has reached its limit of ' + max.intValue() + ' members.');
        }
        Created created = insertMember(ctx.familyId, input);
        AuditService.log(ctx, 'MEMBER_CREATED', 'Portal_User__c', created.member.id, input.role);
        return created;
    }

    /** Validates and inserts an Invited member with a temporary password. Shared with family onboarding. */
    public static Created insertMember(Id familyId, MemberInput input) {
        List<String> errors = new List<String>();
        if (String.isBlank(input.firstName) || input.firstName.length() > 40) {
            errors.add('First name is required (up to 40 characters).');
        }
        if (String.isBlank(input.lastName) || input.lastName.length() > 80) {
            errors.add('Last name is required (up to 80 characters).');
        }
        if (input.username == null || !USERNAME_PATTERN.matcher(input.username).matches()) {
            errors.add('Username must be 4-40 characters: lower-case letters, digits, dot, dash or underscore.');
        } else if (IdentitySelector.usernameTaken(input.username)) {
            errors.add('That username is already taken. Try another.');
        }
        if (String.isNotBlank(input.email) && !EMAIL_PATTERN.matcher(input.email).matches()) {
            errors.add('Enter a valid email address.');
        }
        String role = String.isBlank(input.role) ? 'Member' : input.role;
        if (!ROLES.contains(role)) {
            errors.add('Choose a valid role.');
        }
        if (String.isNotBlank(input.relationship) && !RELATIONSHIPS.contains(input.relationship)) {
            errors.add('Choose a valid relationship.');
        }
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }

        Portal_User__c user = new Portal_User__c(
            Name = (input.firstName + ' ' + input.lastName).left(80),
            Family__c = familyId,
            First_Name__c = input.firstName,
            Last_Name__c = input.lastName,
            Username__c = input.username,
            Email__c = String.isBlank(input.email) ? null : input.email.toLowerCase(),
            Mobile__c = input.mobile,
            Relationship__c = input.relationship,
            Role__c = role,
            Viewer_Scope__c = input.viewerScope == 'Family' ? 'Family' : 'Own',
            Status__c = 'Invited'
        );
        String temporaryPassword = PasswordService.generateTemporaryPassword();
        PasswordService.apply(user, temporaryPassword, true);
        try {
            insert as system user;
        } catch (DmlException e) {
            if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                throw new PortalException('VALIDATION').withError('That username is already taken. Try another.');
            }
            throw e;
        }
        Created created = new Created();
        created.member = PortalDtos.member(user, 0, null);
        created.temporaryPassword = temporaryPassword;
        return created;
    }

    public static PortalDtos.Member updateMember(UserContext ctx, Id memberId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'MEMBERS', 'EDIT');
        PortalUserSelector selector = new PortalUserSelector(ctx);
        Portal_User__c target = selector.memberInFamily(memberId);
        guardFamilyAdminTarget(ctx, target);
        MemberInput input = new MemberInput(body);
        String newStatus = trimmed(body, 'status');
        List<String> changes = new List<String>();
        List<String> errors = new List<String>();

        if (input.firstName != null && input.firstName != target.First_Name__c) {
            target.First_Name__c = input.firstName;
            changes.add('firstName');
        }
        if (input.lastName != null && input.lastName != target.Last_Name__c) {
            target.Last_Name__c = input.lastName;
            changes.add('lastName');
        }
        if (body.containsKey('email')) {
            if (String.isNotBlank(input.email) && !EMAIL_PATTERN.matcher(input.email).matches()) {
                errors.add('Enter a valid email address.');
            }
            target.Email__c = String.isBlank(input.email) ? null : input.email.toLowerCase();
            changes.add('email');
        }
        if (body.containsKey('mobile')) {
            target.Mobile__c = input.mobile;
            changes.add('mobile');
        }
        if (input.relationship != null) {
            if (!RELATIONSHIPS.contains(input.relationship)) {
                errors.add('Choose a valid relationship.');
            }
            target.Relationship__c = input.relationship;
            changes.add('relationship');
        }
        if (input.viewerScope != null) {
            target.Viewer_Scope__c = input.viewerScope == 'Family' ? 'Family' : 'Own';
            changes.add('viewerScope');
        }
        if (String.isBlank(target.First_Name__c) || String.isBlank(target.Last_Name__c)) {
            errors.add('First and last name are required.');
        }

        Boolean roleChange = input.role != null && input.role != target.Role__c;
        Boolean statusChange = newStatus != null && newStatus != target.Status__c;
        if (roleChange || statusChange) {
            if (target.Id == ctx.userId) {
                throw new PortalException('VALIDATION').withError('You can\'t change your own role or status. Ask another Family Admin.');
            }
            AuthService.requireStepUp(ctx, VkfRest.str(body, 'currentPassword'), VkfRest.str(body, 'code'));
            if (roleChange && !ROLES.contains(input.role)) {
                errors.add('Choose a valid role.');
            }
            if (roleChange && input.role == 'Family Admin' && !ctx.isFamilyAdmin()) {
                throw new PortalException('NOT_AUTHORIZED').withError('Only a Family Admin can make someone a Family Admin.');
            }
            if (statusChange && !new Set<String>{ 'Active', 'Disabled', 'Removed' }.contains(newStatus)) {
                errors.add('Choose a valid status.');
            }
            if (statusChange && newStatus == 'Active' && target.Status__c == 'Invited') {
                errors.add('An invited member becomes active after setting their own password.');
            }
            Boolean losesAdmin =
                target.Role__c == 'Family Admin' &&
                ((roleChange && input.role != 'Family Admin') || (statusChange && newStatus != 'Active'));
            if (losesAdmin && selector.countActiveFamilyAdmins() <= 1) {
                errors.add('A family needs at least one Family Admin. Make someone else Family Admin first.');
            }
        }
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }

        if (roleChange) {
            changes.add('role ' + target.Role__c + ' -> ' + input.role);
            target.Role__c = input.role;
        }
        if (statusChange) {
            changes.add('status ' + target.Status__c + ' -> ' + newStatus);
            target.Status__c = newStatus;
            if (newStatus == 'Removed') {
                target.Password_Hash__c = null;
                target.Password_Salt__c = null;
                target.Must_Change_Password__c = false;
                target.MFA_Method__c = 'None';
                target.MFA_Secret__c = null;
                target.MFA_Enrolled_At__c = null;
                target.MFA_Last_Step__c = null;
                delete as system [SELECT Id FROM Auth_Token__c WHERE Portal_User__c = :target.Id WITH SYSTEM_MODE];
            }
        }
        update as system target;
        if (roleChange || statusChange) {
            SessionService.revokeAll(target.Id, 'Role or status changed', null);
        }
        AuditService.log(ctx, 'MEMBER_UPDATED', 'Portal_User__c', target.Id, String.join(changes, '; '));
        return PortalDtos.member(target, 0, ctx.userId);
    }

    public static void unlockMember(UserContext ctx, Id memberId) {
        AccessGuard.require(ctx, 'MEMBER_SECURITY', 'EDIT');
        Portal_User__c target = new PortalUserSelector(ctx).memberInFamily(memberId);
        guardFamilyAdminTarget(ctx, target);
        update as system new Portal_User__c(Id = target.Id, Locked_Until__c = null, Failed_Login_Count__c = 0, Login_Window_Attempts__c = 0);
        AuditService.log(ctx, 'MEMBER_UNLOCKED', 'Portal_User__c', target.Id, null);
    }

    /** Issues a temporary password (shown once to the admin) and signs the member out everywhere. */
    public static String resetMemberPassword(UserContext ctx, Id memberId, String adminPassword) {
        return resetMemberPassword(ctx, memberId, adminPassword, null);
    }

    public static String resetMemberPassword(UserContext ctx, Id memberId, String adminPassword, String code) {
        AccessGuard.require(ctx, 'MEMBER_SECURITY', 'EDIT');
        Portal_User__c target = new PortalUserSelector(ctx).memberInFamily(memberId);
        guardFamilyAdminTarget(ctx, target);
        if (target.Id == ctx.userId) {
            throw new PortalException('VALIDATION').withError('Use Profile > Change password for your own account.');
        }
        if (target.Status__c == 'Disabled') {
            throw new PortalException('VALIDATION').withError('Enable this member before resetting their password.');
        }
        AuthService.requireStepUp(ctx, adminPassword, code);
        String temporaryPassword = PasswordService.generateTemporaryPassword();
        PasswordService.apply(target, temporaryPassword, true);
        update as system new Portal_User__c(
            Id = target.Id,
            Password_Hash__c = target.Password_Hash__c,
            Password_Salt__c = target.Password_Salt__c,
            Hash_Iterations__c = target.Hash_Iterations__c,
            Password_Changed_At__c = target.Password_Changed_At__c,
            Must_Change_Password__c = true,
            Temp_Password_Expires_At__c = target.Temp_Password_Expires_At__c,
            Failed_Login_Count__c = 0,
            Locked_Until__c = null
        );
        SessionService.revokeAll(target.Id, 'Password reset by admin', null);
        AuditService.log(ctx, 'ADMIN_PASSWORD_RESET', 'Portal_User__c', target.Id, null);
        return temporaryPassword;
    }

    /** For a member who lost their phone and recovery codes: turns two-step off so they can sign in and set it up again. */
    public static void resetMemberMfa(UserContext ctx, Id memberId, String adminPassword, String code) {
        AccessGuard.require(ctx, 'MEMBER_SECURITY', 'EDIT');
        Portal_User__c target = new PortalUserSelector(ctx).memberInFamily(memberId);
        guardFamilyAdminTarget(ctx, target);
        if (target.Id == ctx.userId) {
            throw new PortalException('VALIDATION').withError('Use Security on your own profile to change your two-step verification.');
        }
        if (target.MFA_Method__c != MfaService.METHOD_APP) {
            throw new PortalException('VALIDATION').withError('Two-step verification is already off for this member.');
        }
        AuthService.requireStepUp(ctx, adminPassword, code);
        MfaService.clear(target.Id);
        SessionService.revokeAll(target.Id, 'Two-step reset by admin', null);
        NotificationService.notify(
            target.Family__c,
            new Set<Id>{ target.Id },
            new NotificationService.Message(
                'security',
                'warning',
                'Two-step verification was reset',
                ctx.firstName + ' turned off two-step verification on your account. Set it up again from Security.',
                '/profile',
                null
            )
        );
        AuditService.log(ctx, 'ADMIN_MFA_RESET', 'Portal_User__c', target.Id, null);
    }

    public static Integer revokeMemberSessions(UserContext ctx, Id memberId) {
        AccessGuard.require(ctx, 'MEMBER_SECURITY', 'EDIT');
        Portal_User__c target = new PortalUserSelector(ctx).memberInFamily(memberId);
        guardFamilyAdminTarget(ctx, target);
        Integer revoked = SessionService.revokeAll(target.Id, 'Signed out by admin', target.Id == ctx.userId ? ctx.sessionId : null);
        AuditService.log(ctx, 'MEMBER_SESSIONS_REVOKED', 'Portal_User__c', target.Id, revoked + ' session(s)');
        return revoked;
    }

    /** Co-Admins can't act on a Family Admin. */
    private static void guardFamilyAdminTarget(UserContext ctx, Portal_User__c target) {
        if (target.Role__c == 'Family Admin' && !ctx.isFamilyAdmin() && target.Id != ctx.userId) {
            throw new PortalException('NOT_AUTHORIZED').withError('Only a Family Admin can manage a Family Admin.');
        }
    }

    private static String trimmed(Map<String, Object> body, String key) {
        String value = VkfRest.str(body, key);
        return value == null ? null : value.trim();
    }
}

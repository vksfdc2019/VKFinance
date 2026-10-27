// Creates two demo families for trying the portal and checking family isolation.
// Prints each demo Family Admin's temporary password once (it must be changed at first sign-in).
// Delete them from the VK Finance Console > Families tab when you no longer need them.
List<String> lines = new List<String>();
for (String suffix : new List<String>{ 'a', 'b' }) {
    String username = 'demo.admin.' + suffix;
    if (IdentitySelector.byUsername(username) != null) {
        lines.add(username + ' already exists - skipped');
        continue;
    }
    MemberService.MemberInput admin = new MemberService.MemberInput();
    admin.firstName = 'Demo';
    admin.lastName = 'Admin ' + suffix.toUpperCase();
    admin.username = username;
    FamilyOnboardingService.Result r = FamilyOnboardingService.onboard('Demo Family ' + suffix.toUpperCase(), 'INR', 'Asia/Kolkata', 8, admin);
    lines.add(r.familyName + ' ' + r.familyCode + ' | ' + r.username + ' | temporary password: ' + r.temporaryPassword);
}
System.debug(LoggingLevel.ERROR, 'VKF_SEED ' + String.join(lines, ' || '));

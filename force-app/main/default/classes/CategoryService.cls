/**
 * Family categories: seeded from Default_Category__mdt, then renamed, hidden or extended
 * by the Family Admin. System categories (transfers, card payments, adjustments) are fixed.
 */
public without sharing class CategoryService {
    private static final Pattern ICON = Pattern.compile('^[a-z0-9-]{1,40}$');
    private static final Pattern COLOR = Pattern.compile('^#[0-9a-fA-F]{6}$');

    public static List<FinanceDtos.Category> listCategories(UserContext ctx) {
        AccessGuard.require(ctx, 'CATEGORIES', 'READ');
        CategorySelector selector = ensureSeeded(ctx);
        Map<Id, Category__c> all = selector.byIdMap();
        List<FinanceDtos.Category> result = new List<FinanceDtos.Category>();
        for (Category__c c : selector.all()) {
            result.add(FinanceDtos.category(c, all));
        }
        return result;
    }

    /** Families onboarded before Phase 2 get the default categories on first use. */
    public static CategorySelector ensureSeeded(UserContext ctx) {
        CategorySelector selector = new CategorySelector(ctx);
        if (selector.all().isEmpty()) {
            seedDefaults(ctx.familyId);
            selector.reset();
        }
        return selector;
    }

    public static Integer seedDefaults(Id familyId) {
        if ([SELECT COUNT() FROM Category__c WHERE Family__c = :familyId WITH SYSTEM_MODE] > 0) {
            return 0;
        }
        List<Default_Category__mdt> template = [
            SELECT DeveloperName, MasterLabel, Kind__c, Parent_Key__c, Icon__c, Color__c, Is_Essential__c, Tax_Relevant__c, Sort_Order__c, System_Key__c
            FROM Default_Category__mdt
            WITH SYSTEM_MODE
            ORDER BY Sort_Order__c, MasterLabel
        ];
        Map<String, Category__c> parents = new Map<String, Category__c>();
        for (Default_Category__mdt d : template) {
            if (String.isBlank(d.Parent_Key__c)) {
                parents.put(d.DeveloperName, fromTemplate(familyId, d, null));
            }
        }
        insert as system parents.values();
        List<Category__c> children = new List<Category__c>();
        for (Default_Category__mdt d : template) {
            if (String.isNotBlank(d.Parent_Key__c) && parents.containsKey(d.Parent_Key__c)) {
                children.add(fromTemplate(familyId, d, parents.get(d.Parent_Key__c).Id));
            }
        }
        insert as system children;
        return parents.size() + children.size();
    }

    private static Category__c fromTemplate(Id familyId, Default_Category__mdt d, Id parentId) {
        return new Category__c(
            Name = d.MasterLabel,
            Family__c = familyId,
            Kind__c = d.Kind__c,
            Parent_Category__c = parentId,
            Is_Essential__c = d.Is_Essential__c,
            Tax_Relevant__c = d.Tax_Relevant__c,
            Icon__c = d.Icon__c,
            Color__c = d.Color__c,
            Sort_Order__c = d.Sort_Order__c,
            System_Key__c = d.System_Key__c,
            Active__c = true
        );
    }

    public static FinanceDtos.Category createCategory(UserContext ctx, Map<String, Object> body) {
        AccessGuard.require(ctx, 'CATEGORIES', 'CREATE');
        CategorySelector selector = ensureSeeded(ctx);
        String name = requiredName(LedgerUtil.text(body, 'name'));
        Id parentId = VkfRest.toId(LedgerUtil.text(body, 'parentId'));
        String kind = LedgerUtil.text(body, 'kind');
        Category__c parent;
        if (parentId != null) {
            parent = selector.byId(parentId);
            if (parent.Parent_Category__c != null || parent.Kind__c == 'System') {
                throw new PortalException('VALIDATION').withError('Sub-categories can only sit under a top-level income or expense category.');
            }
            kind = parent.Kind__c;
        } else if (kind != 'Income' && kind != 'Expense') {
            throw new PortalException('VALIDATION').withError('Kind must be Income or Expense.');
        }
        assertUniqueName(selector, name, parentId, null);

        Decimal sortOrder = 0;
        for (Category__c c : selector.all()) {
            if (c.Parent_Category__c == parentId && c.Kind__c != 'System' && c.Sort_Order__c != null && c.Sort_Order__c > sortOrder) {
                sortOrder = c.Sort_Order__c;
            }
        }
        Category__c record = new Category__c(
            Name = name,
            Family__c = ctx.familyId,
            Kind__c = kind,
            Parent_Category__c = parentId,
            Is_Essential__c = LedgerUtil.bool(body, 'essential'),
            Tax_Relevant__c = LedgerUtil.bool(body, 'taxRelevant'),
            Icon__c = icon(LedgerUtil.text(body, 'icon')),
            Color__c = color(LedgerUtil.text(body, 'color')),
            Sort_Order__c = sortOrder + (parentId == null ? 10 : 1),
            Active__c = true
        );
        if (parentId == null && String.isBlank(record.Icon__c)) {
            record.Icon__c = 'tag';
        }
        if (parentId == null && String.isBlank(record.Color__c)) {
            record.Color__c = '#0f766e';
        }
        insert as system record;
        AuditService.log(ctx, 'CATEGORY_CREATED', 'Category__c', record.Id, name);
        selector.reset();
        return FinanceDtos.category(selector.byId(record.Id), selector.byIdMap());
    }

    public static FinanceDtos.Category updateCategory(UserContext ctx, Id categoryId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'CATEGORIES', 'EDIT');
        CategorySelector selector = ensureSeeded(ctx);
        Category__c existing = selector.byId(categoryId);
        if (existing.Kind__c == 'System') {
            throw new PortalException('VALIDATION').withError('System categories can\'t be changed.');
        }
        Category__c changes = new Category__c(Id = existing.Id);
        if (LedgerUtil.has(body, 'name')) {
            changes.Name = requiredName(LedgerUtil.text(body, 'name'));
            assertUniqueName(selector, changes.Name, existing.Parent_Category__c, existing.Id);
        }
        if (LedgerUtil.has(body, 'essential')) {
            changes.Is_Essential__c = LedgerUtil.bool(body, 'essential');
        }
        if (LedgerUtil.has(body, 'taxRelevant')) {
            changes.Tax_Relevant__c = LedgerUtil.bool(body, 'taxRelevant');
        }
        if (LedgerUtil.has(body, 'icon')) {
            changes.Icon__c = icon(LedgerUtil.text(body, 'icon'));
        }
        if (LedgerUtil.has(body, 'color')) {
            changes.Color__c = color(LedgerUtil.text(body, 'color'));
        }
        if (LedgerUtil.has(body, 'active')) {
            changes.Active__c = LedgerUtil.bool(body, 'active');
        }
        if (LedgerUtil.has(body, 'sortOrder')) {
            changes.Sort_Order__c = LedgerUtil.dec(body, 'sortOrder', 'Sort order');
        }
        update as system changes;
        AuditService.log(ctx, 'CATEGORY_UPDATED', 'Category__c', existing.Id, String.join(new List<String>(body.keySet()), ','));
        selector.reset();
        return FinanceDtos.category(selector.byId(existing.Id), selector.byIdMap());
    }

    private static String requiredName(String name) {
        if (String.isBlank(name) || name.length() > 40) {
            throw new PortalException('VALIDATION').withError('Name is required (up to 40 characters).');
        }
        return name;
    }

    private static void assertUniqueName(CategorySelector selector, String name, Id parentId, Id exceptId) {
        for (Category__c c : selector.all()) {
            if (c.Id != exceptId && c.Parent_Category__c == parentId && c.Name.equalsIgnoreCase(name)) {
                throw new PortalException('CONFLICT').withError('A category called "' + c.Name + '" already exists there.');
            }
        }
    }

    private static String icon(String value) {
        if (value != null && !ICON.matcher(value).matches()) {
            throw new PortalException('VALIDATION').withError('Icon must be an icon name like "shopping-bag".');
        }
        return value;
    }

    private static String color(String value) {
        if (value != null && !COLOR.matcher(value).matches()) {
            throw new PortalException('VALIDATION').withError('Colour must be a hex colour like #0f766e.');
        }
        return value;
    }
}
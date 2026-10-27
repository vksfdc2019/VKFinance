public without sharing class CategorySelector extends FamilyScopedSelector {
    private List<Category__c> cache;

    public CategorySelector(UserContext ctx) {
        super(ctx);
    }

    public List<Category__c> all() {
        if (cache == null) {
            Id fid = familyId;
            cache = [
                SELECT
                    Id, Name, Kind__c, Parent_Category__c, Is_Essential__c, Tax_Relevant__c, Icon__c, Color__c,
                    Sort_Order__c, Active__c, System_Key__c
                FROM Category__c
                WHERE Family__c = :fid
                WITH SYSTEM_MODE ORDER BY Sort_Order__c NULLS LAST, Name LIMIT 1000
            ];
        }
        return cache;
    }

    public Map<Id, Category__c> byIdMap() {
        return new Map<Id, Category__c>(all());
    }

    public Category__c byId(Id categoryId) {
        Category__c found = categoryId == null ? null : byIdMap().get(categoryId);
        if (found == null) {
            Boolean elsewhere = categoryId != null &&
                [SELECT COUNT() FROM Category__c WHERE Id = :categoryId AND Family__c != :familyId WITH SYSTEM_MODE] > 0;
            throw notFound('Category__c', categoryId, elsewhere);
        }
        return found;
    }

    public Category__c systemCategory(String key) {
        for (Category__c c : all()) {
            if (c.System_Key__c == key) {
                return c;
            }
        }
        return null;
    }

    /** The category itself and, for a top-level category, its sub-categories. */
    public Set<Id> withChildren(Id categoryId) {
        Set<Id> ids = new Set<Id>{ categoryId };
        for (Category__c c : all()) {
            if (c.Parent_Category__c == categoryId) {
                ids.add(c.Id);
            }
        }
        return ids;
    }

    /** Top-level category for reporting: the parent of a sub-category, else itself. */
    public Category__c topLevel(Id categoryId) {
        Map<Id, Category__c> categories = byIdMap();
        Category__c c = categories.get(categoryId);
        if (c != null && c.Parent_Category__c != null && categories.containsKey(c.Parent_Category__c)) {
            return categories.get(c.Parent_Category__c);
        }
        return c;
    }

    public void reset() {
        cache = null;
    }
}

/** Savings schemes (PPF, SSY, NSC, ...), insurance policies (LIC and others) and the year's tax-saving picture. */
public inherited sharing class SavingsDtos {
    public class Portfolio {
        public String currencyCode;
        public String financialYear;
        public List<Scheme> schemes = new List<Scheme>();
        public List<Policy> policies = new List<Policy>();
        /** One per person: 80C, 80CCD(1B) and 80D limits apply to each taxpayer, not the family. */
        public List<TaxSummary> taxes = new List<TaxSummary>();
        public Decimal schemesValue = 0;
        public Decimal schemesMaturityValue = 0;
        public Decimal lifeCover = 0;
        public Decimal healthCover = 0;
        public Decimal yearlyPremiums = 0;
        public Boolean canEdit = false;
    }

    public class Scheme {
        public Id id;
        public Id accountId;
        public String name;
        public String scheme;
        public String schemeLabel;
        public String kind;
        public String institution;
        public Id ownerId;
        public String ownerName;
        public String accountNumber;
        public String accountNumberMasked;
        public String beneficiary;
        public String nominee;
        public Date startDate;
        public Date maturityDate;
        public Integer tenureMonths;
        public Decimal rate;
        public Decimal principal;
        public Decimal plannedContribution;
        public String payout;
        public String status;
        public Decimal balance;
        public Date valueAsOf;
        /** Estimated value at maturity at today's rate; null when it cannot be worked out (market-linked). */
        public Decimal maturityValue;
        /** Interest paid out each payout period (SCSS quarterly, POMIS monthly, PO TD yearly). */
        public Decimal payoutAmount;
        public Decimal contributedThisYear = 0;
        /** The most that can still go in this financial year (PPF, SSY); null when there is no cap. */
        public Decimal roomThisYear;
        public Boolean depositsOpen;
        public Decimal progressPct;
        public Integer daysToMaturity;
        public String taxSection;
        public String taxNote;
        public Boolean canManage;
        public Boolean canDelete;
        public String notes;
    }

    public class Policy {
        public Id id;
        public String insurer;
        public String planName;
        public String policyType;
        public String policyNumber;
        public String policyNumberMasked;
        public Id ownerId;
        public String ownerName;
        public String insuredName;
        public Decimal sumAssured;
        public Decimal premium;
        public String frequency;
        public Decimal yearlyPremium;
        public Date startDate;
        public Date nextDueDate;
        /** Premium mode grace period (IRDAI): 15 days for monthly, 30 days otherwise. */
        public Integer graceDays;
        public Date graceEnds;
        /** Paid, Due, In grace, Overdue (past grace: the policy may lapse), Finished or None. */
        public String premiumState;
        public Integer policyTermYears;
        public Integer premiumTermYears;
        public Date premiumsEnd;
        public Date maturityDate;
        public Decimal maturityValue;
        public String nominee;
        public String taxSection;
        /** Why a premium may not be fully deductible, or a maturity may be taxable. */
        public List<String> taxWarnings = new List<String>();
        public Id payFromAccountId;
        public String payFromAccountName;
        public Id billId;
        public Id openInstanceId;
        public String status;
        public Boolean canManage;
        public String notes;
    }

    public class TaxSummary {
        public Id ownerId;
        public String ownerName;
        public String financialYear;
        public Date fromDate;
        public Date toDate;
        public Decimal section80C = 0;
        public Decimal limit80C = 150000;
        public List<TaxLine> items80C = new List<TaxLine>();
        public Decimal section80CCD1B = 0;
        public Decimal limit80CCD1B = 50000;
        public Decimal section80D = 0;
        public Decimal limit80D = 25000;
        public List<TaxLine> items80D = new List<TaxLine>();
    }

    public class TaxLine {
        public String label;
        public Decimal amount;

        public TaxLine(String label, Decimal amount) {
            this.label = label;
            this.amount = amount;
        }
    }
}

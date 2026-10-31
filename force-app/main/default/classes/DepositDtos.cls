/** JSON shapes for fixed and recurring deposits. */
public inherited sharing class DepositDtos {
    public class Deposit {
        public Id id;
        public Id accountId;
        public String accountName;
        public String institution;
        public Id ownerId;
        public String ownerName;
        public String kind;
        /** The full number only for the account's owner and admins; everyone else gets the masked one. */
        public String depositNumber;
        public String depositNumberMasked;
        public Decimal principal;
        public Decimal instalment;
        public Decimal rate;
        public Boolean seniorCitizen;
        public String compounding;
        public String payout;
        public Date startDate;
        public Integer tenureMonths;
        public Integer tenureDays;
        public Date maturityDate;
        public Decimal maturityAmount;
        public Boolean maturityQuoted;
        public Decimal calculatedMaturity;
        public String onMaturity;
        public Id payoutAccountId;
        public String payoutAccountName;
        public Id fundingAccountId;
        public String fundingAccountName;
        public Id scheduleRuleId;
        public String nominee;
        public Boolean taxSaver;
        public Decimal penaltyRate;
        public Boolean form15Submitted;
        public String status;
        public Date closedOn;
        public Decimal amountReceived;
        public String notes;

        // Worked out as of today.
        public Decimal invested;
        public Decimal interestAtMaturity;
        public Decimal currentValue;
        public Decimal interestThisFy;
        public Decimal payoutPerPeriod;
        public Integer instalmentsDue;
        public Integer daysToMaturity;
        public Decimal progressPct;
        public Decimal prematureValue;
        public Boolean lockedIn;
        public Decimal effectiveYield;
    }

    /** Interest one person earns from one bank this financial year, against the TDS threshold. */
    public class TdsLine {
        public String ownerName;
        public String institution;
        public Decimal interest;
        public Decimal threshold;
        public Decimal estimatedTds;
        public Boolean form15Submitted;
    }

    /** Deposits one person holds with one bank, against the DICGC cover. */
    public class CoverLine {
        public String ownerName;
        public String institution;
        public Decimal amount;
        public Decimal uncovered;
    }

    public class Portfolio {
        public List<Deposit> deposits = new List<Deposit>();
        public Decimal invested = 0;
        public Decimal currentValue = 0;
        public Decimal maturityValue = 0;
        public Decimal interestThisFy = 0;
        public String financialYear;
        public Integer maturingIn30Days = 0;
        public List<TdsLine> tds = new List<TdsLine>();
        public List<CoverLine> cover = new List<CoverLine>();
        public Decimal tdsThreshold;
        public Decimal tdsThresholdSenior;
        public Decimal tdsRate;
        public Decimal dicgcCover;
    }

    public static String mask(String depositNumber) {
        if (String.isBlank(depositNumber)) {
            return null;
        }
        return depositNumber.length() <= 4 ? depositNumber : '•••• ' + depositNumber.right(4);
    }
}

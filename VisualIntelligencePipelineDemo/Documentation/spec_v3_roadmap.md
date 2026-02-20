# Spec v3.0 Roadmap — Financial Integration

> **Date:** 2026-02-19  
> **Status:** Planning — blocked on Apple managed entitlement  
> **Prerequisite:** Spec v2 complete

---

## 1. FinanceKit (Apple Wallet)

- **API:** `FinanceStore` (iOS 26+)
- **Data:** Apple Wallet transactions — amount, merchant, category, date
- **Pattern:** Background delivery extension (Apple sample: `financekit-implementing-a-background-delivery-extension`)
- **Privacy:** On-device only, no server-side processing
- **Blocker:** Requires managed entitlement application to Apple

## 2. Plaid Integration

- **SDK:** Plaid Link iOS SDK (3rd-party dependency)
- **Data:** Non-Apple bank account balances + transaction history
- **Auth:** OAuth2 flow, access tokens stored in iCloud Keychain
- **Maintenance:** Tokens expire; Plaid may require user re-auth when banks update

## 3. Financial Context Aggregator

- **Service:** `FinancialContextAggregator` combines FinanceKit + Plaid → `FinancialSnapshot`
- **Output:** Budget calculations, category averages, spending velocity
- **Types:** `FinancialSnapshot`, `RecentTransaction` (requires `FinancialTypes.swift`)
- **Protocol:** `FinancialContextProviding`

## 4. Financial UI

| View | Description |
|------|-------------|
| `SpendingHistoryChartView` | Swift Charts `BarMark` — monthly category spend vs. budget |
| `BudgetAlertView` | Budget remaining + category context when scanning products |
| FinanceKit consent | Settings flow for Apple Wallet access authorization |
| Plaid Link | Settings flow for bank account connection |

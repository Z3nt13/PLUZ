Markdown
# 🚀 Z3nT1's PS5 Payload Vault (PLUZ)

A unified, automated repository providing direct access and a self-hosted fallback vault for essential PlayStation 5 jailbreak payloads. 

---

## 📋 What It Is & What It Does

**PLUZ** acts as a payload for PS5 `.bin` and `.elf`. Instead of manually tracking individual developer repositories or dealing with broken downstream links, this repository uses an automated scraping engine to monitor upstreams every few hours.

* **Upstream Syncing:** Instantly fetches original binary releases directly from primary developers.
* **Dual Routing Matrix:** The unified manifest file contains both the original upstream developer download links and an absolute, self-hosted raw GitHub fallback (`hosted_url`).
* **N-1 Safety Buffer:** The host repository retains the **current and immediately preceding** version of each payload. If an upstream update breaks compatibility or causes kernel panics, you can easily fall back to a known working release.
* **Integrity Audited:** Every asset is processed through a strict SHA-256 verification loop to guarantee tamper-proof deployments.

---

## 🛠️ How to Use & Integration with pldmgr

This repository structures its metadata database explicitly to integrate with **pldmgr**.

### ➕ Adding the Source in Payload Manager

1. Open the Payload Manager dashboard.
2. Navigate to Settings (gear icon) and select Manage Sources.
3. Click Add Source, paste:
```https
https://raw.githubusercontent.com/Z3nt13/PLUZ/main/Z3nT1s-PLUZ.json
```
4. press Add.
5. The dashboard will validate the source and add it to your catalog list.


   
Open your payload manager deployment configuration file or network settings portal on your host system.

Add the copied URL to your remote sources profile.

Refresh or sync database sources within the app UI to populate the latest verified tools immediately.

---
# 🤝 Acknowledgments & Credits
Special thanks to the entire PlayStation homebrew and security research community for their relentless dedication to documentation and tooling development.

Thanks to itsPLK for ps5-payload-manager (pldmgr).

# Universal Meta-Builder v3.1.0  
*(Project Chimera — Google Framework)*  

## Overview
This repository delivers a **universal, self-healing meta-builder** that bootstraps full developer environments, generates the complete **Project Chimera** license-compliance system, and orchestrates end-to-end builds across macOS 12 + Linux environments.

The meta-builder installs dependencies, validates build integrity, generates modular Java source trees, compiles with Maven, and produces forensic-grade audit logs.

---

## ⚙️ Core Features
- **Cross-Platform Bootstrap:** macOS 12 + Linux detection with Homebrew/Apt/Yum/Apk support  
- **Xcode Guardrails:** ensures proper OpenJDK 17 + Maven 3 toolchain on macOS 12  
- **Self-Healing Resilience:** automatically repairs structure, line endings, and missing directories  
- **Forensic Logging:** timestamped JSONL logs with optional SHA-256 auditing (`--audit`)  
- **Project Chimera Integration:** writes and compiles the full compliance scanner source tree  
- **Immutable Outputs:** artifacts stored in `artifacts/` and reports in `project-chimera/reports/`  

---

## 🧩 Directory Structure
universal_meta_builder/
├─ meta-builder.sh
├─ artifacts/
├─ .meta_logs/
├─ .state/
└─ project-chimera/
├─ pom.xml
├─ src/main/java/…
├─ reports/
└─ graph/
---

## 🚀 Usage
```bash
chmod +x meta-builder.sh
sudo ./meta-builder.sh --bootstrap        # install toolchain
./meta-builder.sh --chimera-init          # write source tree
./meta-builder.sh --chimera-build         # compile + test
./meta-builder.sh --chimera-report        # generate HTML report
./meta-builder.sh --audit                 # verify checksums
🛡️ Security and Compliance
Uses least-privilege sudo operations only where necessary.

Logs are tamper-resistant via SHA-256 audit trail.

All generated source files embed the legal copyright header.

🧠 Author
Devin B. Royal – Chief Technology Officer
www.java1kind.org

#!/usr/bin/env bash
# =============================================================================
# /*
#  * Copyright © 2025 Devin B. Royal.
#  * All Rights Reserved.
#  */
# =============================================================================
# Name: meta-builder.sh (Universal Self-Healing Meta-Builder + Chimera Orchestrator)
# Version: 3.1.0
# Purpose: Bootstrap env, generate full Project Chimera source tree, compile, scan,
#          evaluate policy, render HTML report & DOT graph — with audit logging.
# Platforms: macOS (12+), Debian/Ubuntu, RHEL/CentOS/Fedora, Alpine
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ---------- Globals ----------
VERSION="3.1.0"
ROOT="${ROOT:-$(pwd)}"
LOG_DIR="${LOG_DIR:-$ROOT/.meta_logs}"
ART_DIR="${ART_DIR:-$ROOT/artifacts}"
STATE_DIR="${STATE_DIR:-$ROOT/.state}"
REPORT_DIR="${REPORT_DIR:-$ROOT/project-chimera/reports}"
GRAPH_DIR="${GRAPH_DIR:-$ROOT/project-chimera/graph}"

mkdir -p "$LOG_DIR" "$ART_DIR" "$STATE_DIR"

# ---------- Logging / Errors ----------
log() {
  local lvl="$1"; shift
  local msg="$*"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf '%s\n' "{\"ts\":\"$ts\",\"level\":\"$lvl\",\"msg\":$(python3 - <<PY || echo "\"$msg\""
import json,sys
print(json.dumps(" ".join(sys.argv[1:])))
PY
 "$msg")}" >> "$LOG_DIR/$(date +%F).jsonl"
  [[ "$lvl" == "ERROR" ]] && echo "ERROR: $msg" >&2

die(){ log ERROR "$*"; exit 1; }
on_err(){ die "Unhandled error on line ${BASH_LINENO[0]} (cmd: ${BASH_COMMAND})"; }
trap on_err ERR

# ---------- Platform Detect ----------
OS="unknown"; PKG=""; SUDO="sudo"
detect_platform() {
  case "$(uname -s)" in
    Darwin) OS="macos"; PKG="brew"; SUDO="";;
    Linux)
      if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
          ubuntu|debian|linuxmint) OS="debian"; PKG="apt-get";;
          rhel|centos|fedora|amzn) OS="redhat"; PKG="yum";;
          alpine) OS="alpine"; PKG="apk"; SUDO="";;
          *) OS="linux"; PKG="";;
        esac
      fi
      ;;
  esac
  log INFO "Platform detected: $OS ($PKG)"


# ---------- Prereq checks (macOS Xcode) ----------
ensure_xcode_if_macos() {
  [[ "$OS" != "macos" ]] && return 0
  if ! xcode-select -p >/dev/null 2>&1; then
    cat >&2 <<'EOT'
[macOS] Xcode Command Line Tools not found.
Run: xcode-select --install
Then (if Maven still fails): Install full Xcode.app from App Store, accept license:
sudo xcodebuild -license accept
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
EOT
    die "Xcode tools missing"
  fi


# ---------- Package Installers ----------
need(){ command -v "$1" >/dev/null 2>&1; }

ensure_brew(){
  [[ "$OS" != "macos" ]] && return 0
  if ! need brew; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "brew install failed"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  fi


install_pkg(){
  case "$PKG" in
    brew)
      brew update >/dev/null || true
      brew install "$1" >/dev/null 2>&1 || brew reinstall "$1" >/dev/null 2>&1 || die "brew install $1 failed"
      ;;
    apt-get)
      $SUDO apt-get update -y
      $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "$1" || die "apt-get install $1 failed"
      ;;
    yum)
      $SUDO yum install -y "$1" || die "yum install $1 failed"
      ;;
    apk)
      apk add --no-cache "$1" || die "apk add $1 failed"
      ;;
    *)
      die "No package manager configured for OS=$OS"
      ;;
  esac


# ---------- Environment Bootstrap ----------
bootstrap() {
  log INFO "Bootstrap starting (v$VERSION)"
  detect_platform
  [[ "$OS" == "macos" ]] && ensure_xcode_if_macos && ensure_brew

  # Base tools
  for bin in python3 jq git openssl; do
    need "$bin" || install_pkg "$bin"
  done

  # Java 17 + Maven (handles macOS 12 + Xcode scenario)
  if [[ "$OS" == "macos" ]]; then
    need java || install_pkg openjdk@17
    need mvn  || install_pkg maven
    # Ensure JAVA_HOME on macOS
    if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
      log WARN "JAVA_HOME for 17 not found; using brew openjdk@17 path"
      local jhp
      jhp="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
      export JAVA_HOME="$jhp"
      export PATH="$JAVA_HOME/bin:$PATH"
    else
      export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
      export PATH="$JAVA_HOME/bin:$PATH"
    fi
  else
    need java || install_pkg openjdk-17-jdk || true
    need mvn  || install_pkg maven || install_pkg maven-openjdk || true
  fi

  # Verify
  java -version 2>&1 | tee -a "$LOG_DIR/java.check"
  mvn  -version 2>&1 | tee -a "$LOG_DIR/maven.check"

  mkdir -p "$REPORT_DIR" "$GRAPH_DIR" "$ART_DIR"
  log INFO "Bootstrap complete"
  echo "BOOTSTRAP OK"
'}'

# ---------- Chimera: Write full source tree ----------
chimera_init() {
  log INFO "Writing Project Chimera source tree"
  local base="$ROOT/project-chimera"
  mkdir -p "$base"/{scripts,policy,reports,graph,src/main/java,src/main/resources,src/test/java}
  mkdir -p "$base/src/main/java/com/devinroyal/chimera"/{logging,policy,scan,license,graph,report}
  mkdir -p "$base/src/main/java/com/devinroyal/chimera/scan/parsers"
  mkdir -p "$base/src/test/java/com/devinroyal/chimera"

  # pom.xml
  cat > "$base/pom.xml" <<'XML'
<!--
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
-->
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
                             https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.devinroyal</groupId>
  <artifactId>project-chimera</artifactId>
  <version>1.0.0</version>
  <name>Project Chimera</name>
  <description>Automated license compliance and dependency governance</description>
  <properties>
    <maven.compiler.release>17</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <exec.mainClass>com.devinroyal.chimera.App</exec.mainClass>
    <junit.version>5.10.2</junit.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <version>${junit.version}</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>com.fasterxml.jackson.core</groupId>
      <artifactId>jackson-databind</artifactId>
      <version>2.17.1</version>
    </dependency>
    <dependency>
      <groupId>com.fasterxml.jackson.dataformat</groupId>
      <artifactId>jackson-dataformat-yaml</artifactId>
      <version>2.17.1</version>
    </dependency>
  </dependencies>
  <build>
    <plugins>
      <plugin>
        <groupId>org.codehaus.mojo</groupId>
        <artifactId>exec-maven-plugin</artifactId>
        <version>3.5.0</version>
        <configuration>
          <mainClass>${exec.mainClass}</mainClass>
        </configuration>
      </plugin>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-jar-plugin</artifactId>
        <version>3.3.0</version>
        <configuration>
          <archive>
            <manifest>
              <mainClass>${exec.mainClass}</mainClass>
            </manifest>
          </archive>
        </configuration>
      </plugin>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-surefire-plugin</artifactId>
        <version>3.3.1</version>
      </plugin>
    </plugins>
  </build>
</project>
<!--
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
XML

  # logging.properties
  cat > "$base/src/main/resources/logging.properties" <<'PROP'
#
# /*
#  * Copyright © 2025 Devin B. Royal.
#  * All Rights Reserved.
#  */
#
.handlers=java.util.logging.ConsoleHandler
.level=INFO
java.util.logging.ConsoleHandler.level=INFO
java.util.logging.ConsoleHandler.formatter=java.util.logging.SimpleFormatter
#
#  * Copyright © 2025 Devin B. Royal.
#  * All Rights Reserved.
#
PROP

  # Java sources (all files)
  cat > "$base/src/main/java/com/devinroyal/chimera/App.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera;

import com.devinroyal.chimera.graph.DependencyGraph;
import com.devinroyal.chimera.license.LicenseDetector;
import com.devinroyal.chimera.logging.StructuredLogger;
import com.devinroyal.chimera.policy.PolicyEngine;
import com.devinroyal.chimera.policy.PolicyResult;
import com.devinroyal.chimera.report.ReportService;
import com.devinroyal.chimera.scan.ProjectScanResult;
import com.devinroyal.chimera.scan.ScannerService;

import java.io.File;
import java.nio.file.Path;
import java.util.List;
import java.util.logging.LogManager;

public final class App {

    private App() {}

    public static void main(String[] args) {
        try {
            LogManager.getLogManager().readConfiguration(
                    App.class.getClassLoader().getResourceAsStream("logging.properties"));
        } catch (Exception e) {
            // default logging if file missing
        }

        final StructuredLogger log = StructuredLogger.get(App.class);

        if (args.length < 2) {
            System.err.println("Usage: java -jar project-chimera.jar <command> <path> [options]");
            System.err.println("Commands: scan | policy | graph | report");
            System.exit(2);
        }

        final String cmd = args[0].trim().toLowerCase();
        final Path root = Path.of(args[1]).toAbsolutePath().normalize();

        try {
            switch (cmd) {
                case "scan" -> {
                    ProjectScanResult res = new ScannerService().scan(root);
                    System.out.println(Util.toPrettyJson(res));
                }
                case "policy" -> {
                    ProjectScanResult res = new ScannerService().scan(root);
                    PolicyEngine engine = PolicyEngine.fromDefaultPolicy();
                    PolicyResult pr = engine.evaluate(res);
                    System.out.println(Util.toPrettyJson(pr));
                    if (!pr.isCompliant()) System.exit(1);
                }
                case "graph" -> {
                    ProjectScanResult res = new ScannerService().scan(root);
                    String dot = new DependencyGraph().toDot(res);
                    File out = new File("graph/dependency-graph.dot");
                    out.getParentFile().mkdirs();
                    Util.writeString(out.toPath(), dot);
                    log.info("graph_generated", "file", out.getAbsolutePath());
                    System.out.println(out.getAbsolutePath());
                }
                case "report" -> {
                    ProjectScanResult res = new ScannerService().scan(root);
                    PolicyEngine engine = PolicyEngine.fromDefaultPolicy();
                    PolicyResult pr = engine.evaluate(res);
                    List<String> licenseFindings = new LicenseDetector().summarize(res);
                    File out = new ReportService().renderHtml(res, pr, licenseFindings, Path.of("reports"));
                    log.info("report_generated", "file", out.getAbsolutePath());
                    System.out.println(out.getAbsolutePath());
                    if (!pr.isCompliant()) System.exit(1);
                }
                default -> {
                    System.err.println("Unknown command: " + cmd);
                    System.exit(2);
                }
            }
        } catch (ChimeraException ce) {
            log.error("chimera_error", "code", "CHIMERA", "message", ce.getMessage());
            System.err.println("ERROR: " + ce.getMessage());
            System.exit(1);
        } catch (Exception e) {
            log.error("unexpected_error", "exception", e.getClass().getName(), "message", e.getMessage());
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/ChimeraException.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera;

public final class ChimeraException extends RuntimeException {
    public ChimeraException(String message) { super(message); }
    public ChimeraException(String message, Throwable cause) { super(message, cause); }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/Util.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public final class Util {
    private static final ObjectMapper MAPPER = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);

    private Util() {}

    public static String toPrettyJson(Object o) {
        try { return MAPPER.writeValueAsString(o); }
        catch (JsonProcessingException e) { throw new ChimeraException("Failed to serialize JSON", e); }
    }

    public static void writeString(Path path, String content) {
        try {
            Files.createDirectories(path.getParent());
            Files.writeString(path, content, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new ChimeraException("Failed to write file: " + path, e);
        }
    }

    public static String readString(Path path) {
        try { return Files.readString(path, StandardCharsets.UTF_8); }
        catch (IOException e) { throw new ChimeraException("Failed to read file: " + path, e); }
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/logging/StructuredLogger.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.logging;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

public final class StructuredLogger {
    private final Logger logger;

    private StructuredLogger(Class<?> cls) {
        this.logger = Logger.getLogger(cls.getName());
    }

    public static StructuredLogger get(Class<?> cls) { return new StructuredLogger(cls); }

    public void info(String event, Object... kv) { log(Level.INFO, event, kv); }
    public void warn(String event, Object... kv) { log(Level.WARNING, event, kv); }
    public void error(String event, Object... kv) { log(Level.SEVERE, event, kv); }

    private void log(Level level, String event, Object... kv) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("ts", Instant.now().toString());
        m.put("event", event);
        for (int i = 0; i + 1 < kv.length; i += 2) m.put(String.valueOf(kv[i]), kv[i + 1]);
        logger.log(level, m.toString());
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  # policy
  cat > "$base/policy/policy.json" <<'JSON'
{
  "allowed_spdx": ["MIT", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "ISC"],
  "deny_spdx": ["GPL-3.0", "AGPL-3.0"],
  "exceptions": [
    {
      "artifact": "org.example:legacy-lib",
      "spdx": "GPL-3.0",
      "expires": "2026-01-01",
      "owner": "Legal-OSPO"
    }
  ]

JSON

  cat > "$base/src/main/java/com/devinroyal/chimera/policy/PolicyRule.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.policy;

public record PolicyRule(String artifact, String spdx, String expires, String owner) {}
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/policy/PolicyResult.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.policy;

import com.devinroyal.chimera.scan.Dependency;

import java.util.ArrayList;
import java.util.List;

public final class PolicyResult {
    private boolean compliant;
    private final List<String> violations = new ArrayList<>();
    private final List<Dependency> flagged = new ArrayList<>();

    public boolean isCompliant() { return compliant; }
    public List<String> getViolations() { return violations; }
    public List<Dependency> getFlagged() { return flagged; }

    public void setCompliant(boolean compliant) { this.compliant = compliant; }
    public void addViolation(String v) { violations.add(v); }
    public void addFlagged(Dependency d) { flagged.add(d); }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/policy/PolicyEngine.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.policy;

import com.devinroyal.chimera.ChimeraException;
import com.devinroyal.chimera.Util;
import com.devinroyal.chimera.scan.Dependency;
import com.devinroyal.chimera.scan.ProjectScanResult;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.InputStream;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.*;

public final class PolicyEngine {
    private final Set<String> allow;
    private final Set<String> deny;
    private final List<PolicyRule> exceptions;

    private PolicyEngine(Set<String> allow, Set<String> deny, List<PolicyRule> exceptions) {
        this.allow = allow;
        this.deny = deny;
        this.exceptions = exceptions;
    }

    public static PolicyEngine fromDefaultPolicy() {
        try {
            Path fallback = Path.of("policy/policy.json");
            if (fallback.toFile().exists()) {
                return fromJson(Util.readString(fallback));
            }
            try (InputStream in = PolicyEngine.class.getClassLoader().getResourceAsStream("policy.json")) {
                if (in != null) {
                    String s = new String(in.readAllBytes());
                    return fromJson(s);
                }
            }
            throw new ChimeraException("policy.json not found");
        } catch (Exception e) {
            throw new ChimeraException("Failed to load policy", e);
        }
    }

    public static PolicyEngine fromJson(String json) {
        try {
            ObjectMapper om = new ObjectMapper();
            JsonNode n = om.readTree(json);
            Set<String> allow = toSet(n.get("allowed_spdx"));
            Set<String> deny = toSet(n.get("deny_spdx"));
            List<PolicyRule> exc = new ArrayList<>();
            if (n.has("exceptions")) {
                for (JsonNode e : n.get("exceptions")) {
                    exc.add(new PolicyRule(
                            optText(e, "artifact"),
                            optText(e, "spdx"),
                            optText(e, "expires"),
                            optText(e, "owner")));
                }
            }
            return new PolicyEngine(allow, deny, exc);
        } catch (Exception e) {
            throw new ChimeraException("Invalid policy json", e);
        }
    }

    private static Set<String> toSet(JsonNode n) {
        Set<String> s = new HashSet<>();
        if (n != null && n.isArray()) for (JsonNode i : n) s.add(i.asText());
        return s;
    }

    private static String optText(JsonNode n, String f) {
        return n != null && n.has(f) ? n.get(f).asText() : null;
    }

    public PolicyResult evaluate(ProjectScanResult scan) {
        PolicyResult pr = new PolicyResult();
        boolean compliant = true;

        for (Dependency d : scan.dependencies()) {
            String spdx = Optional.ofNullable(d.spdx()).orElse("UNKNOWN");
            if (deny.contains(spdx) && !isException(d)) {
                compliant = false;
                pr.addFlagged(d);
                pr.addViolation("Denied license " + spdx + " on " + d.coordinate());
            } else if (!allow.contains(spdx) && !"UNKNOWN".equals(spdx)) {
                pr.addViolation("Unapproved license " + spdx + " on " + d.coordinate());
            }
        }

        pr.setCompliant(compliant);
        return pr;
    }

    private boolean isException(Dependency d) {
        String coord = d.coordinate();
        LocalDate today = LocalDate.now();
        for (PolicyRule r : exceptions) {
            if (Objects.equals(r.artifact(), coord) && Objects.equals(r.spdx(), d.spdx())) {
                if (r.expires() == null) return true;
                try {
                    LocalDate exp = LocalDate.parse(r.expires());
                    return !today.isAfter(exp);
                } catch (Exception ignored) {
                    return true;
                }
            }
        }
        return false;
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  # Scanning & parsers
  cat > "$base/src/main/java/com/devinroyal/chimera/scan/Dependency.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.scan;

public record Dependency(String ecosystem, String name, String version, String spdx, String sourcePath) {
    public String coordinate() {
        String n = name == null ? "UNKNOWN" : name;
        String v = version == null ? "0" : version;
        return n + ":" + v;
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/scan/ProjectScanResult.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.scan;

import java.nio.file.Path;
import java.util.List;

public record ProjectScanResult(Path root, List<Dependency> dependencies) {}
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/scan/parsers/ManifestParser.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.scan.parsers;

import com.devinroyal.chimera.scan.Dependency;

import java.nio.file.Path;
import java.util.List;

public interface ManifestParser {
    boolean supports(Path file);
    List<Dependency> parse(Path file);

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/scan/parsers/PomParser.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.scan.parsers;

import com.devinroyal.chimera.ChimeraException;
import com.devinroyal.chimera.scan.Dependency;
import org.w3c.dom.*;
import javax.xml.parsers.DocumentBuilderFactory;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public final class PomParser implements ManifestParser {
    @Override public boolean supports(Path file) { return file.getFileName().toString().equals("pom.xml"); }

    @Override
    public List<Dependency> parse(Path file) {
        List<Dependency> out = new ArrayList<>();
        try {
            Document doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file.toFile());
            NodeList deps = doc.getElementsByTagName("dependency");
            for (int i = 0; i < deps.getLength(); i++) {
                Element d = (Element) deps.item(i);
                String groupId = text(d, "groupId");
                String artifactId = text(d, "artifactId");
                String version = text(d, "version");
                String coord = groupId + ":" + artifactId;
                out.add(new Dependency("maven", coord, version, "UNKNOWN", file.toString()));
            }
            return out;
        } catch (Exception e) {
            throw new ChimeraException("Failed parsing pom.xml: " + file, e);
        }
    }

    private static String text(Element e, String tag) {
        NodeList nl = e.getElementsByTagName(tag);
        if (nl.getLength() == 0) return "";
        return nl.item(0).getTextContent().trim();
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/scan/parsers/RequirementsParser.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.scan.parsers;

import com.devinroyal.chimera.scan.Dependency;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public final class RequirementsParser implements ManifestParser {
    @Override public boolean supports(Path file) {
        String n = file.getFileName().toString().toLowerCase();
        return n.equals("requirements.txt") || n.equals("pipfile");
    }

    @Override
    public List<Dependency> parse(Path file) {
        List<Dependency> out = new ArrayList<>();
        try {
            for (String line : Files.readAllLines(file)) {
                String t = line.trim();
                if (t.isEmpty() || t.startsWith("#")) continue;
                String name = t;
                String version = "UNKNOWN";
                if (t.contains("==")) {
                    String[] parts = t.split("==", 2);
                    name = parts[0].trim();
                    version = parts[1].trim();
                }
                out.add(new Dependency("pip", name, version, "UNKNOWN", file.toString()));
            }
        } catch (Exception e) {
            // soft-fail: proceed with partial
        }
        return out;
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/scan/parsers/GoModParser.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.scan.parsers;

import com.devinroyal.chimera.scan.Dependency;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public final class GoModParser implements ManifestParser {
    @Override public boolean supports(Path file) { return file.getFileName().toString().equals("go.mod"); }

    @Override
    public List<Dependency> parse(Path file) {
        List<Dependency> out = new ArrayList<>();
        try {
            for (String line : Files.readAllLines(file)) {
                String t = line.trim();
                if (!t.startsWith("require ")) continue;
                t = t.replaceFirst("^require\\s+", "").trim();
                String[] parts = t.split("\\s+");
                if (parts.length >= 2) {
                    out.add(new Dependency("gomod", parts[0], parts[1], "UNKNOWN", file.toString()));
                }
            }
        } catch (Exception ignored) {}
        return out;
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/scan/parsers/CargoTomlParser.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.scan.parsers;

import com.devinroyal.chimera.scan.Dependency;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public final class CargoTomlParser implements ManifestParser {
    @Override public boolean supports(Path file) { return file.getFileName().toString().equalsIgnoreCase("Cargo.toml"); }

    @Override
    public List<Dependency> parse(Path file) {
        List<Dependency> out = new ArrayList<>();
        try {
            boolean inDeps = false;
            for (String line : Files.readAllLines(file)) {
                String t = line.trim();
                if (t.startsWith("[dependencies]")) { inDeps = true; continue; }
                if (t.startsWith("[")) { inDeps = false; }
                if (inDeps && !t.isEmpty() && !t.startsWith("#") && t.contains("=")) {
                    String name = t.split("=")[0].trim();
                    String version = "UNKNOWN";
                    int i = t.indexOf("version");
                    if (i >= 0) {
                        String sub = t.substring(i);
                        String[] pv = sub.split("=");
                        if (pv.length >= 2) {
                            version = pv[1].replaceAll("[\"\\s]", "");
                        }
                    }
                    out.add(new Dependency("cargo", name, version, "UNKNOWN", file.toString()));
                }
            }
        } catch (Exception ignored) {}
        return out;
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/scan/ScannerService.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.scan;

import com.devinroyal.chimera.logging.StructuredLogger;
import com.devinroyal.chimera.scan.parsers.*;

import java.io.IOException;
import java.nio.file.*;
import java.util.ArrayList;
import java.util.List;

public final class ScannerService {
    private final StructuredLogger log = StructuredLogger.get(ScannerService.class);
    private final List<ManifestParser> parsers = List.of(
            new PomParser(), new RequirementsParser(), new GoModParser(), new CargoTomlParser()
    );

    public ProjectScanResult scan(Path root) {
        List<Dependency> deps = new ArrayList<>();
        try {
            Files.walk(root)
                    .filter(Files::isRegularFile)
                    .forEach(p -> {
                        for (ManifestParser mp : parsers) {
                            try {
                                if (mp.supports(p)) {
                                    deps.addAll(mp.parse(p));
                                }
                            } catch (Exception e) {
                                log.warn("parser_error", "file", p.toString(), "parser", mp.getClass().getSimpleName());
                            }
                        }
                    });
        } catch (IOException e) {
            throw new com.devinroyal.chimera.ChimeraException("Failed to walk: " + root, e);
        }
        return new ProjectScanResult(root, deps);
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  # License detection
  cat > "$base/src/main/java/com/devinroyal/chimera/license/LicenseFinding.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.license;

public record LicenseFinding(String path, String spdx, String raw) {}
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/license/LicenseDetector.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.license;

import com.devinroyal.chimera.scan.Dependency;

import java.util.ArrayList;
import java.util.List;

public final class LicenseDetector {
    public String detectSpdx(String candidate) {
        if (candidate == null) return "UNKNOWN";
        String s = candidate.toUpperCase();
        if (s.contains("APACHE") && s.contains("2")) return "Apache-2.0";
        if (s.contains("MIT")) return "MIT";
        if (s.contains("BSD")) return "BSD-3-Clause";
        if (s.contains("GPL") && s.contains("3")) return "GPL-3.0";
        if (s.contains("AGPL")) return "AGPL-3.0";
        if (s.contains("ISC")) return "ISC";
        return "UNKNOWN";
    }

    public List<String> summarize(com.devinroyal.chimera.scan.ProjectScanResult res) {
        List<String> out = new ArrayList<>();
        for (Dependency d : res.dependencies()) {
            String spdx = d.spdx() == null ? "UNKNOWN" : d.spdx();
            out.add(d.ecosystem() + "::" + d.coordinate() + "::" + spdx);
        }
        return out;
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  # Graph / Report
  cat > "$base/src/main/java/com/devinroyal/chimera/graph/DependencyGraph.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.graph;

import com.devinroyal.chimera.scan.Dependency;
import com.devinroyal.chimera.scan.ProjectScanResult;

import java.util.HashSet;
import java.util.Set;

public final class DependencyGraph {
    public String toDot(ProjectScanResult res) {
        StringBuilder sb = new StringBuilder("digraph G {\n");
        sb.append("  rankdir=LR;\n");
        Set<String> nodes = new HashSet<>();
        for (Dependency d : res.dependencies()) {
            String node = sanitize(d.coordinate());
            if (nodes.add(node)) {
                sb.append("  \"").append(node).append("\" [label=\"")
                        .append(d.coordinate()).append("\\n").append(d.spdx() == null ? "UNKNOWN" : d.spdx())
                        .append("\"];\n");
            }
            sb.append("  \"ROOT\" -> \"").append(node).append("\";\n");
        }
        sb.append("  \"ROOT\" [shape=box, style=filled, label=\"")
          .append(res.root().getFileName().toString()).append("\"];\n");
        sb.append("}\n");
        return sb.toString();
    }

    private static String sanitize(String s) { return s.replace("\"", "\\\""); }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/report/ReportService.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.report;

import com.devinroyal.chimera.Util;
import com.devinroyal.chimera.policy.PolicyResult;
import com.devinroyal.chimera.scan.ProjectScanResult;

import java.io.File;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;

public final class ReportService {
    public File renderHtml(ProjectScanResult scan, PolicyResult policy, List<String> licenseSummary, Path outDir) {
        String html = new HtmlReportRenderer().render(scan, policy, licenseSummary);
        Path out = outDir.resolve("chimera-report-" + Instant.now().toEpochMilli() + ".html");
        Util.writeString(out, html);
        return out.toFile();
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  cat > "$base/src/main/java/com/devinroyal/chimera/report/HtmlReportRenderer.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera.report;

import com.devinroyal.chimera.policy.PolicyResult;
import com.devinroyal.chimera.scan.Dependency;
import com.devinroyal.chimera.scan.ProjectScanResult;

import java.util.List;

public final class HtmlReportRenderer {
    public String render(ProjectScanResult scan, PolicyResult pr, List<String> licenseSummary) {
        StringBuilder sb = new StringBuilder();
        sb.append("<!doctype html><html><head><meta charset='utf-8'>")
          .append("<title>Chimera Report</title>")
          .append("<style>body{font-family:system-ui,Arial;margin:24px;} code{background:#f3f3f3;padding:2px 4px;border-radius:4px;}</style>")
          .append("</head><body>");
        sb.append("<h1>Project Chimera — Compliance Report</h1>");
        sb.append("<p><strong>Root:</strong> ").append(scan.root()).append("</p>");
        sb.append("<p><strong>Compliant:</strong> ").append(pr.isCompliant()).append("</p>");
        sb.append("<h2>Violations</h2><ul>");
        for (String v : pr.getViolations()) sb.append("<li>").append(escape(v)).append("</li>");
        sb.append("</ul>");
        sb.append("<h2>Dependencies</h2><table border='1' cellspacing='0' cellpadding='6'>")
          .append("<tr><th>Ecosystem</th><th>Name</th><th>Version</th><th>SPDX</th><th>Source</th></tr>");
        for (Dependency d : scan.dependencies()) {
            sb.append("<tr><td>").append(escape(d.ecosystem()))
              .append("</td><td>").append(escape(d.name()))
              .append("</td><td>").append(escape(d.version()))
              .append("</td><td>").append(escape(d.spdx()))
              .append("</td><td><code>").append(escape(d.sourcePath()))
              .append("</code></td></tr>");
        }
        sb.append("</table>");
        sb.append("<h2>License Summary</h2><pre>");
        for (String s : licenseSummary) sb.append(escape(s)).append("\n");
        sb.append("</pre>");
        sb.append("</body></html>");
        return sb.toString();
    }

    private static String escape(String s) { return s == null ? "" : s.replace("&","&amp;").replace("<","&lt;"); }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  # Unit test
  cat > "$base/src/test/java/com/devinroyal/chimera/PolicyEngineTest.java" <<'JAVA'
/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
package com.devinroyal.chimera;

import com.devinroyal.chimera.policy.PolicyEngine;
import com.devinroyal.chimera.policy.PolicyResult;
import com.devinroyal.chimera.scan.Dependency;
import com.devinroyal.chimera.scan.ProjectScanResult;
import org.junit.jupiter.api.Test;

import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

public class PolicyEngineTest {
    @Test
    public void testDenyGpl() {
        var engine = PolicyEngine.fromJson("""
            {"allowed_spdx":["MIT"],"deny_spdx":["GPL-3.0"],"exceptions":[]}
        """);
        var res = new ProjectScanResult(Path.of("."), List.of(
                new Dependency("maven","org.ex:gplib","1.0","GPL-3.0","pom.xml"),
                new Dependency("pip","mitlib","2.0","MIT","requirements.txt")
        ));
        PolicyResult pr = engine.evaluate(res);
        assertFalse(pr.isCompliant());
        assertTrue(pr.getViolations().stream().anyMatch(v->v.contains("GPL-3.0")));
    }

/*
 * Copyright © 2025 Devin B. Royal.
 * All Rights Reserved.
 */
JAVA

  log INFO "Chimera source written to $base"
  echo "CHIMERA INIT OK -> $base"


# ---------- Build / Report ----------
chimera_build() {
  local base="$ROOT/project-chimera"
  [[ -f "$base/pom.xml" ]] || die "Chimera not initialized. Run: $0 --chimera-init"
  log INFO "Compiling Chimera"
  (cd "$base" && mvn -B -ntp -DskipTests=false clean verify) | tee -a "$LOG_DIR/chimera.build.log"
  cp -f "$base/target/"*.jar "$ART_DIR"/ 2>/dev/null || true
  echo "BUILD OK -> JAR in $ART_DIR"


chimera_scan() {
  local base="$ROOT/project-chimera"
  [[ -f "$ART_DIR/project-chimera-1.0.0.jar" ]] || die "Chimera jar not found. Run: $0 --chimera-build"
  (cd "$base" && java -jar "$ART_DIR/project-chimera-1.0.0.jar" scan .) | tee "$LOG_DIR/chimera.scan.json"


chimera_policy() {
  local base="$ROOT/project-chimera"
  [[ -f "$ART_DIR/project-chimera-1.0.0.jar" ]] || die "Chimera jar not found. Run: $0 --chimera-build"
  (cd "$base" && java -jar "$ART_DIR/project-chimera-1.0.0.jar" policy .) | tee "$LOG_DIR/chimera.policy.json"


chimera_report() {
  local base="$ROOT/project-chimera"
  [[ -f "$ART_DIR/project-chimera-1.0.0.jar" ]] || die "Chimera jar not found. Run: $0 --chimera-build"
  (cd "$base" && java -jar "$ART_DIR/project-chimera-1.0.0.jar" report .)
  echo "Report(s) -> $base/reports/"


chimera_graph() {
  local base="$ROOT/project-chimera"
  [[ -f "$ART_DIR/project-chimera-1.0.0.jar" ]] || die "Chimera jar not found. Run: $0 --chimera-build"
  (cd "$base" && java -jar "$ART_DIR/project-chimera-1.0.0.jar" graph .)
  echo "DOT graph -> $base/graph/dependency-graph.dot"


# ---------- Self-Heal / Audit ----------
heal(){
  log INFO "Heal: verifying dirs and line endings"
  mkdir -p "$REPORT_DIR" "$GRAPH_DIR" "$ART_DIR"
  find "$ROOT" -type f -name "*.sh" -exec sed -i.bak -e 's/\r$//' {} \; 2>/dev/null || true
  find "$ROOT" -type f -name "*.sh.bak" -delete 2>/dev/null || true
  echo "HEAL OK"


audit(){
  log INFO "Audit: checksumming logs and artifacts"
  (cd "$LOG_DIR" && shasum -a 256 *.jsonl 2>/dev/null || true)
  (cd "$ART_DIR" && shasum -a 256 *.jar 2>/dev/null || true)
  echo "AUDIT OK"


# ---------- Usage ----------
usage(){
cat <<'HELP'
meta-builder.sh — v3.1.0  © 2025 Devin B. Royal. All Rights Reserved.

Bootstrap:
  --bootstrap                Install prerequisites (handles macOS 12 + Xcode)

Chimera (Google) end-to-end:
  --chimera-init             Write full Project Chimera source tree
  --chimera-build            Compile + test (Maven)
  --chimera-scan             Scan current repo manifests
  --chimera-policy           Evaluate policy (exit 1 on deny)
  --chimera-report           Render HTML report to project-chimera/reports
  --chimera-graph            Emit DOT graph to project-chimera/graph

Maintenance:
  --heal                     Normalize line endings & ensure dirs
  --audit                    SHA-256 over logs & artifacts
  --version                  Print version
  --help                     This help
HELP


# ---------- Main ----------
main(){
  local cmd="${1:-}"
  case "$cmd" in
    --bootstrap)       bootstrap ;;
    --chimera-init)    chimera_init ;;
    --chimera-build)   chimera_build ;;
    --chimera-scan)    chimera_scan ;;
    --chimera-policy)  chimera_policy ;;
    --chimera-report)  chimera_report ;;
    --chimera-graph)   chimera_graph ;;
    --heal)            heal ;;
    --audit)           audit ;;
    --version)         echo "$VERSION" ;;
    --help|"")         usage ;;
    *)                 usage; exit 2 ;;
  esac
}
main "$@"

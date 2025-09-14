# Makefile for slurm_gpu_report.sh

# --- Config -------------------------------------------------------------
SCRIPT       := slurm_gpu_report.sh

# system-wide install (use sudo for `make install`)
PREFIX       := /usr/local
BINDIR       := $(PREFIX)/bin

# user install (no sudo needed)
USER_BINDIR  := $(HOME)/.local/bin

# --- Phony targets ------------------------------------------------------
.PHONY: help install install-user uninstall uninstall-user check-deps lint fmt smoke

help:
	@echo "Slurm GPU Report - Make targets"
	@echo ""
	@echo "  make install          Install to $(BINDIR)"
	@echo "  make install-user     Install to $(USER_BINDIR) (no sudo)"
	@echo "  make uninstall        Remove from $(BINDIR)"
	@echo "  make uninstall-user   Remove from $(USER_BINDIR)"
	@echo "  make check-deps       Check required/optional tools are available"
	@echo "  make lint             Lint with shellcheck (if present)"
	@echo "  make fmt              Format with shfmt (if present)"
	@echo "  make smoke            Quick smoke test (no cluster changes)"
	@echo "  make help             This help"

# --- Install / Uninstall -----------------------------------------------

# Portable install (works on GNU/BSD): create dir then install with mode 0755
install: $(SCRIPT)
	@echo "Installing $(SCRIPT) to $(BINDIR)"
	@mkdir -p "$(BINDIR)"
	@install -m 0755 "$(SCRIPT)" "$(BINDIR)/slurm_gpu_report"

install-user: $(SCRIPT)
	@echo "Installing $(SCRIPT) to $(USER_BINDIR)"
	@mkdir -p "$(USER_BINDIR)"
	@install -m 0755 "$(SCRIPT)" "$(USER_BINDIR)/slurm_gpu_report"
	@echo "Ensure $(USER_BINDIR) is on your PATH."

uninstall:
	@echo "Removing $(BINDIR)/slurm_gpu_report"
	@rm -f "$(BINDIR)/slurm_gpu_report"

uninstall-user:
	@echo "Removing $(USER_BINDIR)/slurm_gpu_report"
	@rm -f "$(USER_BINDIR)/slurm_gpu_report"

# --- QA / Dev helpers ---------------------------------------------------

check-deps:
	@ok=1; \
	for cmd in bash awk sed grep cut column; do \
		if ! command -v $$cmd >/dev/null 2>&1; then \
			echo "Missing required tool: $$cmd"; ok=0; fi; \
	done; \
	for cmd in sinfo squeue scontrol; do \
		if ! command -v $$cmd >/dev/null 2>&1; then \
			echo "Warning: Slurm command not found (some features will not work): $$cmd"; fi; \
	done; \
	if [ $$ok -eq 1 ]; then echo "All required base tools found."; else echo "Please install missing tools."; exit 1; fi

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck..."; \
		shellcheck -x "$(SCRIPT)"; \
	else \
		echo "shellcheck not found (skip). Install from https://www.shellcheck.net/"; \
	fi

fmt:
	@if command -v shfmt >/dev/null 2>&1; then \
		echo "Running shfmt..."; \
		shfmt -w -i 2 -ci -sr "$(SCRIPT)"; \
	else \
		echo "shfmt not found (skip). Install: https://github.com/mvdan/sh"; \
	fi

# "smoke test" = basic sanity checks without needing active jobs
smoke:
	@echo "# Bash parse check"
	@bash -n "$(SCRIPT)"
	@echo "# --help"
	@bash "$(SCRIPT)" --help || true
	@echo "# Nodes view (first 5 lines)"
	@bash "$(SCRIPT)" --nodes | head -n 5 || true
	@echo "# Jobs view (first 5 lines)"
	@bash "$(SCRIPT)" --jobs  | head -n 5 || true
	@echo "# Users view (first 5 lines)"
	@bash "$(SCRIPT)" --users | head -n 5 || true
	@echo "Smoke test complete (some commands may print empty tables if no jobs are present)."

# Slurm GPU Report

`slurm_gpu_report.sh` is a Bash script that summarizes GPU allocation and job usage in a Slurm cluster.  
It provides **three views** (nodes, jobs, users) and can export results to **CSV**.

## ✨ Features

- **Node-centric view (`--nodes`, default)**  
  GPUs per node: partitions, models, total/allocated/idle GPUs, jobs, and job IDs.

- **Job-centric view (`--jobs`)**  
  One row per job: ID, user, partition, state, elapsed time, GPUs, and node list/reason.

- **User-centric view (`--users`)**  
  Aggregated per user: total jobs, total GPUs, distinct nodes, partitions, job IDs, node list.

- **CSV export (`--csv FILE`)**  
  Write the same data to a properly quoted CSV file for further analysis.

- Clean aligned tables (using `column` if available).

## 📦 Installation

### Option 1: User-level install (recommended, no sudo)
```bash
git clone https://github.com/YOURNAME/slurm-gpu-report.git
cd slurm-gpu-report
make install-user
```
This installs slurm_gpu_report into` ~/.local/bin`.
Ensure `~/.local/bin` is on your $PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Option 2: System-wide install (admin only)
```bash
git clone https://github.com/YOURNAME/slurm-gpu-report.git
cd slurm-gpu-report
sudo make install
```
This installs to `/usr/local/bin/slurm_gpu_report` for all users.

### Option 3: One-liner (quick download)
```bash
wget https://raw.githubusercontent.com/TYTTYTTYT/slurm-gpu-report/main/slurm_gpu_report.sh -O slurm_gpu_report
chmod +x slurm_gpu_report
mv slurm_gpu_report ~/.local/bin/
```

## 💻 Usage
```bash
slurm_gpu_report [--nodes|--jobs|--users] [--csv FILE]
```

### Examples
```bash
# Node-centric (default)
slurm_gpu_report

# Job-centric (includes pending jobs)
slurm_gpu_report --jobs

# User-centric
slurm_gpu_report --users

# Export to CSV
slurm_gpu_report --nodes --csv nodes.csv
slurm_gpu_report --jobs  --csv jobs.csv
slurm_gpu_report --users --csv users.csv
```

## 🔧 Dependencies
* **Slurm commands:** `sinfo`, `squeue`, `scontrol`
* Core utils: `awk`, `bash`, `grep`, `sed`, `cut`, `column` (optional but recommended)

For development:

* [ShellCheck](https://www.shellcheck.net/)
 for linting (`make lint`)
* [shfmt](https://github.com/mvdan/sh?tab=readme-ov-file#shfmt)
 for formatting (`make fmt`)

## 🤝 Contributing

Pull requests are welcome!

Run `make lint` and `make smoke` before submitting a PR.

## 📜 License

MIT License © 2025 Yintao Tai

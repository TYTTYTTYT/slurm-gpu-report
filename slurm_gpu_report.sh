#!/usr/bin/env bash
# slurm_gpu_report.sh
# Views:
#   --nodes  Node-centric (default)
#   --jobs   Job-centric (includes pending)
#   --users  User-centric
# Extras:
#   --csv FILE  also write output to CSV (quoted)

set -euo pipefail

VIEW="nodes"
CSV_OUT=""

while (( $# )); do
  case "$1" in
    --nodes) VIEW="nodes"; shift ;;
    --jobs)  VIEW="jobs";  shift ;;
    --users) VIEW="users"; shift ;;
    --csv)   CSV_OUT="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: slurm_gpu_report.sh [--nodes|--jobs|--users] [--csv FILE]

--nodes       Node-centric GPU table (default).
--jobs        Job-centric GPU table (includes pending; sums GPUs from GRES).
--users       User-centric summary: Jobs, GPUs sum, Node tokens count/list, Partitions, JobIDs.
--csv FILE    Also write the same rows to FILE in CSV format (properly quoted).
--help        Show this help.
EOF
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

have_column() { command -v column >/dev/null 2>&1; }

tabs_to_csv() {
  local out="$1"
  awk -F'\t' -v OFS=',' '
    function esc(s){ gsub(/"/,"\"\"",s); return "\"" s "\"" }
    { for(i=1;i<=NF;i++) $i=esc($i); print $0 }
  ' > "$out"
}

# ---- helpers ----
sum_gpus_from_gres() {
  awk -v s="$1" 'BEGIN{
    t=0
    if (s=="" || s=="(null)") { print 0; exit }
    n=split(s,a,",")
    for(i=1;i<=n;i++){
      x=a[i]; sub(/^gres\//,"",x)
      if (x ~ /^gpu(:|[^,]*)/) {
        m=split(x,f,":")
        if (m>=3){ c=f[3]; sub(/[^0-9].*$/,"",c); if (c~/^[0-9]+$/) t+=c+0 }
        else if (m==2){ c=f[2]; sub(/[^0-9].*$/,"",c); if (c~/^[0-9]+$/) t+=c+0 }
      }
    }
    print t
  }'
}

# ---------- NODE-CENTRIC VIEW ----------
run_nodes_view() {
  declare -A TOTAL MODELS PARTS SEEN_NODE ALLOC JCOUNT JOBS
  ORDERED_NODES=()

  # 1) Nodes, GRES, partitions
  mapfile -t SINFOROWS < <(sinfo -aN -h --states=all -o "%n %G %P")
  for row in "${SINFOROWS[@]}"; do
    node="${row%% *}"; rest="${row#* }"
    gres="${rest%% *}"; part="${rest##* }"

    if [[ -z "${SEEN_NODE[$node]+x}" ]]; then SEEN_NODE["$node"]=1; ORDERED_NODES+=("$node"); fi

    if [[ -n "${PARTS[$node]+x}" ]]; then
      case ",${PARTS[$node]}," in *,"$part",*) : ;; *) PARTS["$node"]+=",${part}" ;; esac
    else
      PARTS["$node"]="$part"
    fi

    MODELS["$node"]="$(awk -v s="$gres" 'BEGIN{
      if (s=="" || s=="-" || s=="(null)") { print "-"; exit }
      n=split(s,a,","); out=""
      for(i=1;i<=n;i++) if (a[i] ~ /^gpu:/) {
        m=split(a[i], f, ":");
        if (m>=3){ cnt=f[3]; sub(/[^0-9].*$/,"",cnt); mdl=f[2];
                   out=out (out!=""?"+":"") mdl ":" (cnt==""?"?":cnt) }
        else if (m==2){ cnt=f[2]; sub(/[^0-9].*$/,"",cnt);
                        out=out (out!=""?"+":"") ":" (cnt==""?"?":cnt) }
      }
      print (out==""?"-":out)
    }')"

    TOTAL["$node"]="$(awk -v s="$gres" 'BEGIN{
      t=0; if (s=="" || s=="-" || s=="(null)"){ print 0; exit }
      n=split(s,a,",");
      for(i=1;i<=n;i++) if (a[i] ~ /^gpu(:|[^,]*)/) {
        m=split(a[i], f, ":")
        if (m>=3){ c=f[3]; sub(/[^0-9].*$/,"",c); if (c~/^[0-9]+$/) t+=c+0 }
        else if (m==2){ c=f[2]; sub(/[^0-9].*$/,"",c); if (c~/^[0-9]+$/) t+=c+0 }
      }
      print t
    }')"
  done

  # 2) Per-node allocations (+ jobs). Use process substitution so the while
  #    runs in the current shell (no subshell variable loss).
  #    Also expand hostlists like node[01-03] to individual nodes when possible.
  while IFS=$'\t' read -r nodelist gcount jid user part; do
    # expand ranges if scontrol is available and pattern looks like a hostlist
    if [[ "$nodelist" == *"["*"]"* ]] && command -v scontrol >/dev/null 2>&1; then
      while read -r one; do
        (( ALLOC["$one"] = ${ALLOC["$one"]:-0} + gcount ))
        (( JCOUNT["$one"] = ${JCOUNT["$one"]:-0} + 1 ))
        JOBS["$one"]="${JOBS["$one"]:+${JOBS["$one"]},}$jid(${user})"
        # merge partition
        if [[ -n "$part" ]]; then
          if [[ -n "${PARTS[$one]+x}" ]]; then
            case ",${PARTS[$one]}," in *,"$part",*) : ;; *) PARTS["$one"]+=",${part}" ;; esac
          else
            PARTS["$one"]="$part"
          fi
        fi
      done < <(scontrol show hostnames "$nodelist")
    else
      node="$nodelist"
      [[ -z "$node" || "$node" == "(Priority)" || "$node" == "n/a" ]] && continue
      (( ALLOC["$node"] = ${ALLOC["$node"]:-0} + gcount ))
      (( JCOUNT["$node"] = ${JCOUNT["$node"]:-0} + 1 ))
      JOBS["$node"]="${JOBS["$node"]:+${JOBS["$node"]},}$jid(${user})"
      if [[ -n "$part" ]]; then
        if [[ -n "${PARTS[$node]+x}" ]]; then
          case ",${PARTS[$node]}," in *,"$part",*) : ;; *) PARTS["$node"]+=",${part}" ;; esac
        else
          PARTS["$node"]="$part"
        fi
      fi
    fi
  done < <(
    # Build rows: NodeList(token), GPU count, JobID, user, partition
    squeue -h -o "%R|%b|%i|%u|%P" \
    | awk -F"|" 'BEGIN{OFS="\t"}{
        nodelist=$1; gres=$2; jid=$3; user=$4; part=$5;
        if (nodelist=="" || nodelist=="(Priority)" || nodelist=="n/a") next;
        # sum GPUs in this job
        g=0;
        if (gres!="" && gres!="(null)"){
          n=split(gres,arr,",");
          for(i=1;i<=n;i++){
            x=arr[i]; sub(/^gres\//,"",x);
            if (x ~ /^gpu(:|[^,]*)/){
              m=split(x,f,":");
              if (m>=3){ c=f[3]; sub(/[^0-9].*$/,"",c); if (c~/^[0-9]+$/) g+=c+0 }
              else if (m==2){ c=f[2]; sub(/[^0-9].*$/,"",c); if (c~/^[0-9]+$/) g+=c+0 }
            }
          }
        }
        print nodelist, g, jid, user, part
      }'
  )

  build_tsv() {
    printf "Partition(s)\tNode\tGPU(Models)\tTotal\tAlloc\tIdle\tJobs\tJobIDs(User)\n"
    for node in "${ORDERED_NODES[@]}"; do
      parts="${PARTS[$node]:--}"
      models="${MODELS[$node]:--}"
      total="${TOTAL[$node]:-0}"
      alloc="${ALLOC[$node]:-0}"
      idle=$(( total - alloc )); (( idle < 0 )) && idle=0
      jobs="${JCOUNT[$node]:-0}"
      jlist="${JOBS[$node]:--}"
      printf "%s\t%s\t%s\t%d\t%d\t%d\t%d\t%s\n" \
        "$parts" "$node" "$models" "$total" "$alloc" "$idle" "$jobs" "$jlist"
    done
  }

  if have_column; then build_tsv | column -ts $'\t'; else build_tsv; fi
  if [[ -n "$CSV_OUT" ]]; then build_tsv | tabs_to_csv "$CSV_OUT"; echo "CSV written to: $CSV_OUT" >&2; fi
}

# ---------- JOB-CENTRIC VIEW ----------
run_jobs_view() {
  build_tsv() {
    printf "JobID\tUser\tPartition\tName\tState\tElapsed\tNodes\tGPUs\tNodeList/Reason\n"
    squeue -h -t all -o "%i|%u|%P|%j|%t|%M|%D|%R|%b" \
    | awk -F"|" 'BEGIN{OFS="\t"}{
        job=$1; user=$2; part=$3; name=$4; state=$5; elapsed=$6; nodes=$7; nlist=$8; gres=$9;
        g=0
        if (gres != "" && gres != "(null)") {
          n = split(gres, arr, ",")
          for (i=1; i<=n; i++) {
            x = arr[i]
            sub(/^gres\//,"",x)
            if (x ~ /^gpu(:|[^,]*)/) {
              m = split(x, f, ":")
              if (m >= 3) { c=f[3]; sub(/[^0-9].*$/, "", c); if (c ~ /^[0-9]+$/) g += c+0 }
              else if (m == 2) { c=f[2]; sub(/[^0-9].*$/, "", c); if (c ~ /^[0-9]+$/) g += c+0 }
            }
          }
        }
        print job, user, part, name, state, elapsed, nodes, g, nlist
      }'
  }
  if have_column; then build_tsv | column -ts $'\t'; else build_tsv; fi
  if [[ -n "$CSV_OUT" ]]; then build_tsv | tabs_to_csv "$CSV_OUT"; echo "CSV written to: $CSV_OUT" >&2; fi
}

# ---------- USER-CENTRIC VIEW ----------
run_users_view() {
  declare -A JCOUNT GPUS USERS_PARTS USERS_NODES USERS_JIDS
  mapfile -t ROWS < <(squeue -h -t all -o "%u|%i|%P|%R|%b")
  for line in "${ROWS[@]}"; do
    user="${line%%|*}"; rest="${line#*|}"
    jid="${rest%%|*}"; rest="${rest#*|}"
    part="${rest%%|*}"; rest="${rest#*|}"
    nlist="${rest%%|*}"; gres="${rest#*|}"

    gcount="$(sum_gpus_from_gres "$gres")"

    (( JCOUNT["$user"] = ${JCOUNT["$user"]:-0} + 1 ))
    (( GPUS["$user"]   = ${GPUS["$user"]:-0}   + gcount ))

    if [[ -n "${USERS_PARTS[$user]+x}" ]]; then
      case ",${USERS_PARTS[$user]}," in *,"$part",*) : ;; *) USERS_PARTS["$user"]+=",${part}" ;; esac
    else USERS_PARTS["$user"]="$part"; fi

    if [[ -n "${USERS_NODES[$user]+x}" ]]; then
      case ",${USERS_NODES[$user]}," in *,"$nlist",*) : ;; *) USERS_NODES["$user"]+=",${nlist}" ;; esac
    else USERS_NODES["$user"]="$nlist"; fi

    USERS_JIDS["$user"]="${USERS_JIDS["$user"]:+${USERS_JIDS["$user"]},}$jid"
  done

  distinct_node_count() {
    local tokenlist="$1" IFS=','; read -r -a arr <<<"$tokenlist"; declare -A seen; local c=0
    for t in "${arr[@]}"; do
      [[ -z "$t" || "$t" == "(Priority)" || "$t" == "n/a" ]] && continue
      if [[ -z "${seen[$t]+x}" ]]; then seen["$t"]=1; ((c++)); fi
    done
    echo "$c"
  }

  build_tsv() {
    printf "User\tJobs\tGPUs\tNodeTokens\tPartitions\tJobIDs\tNodeTokens(List)\n"
    for user in "${!JCOUNT[@]}"; do
      jobs="${JCOUNT[$user]}"; gpus="${GPUS[$user]:-0}"
      parts="${USERS_PARTS[$user]:--}"; nodes_raw="${USERS_NODES[$user]:--}"
      nodecnt="$(distinct_node_count "$nodes_raw")"
      jids="${USERS_JIDS[$user]}"
      printf "%s\t%d\t%d\t%d\t%s\t%s\t%s\n" "$user" "$jobs" "$gpus" "$nodecnt" "$parts" "$jids" "$nodes_raw"
    done | sort -k1,1
  }

  if have_column; then build_tsv | column -ts $'\t'; else build_tsv; fi
  if [[ -n "$CSV_OUT" ]]; then build_tsv | tabs_to_csv "$CSV_OUT"; echo "CSV written to: $CSV_OUT" >&2; fi
}

# ---------- Dispatch ----------
case "$VIEW" in
  nodes) run_nodes_view ;;
  jobs)  run_jobs_view  ;;
  users) run_users_view ;;
esac

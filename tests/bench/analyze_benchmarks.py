
# analyze_benchmarks.py
# Usage: python analyze_benchmarks.py [--input benchmarks.csv] [--outdir out]
# Requires: pandas, matplotlib, numpy
import argparse
import os
from pathlib import Path
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

# ---- Helpers ----

def ensure_outdir(d: Path):
    d.mkdir(parents=True, exist_ok=True)

# Percentiles util
PCT = [50, 95]

def pct(series):
    return {f"p{p}": float(np.nanpercentile(series, p)) for p in PCT}

# ---- Load & derive ----

def load(input_csv: Path) -> pd.DataFrame:
    # Identify which timestamp columns exist before parsing
    header = pd.read_csv(input_csv, nrows=0)
    parse_cols = [c for c in ["submitted_at_utc","included_at_utc","finalized_at_utc"] if c in header.columns]
    df = pd.read_csv(input_csv, parse_dates=parse_cols)

    # Derive latencies (seconds)
    if "included_at_utc" in df.columns and "submitted_at_utc" in df.columns:
        df["latency_inclusion_s"] = (df["included_at_utc"] - df["submitted_at_utc"]).dt.total_seconds()
    else:
        df["latency_inclusion_s"] = np.nan
    if "finalized_at_utc" in df.columns and df["finalized_at_utc"].notna().any():
        df["latency_finality_s"] = (df["finalized_at_utc"] - df["submitted_at_utc"]).dt.total_seconds()
    else:
        df["latency_finality_s"] = np.nan

    # Cost in native token
    if "gas_used" in df.columns and "effective_gas_price_wei" in df.columns:
        df["cost_native"] = pd.to_numeric(df["gas_used"], errors="coerce") * pd.to_numeric(df["effective_gas_price_wei"], errors="coerce") / 1e18
    else:
        df["cost_native"] = np.nan

    # Success flag numeric
    if "success" in df.columns:
        df["success"] = pd.to_numeric(df["success"], errors="coerce")
    else:
        df["success"] = 1
    return df

# ---- Figures ----
def cdf_xy(arr: np.ndarray):
    x = np.sort(arr)
    y = np.arange(1, len(x)+1) / len(x)
    return x, y

def plot_latency_cdf(df: pd.DataFrame, which: str, outpath: Path):
    if which not in df.columns or df[which].dropna().empty:
        return
    plt.figure()
    key = which
    for (net, wf), g in df[df[key].notna()].groupby(["network","workflow"], dropna=False):
        xs, ys = cdf_xy(g[key].values)
        label = f"{net}-{wf}"
        plt.plot(xs, ys, label=label)
    plt.xlabel("Latency (s)")
    plt.ylabel("CDF")
    ttl = "Latency CDF (" + which.replace("_"," ") + ")"
    plt.title(ttl)
    plt.legend()
    plt.tight_layout()
    plt.savefig(outpath, dpi=200)
    plt.close()

def plot_throughput_vs_concurrency(df: pd.DataFrame, outpath: Path):
    # Throughput per run: successful ops / (max(included) - min(submitted))
    rows = []
    ok = df[df["success"]==1].copy()
    if ok.empty or "submitted_at_utc" not in ok or "included_at_utc" not in ok:
        return
    for (net, wf, run), g in ok.groupby(["network","workflow","run_id"], dropna=False):
        start = g["submitted_at_utc"].min()
        end = g["included_at_utc"].max()
        dur = max((end - start).total_seconds(), 1.0)
        ops = len(g)
        try:
            conc = int(pd.to_numeric(g["concurrency"], errors="coerce").dropna().median())
        except Exception:
            conc = np.nan
        rows.append({"network":net, "workflow":wf, "run_id":run, "concurrency":conc, "tps": ops/dur})
    tdf = pd.DataFrame(rows)
    if tdf.empty:
        return
    plt.figure()
    for (net, wf), g in tdf.groupby(["network","workflow"], dropna=False):
        g = g.sort_values("concurrency")
        plt.plot(g["concurrency"], g["tps"], marker="o", label=f"{net}-{wf}")
    plt.xlabel("Concurrency (clients)")
    plt.ylabel("Throughput (TPS)")
    plt.title("Throughput vs. Concurrency")
    plt.legend()
    plt.tight_layout()
    plt.savefig(outpath, dpi=200)
    plt.close()

def plot_cost_per_uav(df: pd.DataFrame, outpath: Path):
    ok = df[df["success"]==1].copy()
    if ok.empty:
        return
    # Aggregate per run
    agg = ok.groupby(["network","workflow","run_id"]).agg({"cost_native":"sum","uav_count":"max"}).reset_index()
    agg["uav_count"] = pd.to_numeric(agg["uav_count"], errors="coerce")
    agg["cost_per_uav_native"] = agg["cost_native"] / agg["uav_count"].replace(0, np.nan)
    plt.figure()
    for net, g in agg.groupby("network", dropna=False):
        m = g.groupby("workflow")["cost_per_uav_native"].median().reset_index()
        plt.plot(m["workflow"], m["cost_per_uav_native"], marker="o", label=str(net))
    plt.xlabel("Workflow")
    plt.ylabel("Median Cost per UAV (native token)")
    plt.title("Cost per UAV by Workflow and Network")
    plt.xticks(rotation=20)
    plt.legend()
    plt.tight_layout()
    plt.savefig(outpath, dpi=200)
    plt.close()

# ---- Tables ----
def table_latency_by_op(df: pd.DataFrame) -> pd.DataFrame:
    # Median and P95 inclusion latency by network/workflow/op_type
    if "latency_inclusion_s" not in df:
        return pd.DataFrame()
    d = df[df["latency_inclusion_s"].notna()].copy()
    if d.empty:
        return pd.DataFrame()
    g = d.groupby(["network","workflow","op_type"])['latency_inclusion_s']
    out = g.agg([('p50_s', lambda s: float(np.nanpercentile(s, 50))),
                 ('p95_s', lambda s: float(np.nanpercentile(s, 95))),
                 ('count', 'count')]).reset_index()
    return out

def table_success_rates(df: pd.DataFrame) -> pd.DataFrame:
    g = df.groupby(["network","workflow","run_id"]).agg(
        ops=("success","size"),
        ok=("success", lambda s: int(np.nansum(s)))
    ).reset_index()
    g["success_rate"] = g["ok"] / g["ops"]
    return g

def table_throughput(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    ok = df[df["success"]==1].copy()
    if ok.empty or "submitted_at_utc" not in ok or "included_at_utc" not in ok:
        return pd.DataFrame()
    for (net, wf, run), g in ok.groupby(["network","workflow","run_id"], dropna=False):
        start = g["submitted_at_utc"].min()
        end = g["included_at_utc"].max()
        dur = max((end - start).total_seconds(), 1.0)
        ops = len(g)
        conc = pd.to_numeric(g["concurrency"], errors="coerce").dropna().median() if "concurrency" in g else np.nan
        rows.append({"network":net, "workflow":wf, "run_id":run, "concurrency":conc, "tps": ops/dur, "ops":ops, "duration_s":dur})
    return pd.DataFrame(rows)

def table_costs(df: pd.DataFrame) -> pd.DataFrame:
    ok = df[df["success"]==1].copy()
    if ok.empty:
        return pd.DataFrame()
    agg = ok.groupby(["network","workflow","run_id"]).agg({"cost_native":"sum","uav_count":"max"}).reset_index()
    agg["uav_count"] = pd.to_numeric(agg["uav_count"], errors="coerce")
    agg["cost_per_uav_native"] = agg["cost_native"] / agg["uav_count"].replace(0, np.nan)
    return agg

def to_latex(df: pd.DataFrame, out: Path, caption: str, label: str):
    if df.empty:
        return
    tex = df.to_latex(index=False, escape=True, caption=caption, label=label)
    out.write_text(tex, encoding='utf-8')

# ---- Main ----
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', default='benchmarks.csv')
    ap.add_argument('--outdir', default='perf_out')
    args = ap.parse_args()

    input_csv = Path(args.input)
    outdir = Path(args.outdir)
    ensure_outdir(outdir)

    df = load(input_csv)

    # Save cleaned/derived
    df.to_csv(outdir / 'benchmarks_derived.csv', index=False)

    # Figures
    plot_latency_cdf(df, 'latency_inclusion_s', outdir / 'fig_latency_inclusion_cdf.png')
    if df['latency_finality_s'].notna().any():
        plot_latency_cdf(df, 'latency_finality_s', outdir / 'fig_latency_finality_cdf.png')
    plot_throughput_vs_concurrency(df, outdir / 'fig_throughput_vs_concurrency.png')
    plot_cost_per_uav(df, outdir / 'fig_cost_per_uav.png')

    # Tables
    t_lat = table_latency_by_op(df)
    t_succ = table_success_rates(df)
    t_thr = table_throughput(df)
    t_cost = table_costs(df)

    t_lat.to_csv(outdir / 'table_latency_by_op.csv', index=False)
    t_succ.to_csv(outdir / 'table_success_rates.csv', index=False)
    t_thr.to_csv(outdir / 'table_throughput_by_run.csv', index=False)
    t_cost.to_csv(outdir / 'table_costs_by_run.csv', index=False)

    # Optional LaTeX tables for paper
    to_latex(t_lat, outdir / 'table_latency_by_op.tex', caption='Latency (p50/p95) by operation', label='tab:latency_by_op')
    to_latex(t_thr, outdir / 'table_throughput_by_run.tex', caption='Throughput per run', label='tab:throughput_by_run')
    to_latex(t_cost, outdir / 'table_costs_by_run.tex', caption='Cost per run and per UAV (native token)', label='tab:costs_by_run')

    print('Wrote figures and tables to', outdir)

if __name__ == '__main__':
    main()

# -*- coding: utf-8 -*-
"""
Converte i dati orari REALI scaricati dall'API PVGIS (PVGIS-SARAH3, Barletta 2013,
1 kWp, perdite 14%, tilt 30 azimut 0) nel formato richiesto da
progetto_cementificio.m:  month;day;hour;P_kW_per_kWp  (separatore ';').

Il campo PVGIS 'P' e' la potenza AC in WATT per 1 kWp installato; si divide per
1000 per ottenere kW/kWp. Il timestamp PVGIS e' 'YYYYMMDD:HHMM' in ora UTC con
i minuti a :10 (centro intervallo orario): si mappa l'ora HH -> colonna hour.
"""

import json
import csv
from collections import defaultdict

with open("pvgis_raw_2013.json", "r", encoding="utf-8-sig") as f:
    j = json.load(f)

hourly = j["outputs"]["hourly"]

# Accumulo per (month, day, hour): in genere un solo record per ora.
prof = {}
for rec in hourly:
    ts = rec["time"]            # es. '20130621:1110'
    ymd, hm = ts.split(":")
    month = int(ymd[4:6])
    day   = int(ymd[6:8])
    hour  = int(hm[:2])
    P_kW  = rec["P"] / 1000.0   # W/kWp -> kW/kWp
    prof[(month, day, hour)] = P_kW

# Scrittura ordinata
righe = sorted(prof.items())
with open("pvgis_barletta_2013_sarah3.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, delimiter=";")
    w.writerow(["month", "day", "hour", "P_kW_per_kWp"])
    for (m, d, h), p in righe:
        w.writerow([m, d, h, round(p, 5)])

# --- Controlli ---
resa_mese = defaultdict(float)
for (m, d, h), p in prof.items():
    resa_mese[m] += p
resa_anno = sum(resa_mese.values())

nomi = ["Gen","Feb","Mar","Apr","Mag","Giu","Lug","Ago","Set","Ott","Nov","Dic"]
print("Record orari convertiti :", len(prof))
print("Resa annua (REALE PVGIS):", round(resa_anno), "kWh/kWp/anno   [atteso ~1266]")
print("Resa mensile [kWh/kWp]:")
print("  " + "  ".join("%s %3.0f" % (nomi[m-1], resa_mese[m]) for m in range(1, 13)))
print("Picco orario massimo    :", round(max(prof.values()), 3), "kW/kWp")

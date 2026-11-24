# -*- coding: utf-8 -*-
"""
Ricostruzione dei due file dati di ingresso del modello progetto_cementificio.m
per lo stabilimento Buzzi di Barletta (BT). I dati sono SINTETICI ma CALIBRATI
sui valori dichiarati nella presentazione e nelle fonti [2][8][PVGIS]:

  - emissioni_barletta_2024_2025.csv : funzionamento "a campagne" del forno
        CF ore ~43 %, ~15 avviamenti, durata media campagne ~23 giorni,
        clinker ~830 kt/anno (vol. specifico fumi 2300 Nm3/t clinker).
  - pvgis_barletta_2013_sarah3.csv   : profilo orario PV per kWp,
        integrale annuo ~1266 kWh/kWp alla latitudine di Barletta (~41,3 N).

Esecuzione: python ricostruisci_dati.py
"""

import csv
import random
from datetime import date, timedelta

random.seed(20240101)  # riproducibilita'

# ----------------------------------------------------------------------------
# PARAMETRI DI CALIBRAZIONE
# ----------------------------------------------------------------------------
VOL_SPEC      = 2300.0      # [Nm3/t clinker] volume specifico fumi secchi [BREF]
CLINKER_TARGET= 830_000.0   # [t/anno] produzione clinker stimata [2]
CF_TARGET     = 0.43        # [-] capacity factor su base ore [8]
N_CAMP_TARGET = 15          # [-] numero di campagne nel biennio (slide Dinamica)
DUR_CAMP_MED  = 23          # [giorni] durata media campagna [8][9]
LAT           = 41.32       # [deg] latitudine Barletta
PV_TARGET     = 1266.0      # [kWh/kWp/anno] producibilita' PV del sito [PVGIS]

START = date(2024, 1, 1)
END   = date(2025, 12, 31)

# ============================================================================
#  1) FILE FORNO A CAMPAGNE
# ============================================================================
n_giorni = (END - START).days + 1
giorni   = [START + timedelta(days=i) for i in range(n_giorni)]

# --- Costruzione delle campagne (ON) e fermate (OFF) ------------------------
# Si vuole: ~15 campagne nel biennio, durata media ~23 gg, CF ore ~0.43.
# Le fermate si scelgono perche' (sum ON)/(n_giorni) ~ CF, lasciando il forno
# spento ~57 % dei giorni.
ore_giorno_on = 24.0  # a forno acceso la marcia e' continua nelle 24 h della giornata

# Durate campagne: distribuzione attorno a 23 gg (10..50), somma ~ CF*n_giorni
durate_camp = []
random.seed(7)
while len(durate_camp) < N_CAMP_TARGET:
    d = int(random.gauss(DUR_CAMP_MED, 9))
    d = max(12, min(45, d))
    durate_camp.append(d)

# Riscalo le durate per centrare CONTEMPORANEAMENTE il CF (somma giorni ON) e
# la durata media ~ DUR_CAMP_MED: con 15 campagne e CF*731 ~ 314 gg, la media
# naturale e' ~21 gg; aggiungo un piccolo aggiustamento per avvicinarla a 23.
giorni_on_target = round(CF_TARGET * n_giorni)
fattore = giorni_on_target / sum(durate_camp)
durate_camp = [max(12, round(d * fattore)) for d in durate_camp]

# Fermate: il resto dei giorni diviso tra le campagne (n_camp+1 intervalli)
giorni_off_tot = n_giorni - sum(durate_camp)
n_gap = N_CAMP_TARGET + 1
base_gap = giorni_off_tot // n_gap
resto    = giorni_off_tot - base_gap * n_gap
durate_off = [base_gap + (1 if i < resto else 0) for i in range(n_gap)]
random.shuffle(durate_off)

# Sequenza temporale: OFF, ON, OFF, ON, ..., OFF
inprod = [0] * n_giorni
idx = 0
idx += durate_off[0]
for k in range(N_CAMP_TARGET):
    for _ in range(durate_camp[k]):
        if idx < n_giorni:
            inprod[idx] = 1
            idx += 1
    if idx < n_giorni:
        idx += durate_off[k + 1]

# --- Portata fumi a regime: calibrata per ottenere CLINKER_TARGET -----------
# clinker_anno = sum(portata*24)/VOL_SPEC ; impongo la portata media a regime
giorni_on_eff = sum(inprod) / 2.0  # /2 perche' due anni -> media annua
# portata media necessaria [Nm3/h] per anno: clinker*vol_spec/(ore_on_anno)
ore_on_anno = sum(inprod) * 24.0 / 2.0
portata_media = CLINKER_TARGET * VOL_SPEC / ore_on_anno

# Genero portata oraria-media giornaliera con variabilita' realistica (rampe
# di avvio/arresto + rumore di processo), poi normalizzo per centrare il target.
portata = [0.0] * n_giorni
# individua inizio/fine di ogni campagna per le rampe
k = 0
while k < n_giorni:
    if inprod[k] == 1:
        j = k
        while j < n_giorni and inprod[j] == 1:
            j += 1
        L = j - k  # durata campagna
        for t in range(L):
            # Trend tipo slide: rampa di avvio (1 gg) e arresto (1 gg), poi
            # regime piatto con RUMORE UNIFORME +/-3% (non gaussiano), cosi'
            # la banda resta "pulita" e ondeggia uniformemente attorno al regime.
            if t == 0:
                f = 0.55
            elif t == L - 1:
                f = 0.6
            else:
                f = 1.0 + random.uniform(-0.03, 0.03)
            portata[k + t] = portata_media * max(0.3, f)
        k = j
    else:
        k += 1

# normalizzo perche' l'integrale dia esattamente il clinker target
clinker_grezzo = sum(p * 24.0 for p in portata) / VOL_SPEC / 2.0
scala = CLINKER_TARGET / clinker_grezzo
portata = [p * scala for p in portata]

# semiore di funzionamento (48 = 24 h piene) a forno acceso, 0 a forno spento
semiore = [48 if inprod[i] else 0 for i in range(n_giorni)]

# --- Scrittura CSV forno ----------------------------------------------------
fpath1 = "emissioni_barletta_2024_2025.csv"
with open(fpath1, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, delimiter=";")
    w.writerow(["Data", "Semiore_Funzionamento", "Portata_Fumi_Nm3h", "In_Produzione"])
    for i, g in enumerate(giorni):
        port = "" if inprod[i] == 0 else str(int(round(portata[i])))
        w.writerow([g.strftime("%d/%m/%Y"), semiore[i], port, inprod[i]])

# ============================================================================
#  2) FILE PROFILO PV ORARIO
# ============================================================================
# NB: il profilo PV NON viene piu' generato qui. E' scaricato REALE dall'API
# PVGIS (PVGIS-SARAH3, Barletta 2013, 1 kWp, perdite 14%, tilt 5 deg) e
# convertito da 'converti_pvgis.py' nel file 'pvgis_barletta_2013_sarah3.csv'.
# Questo script si occupa SOLTANTO del file del forno, per non sovrascrivere
# il profilo PV reale.

# ============================================================================
#  CONTROLLI DI VERIFICA
# ============================================================================
# forno
def identifica_cicli(x):
    durate, n = [], 0
    i = 0
    while i < len(x):
        if x[i] == 1:
            j = i
            while j < len(x) and x[j] == 1:
                j += 1
            durate.append(j - i); n += 1; i = j
        else:
            i += 1
    return durate, n

dur_camp, n_camp = identifica_cicli(inprod)
ore_tot   = sum(semiore) / 2.0
CF_ore    = ore_tot / (n_giorni * 24.0)
clinker_y = sum(p * 24.0 for p in portata) / VOL_SPEC / 2.0

print("=" * 64)
print("CONTROLLI - FILE FORNO  (%s)" % fpath1)
print("=" * 64)
print("  Giorni totali        : %d (%s -> %s)" % (n_giorni, START, END))
print("  Giorni in produzione : %d (%.1f%% dei giorni)" % (sum(inprod), 100 * sum(inprod) / n_giorni))
print("  Capacity factor (ore): %.1f%%   [target ~43%%]" % (100 * CF_ore))
print("  N. campagne          : %d        [target ~15]" % n_camp)
print("  Durata media campagna: %.1f gg   [target ~23]" % (sum(dur_camp) / len(dur_camp)))
print("  Durata max campagna  : %d gg" % max(dur_camp))
regime_vals = [p for p in portata if p > 400000]
reg_media = sum(regime_vals) / len(regime_vals)
reg_dev = (sum((p - reg_media) ** 2 for p in regime_vals) / len(regime_vals)) ** 0.5
print("  Portata a regime     : media %d, min %d, max %d Nm3/h" %
      (round(reg_media), round(min(regime_vals)), round(max(regime_vals))))
print("  Rumore regime        : +/-%.1f%% (uniforme)  [slide ~500k +/-rumore]" % (100 * reg_dev / reg_media))
print("  Clinker medio annuo  : %.1f kt/anno  [target ~830]" % (clinker_y / 1e3))
print()
print("NB: il profilo PV e' REALE (PVGIS) e si genera con 'converti_pvgis.py'.")
print("File forno scritto nella cartella corrente: %s" % fpath1)

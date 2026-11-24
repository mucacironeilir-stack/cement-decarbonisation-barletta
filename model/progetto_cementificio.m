% =========================================================================
%  DECARBONIZZAZIONE DELLA CEMENTERIA BUZZI DI BARLETTA (BT)
%  Progetto per il corso "Progettazione di impianti rinnovabili"
%
%  Configurazione studiata: idrogeno verde da PV + inverter + elettrolizzatore
%  (senza accumulo), bruciato nel forno in combustione blended. Il PV in
%  eccesso copre il carico elettrico dello stabilimento e, oltre il carico,
%  produce H2 venduto a terzi. La configurazione e' valutata a varie taglie.
%
%  Esecuzione consigliata: per celle (Run Section). Richiede MATLAB R2019b+.
% =========================================================================

clear; clc; close all;

%% ===================== SEZIONE 0 - DATI DI INPUT ========================
% Fonti: [BUZZI] Bilancio di Sostenibilita' Buzzi 2023   [BREF] BAT cemento UE
%        [ISPRA] rete elettrica IT    [IPCC] combustibili
%        [PVGIS] producibilita' solare [G.EARTH] misure satellitari
%        [IPOT]  ipotesi di progetto

P = struct();

% File di lavoro
P.csvFile  = 'emissioni_barletta_2024_2025.csv';  % dati SME giornalieri del forno
P.figDir   = 'figure';
P.salvaFig = true;                                % esporta le figure in PNG+PDF

% Processo cemento
P.q_th_clinker   = 4.175;  % [GJ/t clinker] consumo termico specifico [BUZZI]
P.e_el_cemento   = 123;    % [kWh/t cemento] consumo elettrico specifico [BUZZI]
P.clinker_factor = 0.782;  % [t clinker/t cemento] [BUZZI]
P.vol_fumi_spec  = 2300;   % [Nm3/t clinker] volume specifico fumi secchi [BREF]

% Ripartizione del consumo elettrico sulle 5 fasi della filiera [BREF/IPOT]
P.fasi    = {'Escavazione e frantumazione','Macinazione farina (crudo)', ...
             'Cottura clinker (forno)','Macinazione cemento','Trasporto e spedizione'};
P.perc_el = [0.04 0.24 0.24 0.40 0.08];   % quote (somma = 1)

% Emissioni di CO2
P.co2_calcinazione = 0.525; % [t CO2/t clinker] CO2 di processo (calcinazione) [GCCA]
P.thermal_subst    = 0.292; % [-] quota di sostituzione calorica (CSS/biomassa) [BUZZI]
P.EF_fossile       = 95;    % [kg CO2/GJ] fattore emissione combustibile fossile [IPCC]
P.EF_alt_netto     = 30;    % [kg CO2/GJ] fattore emissione netto comb. alternativi [IPOT]
P.co2_grid         = 0.28;  % [kg CO2/kWh] fattore emissione rete elettrica IT [ISPRA]
P.co2_buzzi_net    = 607;   % [kg CO2/t cem] dirette nette dichiarate (cross-check) [BUZZI]
P.co2_buzzi_gross  = 665;   % [kg CO2/t cem] dirette lorde dichiarate = Scope 1 [BUZZI]

% Parametri economici
P.r           = 0.06; % [-] tasso di sconto
P.N           = 20;   % [anni] orizzonte di valutazione
P.prezzo_ETS  = 80;   % [EUR/t CO2] prezzo quota EU-ETS
P.prezzo_el   = 0.2;  % [EUR/kWh] elettricita' di rete evitata
P.prezzo_export = 0.10; % [EUR/kWh] energia PV in eccesso immessa in rete e venduta [IPOT]
P.prezzo_fuel = 5.0;  % [EUR/GJ] combustibile fossile sostituito (petcoke)

% Impianto PV + inverter + elettrolizzatore (taglia reale da coperture)
P.B_area_m2    = 29693;  % [m2] superficie lorda delle coperture disponibili [G.EARTH]
P.B_area_util  = 0.70;   % [-] frazione utilizzabile delle coperture [IPOT]
P.B_pv_density = 0.19;   % [kWp/m2] densita' di potenza dei moduli [IPOT]
P.B_PV_MWp     = P.B_area_m2*P.B_area_util*P.B_pv_density/1000;  % [MWp] taglia reale (~3.9)
P.B_pvgis_file = 'pvgis_barletta_2013_sarah3.csv';  % profilo orario PV per kWp [PVGIS]
P.B_ely_kWhkg  = 53;     % [kWh/kg H2] consumo specifico elettrolizzatore PEM (sistema, range 49-54) [IRENA]
P.B_dur_pct    = 0.75;   % [-] percentile della potenza PV per la taglia elettrolizzatore [IPOT]
P.B_LHV_H2     = 0.120;  % [GJ/kg] potere calorifico inferiore dell'H2
P.B_max_subst  = 0.20;   % [-] quota massima di H2 in combustione blended (limite di fiamma) [IPOT]
P.B_DCAC       = 1.20;   % [-] rapporto DC/AC dell'inverter [IPOT]
% CAPEX con economia di scala: C_i = C0*(P/P0)^m  [P in MW] [IPOT, legge di scala]
% C0 = costo INSTALLATO (chiavi-in-mano: moduli/inverter/stack + BOS, strutture,
% installazione, connessione, balance-of-plant) a P0 = 1 MW; l'esponente m < 1 da'
% il risparmio unitario al crescere della taglia (PV/inverter m=0.95; elettrolizz. m=0.90).
P.B_capexPV  = [ 800000 1 0.95];  % [C0 EUR a 1 MW, P0 MW, m] campo PV chiavi-in-mano
P.B_capexInv = [  60000 1 0.95];  % [C0 EUR a 1 MW, P0 MW, m] inverter
P.B_capexEly = [1500000 1 0.90];  % [C0 EUR a 1 MW, P0 MW, m] elettrolizzatore (BOP incl.)
P.B_capex_retr = 3.0e6;  % [EUR] retrofit del bruciatore per combustione blended [IPOT]
P.B_opex       = 0.03;   % [-] OPEX annuo come frazione del CAPEX totale

% Studio per taglie
P.B_prezzo_H2  = 5.0;     % [EUR/kg] prezzo di mercato H2 (riferimento per la sensibilita') [IPOT]
P.B_taglie_pct = [1 2 5]; % [%] obiettivi di sostituzione termica
P.B_PV_max     = 160;     % [MWp] estremo superiore dello sweep di taglia

% Clinker substitution (sostituzione del clinker) - FASE C
% Leva sulla CALCINAZIONE (il 59% irriducibile con H2): si abbassa il rapporto
% clinker/cemento r (P.clinker_factor) sostituendo clinker con FILLER CALCAREO CRUDO.
% CO2 di processo evitata = EF_calc*dr*cemento. Buzzi produce gia' CEM II (r=0,782):
% la leva e' spingere la quota di calcare, entro i limiti normativi (EN 197-1) e
% prestazionali (resistenza). Materiale CRUDO: zero cottura -> zero CO2 aggiuntiva.
P.B_cs_dr      = [0 0.04 0.08 0.12];   % [-] riduzioni di r testate (r: 0,782 -> 0,742 / 0,702 / 0,662)
P.B_cs_scm     = {'baseline (CEM II attuale)', ...     % materiale: filler calcareo crudo, quota crescente
                  'filler calcareo -> CEM II/A-L', ...
                  'filler calcareo -> CEM II/B-LL', ...
                  'filler calcareo -> CEM II/B-LL (max)'};
P.B_cs_cost    = [0 5 7 9];            % [EUR/t CO2 evitata] costo da letteratura [BENCHMARK]
                                       % filler calcareo crudo: basso (solo macinazione, no cottura)
P.B_cs_reperib = {'-', ...                              % provenienza del filler per Barletta
                  'cava Buzzi (zero cottura)', ...
                  'cava Buzzi (zero cottura)', ...
                  'cava Buzzi (zero cottura)'};
% MATERIALE: filler calcareo crudo = stesso calcare gia' estratto in cava per il
% clinker, solo macinato anziche' cotto. Reperibilita' a km zero (Puglia = regione
% calcarea, Murge), zero cottura -> zero decarbonatazione, zero CO2 per la frazione.
% EN 197-1: CEM II/A-L (6-20% calcare), CEM II/B-LL (21-35%); tetto ~35% (oltre cala
% la resistenza). SCARTATI: argilla calcinata/LC3 (richiede cottura ~800 C); pozzolane
% naturali (giacimenti Campania/Lazio, non in Puglia); loppa/ceneri (declino, non locali).
% Fonti: it.wikipedia Cementeria di Barletta (materie prime locali); EN 197-1.

% Storage elettrico (BESS) - FASE 2 [IPOT]
% Polmone elettrico INTRA-DAY: accumula il PV in eccesso e lo restituisce
% all'elettrolizzatore quando il forno e' acceso ma il PV e' insufficiente.
% Con Eb=0 il dispatch coincide col caso senza accumulo (riferimento).
P.B_bess_Eb   = 0;       % [MWh] energia utile della batteria (0 = nessun accumulo)
P.B_bess_Pb   = 0;       % [MW]  potenza di carica/scarica (0 = auto: Eb/4, C-rate 0,25)
P.B_bess_eta  = 0.90;    % [-]   efficienza round-trip (sqrt applicata in carica e scarica)
P.B_bess_capex = 350;    % [EUR/kWh] CAPEX specifico BESS (storage 2-4 h) [IPOT]
P.B_bess_opex  = 0.02;   % [-]   OPEX BESS come frazione del proprio CAPEX/anno [IPOT]

% Storage di IDROGENO (serbatoi a pressione) - FASE A [IPOT]
% Polmone di H2: accumula l'idrogeno prodotto in eccesso nelle ore di sole
% (oggi venduto a terzi) e lo restituisce al forno nelle ore senza sole ma con
% forno acceso, potendo cosi' superare il tetto di sostituzione del dispatch in
% tempo reale (~9,7%). Con Eb=0 il dispatch coincide col caso senza accumulo.
P.B_h2s_Eb    = 0;       % [kg]   capacita' utile del serbatoio H2 (0 = nessun accumulo)
P.B_h2s_eta   = 0.95;    % [-]    efficienza del ciclo di stoccaggio (compress./decompress.) [IRENA]
P.B_h2s_capex = 600;     % [EUR/kg] CAPEX specifico serbatoi H2 ad alta pressione (350-700 bar) [IEA/IRENA]
P.B_h2s_opex  = 0.02;    % [-]    OPEX serbatoi come frazione del proprio CAPEX/anno [IPOT]

fprintf('Sezione 0: parametri caricati.\n');

%% ===================== SEZIONE 1 - LETTURA DATI =========================
% CSV con separatore ';', date dd/MM/yyyy, portata vuota nei giorni di fermo.

assert(isfile(P.csvFile), 'File dati non trovato: %s', P.csvFile);

opts = detectImportOptions(P.csvFile, 'Delimiter', ';');
opts = setvartype(opts, 'Data', 'datetime');
opts = setvaropts(opts, 'Data', 'InputFormat', 'dd/MM/yyyy');
T = readtable(P.csvFile, opts);

data    = T.Data;                       % [datetime] giorno
semiore = double(T.Semiore_Funzionamento);
ore     = semiore/2;                    % [h/giorno] ore di marcia
portata = double(T.Portata_Fumi_Nm3h);  % [Nm3/h] portata fumi
portata(isnan(portata)) = 0;            % giorni fermi
inprod  = double(T.In_Produzione) > 0;  % forno acceso/spento

anni      = year(data);
mesi      = month(data);
listaAnni = unique(anni)';
nGiorni   = height(T);

fprintf('Sezione 1: letti %d giorni (%d-%d).\n', nGiorni, min(anni), max(anni));
if P.salvaFig && ~exist(P.figDir,'dir'); mkdir(P.figDir); end

%% ===================== SEZIONE 2 - PRODUZIONE E BASELINE ================
% Produzione di clinker stimata dalla portata fumi; bilancio energetico ed
% emissivo dell'impianto.

% Produzione clinker: integrale (portata*ore) / volume specifico fumi
volFumi_giorno = portata .* ore;                    % [Nm3/giorno]
clinker_giorno = volFumi_giorno / P.vol_fumi_spec;  % [t clinker/giorno]

clinker_anno = zeros(size(listaAnni));
for k = 1:numel(listaAnni)
    clinker_anno(k) = sum(clinker_giorno(anni==listaAnni(k)));
end
clinker_y = mean(clinker_anno);              % [t clinker/anno]
cemento_y = clinker_y / P.clinker_factor;    % [t cemento/anno]

fprintf('\n--- BASELINE ---\n');
for k = 1:numel(listaAnni)
    fprintf('  Clinker %d : %s t\n', listaAnni(k), comma(round(clinker_anno(k))));
end
fprintf('  Clinker medio annuo : %s t/anno\n', comma(round(clinker_y)));
fprintf('  Cemento medio annuo : %s t/anno\n', comma(round(cemento_y)));

% Energia per fase di filiera
e_el_fase   = P.e_el_cemento * P.perc_el;             % [kWh/t cem] per fase
E_el_fase_y = e_el_fase * cemento_y / 1e6;            % [GWh/anno] per fase
E_el_tot_y  = sum(E_el_fase_y);                       % [GWh/anno] elettrico totale
E_th_tot_y  = P.q_th_clinker * clinker_y / 3.6 / 1e3; % [GWh_th/anno]

fprintf('  Fabbisogno elettrico  : %.1f GWh/anno\n', E_el_tot_y);
fprintf('  Fabbisogno termico    : %.1f GWh_th/anno (%.0f TJ)\n', ...
        E_th_tot_y, P.q_th_clinker*clinker_y/1e3);

% Emissioni di CO2: il dato dichiarato Buzzi gross e' lo Scope 1 diretto
% (calcinazione + combustione); la calcinazione e' il termine stechiometrico
% e la combustione il residuo. L'elettrico (Scope 2, rete) si somma sopra.
co2_calc_tcem = P.co2_calcinazione * P.clinker_factor * 1000; % [kg/t cem] calcinazione
co2_elec_tcem = P.e_el_cemento * P.co2_grid;                  % [kg/t cem] elettrico (Scope 2)
co2_s1_tcem   = P.co2_buzzi_gross;                            % [kg/t cem] Scope 1 dichiarato
co2_comb_tcem = co2_s1_tcem - co2_calc_tcem;                  % [kg/t cem] combustione (residuo)
co2_tot_tcem  = co2_s1_tcem + co2_elec_tcem;                  % [kg/t cem] totale Scope 1+2
% Validazione della combustione con i fattori di emissione del mix combustibili
EF_mix            = P.thermal_subst*P.EF_alt_netto + (1-P.thermal_subst)*P.EF_fossile; % [kg/GJ]
co2_comb_bottomup = P.q_th_clinker * P.clinker_factor * EF_mix;                        % [kg/t cem]

% Totali annui [t CO2/anno]
CO2.calc = co2_calc_tcem * cemento_y / 1000;
CO2.comb = co2_comb_tcem * cemento_y / 1000;
CO2.elec = co2_elec_tcem * cemento_y / 1000;
CO2.tot  = co2_tot_tcem  * cemento_y / 1000;

fprintf('  CO2 Scope 1 (Buzzi gross): %.0f kg/t cem (net %d)\n', co2_s1_tcem, P.co2_buzzi_net);
fprintf('  CO2 totale Scope 1+2     : %.0f kg/t cem = %s t/anno\n', co2_tot_tcem, comma(round(CO2.tot)));
fprintf('     split: calcinazione %.0f%% | combustione %.0f%% | elettrico %.0f%%\n', ...
        100*co2_calc_tcem/co2_tot_tcem, 100*co2_comb_tcem/co2_tot_tcem, 100*co2_elec_tcem/co2_tot_tcem);
fprintf('     validazione combustione: residuo %.0f vs stima EF mix %.0f kg/t\n', ...
        co2_comb_tcem, co2_comb_bottomup);

% --- GRAFICO 02a: consumo elettrico per fase ----------------------------
f = figure('Name','Filiera - consumo elettrico','Color','w','Position',[80 80 760 460]);
bar(categorical(P.fasi,P.fasi), e_el_fase, 0.6, 'FaceColor',[0.20 0.45 0.70]);
ylabel('Consumo elettrico [kWh/t cemento]');
title(sprintf('Ripartizione del consumo elettrico per fase (tot %d kWh/t)', round(P.e_el_cemento)));
grid on; xtickangle(20);
text(1:numel(e_el_fase), e_el_fase, compose('%.1f',e_el_fase), ...
     'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold');
esporta(f, fullfile(P.figDir,'02a_filiera_elettrico'), P);

% --- GRAFICO 02d: energia elettrica e termica per fase ------------------
e_th_fase    = zeros(1, numel(P.fasi));
e_th_fase(3) = P.q_th_clinker * P.clinker_factor / 3.6 * 1000;  % [kWh_th/t cem] tutta in cottura

f = figure('Name','Filiera - elettrico e termico','Color','w','Position',[100 100 1040 460]);
subplot(1,2,1);
bar(categorical(P.fasi,P.fasi), e_el_fase, 0.6, 'FaceColor',[0.20 0.45 0.70]);
ylabel('Energia elettrica [kWh/t cemento]'); grid on; xtickangle(20);
title(sprintf('Consumo ELETTRICO per fase (tot %d kWh/t)', round(P.e_el_cemento)));
subplot(1,2,2);
bar(categorical(P.fasi,P.fasi), [e_el_fase' e_th_fase'], 'stacked');
ylabel('Energia [kWh/t cemento]'); grid on; xtickangle(20);
legend({'Elettrica','Termica'},'Location','northwest');
title(sprintf('Energia ELETTRICA + TERMICA per fase (termico %.0f kWh/t)', e_th_fase(3)));
esporta(f, fullfile(P.figDir,'02d_filiera_energia'), P);

% --- GRAFICO 02b: emissioni di CO2 per origine ---------------------------
f = figure('Name','CO2 per origine','Color','w','Position',[120 120 620 480]);
val   = [co2_calc_tcem co2_comb_tcem co2_elec_tcem];
etich = {sprintf('Calcinazione\n%.0f kg/t (%.0f%%)',co2_calc_tcem,100*co2_calc_tcem/co2_tot_tcem), ...
         sprintf('Combustione\n%.0f kg/t (%.0f%%)',co2_comb_tcem,100*co2_comb_tcem/co2_tot_tcem), ...
         sprintf('Elettrico\n%.0f kg/t (%.0f%%)',co2_elec_tcem,100*co2_elec_tcem/co2_tot_tcem)};
hp = pie(val, etich);
colormap(gca, [0.85 0.33 0.10; 0.47 0.67 0.19; 0.30 0.55 0.85]);
title(sprintf('Origine delle emissioni di CO_2  (%.0f kg/t cemento, Scope 1+2)', co2_tot_tcem));
% l'etichetta "Elettrico" viene spostata per non sovrapporsi al titolo
hp(6).Clipping = 'off';
hp(6).Position = hp(6).Position + [0.22 -0.14 0];
esporta(f, fullfile(P.figDir,'02b_CO2_origine'), P);

% --- GRAFICO 02c: validazione della quota combustione --------------------
f = figure('Name','CO2 cross-check','Color','w','Position',[160 160 560 440]);
bar(categorical({'Combustione (residuo)','Combustione (stima EF mix)'}, ...
    {'Combustione (residuo)','Combustione (stima EF mix)'}), ...
    [co2_comb_tcem co2_comb_bottomup], 0.5, 'FaceColor',[0.40 0.40 0.45]);
ylabel('kg CO_2 / t cemento'); grid on;
title('Validazione: combustione (residuo del totale dichiarato) vs stima da EF');
esporta(f, fullfile(P.figDir,'02c_CO2_crosscheck'), P);

%% ===================== SEZIONE 3 - DINAMICA DEL FORNO ===================
% Funzionamento "a campagne": cicli on/off e capacity factor.

ore_tot   = sum(ore);              % [h] ore di marcia nel periodo
ore_pieno = nGiorni*24;            % [h] ore solari nel periodo
CF_giorni = sum(inprod)/nGiorni;   % [-] capacity factor su base giorni
CF_ore    = ore_tot/ore_pieno;     % [-] capacity factor su base ore

cicli = identifica_cicli(inprod);

fprintf('\n--- DINAMICA ---\n');
fprintf('  Giorni in produzione : %d/%d (%.1f%%)\n', sum(inprod), nGiorni, 100*CF_giorni);
fprintf('  Capacity factor (ore): %.1f%%\n', 100*CF_ore);
fprintf('  N. campagne          : %d\n', cicli.n_campagne);
fprintf('  Durata media campagna: %.1f giorni (max %d)\n', mean(cicli.dur_campagne), max(cicli.dur_campagne));
if ~isempty(cicli.dur_fermate)
    fprintf('  Durata media fermata : %.1f giorni (max %d)\n', mean(cicli.dur_fermate), max(cicli.dur_fermate));
end

% --- GRAFICO 03a: serie temporale portata fumi + stato forno -------------
f = figure('Name','Dinamica forno','Color','w','Position',[80 80 1000 440]);
yyaxis left
area(data, portata/1000, 'FaceColor',[0.20 0.45 0.70],'FaceAlpha',0.6,'EdgeColor','none');
ylabel('Portata fumi [10^3 Nm^3/h]');
yyaxis right
stairs(data, inprod, 'Color',[0.85 0.33 0.10],'LineWidth',1.2);
ylim([-0.1 1.4]); yticks([0 1]); yticklabels({'OFF','ON'});
ylabel('Stato forno');
title(sprintf('Funzionamento a campagne del forno  (CF = %.0f%% ore, %d avviamenti)', ...
      100*CF_ore, cicli.n_campagne));
grid on; xlabel('Data');
esporta(f, fullfile(P.figDir,'03a_dinamica_timeseries'), P);

% --- GRAFICO 03b: distribuzione delle durate ------------------------------
f = figure('Name','Durate cicli','Color','w','Position',[120 120 820 420]);
subplot(1,2,1);
histogram(cicli.dur_campagne, 'FaceColor',[0.20 0.45 0.70]);
xlabel('Durata campagna [giorni]'); ylabel('Frequenza'); title('Campagne di marcia'); grid on;
subplot(1,2,2);
histogram(cicli.dur_fermate, 'FaceColor',[0.85 0.33 0.10]);
xlabel('Durata fermata [giorni]'); ylabel('Frequenza'); title('Fermate'); grid on;
esporta(f, fullfile(P.figDir,'03b_durate_cicli'), P);

% --- GRAFICO 03c: ore di marcia per mese ----------------------------------
oreMese = zeros(12, numel(listaAnni));
for k = 1:numel(listaAnni)
    for m = 1:12
        oreMese(m,k) = sum(ore(anni==listaAnni(k) & mesi==m));
    end
end
f = figure('Name','Ore marcia per mese','Color','w','Position',[160 160 860 420]);
bar(1:12, oreMese, 'grouped'); grid on;
xticks(1:12); xticklabels({'G','F','M','A','M','G','L','A','S','O','N','D'});
ylabel('Ore di marcia'); xlabel('Mese');
legend(string(listaAnni),'Location','best');
title('Ore di marcia mensili del forno');
esporta(f, fullfile(P.figDir,'03c_ore_mensili'), P);

%% ===================== SEZIONE 4 - PROFILI ORARI E DIMENSIONAMENTO ======
% Profilo PV orario reale (PVGIS), taglia di inverter ed elettrolizzatore,
% domanda di H2 del forno e carico elettrico dello stabilimento.

% Profilo PV orario per kWp (PVGIS 2013, SARAH3, perdite 14%), mappato sul
% calendario dei dati SME per (mese, giorno)
PG   = readtable(P.B_pvgis_file, 'Delimiter', ';');  % colonne: month;day;hour;P_kW_per_kWp
prof = nan(12,31,24);                                % [kW/kWp]
for i = 1:height(PG)
    prof(PG.month(i), PG.day(i), PG.hour(i)+1) = PG.P_kW_per_kWp(i);
end
mm  = month(data);  dd = day(data);
Ppv = zeros(nGiorni,24);                             % [kW] potenza PV taglia reale
for d = 1:nGiorni
    gd = dd(d);
    if mm(d)==2 && gd==29, gd = 28; end              % 29 febbraio -> profilo 28 febbraio
    Ppv(d,:) = squeeze(prof(mm(d),gd,:))' * P.B_PV_MWp*1000;
end
Ppv(isnan(Ppv)) = 0;
Ppv_v = reshape(Ppv',[],1);                          % [kW] vettore orario DC

% Inverter: taglia AC dal rapporto DC/AC, con clipping dei picchi
P_inv    = P.B_PV_MWp*1000 / P.B_DCAC;               % [kW_AC]
B.inv_MW = P_inv/1000;
Ppv_v    = min(Ppv_v, P_inv);                        % [kW] potenza AC oraria

% Elettrolizzatore: 75-esimo percentile della potenza PV nelle ore di sole
sunP     = Ppv_v(Ppv_v > 1e-6);
P_ely    = pctl(sunP, 100*P.B_dur_pct);              % [kW]
B.ely_MW = P_ely/1000;

% Domanda oraria di H2 del forno (quota massima blended, spalmata sulle 24 h)
th_day_GJ = clinker_giorno * P.q_th_clinker;         % [GJ/giorno] termico forno
demH2_day = P.B_max_subst * th_day_GJ / P.B_LHV_H2;  % [kg/giorno] H2 accettabile dal forno
demH2     = repmat((demH2_day/24).*inprod, 1, 24);   % [kg/h] (zero a forno spento)
demH2_v   = reshape(demH2',[],1);

% Carico elettrico orario dello stabilimento: baseload continuo (macinazione,
% servizi) + quota di cottura presente solo a forno acceso [IPOT]
elec_y_kWh = E_el_tot_y*1e6;                         % [kWh/anno]
ore_on_y   = sum(inprod)*24/numel(listaAnni);        % [h/anno] forno acceso
P_base     = elec_y_kWh*(1-P.perc_el(3))/8760;       % [kW] baseload non-forno
P_kiln_el  = elec_y_kWh*P.perc_el(3)/ore_on_y;       % [kW] quota elettrica del forno
load_mat   = (P_base + P_kiln_el*double(inprod)) .* ones(1,24);
load_v     = reshape(load_mat',[],1);                % [kW] carico orario

fprintf('\n--- DIMENSIONAMENTO (taglia reale %.2f MWp) ---\n', P.B_PV_MWp);
fprintf('  Inverter (DC/AC %.2f) : %.2f MW_AC\n', P.B_DCAC, B.inv_MW);
fprintf('  Elettrolizzatore     : %.2f MW (percentile %.0f della potenza PV)\n', ...
        B.ely_MW, 100*P.B_dur_pct);

% --- GRAFICO 05c: curva di durata della produzione PV --------------------
f = figure('Name','Curva di durata PV','Color','w','Position',[80 80 720 460]);
ss = sort(sunP,'descend')/1000;  xx = linspace(0,100,numel(ss));
plot(xx, ss, 'Color',[0.95 0.70 0.10],'LineWidth',2); hold on; grid on;
yline(B.ely_MW,'--','Color',[0.20 0.45 0.70],'LineWidth',1.6, ...
      'Label',sprintf('Elettrolizzatore %.2f MW',B.ely_MW));
xline(100*(1-P.B_dur_pct),':','Color',[0.85 0.33 0.10],'LineWidth',1.6);
plot(100*(1-P.B_dur_pct), B.ely_MW,'o','MarkerFaceColor',[0.85 0.33 0.10],'MarkerEdgeColor','k');
xlabel('% delle ore di sole'); ylabel('Potenza [MW]'); xlim([0 100]); ylim([0 inf]);
title('Curva di durata della produzione PV e taglia dell''elettrolizzatore');
esporta(f, fullfile(P.figDir,'05c_curva_durata_PV'), P);

%% ===================== SEZIONE 5 - DISPATCH A CASCATA E TAGLIE ==========
% Dispacciamento orario senza accumulo, con priorita':
%  1) PV -> elettrolizzatore -> H2 al forno (Scope 1)
%  2) PV in eccesso -> carico elettrico d'impianto (Scope 2)
%  3) PV oltre il carico -> H2 venduto a terzi
%  4) residuo -> curtailment/export
% Prima si valuta la taglia reale, poi la stessa cascata e' replicata a
% taglie crescenti (funzione cascata_B) per gli obiettivi di sostituzione.

CRF = P.r*(1+P.r)^P.N / ((1+P.r)^P.N - 1);   % [-] fattore di recupero del capitale

% --- Cascata oraria alla taglia reale ------------------------------------
pv_ely  = min(Ppv_v, P_ely);                          % [kW] PV verso elettrolizzatore
h2_made = min(pv_ely/P.B_ely_kWhkg, demH2_v);         % [kg/h] H2 bruciato nel forno
e_kiln  = h2_made*P.B_ely_kWhkg;                      % [kWh] elettricita' per H2 al forno
pv_rem  = Ppv_v - e_kiln;                             % [kW] PV residuo
ely_rem = max(P_ely - e_kiln, 0);                     % [kW] capacita' elettrolizzatore residua
E_self  = min(pv_rem, load_v);                        % [kWh] PV -> carico d'impianto
pv_rem2 = pv_rem - E_self;                            % [kW] PV oltre il carico
h2_sale = min(pv_rem2/P.B_ely_kWhkg, ely_rem/P.B_ely_kWhkg);  % [kg/h] H2 venduto
e_curt  = pv_rem2 - h2_sale*P.B_ely_kWhkg;            % [kWh] curtailment/export

% --- KPI tecnici alla taglia reale ---------------------------------------
H2_kiln_y = sum(h2_made)/numel(listaAnni);            % [kg/anno] H2 al forno
H2_sale_y = sum(h2_sale)/numel(listaAnni);            % [kg/anno] H2 venduto
E_self_y  = sum(E_self)/numel(listaAnni);             % [kWh/anno] autoconsumo elettrico
E_curt_y  = sum(e_curt)/numel(listaAnni);             % [kWh/anno] curtailment
B.subst   = sum(h2_made)*P.B_LHV_H2 / sum(th_day_GJ); % [-] sostituzione termica al forno
B.H2_y    = H2_kiln_y;
B.H2_sale = H2_sale_y;
B.Eself_y = E_self_y;
B.Ecurt_y = E_curt_y;
% CO2 evitata DALLA cementeria = Scope 1 (H2 al forno) + Scope 2 (autoconsumo)
B.CO2_s1 = H2_kiln_y * P.B_LHV_H2 * P.EF_fossile / 1000;  % [t/anno]
B.CO2_s2 = E_self_y * P.co2_grid / 1000;                  % [t/anno]
B.CO2    = B.CO2_s1 + B.CO2_s2;                           % [t/anno]
% CO2 evitata con l'H2 venduto: e' del compratore, non si somma a B.CO2
B.CO2_exp = H2_sale_y * P.B_LHV_H2 * P.EF_fossile / 1000; % [t/anno]

% --- CAPEX e OPEX (con economia di scala C_i = C0*(P/P0)^m) ---------------
costPV  = capex_scala(P.B_PV_MWp, P.B_capexPV);   % [EUR] moduli PV
costInv = capex_scala(P_inv/1000, P.B_capexInv);  % [EUR] inverter (P in MW)
costEly = capex_scala(P_ely/1000, P.B_capexEly);  % [EUR] elettrolizzatore (P in MW)
B.CAPEX = costPV + costInv + costEly + P.B_capex_retr;   % [EUR]
B.OPEX  = B.CAPEX * P.B_opex;                     % [EUR/anno]
B.capexPV = costPV; B.capexInv = costInv;         % [EUR] scomposizione CAPEX
B.capexEly = costEly; B.capexRetr = P.B_capex_retr;

% Riferimento: stesso PV interamente autoconsumato come elettricita' (no H2)
Eref_y    = sum(Ppv_v)/numel(listaAnni);          % [kWh/anno] energia PV prodotta
B.yield   = Eref_y / (P.B_PV_MWp*1000);           % [kWh/kWp/anno] producibilita'
B.CO2_ref = Eref_y * P.co2_grid / 1000;           % [t/anno]
CAPEX_ref = costPV + costInv;                     % [EUR] PV+inverter
sav_ref   = Eref_y*P.prezzo_el + B.CO2_ref*P.prezzo_ETS - CAPEX_ref*P.B_opex;
B.VAN_ref = calcola_VAN([-CAPEX_ref, repmat(sav_ref,1,P.N)], P.r);

% --- LCOH (metodologia European Hydrogen Observatory) ---------------------
% Tre voci per kg di H2: CAPEX del solo elettrolizzatore annualizzato col CRF,
% elettricita' consumata valutata al LCOE del campo PV, OPEX elettrolizzatore.
H2_tot_y  = H2_kiln_y + H2_sale_y;                            % [kg/anno]
B.LCOE_PV = (CAPEX_ref*CRF + CAPEX_ref*P.B_opex) / Eref_y;    % [EUR/kWh]
E_to_H2_y = H2_tot_y * P.B_ely_kWhkg;                         % [kWh/anno]
CAPEX_ely = costEly;                                         % [EUR]
B.LCOH_cap = CAPEX_ely*CRF       / H2_tot_y;                  % [EUR/kg] quota CAPEX
B.LCOH_ele = E_to_H2_y*B.LCOE_PV / H2_tot_y;                  % [EUR/kg] quota elettricita'
B.LCOH_opx = CAPEX_ely*P.B_opex  / H2_tot_y;                  % [EUR/kg] quota OPEX
B.LCOH     = B.LCOH_cap + B.LCOH_ele + B.LCOH_opx;            % [EUR/kg]
B.CF_ely   = E_to_H2_y / (P_ely*8760);                        % [-] CF elettrolizzatore
B.ore_eq   = B.CF_ely*8760;                                   % [h/anno] ore equivalenti elettrolizzatore (no accumulo)
B.fracUtil = 100*(H2_kiln_y*P.B_ely_kWhkg + E_self_y)/max(Eref_y,1e-9);  % [%] quota PV utile alla cementeria (forno + autoconsumo)

% --- Ricavi annui e VAN ----------------------------------------------------
% L'H2 in eccesso e' venduto al proprio LCOH (vendita al costo, margine nullo);
% alla taglia reale la vendita e' comunque nulla.
saving_fuel = H2_kiln_y*P.B_LHV_H2 * P.prezzo_fuel;  % [EUR/anno] fossile evitato
saving_el   = E_self_y * P.prezzo_el;                % [EUR/anno] elettricita' evitata
saving_h2   = H2_sale_y * B.LCOH;                    % [EUR/anno] H2 venduto al LCOH
saving_exp  = E_curt_y * P.prezzo_export;            % [EUR/anno] energia in eccesso in rete
saving_co2  = B.CO2 * P.prezzo_ETS;                  % [EUR/anno] quote ETS evitate
B.saving = saving_fuel + saving_el + saving_h2 + saving_exp + saving_co2 - B.OPEX;
B.VAN    = calcola_VAN([-B.CAPEX, repmat(B.saving,1,P.N)], P.r);

fprintf('\n--- CONFIGURAZIONE H2, taglia reale (%.2f MWp) ---\n', P.B_PV_MWp);
fprintf('  H2 al forno            : %s kg/anno | sostituzione termica %.2f%%\n', ...
        comma(round(H2_kiln_y)), 100*B.subst);
fprintf('  Autoconsumo elettrico  : %.1f GWh/anno\n', E_self_y/1e6);
fprintf('  CO2 evitata            : %s t/anno (Scope1 %s + Scope2 %s)\n', ...
        comma(round(B.CO2)), comma(round(B.CO2_s1)), comma(round(B.CO2_s2)));
fprintf('  CAPEX %.1f M EUR | VAN %.1f M EUR\n', B.CAPEX/1e6, B.VAN/1e6);
fprintf('  LCOH %.2f EUR/kg = CAPEX %.2f + elettricita'' %.2f + OPEX %.2f\n', ...
        B.LCOH, B.LCOH_cap, B.LCOH_ele, B.LCOH_opx);
fprintf('     (LCOE PV %.0f EUR/MWh | CF elettrolizzatore %.0f%%)\n', 1000*B.LCOE_PV, 100*B.CF_ely);
fprintf('  Riferimento PV->elettricita'': VAN %.1f M EUR | CO2 %s t/anno\n', ...
        B.VAN_ref/1e6, comma(round(B.CO2_ref)));

% --- GRAFICO 05a: H2 al forno e destinazione giornaliera del PV ----------
used_d = sum(reshape(h2_made,24,nGiorni),1)';       % [kg/giorno] H2 al forno
el_d   = sum(reshape(E_self,24,nGiorni),1)'/1000;   % [MWh/giorno] autoconsumo
h2en_d = used_d*P.B_ely_kWhkg/1000;                 % [MWh/giorno] PV verso H2
f = figure('Name','H2 - dinamica giornaliera','Color','w','Position',[80 80 1000 600]);
subplot(2,1,1);
plot(data, used_d,'Color',[0.20 0.45 0.70],'LineWidth',1.0); grid on;
ylabel('H_2 al forno [kg/g]');
title('Combustione blended: H_2 bruciato solo a forno in marcia con PV disponibile');
subplot(2,1,2);
ar = area(data, [el_d h2en_d],'EdgeColor','none');
ar(1).FaceColor = [0.85 0.33 0.10];  ar(2).FaceColor = [0.20 0.45 0.70];
grid on; ylabel('Energia PV [MWh/g]'); xlabel('Data');
legend('PV \rightarrow autoconsumo','PV \rightarrow H_2 (combustione blended)','Location','best');
esporta(f, fullfile(P.figDir,'05a_H2_dinamica'), P);

% --- GRAFICO 05d: profilo orario di una settimana tipo --------------------
% Si sceglie la settimana piu' soleggiata con forno acceso: rende evidente
% che, senza accumulo, l'elettrolizzatore lavora solo nelle ore di sole.
t_h = NaT(nGiorni*24,1);
for d = 1:nGiorni
    t_h((d-1)*24+(1:24)) = data(d) + hours(0:23);
end
Epv_d = sum(reshape(Ppv_v,24,nGiorni),1)';          % [kWh/giorno] energia PV
score = zeros(nGiorni-6,1);
for d = 1:nGiorni-6
    idx = d:d+6;
    score(d) = sum(Epv_d(idx).*inprod(idx));
end
[~,d0] = max(score);
idxW   = (d0-1)*24 + (1:7*24);                      % indici orari della settimana
tW     = t_h(idxW);
Pely_load = h2_made*P.B_ely_kWhkg;                  % [kW] carico dell'elettrolizzatore

f = figure('Name','H2 - settimana tipo','Color','w','Position',[90 90 1000 600]);
subplot(2,1,1);
ar = area(tW, [Pely_load(idxW) E_self(idxW)]/1000, 'EdgeColor','none'); hold on;
ar(1).FaceColor = [0.20 0.45 0.70];  ar(2).FaceColor = [0.85 0.33 0.10];
yline(P_ely/1000,'--','Color',[0.20 0.45 0.70],'LineWidth',1.4);
text(tW(1)+hours(4), P_ely/1000, sprintf('Taglia elettrolizzatore %.2f MW',P_ely/1000), ...
     'Color','k','FontWeight','bold','HorizontalAlignment','left','VerticalAlignment','bottom');
grid on; ylabel('Potenza PV [MW]'); ylim([0 inf]); xlim([tW(1) tW(end)]);
legend(ar, {'PV \rightarrow elettrolizzatore (H_2)','PV \rightarrow autoconsumo'}, ...
       'Location','northeast');
title(sprintf('Settimana tipo (%s - %s) estiva', ...
      datestr(tW(1),'dd/mm'), datestr(tW(end),'dd/mm/yyyy')));
subplot(2,1,2);
area(tW, h2_made(idxW),'FaceColor',[0.20 0.45 0.70],'EdgeColor','none');
grid on; ylabel('H_2 al forno [kg/h]'); xlabel('Data e ora'); xlim([tW(1) tW(end)]);
title('Idrogeno prodotto e utilizzato in tempo reale');
esporta(f, fullfile(P.figDir,'05d_settimana_tipo'), P);

% --- GRAFICO 05e: ripartizione dell'energia del PV (taglia reale) --------
% Coerente con la 05i (slide successiva): il ramo H2 e' scomposto in energia
% UTILE al forno (al PCI) e PERDITA di conversione dell'elettrolizzatore, cosi'
% la torta usa la stessa convenzione "energia utile + perdita" del grafico per
% taglia e le ripartizioni delle due slide combaciano (l'autoconsumo coincide).
E_h2_pci   = sum(h2_made)*P.B_LHV_H2/numel(listaAnni)/3600;    % [GWh/anno] H2 utile al forno (PCI)
E_h2_ele   = sum(h2_made)*P.B_ely_kWhkg/numel(listaAnni)/1e6;  % [GWh/anno] elettricita' all'elettrolizzatore
E_h2_loss  = E_h2_ele - E_h2_pci;                             % [GWh/anno] perdita di conversione (~37%)
E_self_GWh = sum(E_self)/numel(listaAnni)/1e6;                % [GWh/anno] PV -> carico (autoconsumo)
f = figure('Name','H2 - ripartizione PV','Color','w','Position',[120 120 560 480]);
hp = pie([E_h2_pci E_h2_loss E_self_GWh]);
hp(1).FaceColor = [0.20 0.45 0.70];   % H2 utile al forno (PCI)
hp(3).FaceColor = [0.80 0.42 0.40];   % perdita di conversione (stesso rosso della banda 05i)
hp(5).FaceColor = [0.85 0.33 0.10];   % autoconsumo elettrico
legend({sprintf('PV \\rightarrow H_2 utile al forno (PCI): %.2f GWh/a',E_h2_pci), ...
        sprintf('Perdita di conversione elettrolizzatore: %.2f GWh/a',E_h2_loss), ...
        sprintf('PV \\rightarrow autoconsumo elettrico: %.2f GWh/a',E_self_GWh)}, ...
       'Location','southoutside');
title('Ripartizione dell''energia elettrica del PV');
esporta(f, fullfile(P.figDir,'05e_ripartizione_PV'), P);

% --- GRAFICO 05b: confronto delle due destinazioni del PV ------------------
f = figure('Name','H2 - confronto rotte','Color','w','Position',[100 100 940 440]);
cats = categorical({'PV -> elettricita''','PV -> H_2 combustione blended'});
cats = reordercats(cats,{'PV -> elettricita''','PV -> H_2 combustione blended'});
subplot(1,2,1);
bar(cats, [B.VAN_ref B.VAN]/1e6, 0.6); grid on; yline(0,'k');
ylabel('VAN [M EUR]'); title('Valore attuale netto');
subplot(1,2,2);
bar(cats, [B.CO2_ref 0; B.CO2_s2 B.CO2_s1], 'stacked'); grid on;
ylabel('CO_2 evitata [t/anno]'); title('CO_2 evitata');
legend('Scope 2 (elettricita'')','Scope 1 (H_2)','Location','best');
esporta(f, fullfile(P.figDir,'05b_H2_economia'), P);

% --- GRAFICO 05f: scomposizione del LCOH (taglia reale) -------------------
f = figure('Name','H2 - LCOH','Color','w','Position',[120 120 560 500]);
comp = [B.LCOH_cap, B.LCOH_ele, B.LCOH_opx];
hb = bar(1, comp, 0.45, 'stacked');
hb(1).FaceColor = [0.20 0.45 0.70];
hb(2).FaceColor = [0.95 0.70 0.10];
hb(3).FaceColor = [0.47 0.67 0.19];
grid on; ylabel('LCOH [EUR/kg H_2]'); xticks(1); xticklabels({'Taglia reale'});
xlim([0.4 1.6]); ylim([0 1.18*B.LCOH]);
ctr = [comp(1)/2, comp(1)+comp(2)/2, comp(1)+comp(2)+comp(3)/2];
for i = 1:3
    text(1, ctr(i), sprintf('%.2f',comp(i)), 'Color','w', ...
         'HorizontalAlignment','center','VerticalAlignment','middle','FontWeight','bold');
end
text(1, B.LCOH, sprintf('LCOH = %.1f EUR/kg',B.LCOH), ...
     'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold');
legend({sprintf('CAPEX elettrolizzatore (CF %.0f%%)',100*B.CF_ely), ...
        sprintf('Elettricita'' (PV @ %.0f EUR/MWh)',1000*B.LCOE_PV), ...
        'OPEX'}, 'Location','southoutside','Box','off');
title('Scomposizione del costo dell''idrogeno');
esporta(f, fullfile(P.figDir,'05f_LCOH_breakdown'), P);

% ====================== STUDIO PER TAGLIE =================================
% La stessa cascata e' replicata a taglie crescenti di PV+elettrolizzatore.
% Il contesto C raccoglie i profili orari per MWp, cosi' cascata_B puo'
% valutare una taglia qualsiasi.
C = struct();
C.Ppv1   = Ppv_v / P.B_PV_MWp;       % [kW/MWp] profilo PV unitario
C.load   = load_v;                   % [kW] carico orario d'impianto
C.demK   = demH2_v;                  % [kg/h] domanda H2 del forno
C.pely1  = P_ely / P.B_PV_MWp;       % [kW/MWp] elettrolizzatore per MWp di PV
C.nAnni  = numel(listaAnni);
C.th_y   = sum(th_day_GJ)/C.nAnni;   % [GJ/anno] termico del forno
C.CRF    = CRF;
C.haMWp  = 1000/(P.B_area_util*P.B_pv_density)/1e4;  % [ha/MWp] superficie occupata
C.siteHa = P.B_area_m2/1e4;          % [ha] superficie del sito

% Tetto asintotico di sostituzione (PV -> infinito): senza accumulo l'H2 si
% brucia solo nelle ore diurne a forno acceso
giorno = C.Ppv1 > 1e-6;
B.subst_ceiling = 100*(sum(C.demK(giorno))/C.nAnni)*P.B_LHV_H2/C.th_y;   % [%]

% ====================== FASE 2 - VERIFICA STORAGE ELETTRICO (BESS) ========
% Si verifica se un BESS intra-day, che dirotta il PV verso l'elettrolizzatore
% per produrre piu' H2, sia conveniente. ESITO: NON conveniente a nessuna
% taglia. Causa: l'H2 al forno vale ~0,029 EUR/kWh (fuel 5 EUR/GJ + ETS),
% contro 0,20 EUR/kWh dell'autoconsumo elettrico; il PV residuo che il BESS
% potrebbe spostare e' poco e di basso valore, mentre il CAPEX del BESS e'
% elevato (~350 EUR/kWh). Il blocco resta come PROVA del finding.
if ~isfield(P,'B_bess_sweep'), P.B_bess_sweep = true; end
if P.B_bess_sweep
    Pbase = P;
    % valore marginale dell'energia nelle due destinazioni [EUR/kWh]
    val_h2  = (1/P.B_ely_kWhkg)*P.B_LHV_H2*P.prezzo_fuel ...
            + (1/P.B_ely_kWhkg)*P.B_LHV_H2*P.EF_fossile/1000*P.prezzo_ETS;
    fprintf('\n--- FASE 2: VERIFICA BESS ELETTRICO ---\n');
    fprintf('  Valore marginale PV->H2 al forno : %.3f EUR/kWh\n', val_h2);
    fprintf('  Valore marginale PV->autoconsumo : %.3f EUR/kWh\n', P.prezzo_el);
    fprintf('  -> l''autoconsumo vale %.1fx l''H2: il BESS verso l''ely non e'' giustificato\n', P.prezzo_el/val_h2);
    fprintf('  %-6s %5s %8s %8s %8s %10s\n','taglia','Eb','subst%','ore-eq','VAN M','Ecurt GWh');
    PVtest = [P.B_PV_MWp, 62.7, 160.6];  nomiT = {'reale','~2%','~5%'};
    BESS = struct('val_h2',val_h2,'val_self',P.prezzo_el,'rows',[]);
    for j = 1:numel(PVtest)
        for Eb = [0 20 50]
            P.B_bess_Eb = Eb;
            rr = cascata_B(PVtest(j), P, C);
            fprintf('  %-6s %5d %8.3f %8.0f %8.2f %10.2f\n', ...
                    nomiT{j}, Eb, rr.subst, rr.ore_eq, rr.VAN, rr.Ecurt/1e6);
            BESS.rows(end+1,:) = [PVtest(j), Eb, rr.subst, rr.ore_eq, rr.VAN, rr.Ecurt/1e6];
        end
    end
    fprintf('  >> FINDING: a ogni taglia il BESS alza la sostituzione di <0,15 punti\n');
    fprintf('     ma peggiora il VAN di milioni: storage elettrico NON conveniente.\n');
    B.bess = BESS;
    P = Pbase;  P.B_bess_Eb = 0;             % il resto gira senza accumulo
end

% ====================== FASE A - VERIFICA STORAGE H2 ======================
% Si verifica se un serbatoio di IDROGENO, che accumula l'H2 prodotto in eccesso
% nelle ore di sole (oggi venduto) e lo restituisce al forno nelle ore senza sole
% ma con forno acceso, possa superare il tetto di sostituzione del dispatch in
% tempo reale (~9,7%). A differenza del BESS, alle taglie grandi c'e' H2 reale in
% eccesso da dirottare. Si fa lo sweep della capacita' serbatoio a taglie fisse.
if ~isfield(P,'B_h2s_sweep'), P.B_h2s_sweep = true; end
if P.B_h2s_sweep
    Pbase = P;
    Ebs   = [0 5 20 50 100]*1000;            % [kg] capacita' serbatoio (0,5,20,50,100 t)
    PVtest = [P.B_PV_MWp, 62.7, 160.6];  nomiT = {'reale','~2%','~5%'};
    fprintf('\n--- FASE A: VERIFICA STORAGE H2 (tetto senza accumulo %.1f%%) ---\n', B.subst_ceiling);
    fprintf('  %-6s %7s %8s %8s %9s %9s %10s\n','taglia','Eb_t','subst%','ore-eq','VAN M','H2vend t','Ecurt GWh');
    H2S = struct('Eb',Ebs/1000,'PV',PVtest,'rows',[]);
    for j = 1:numel(PVtest)
        for k = 1:numel(Ebs)
            P.B_h2s_Eb = Ebs(k);
            rr = cascata_B(PVtest(j), P, C);
            fprintf('  %-6s %7.0f %8.3f %8.0f %9.2f %9.0f %10.2f\n', ...
                    nomiT{j}, Ebs(k)/1000, rr.subst, rr.ore_eq, rr.VAN, rr.H2s/1000, rr.Ecurt/1e6);
            H2S.rows(end+1,:) = [PVtest(j), Ebs(k)/1000, rr.subst, rr.ore_eq, rr.VAN, rr.H2s/1000, rr.capexH2S];
        end
    end
    % sostituzione max raggiunta e se supera il tetto
    sub5 = H2S.rows(H2S.rows(:,1)==PVtest(3),3);   % sostituzioni al 5% per ogni Eb
    fprintf('  >> Al 5%%: sostituzione da %.2f%% (no accumulo) a %.2f%% (100 t serbatoio)\n', sub5(1), sub5(end));
    if sub5(end) > B.subst_ceiling
        fprintf('     -> lo storage H2 SUPERA il tetto del %.1f%% (a differenza del BESS)\n', B.subst_ceiling);
    else
        fprintf('     -> lo storage H2 NON supera il tetto del %.1f%%\n', B.subst_ceiling);
    end
    B.h2store = H2S;
    P = Pbase;  P.B_h2s_Eb = 0;              % il resto gira senza accumulo

    % --- FIGURA 07a: sostituzione e VAN vs capacita' serbatoio (taglie grandi) ---
    EbF = linspace(0, 100, 26)*1000;         % [kg] sweep fine per la curva
    PVf = [62.7, 160.6];  nomiF = {'2% (62,7 MWp)','5% (160,6 MWp)'};
    colF = [0.20 0.45 0.70; 0.85 0.33 0.10];
    subF = zeros(numel(EbF), numel(PVf));  vanF = subF;
    for jj = 1:numel(PVf)
        for ii = 1:numel(EbF)
            P.B_h2s_Eb = EbF(ii);
            rr = cascata_B(PVf(jj), P, C);
            subF(ii,jj) = rr.subst;  vanF(ii,jj) = rr.VAN;
        end
    end
    P = Pbase;  P.B_h2s_Eb = 0;
    f = figure('Name','Storage H2','Color','w','Position',[80 80 1000 430]);
    subplot(1,2,1); hold on; grid on;
    for jj = 1:numel(PVf)
        plot(EbF/1000, subF(:,jj), '-', 'Color',colF(jj,:),'LineWidth',2.2);
    end
    yline(B.subst_ceiling,'--','Color',[0.4 0.4 0.4],'LineWidth',1.4, ...
          'Label',sprintf('tetto senza accumulo %.1f%%',B.subst_ceiling), ...
          'LabelHorizontalAlignment','left');
    xlabel('Capacita'' serbatoio H_2 [t]'); ylabel('Sostituzione termica [%]');
    title('Sostituzione vs taglia del serbatoio'); legend(nomiF,'Location','southeast');
    subplot(1,2,2); hold on; grid on;
    for jj = 1:numel(PVf)
        plot(EbF/1000, vanF(:,jj), '-', 'Color',colF(jj,:),'LineWidth',2.2);
    end
    yline(0,'-','Color',[0 0 0],'LineWidth',0.8);
    xlabel('Capacita'' serbatoio H_2 [t]'); ylabel('VAN [M EUR]');
    title('VAN vs taglia del serbatoio'); legend(nomiF,'Location','northeast');
    sgtitle('Storage di idrogeno: effetto sulla sostituzione e sul VAN','FontWeight','bold');
    esporta(f, fullfile(P.figDir,'07a_storage_h2'), P);
end

% ====================== FASE C - CLINKER SUBSTITUTION =====================
% Leva sulla CALCINAZIONE (il 59% irriducibile con l'H2). Si abbassa il rapporto
% clinker/cemento r sostituendo clinker con SCM che non vanno cotti: la CO2 di
% processo evitata e' EF_calc*dr*cemento. La confrontiamo con la CO2 evitata
% dall'idrogeno alla taglia reale (B.CO2_s1, ~415 t/a) per misurare quanto la
% sostituzione del clinker batte l'idrogeno sul vero collo di bottiglia.
fprintf('\n--- FASE C: CLINKER SUBSTITUTION (leva sulla calcinazione) ---\n');
fprintf('  r baseline = %.3f | calcinazione baseline = %.1f kt/a (%.0f%% del totale)\n', ...
        P.clinker_factor, CO2.calc/1000, 100*CO2.calc/CO2.tot);
fprintf('  CO2 evitata dall''H2 (taglia reale, riferimento) = %.0f t/a\n', B.CO2_s1);
fprintf('  %-38s %6s %6s %8s %9s %8s %9s  %s\n', ...
        'scenario','dr','r','dCO2 kt','rid.tot%','x vs H2','filler kt','provenienza');
CS = struct('dr',P.B_cs_dr,'scm',{P.B_cs_scm},'cost',P.B_cs_cost, ...
            'reperib',{P.B_cs_reperib},'rows',[],'m_scm',[]);
for k = 1:numel(P.B_cs_dr)
    dr        = P.B_cs_dr(k);
    r_new     = P.clinker_factor - dr;
    dCO2_t    = P.co2_calcinazione * dr * cemento_y;   % [t CO2/anno] calcinazione evitata
    dCO2_kt   = dCO2_t / 1000;                         % [kt/anno]
    rid_pct   = 100 * dCO2_t / CO2.tot;                % [%] riduzione sul totale baseline (CO2.tot in t)
    x_vs_h2   = dCO2_t / max(B.CO2_s1, 1e-9);          % [-] multiplo della CO2 evitata dall'H2
    m_filler  = dr * cemento_y;                        % [t/anno] filler che sostituisce il clinker
    m_filler_kt = m_filler / 1000;                     % [kt/anno]
    fprintf('  %-38s %6.2f %6.3f %8.1f %9.2f %8.0f %9.0f  %s\n', ...
            P.B_cs_scm{k}, dr, r_new, dCO2_kt, rid_pct, x_vs_h2, m_filler_kt, P.B_cs_reperib{k});
    CS.rows(end+1,:) = [dr, r_new, dCO2_kt, rid_pct, x_vs_h2, P.B_cs_cost(k)];
    CS.m_scm(end+1)  = m_filler_kt;                    % [kt/anno] volume di filler per scenario
end
% Sintesi del finding (primo scenario non-baseline)
kref = find(P.B_cs_dr > 0, 1);
fprintf('  >> Gia'' con dr=%.2f (r=%.3f), ~%.0f kt/a di filler calcareo crudo (cava Buzzi, zero cottura),\n', ...
        P.B_cs_dr(kref), P.clinker_factor-P.B_cs_dr(kref), CS.m_scm(kref));
fprintf('     la clinker substitution evita %.1f kt/a di CO2: %.0fx l''idrogeno\n', ...
        CS.rows(kref,3), CS.rows(kref,5));
fprintf('     Limite: norma EN 197-1 e prestazioni (resistenza/presa) -> dr non illimitato.\n');
B.clinker = CS;

% --- FIGURA 08a: clinker substitution vs idrogeno (CO2 evitata) -----------
% Confronto dell'ordine di grandezza: gli scenari di clinker substitution
% (calcinazione) contro l'idrogeno alla taglia reale (combustione, 415 t/a).
idx   = P.B_cs_dr > 0;                       % scenari non-baseline
labCS = {'filler \rightarrow CEM II/A-L','filler \rightarrow CEM II/B-LL','filler \rightarrow B-LL (max)'}; % etichette compatte
dCO2v = CS.rows(idx,3);                       % [kt/a] CO2 evitata per scenario
ridv  = CS.rows(idx,4);                       % [%] riduzione sul totale
co2H2 = B.CO2_s1/1000;                        % [kt/a] idrogeno taglia reale (~0,415)
labels = [{'idrogeno (taglia reale)'}, labCS];
valsK  = [co2H2; dCO2v];                      % [kt/a]
valsR  = [100*B.CO2_s1/CO2.tot; ridv];        % [%] (H2 ~0,06%)
cols   = [0.85 0.33 0.10; repmat([0.20 0.45 0.70], numel(dCO2v),1)];  % H2 arancio, clinker blu

f = figure('Name','Clinker vs H2','Color','w','Position',[80 80 1020 440]);
subplot(1,2,1); hold on; grid on;
hb = bar(valsK, 0.6, 'FaceColor','flat');
hb.CData = cols;
set(gca,'XTick',1:numel(labels),'XTickLabel',labels); xtickangle(15);
ylabel('CO_2 evitata [kt/anno]');
title('CO_2 evitata: filler calcareo vs idrogeno');
text(1:numel(valsK), valsK, compose('%.1f',valsK), ...
     'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold');
ylim([0, max(valsK)*1.15]);

subplot(1,2,2); hold on; grid on;
hb2 = bar(valsR, 0.6, 'FaceColor','flat');
hb2.CData = cols;
set(gca,'XTick',1:numel(labels),'XTickLabel',labels); xtickangle(15);
ylabel('Riduzione sul totale Scope 1+2 [%]');
title('Riduzione delle emissioni totali (baseline 742 kt/a)');
text(1:numel(valsR), valsR, compose('%.2f%%',valsR), ...
     'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold');
ylim([0, max(valsR)*1.15]);
sgtitle('Filler calcareo crudo (cava Buzzi, zero cottura): una leva sulla calcinazione, decine di volte l''idrogeno','FontWeight','bold');
esporta(f, fullfile(P.figDir,'08a_clinker_vs_h2'), P);

% --- FIGURA 08b: scenari di clinker substitution (SOLO filler, no idrogeno) -
% Versione per l'Atto 1 (analisi tecnica): la leva sulla calcinazione presentata
% in modo neutro, senza il confronto con l'idrogeno (che lì sarebbe prematuro).
% Il confronto col fattore "x vs H2" resta nella 08a, riusata in Atto 3.
labCSb = {'CEM II/A-L','CEM II/B-LL','B-LL (max)'};   % classi EN 197-1
dCO2vb = CS.rows(idx,3);                               % [kt/a]
ridvb  = CS.rows(idx,4);                               % [%]
colsb  = [0.20 0.55 0.35; 0.16 0.45 0.30; 0.12 0.36 0.24]; % verdi (leva neutra)

fb = figure('Name','Clinker scenari','Color','w','Position',[80 80 1020 440]);
subplot(1,2,1); hold on; grid on;
hbb = bar(dCO2vb, 0.6, 'FaceColor','flat'); hbb.CData = colsb;
set(gca,'XTick',1:numel(labCSb),'XTickLabel',labCSb);
ylabel('CO_2 di processo evitata [kt/anno]');
title('CO_2 evitata sulla calcinazione');
text(1:numel(dCO2vb), dCO2vb, compose('%.1f',dCO2vb), ...
     'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold');
ylim([0, max(dCO2vb)*1.18]);

subplot(1,2,2); hold on; grid on;
hbb2 = bar(ridvb, 0.6, 'FaceColor','flat'); hbb2.CData = colsb;
set(gca,'XTick',1:numel(labCSb),'XTickLabel',labCSb);
ylabel('Riduzione sul totale Scope 1+2 [%]');
title('Riduzione delle emissioni totali (baseline 742 kt/a)');
text(1:numel(ridvb), ridvb, compose('%.1f%%',ridvb), ...
     'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold');
ylim([0, max(ridvb)*1.18]);
sgtitle('Sostituzione del clinker con filler calcareo crudo: leva tecnica sulla calcinazione (59% del totale)','FontWeight','bold');
esporta(fb, fullfile(P.figDir,'08b_clinker_scenari'), P);

% Sweep di taglia per le figure
PVgrid = linspace(P.B_PV_MWp, P.B_PV_max, 80);
subv = zeros(size(PVgrid)); vanv = subv; lcohv = subv;
for i = 1:numel(PVgrid)
    r = cascata_B(PVgrid(i), P, C);
    subv(i) = r.subst;  vanv(i) = r.VAN;  lcohv(i) = r.LCOH;
end

% Taglie che raggiungono gli obiettivi di sostituzione (bisezione su PV)
nomi = [{'reale'}, arrayfun(@(p) sprintf('%d%%',p), P.B_taglie_pct, 'UniformOutput',false)];
PVs  = [P.B_PV_MWp, zeros(1,numel(P.B_taglie_pct))];
for k = 1:numel(P.B_taglie_pct)
    lo = P.B_PV_MWp;  hi = 5000;
    for it = 1:80
        mid = 0.5*(lo+hi);
        rr  = cascata_B(mid, P, C);
        if rr.subst < P.B_taglie_pct(k), lo = mid; else, hi = mid; end
    end
    PVs(k+1) = 0.5*(lo+hi);
end
for k = 1:numel(PVs)
    r = cascata_B(PVs(k), P, C);
    B.taglie(k) = struct('nome',nomi{k},'PV',r.PV,'subst',r.subst,'ha',r.ha, ...
                         'ratio',r.ratio,'CO2',r.CO2,'CO2s1',r.CO2_s1,'CO2s2',r.CO2_s2, ...
                         'CO2exp',r.CO2_exp,'H2k',r.H2k, ...
                         'VAN',r.VAN,'LCOH',r.LCOH,'LCOE',r.LCOE,'H2s',r.H2s, ...
                         'Ecurt',r.Ecurt,'LCOH_cap',r.LCOH_cap,'LCOH_ele',r.LCOH_ele,'LCOH_opx',r.LCOH_opx, ...
                         'CF_ely',r.CF_ely,'ore_eq',r.ore_eq,'fracUtil',r.fracUtil,'ely',r.ely,'CAPEX',r.CAPEX);
end
nT = numel(B.taglie);

% Prezzo di vendita dell'H2 a cui il VAN si annulla (pareggio), per taglia.
% Il VAN e' lineare nel prezzo: VAN(p) = VAN_base + (p - LCOH)*H2s*AF, dove il
% caso base vende l'H2 in eccesso al proprio LCOH. Quindi
%   p_be = LCOH - VAN_base/(H2s*AF).
% NB: se VAN_base>0 il pareggio cade SOTTO il LCOH (il resto del progetto,
% soprattutto l'autoconsumo elettrico, copre la vendita dell'H2 sotto costo);
% se VAN_base<0 cade SOPRA. Se la taglia non vende H2 (H2s=0) il VAN e' piatto
% e il pareggio non esiste (NaN).
AFq = (1 - (1+P.r)^(-P.N))/P.r;          % [-] fattore di annualita'
for k = 1:nT
    t = B.taglie(k);
    if t.H2s > 0
        B.taglie(k).p_be = t.LCOH - t.VAN*1e6/(t.H2s*AFq);   % [EUR/kg]
    else
        B.taglie(k).p_be = NaN;
    end
end

fprintf('\n--- STUDIO PER TAGLIE (tetto sostituzione ~%.1f%% senza accumulo) ---\n', B.subst_ceiling);
for k = 1:nT
    t = B.taglie(k);
    fprintf('  %-6s PV %6.1f MWp | %4.0f ha (%4.1fx sito) | subst %.2f%% | ore-eq %4.0f h/a | PV util %3.0f%% | CO2 %6.0f t/a | VAN %6.1f M | LCOH %.2f | LCOE %3.0f EUR/MWh | pareggio %5.2f EUR/kg\n', ...
            t.nome, t.PV, t.ha, t.ratio, t.subst, t.ore_eq, t.fracUtil, t.CO2, t.VAN, t.LCOH, 1000*t.LCOE, t.p_be);
end

% --- GRAFICO 05g: sostituzione, VAN e LCOH al variare della taglia --------
f = figure('Name','Studio per taglie','Color','w','Position',[60 60 1100 460]);
subplot(1,2,1);
plot(PVgrid, subv, 'Color',[0.20 0.45 0.70],'LineWidth',2.2); hold on;
yline(B.subst_ceiling,'--','Color',[0.85 0.33 0.10],'LineWidth',1.6, ...
      'Label',sprintf('Limite combustione ~%.0f%%',B.subst_ceiling), ...
      'LabelHorizontalAlignment','left','LabelVerticalAlignment','bottom');
for k = 1:nT
    t = B.taglie(k);
    plot(t.PV, t.subst, 'o','MarkerFaceColor',[0.20 0.45 0.70],'MarkerEdgeColor','k');
    if k == 1, lab = sprintf('  reale %.1f MWp', t.PV);
    else,      lab = sprintf('  %s %.0f MWp', t.nome, t.PV); end
    text(t.PV, t.subst, lab, 'FontSize',8, 'VerticalAlignment','middle');
end
grid on; xlim([0 P.B_PV_max]); ylim([0 B.subst_ceiling*1.18]);
xlabel('Taglia fotovoltaico [MWp]'); ylabel('Sostituzione termica al forno [%]');
title('Sostituzione termica');
subplot(1,2,2);
yyaxis left;
hV = plot(PVgrid, vanv, '-', 'Color',[0.85 0.33 0.10],'LineWidth',2.2); hold on;
yline(0,'-','Color',[0 0 0],'LineWidth',0.8);
for k = 1:nT
    t = B.taglie(k);
    plot(t.PV, t.VAN, 'o','MarkerFaceColor',[0.85 0.33 0.10],'MarkerEdgeColor','k');
    if k == 1, lab = sprintf('  reale %.1f MWp', t.PV);
    else,      lab = sprintf('  %s %.0f MWp', t.nome, t.PV); end
    text(t.PV, t.VAN, lab, 'FontSize',8, 'VerticalAlignment','middle');
end
ylabel('VAN [M EUR]');
yyaxis right;
hL = plot(PVgrid, lcohv, '--', 'Color',[0.20 0.45 0.70],'LineWidth',2.2);
ylabel('LCOH [EUR/kg H_2]'); ylim([0 max(4, 1.15*max(lcohv))]);
grid on; xlim([0 P.B_PV_max]); xlabel('Taglia fotovoltaico [MWp]');
title(' ');
ax = gca; ax.YAxis(1).Color = [0.85 0.33 0.10]; ax.YAxis(2).Color = [0.20 0.45 0.70];
legend([hV hL], {'VAN [M EUR]','LCOH [EUR/kg]'}, 'Location','southwest');
esporta(f, fullfile(P.figDir,'05g_studio_taglie'), P);

% --- GRAFICO 05h: sensibilita' del VAN al prezzo di vendita dell'H2 -------
% Caso base (pallino): H2 venduto al proprio LCOH. Il VAN e' lineare nel
% prezzo con pendenza pari all'H2 venduto annualizzato.
AF    = (1 - (1+P.r)^(-P.N))/P.r;     % [-] fattore di annualita'
pgrid = linspace(0, 12, 121);         % [EUR/kg] prezzo di vendita H2
allv  = zeros(nT, numel(pgrid));      % [M EUR] VAN per taglia in funzione del prezzo
for k = 1:nT
    t = B.taglie(k);
    allv(k,:) = t.VAN + (pgrid - t.LCOH)*t.H2s*AF/1e6;
end
ylo = min(0, 1.10*min(allv(:)));  yhi = 1.10*max(allv(:));   % assi adattivi
f = figure('Name','Sensibilita prezzo H2','Color','w','Position',[80 80 780 480]);
patch([5 8 8 5],[ylo ylo yhi yhi],[0.90 0.90 0.90],'EdgeColor','none'); hold on;
colT = lines(nT);
hh = cell(1,nT);  leg = cell(1,nT);
for k = 1:nT
    t = B.taglie(k);
    hh{k} = plot(pgrid, allv(k,:), '-', 'Color',colT(k,:),'LineWidth',2.2);
    plot(t.LCOH, t.VAN, 'o','MarkerFaceColor',colT(k,:),'MarkerEdgeColor','k','MarkerSize',7);
    leg{k} = sprintf('%s (%.0f MWp)', t.nome, t.PV);
end
yline(0,'-','Color',[0 0 0],'LineWidth',0.8);
grid on; xlim([0 12]); ylim([ylo yhi]);
xlabel('Prezzo di vendita H_2 [EUR/kg]'); ylabel('VAN [M EUR]');
title('Sensibilita'' del VAN al prezzo di vendita dell''H_2 per taglia');
legend([hh{:}], leg, 'Location','northwest');
esporta(f, fullfile(P.figDir,'05h_sensibilita_H2'), P);

% --- GRAFICO 05i: destinazione dell'energia del PV al crescere della taglia
% Energia utile consegnata (H2 al PCI + autoconsumo) e perdita di conversione
% dell'elettrolizzatore (53 kWh/kg in ingresso contro 33.3 kWh/kg al PCI).
UK = zeros(size(PVgrid)); ES = UK; UV = UK; LOSS = UK; EXP = UK;   % [GWh/anno]
for i = 1:numel(PVgrid)
    r       = cascata_B(PVgrid(i), P, C);
    UK(i)   = r.H2k*P.B_LHV_H2/3600;                       % H2 utile al forno (PCI)
    UV(i)   = r.H2s*P.B_LHV_H2/3600;                       % H2 utile in vendita (PCI)
    ES(i)   = r.Esf/1e6;                                   % autoconsumo elettrico
    LOSS(i) = (r.H2k+r.H2s)*P.B_ely_kWhkg/1e6 - UK(i) - UV(i);  % perdita elettrolizzatore
    EXP(i)  = r.Ecurt/1e6;                                 % energia in eccesso immessa in rete
end
f = figure('Name','Destinazione energia per taglia','Color','w','Position',[80 80 820 470]);
hA = area(PVgrid, [UK; ES; UV; LOSS; EXP]');
hA(1).FaceColor=[0.42 0.55 0.75]; hA(2).FaceColor=[0.84 0.71 0.34];
hA(3).FaceColor=[0.59 0.45 0.65]; hA(4).FaceColor=[0.80 0.42 0.40];
hA(5).FaceColor=[0.55 0.70 0.55];
for k = 1:5, hA(k).EdgeColor='none'; hA(k).FaceAlpha=0.92; end
hold on;
for k = 1:nT
    rk  = cascata_B(B.taglie(k).PV, P, C);
    tot = (rk.H2k*P.B_ely_kWhkg + rk.Esf + rk.H2s*P.B_ely_kWhkg + rk.Ecurt)/1e6;
    plot(B.taglie(k).PV, tot, 'o','MarkerFaceColor','w','MarkerEdgeColor','k', ...
         'MarkerSize',7,'LineWidth',1.2);
    text(B.taglie(k).PV, tot, ['  ' B.taglie(k).nome], 'FontSize',8.5, ...
         'VerticalAlignment','bottom','FontWeight','bold');
end
grid on; xlim([P.B_PV_MWp P.B_PV_max]);
xlabel('Taglia fotovoltaico [MWp]'); ylabel('Energia [GWh/a]');
title('Destinazione dell''energia del PV: energia utile, perdita e immissione in rete');
legend({'H_2 utile al forno (PCI)','autoconsumo elettrico','H_2 utile in vendita (PCI)', ...
        'perdita elettrolizzatore','immesso in rete (venduto)'},'Location','northwest');
esporta(f, fullfile(P.figDir,'05i_allocazione_taglie'), P);

% --- GRAFICO 05j: scomposizione del LCOH per taglia ------------------------
M    = zeros(nT,3);
xlab = cell(1,nT);
for k = 1:nT
    t = B.taglie(k);
    M(k,:)  = [t.LCOH_cap, t.LCOH_ele, t.LCOH_opx];
    xlab{k} = sprintf('PV %.1f MWp\\newlineely %.1f MW\\newlineLCOE %.0f EUR/MWh', t.PV, t.ely, 1000*t.LCOE);
end
ymax = 1.20*max(sum(M,2));
f = figure('Name','LCOH per taglia','Color','w','Position',[120 120 760 520]);
hb = bar(1:nT, M, 0.55, 'stacked');
hb(1).FaceColor = [0.20 0.45 0.70];
hb(2).FaceColor = [0.95 0.70 0.10];
hb(3).FaceColor = [0.47 0.67 0.19];
grid on; ylabel('LCOH [EUR/kg H_2]');
xticks(1:nT); xticklabels(xlab); set(gca,'TickLabelInterpreter','tex');
xlim([0.4 nT+0.6]); ylim([0 ymax]);
for k = 1:nT
    comp = M(k,:);  tot = sum(comp);
    ctr  = [comp(1)/2, comp(1)+comp(2)/2, comp(1)+comp(2)+comp(3)/2];
    for i = 1:3
        if comp(i) > 0.04*ymax
            text(k, ctr(i), sprintf('%.2f',comp(i)), 'Color','w', ...
                 'HorizontalAlignment','center','VerticalAlignment','middle', ...
                 'FontWeight','bold','FontSize',9);
        end
    end
    text(k, tot, sprintf('%.2f',tot), 'HorizontalAlignment','center', ...
         'VerticalAlignment','bottom','FontWeight','bold');
end
legend({'CAPEX elettrolizzatore','Elettricita'' (PV al suo LCOE)','OPEX'}, ...
       'Location','northoutside','Orientation','horizontal','Box','off');
title('Scomposizione del LCOH per taglia');
esporta(f, fullfile(P.figDir,'05j_LCOH_taglie'), P);

% --- GRAFICO 05k: settimana tipo alle varie taglie -------------------------
% Stessa settimana della 05d, replicata per ogni taglia: si vede la cascata
% riempirsi (forno, poi carico, poi vendita, infine curtailment).
colK = [0.20 0.45 0.70];   % H2 al forno
colS = [0.85 0.33 0.10];   % carico d'impianto
colV = [0.59 0.45 0.65];   % H2 venduto
colC = [0.65 0.65 0.65];   % curtailment
f = figure('Name','Settimana tipo per taglia','Color','w','Position',[60 60 1100 700]);
for k = 1:nT
    t = B.taglie(k);
    r = cascata_B(t.PV, P, C);
    subplot(2,2,k);
    ar = area(tW, [r.e_k(idxW) r.e_s(idxW) r.e_sale(idxW) r.e_curt(idxW)]/1000, ...
              'EdgeColor','none');
    ar(1).FaceColor = colK;  ar(2).FaceColor = colS;
    ar(3).FaceColor = colV;  ar(4).FaceColor = colC;
    grid on; ylabel('Potenza PV [MW]'); xlim([tW(1) tW(end)]);
    title(sprintf('Taglia %s (PV %.1f MWp)', t.nome, t.PV));
    if k == 1
        legend({'H_2 al forno','carico d''impianto','H_2 venduto','immesso in rete'}, ...
               'Location','northwest');
    end
end
sgtitle('Settimana tipo: destinazione oraria del PV alle varie taglie','FontWeight','bold');
esporta(f, fullfile(P.figDir,'05k_settimana_taglie'), P);

% --- GRAFICO 05l: bilancio annuo dell'energia del PV per taglia ------------
% Versione per taglie della 05e: dove finisce l'energia elettrica del PV
% in un anno, curtailment incluso.
Mdest = zeros(nT,4);   % [GWh/anno] H2 forno | carico | H2 vendita | curtailment
xlbl  = cell(1,nT);
for k = 1:nT
    t = B.taglie(k);
    r = cascata_B(t.PV, P, C);
    Mdest(k,:) = [r.H2k*P.B_ely_kWhkg, r.Esf, r.H2s*P.B_ely_kWhkg, r.Ecurt]/1e6;
    xlbl{k} = sprintf('%s\\newline%.1f MWp', t.nome, t.PV);
end
f = figure('Name','Bilancio PV per taglia','Color','w','Position',[100 100 780 500]);
hb = bar(1:nT, Mdest, 0.55, 'stacked');
hb(1).FaceColor = colK;  hb(2).FaceColor = colS;
hb(3).FaceColor = colV;  hb(4).FaceColor = colC;
grid on; ylabel('Energia elettrica del PV [GWh/anno]');
xticks(1:nT); xticklabels(xlbl); set(gca,'TickLabelInterpreter','tex');
for k = 1:nT
    text(k, sum(Mdest(k,:)), sprintf('%.0f',sum(Mdest(k,:))), ...
         'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold');
end
legend({'elettrolizzatore (H_2 al forno)','carico d''impianto', ...
        'elettrolizzatore (H_2 venduto)','immesso in rete (venduto)'},'Location','northwest');
title('Destinazione annua dell''energia del PV per taglia');
esporta(f, fullfile(P.figDir,'05l_bilancio_PV_taglie'), P);

% --- GRAFICO 05m: CAPEX/OPEX per componente e costo specifico vs taglia ----
% Trasparenza sulle ipotesi di costo: ripartizione del CAPEX della taglia reale
% e andamento del costo specifico con la taglia (economia di scala, m<1).
costPV_r  = capex_scala(P.B_PV_MWp, P.B_capexPV);   % [EUR]
costInv_r = capex_scala(P_inv/1000, P.B_capexInv);  % [EUR]
costEly_r = capex_scala(P_ely/1000, P.B_capexEly);  % [EUR]
capex_comp = [costPV_r costInv_r costEly_r P.B_capex_retr]/1e6;   % [M EUR]
nomi_comp  = {'PV','Inverter','Elettrolizzatore','Retrofit forno'};
colComp    = [0.95 0.70 0.10; 0.30 0.55 0.85; 0.20 0.45 0.70; 0.85 0.33 0.10];
f = figure('Name','CAPEX e costi per componente','Color','w','Position',[80 80 1100 460]);

% Pannello 1: ripartizione del CAPEX della taglia reale
subplot(1,2,1);
etich = arrayfun(@(j) sprintf('%s %.2f M (%.0f%%)', nomi_comp{j}, capex_comp(j), ...
                 100*capex_comp(j)/sum(capex_comp)), 1:4, 'UniformOutput',false);
pie(capex_comp, etich);
colormap(gca, colComp);
title(sprintf('CAPEX taglia reale %.1f M EUR'));

% Pannello 2: costo specifico vs taglia (economia di scala)
cPVs = zeros(size(PVgrid)); cELYs = cPVs;
for i = 1:numel(PVgrid)
    cPVs(i)  = capex_scala(PVgrid(i), P.B_capexPV)/(PVgrid(i)*1000);  % [EUR/kW]
    pe       = C.pely1*PVgrid(i);                                     % [kW] elettrolizz.
    cELYs(i) = capex_scala(pe/1000, P.B_capexEly)/pe;                 % [EUR/kW]
end
subplot(1,2,2);
plot(PVgrid, cPVs, '-', 'Color',[0.95 0.70 0.10],'LineWidth',2.2); hold on;
plot(PVgrid, cELYs,'-', 'Color',[0.20 0.45 0.70],'LineWidth',2.2);
for k = 1:nT
    t = B.taglie(k);
    plot(t.PV,  capex_scala(t.PV, P.B_capexPV)/(t.PV*1000), ...
         'o','MarkerFaceColor',[0.95 0.70 0.10],'MarkerEdgeColor','k');
    plot(t.PV,  capex_scala(t.ely,P.B_capexEly)/(t.ely*1000), ...
         'o','MarkerFaceColor',[0.20 0.45 0.70],'MarkerEdgeColor','k');
end
grid on; xlim([0 P.B_PV_max]); ylim([0 inf]);
xlabel('Taglia fotovoltaico [MWp]'); ylabel('Costo specifico [EUR/kW]');
legend({'Impianto PV','Elettrolizzatore'},'Location','northeast');
title('Costo specifico');
esporta(f, fullfile(P.figDir,'05m_capex_opex'), P);

% --- GRAFICO 05n: verifica economica del SOLO PV (autoconsumo + vendita) ---
% Caso "solo PV": niente elettrolizzatore ne' retrofit del bruciatore. La
% produzione si divide in due flussi: l'autoconsumo che copre il carico
% d'impianto (E_self_y, ~3,12 GWh, evita il prelievo a 0,20 EUR/kWh) e
% l'eccedenza, che senza elettrolizzatore viene interamente venduta in rete
% al prezzo di ritiro (P.prezzo_export). CAPEX del solo PV+inverter.
E_exp_y    = max(Eref_y - E_self_y, 0);          % [kWh/anno] eccedenza venduta in rete
capex_self = costPV_r + costInv_r;               % [EUR] PV + inverter
opex_self  = capex_self * P.B_opex;              % [EUR/anno] 3% del CAPEX
sav_en     = E_self_y * P.prezzo_el;             % [EUR/anno] elettricita' evitata (autoconsumo, 0,20 EUR/kWh)
sav_exp    = E_exp_y  * P.prezzo_export;         % [EUR/anno] eccedenza venduta in rete (0,10 EUR/kWh)
sav_ets    = B.CO2_s2 * P.prezzo_ETS;            % [EUR/anno] quote ETS evitate (Scope 2, solo autoconsumo)
net_self   = sav_en + sav_exp + sav_ets - opex_self;  % [EUR/anno] flusso netto annuo
van_self   = calcola_VAN([-capex_self, repmat(net_self,1,P.N)], P.r);  % [EUR]
pb_self    = capex_self / net_self;              % [anni] payback semplice
% Costo di abbattimento (CAPEX annualizzato + OPEX) / tCO2 Scope 2 evitata
abat_self  = (capex_self*CRF + opex_self) / B.CO2_s2;   % [EUR/tCO2]

% Cash-flow cumulato attualizzato anno per anno (anno 0 = -CAPEX)
anni_cf = 0:P.N;
cf_cum  = zeros(1,P.N+1);
cf_cum(1) = -capex_self;
for k = 1:P.N
    cf_cum(k+1) = cf_cum(k) + net_self/(1+P.r)^k;
end

f = figure('Name','Verifica economica solo PV','Color','w','Position',[80 80 1100 460]);

% Pannello 1: scomposizione del flusso netto annuo
subplot(1,2,1);
voci = [sav_en, sav_exp, sav_ets, -opex_self]/1e6;        % [M EUR/anno]
hb = bar(voci, 'FaceColor','flat');
hb.CData = [0.95 0.70 0.10; 0.45 0.75 0.45; 0.30 0.55 0.85; 0.85 0.33 0.10];
grid on; ylabel('Flusso annuo [M EUR/anno]');
xticks(1:4); xticklabels({'Autoconsumo','Vendita ecc.','Beneficio ETS','OPEX'});
set(gca,'TickLabelInterpreter','tex');
for k = 1:4
    if voci(k) >= 0, va = 'bottom'; else, va = 'top'; end
    text(k, voci(k), sprintf('%+.2f', voci(k)), 'HorizontalAlignment','center', ...
         'VerticalAlignment', va, 'FontWeight','bold');
end
yline(0,'k-');
title(sprintf('Flusso netto %.2f M EUR/anno', net_self/1e6));

% Pannello 2: cash-flow cumulato attualizzato e payback
subplot(1,2,2);
plot(anni_cf, cf_cum/1e6, '-o', 'Color',[0.20 0.45 0.70], 'LineWidth',2.2, ...
     'MarkerFaceColor',[0.20 0.45 0.70], 'MarkerEdgeColor','k', 'MarkerSize',4); hold on;
yline(0,'k--');
xline(pb_self,'r--','LineWidth',1.5);
text(pb_self, 0, sprintf('  payback %.1f a', pb_self), 'Color','r', ...
     'VerticalAlignment','bottom','FontWeight','bold');
grid on; xlim([0 P.N]);
xlabel('Anno'); ylabel('Cash-flow cumulato attualizzato [M EUR]');
title(sprintf('VAN @ %.0f%%, %d a = %+.1f M EUR', 100*P.r, P.N, van_self/1e6));
esporta(f, fullfile(P.figDir,'05n_pv_autoconsumo'), P);

fprintf('\n--- VERIFICA ECONOMICA: solo PV (autoconsumo + vendita eccedenza) ---\n');
fprintf('  CAPEX PV+inverter      : %.2f M EUR\n', capex_self/1e6);
fprintf('  Autoconsumo            : %.2f GWh/anno x %.2f EUR/kWh = %.3f M EUR/anno\n', ...
        E_self_y/1e6, P.prezzo_el, sav_en/1e6);
fprintf('  Vendita eccedenza      : %.2f GWh/anno x %.2f EUR/kWh = %.3f M EUR/anno\n', ...
        E_exp_y/1e6, P.prezzo_export, sav_exp/1e6);
fprintf('  Beneficio ETS (Scope2) : %s tCO2 x %.0f EUR/t = %.3f M EUR/anno\n', ...
        comma(round(B.CO2_s2)), P.prezzo_ETS, sav_ets/1e6);
fprintf('  OPEX (3%%)              : %.3f M EUR/anno\n', opex_self/1e6);
fprintf('  Flusso netto           : %.3f M EUR/anno\n', net_self/1e6);
fprintf('  Payback semplice       : %.1f anni\n', pb_self);
fprintf('  VAN @ %.0f%%, %d anni    : %+.2f M EUR\n', 100*P.r, P.N, van_self/1e6);
fprintf('  Costo abbattimento     : %.0f EUR/tCO2 (Scope 2; il PV vale sul kWh, non sulla CO2)\n', abat_self);

%% ===================== SEZIONE 6 - SINTESI: PESO SUL TOTALE =============
% Peso della CO2 evitata sulle emissioni complessive d'impianto: anche le
% taglie irrealizzabili restano una frazione e la calcinazione resta intatta.

% --- GRAFICO 06c: peso dei risparmi sulle emissioni d'impianto -------------
f = figure('Name','Peso sul totale impianto','Color','w','Position',[80 80 1000 520]);
yImp    = nT + 1;                    % la barra d'impianto sta in cima
colComb = [0.47 0.67 0.19];
colElec = [0.30 0.55 0.85];
colCalc = [0.85 0.33 0.10];
x_agg   = CO2.comb + CO2.elec;       % confine zona aggredibile | calcinazione

% Barra d'impianto: combustione+elettrico (aggredibili) a sinistra,
% calcinazione a destra, cosi' i risparmi non la raggiungono mai
hI = barh(yImp, [CO2.comb CO2.elec CO2.calc], 0.55, 'stacked'); hold on;
hI(1).FaceColor = colComb; hI(2).FaceColor = colElec; hI(3).FaceColor = colCalc;
for k = 1:3, hI(k).EdgeColor = 'w'; hI(k).LineWidth = 1; end
text(CO2.comb/2, yImp, sprintf('Combustione\n%.0f%%',100*CO2.comb/CO2.tot), ...
     'Color','w','FontWeight','bold','HorizontalAlignment','center');
text(CO2.comb+CO2.elec/2, yImp+0.42, sprintf('Elettrico %.0f%%',100*CO2.elec/CO2.tot), ...
     'Color',colElec,'FontWeight','bold','HorizontalAlignment','center');
text(x_agg+CO2.calc/2, yImp, sprintf('Calcinazione %.0f%%',100*CO2.calc/CO2.tot), ...
     'Color','w','FontWeight','bold','HorizontalAlignment','center');
text(CO2.tot*1.01, yImp, sprintf('%s t CO_2/a',comma(round(CO2.tot))), ...
     'HorizontalAlignment','left','FontWeight','bold');

% Barre dei risparmi per taglia, in scala reale
lbl = cell(1,nT);
for k = 1:nT
    t = B.taglie(k);
    y = nT + 1 - k;
    lbl{k} = sprintf('%.1f MWp', t.PV);
    hb = barh(y, [t.CO2s1 t.CO2s2], 0.55, 'stacked');
    hb(1).FaceColor = colComb; hb(2).FaceColor = colElec;
    for j = 1:2, hb(j).EdgeColor = 'w'; hb(j).LineWidth = 0.4; end
    text(t.CO2 + CO2.tot*0.012, y, ...
         sprintf('%s: %.2f%%  (%s t CO_2/a)', t.nome, 100*t.CO2/CO2.tot, comma(round(t.CO2))), ...
         'HorizontalAlignment','left','VerticalAlignment','middle','FontSize',9);
end

set(gca,'YTick', 1:yImp, 'YTickLabel', [fliplr(lbl), {'IMPIANTO'}]);
ylim([0.4 yImp+0.7]); xlim([0 CO2.tot*1.18]);
xlabel('CO_2 [t/anno]'); grid on; box off;
title('Peso dei risparmi di CO_2 sulle emissioni d''impianto');
legend(hI(1:3), {'Combustione (Scope 1, H_2)','Elettrico (Scope 2, autoconsumo)', ...
       'Calcinazione'}, 'Location','southeast');
esporta(f, fullfile(P.figDir,'06c_peso_impianto'), P);

% --- GRAFICO 06d: l'H2 venduto come risparmio di sistema -------------------
% La CO2 evitata dall'H2 venduto e' del compratore, non della cementeria.
f = figure('Name','H2 venduto - beneficio di sistema','Color','w','Position',[60 60 1120 480]);
xc   = 1:nT;
xlbl = cell(1,nT);
H2k_t = zeros(1,nT); H2s_t = H2k_t; CEM = H2k_t; EXP = H2k_t;
for k = 1:nT
    t = B.taglie(k);
    xlbl{k}  = sprintf('%.1f MWp (%s)', t.PV, t.nome);
    H2k_t(k) = t.H2k/1000;     % [t/anno] H2 al forno
    H2s_t(k) = t.H2s/1000;     % [t/anno] H2 venduto
    CEM(k)   = t.CO2;          % [t/anno] CO2 evitata dalla cementeria
    EXP(k)   = t.CO2exp;       % [t/anno] CO2 evitata a valle dal compratore
end
colCem = [0.20 0.45 0.70];
colExp = [0.47 0.67 0.19];

subplot(1,2,1);
ha = bar(xc, [H2k_t(:) H2s_t(:)], 0.6, 'stacked'); hold on;
ha(1).FaceColor = colExp; ha(1).EdgeColor = 'w';
ha(2).FaceColor = colExp; ha(2).FaceAlpha = 0.30; ha(2).EdgeColor = colExp;
for k = 1:nT
    if H2s_t(k) > 0
        text(k, H2k_t(k)+H2s_t(k), sprintf('%.0f%% venduto',100*H2s_t(k)/(H2k_t(k)+H2s_t(k))), ...
             'HorizontalAlignment','center','VerticalAlignment','bottom','FontSize',8);
    end
end
set(gca,'XTick',xc,'XTickLabel',xlbl); xtickangle(20);
ylabel('H_2 prodotto [t/anno]'); grid on; box off;
title('Destinazione dell''H_2 per taglia');
legend({'al forno (autoconsumo)','venduto a terzi'},'Location','northwest');

subplot(1,2,2);
hb = bar(xc, [CEM(:) EXP(:)], 0.6, 'stacked'); hold on;
hb(1).FaceColor = colCem; hb(1).EdgeColor = 'w';
hb(2).FaceColor = colExp; hb(2).FaceAlpha = 0.30; hb(2).EdgeColor = colExp;
for k = 1:nT
    text(k, CEM(k)+EXP(k), sprintf('%.2f%%\ndi sistema',100*(CEM(k)+EXP(k))/CO2.tot), ...
         'HorizontalAlignment','center','VerticalAlignment','bottom','FontSize',8);
end
set(gca,'XTick',xc,'XTickLabel',xlbl); xtickangle(20);
ylim([0 max(CEM+EXP)*1.22]);
ylabel('CO_2 evitata [t/anno]'); grid on; box off;
title('CO_2 evitata: d''impianto e di sistema');
legend({'dalla cementeria (Scope 1+2)','a valle, dal compratore (H_2 venduto)'}, ...
       'Location','northwest');
sgtitle('H_2 venduto: un risparmio di CO_2 di sistema, non della cementeria','FontWeight','bold');
esporta(f, fullfile(P.figDir,'06d_h2_sistema'), P);

%% ===================== SEZIONE 7 - EXPORT WORKSPACE E KPI ===============
% Salva il workspace completo e un riepilogo dei KPI (csv + txt), cosi' i
% numeri delle slide sono verificabili senza rieseguire lo script.

outDir = pwd;
clear f ar hb hp hI hA ha hh hV hL;   % handle grafici: non servono nel .mat

KPI = {
  '=== PARAMETRI E IPOTESI (Sez.0) ===', '',                              ''
  'Tasso di sconto',                 sprintf('%.0f', 100*P.r),              '%'
  'Orizzonte di valutazione',        sprintf('%d',   P.N),                  'anni'
  'Prezzo elettricita (autoconsumo)',sprintf('%.2f', P.prezzo_el),          'EUR/kWh'
  'Prezzo combustibile sostituito',  sprintf('%.1f', P.prezzo_fuel),        'EUR/GJ'
  'Prezzo quota EU-ETS',             sprintf('%.0f', P.prezzo_ETS),         'EUR/t'
  'Prezzo export in rete',           sprintf('%.2f', P.prezzo_export),      'EUR/kWh'
  'Prezzo H2 mercato (rif.)',        sprintf('%.1f', P.B_prezzo_H2),        'EUR/kg'
  'OPEX (frazione del CAPEX)',       sprintf('%.0f', 100*P.B_opex),         '%/anno'
  'CAPEX C0 PV / inverter / ely',    sprintf('%.0f / %.0f / %.0f', P.B_capexPV(1)/1e3, P.B_capexInv(1)/1e3, P.B_capexEly(1)/1e3), 'EUR/kW a 1 MW'
  'Esponenti di scala m (PV/inv/ely)', sprintf('%.2f / %.2f / %.2f', P.B_capexPV(3), P.B_capexInv(3), P.B_capexEly(3)), '-'
  'Retrofit bruciatore (fisso)',     sprintf('%.1f', P.B_capex_retr/1e6),   'M EUR'
  'Consumo specifico elettrolizz.',  sprintf('%.0f', P.B_ely_kWhkg),        'kWh/kg H2'
  'Rapporto DC/AC inverter',         sprintf('%.2f', P.B_DCAC),             '-'
  '=== BASELINE (Sez.2) ===',        '',                                    ''
  'Periodo dati',                    sprintf('%d-%d',min(anni),max(anni)),  '-'
  'Clinker medio annuo',             sprintf('%.0f', clinker_y),            't/anno'
  'Cemento medio annuo',             sprintf('%.0f', cemento_y),            't/anno'
  'Fabbisogno elettrico',            sprintf('%.1f', E_el_tot_y),           'GWh/anno'
  'Fabbisogno termico',              sprintf('%.1f', E_th_tot_y),           'GWh_th/anno'
  'Termico specifico (cottura)',     sprintf('%.0f', e_th_fase(3)),         'kWh_th/t cem'
  'CO2 specifica (calcolata)',       sprintf('%.0f', co2_tot_tcem),         'kg/t cem'
  'CO2 totale impianto',             sprintf('%.0f', CO2.tot),              't/anno'
  'CO2 calcinazione',                sprintf('%.0f', CO2.calc),             't/anno'
  'CO2 combustione',                 sprintf('%.0f', CO2.comb),             't/anno'
  'CO2 elettrico',                   sprintf('%.0f', CO2.elec),             't/anno'
  'Quota calcinazione',              sprintf('%.1f', 100*co2_calc_tcem/co2_tot_tcem), '%'
  'Quota combustione',               sprintf('%.1f', 100*co2_comb_tcem/co2_tot_tcem), '%'
  'Quota elettrico',                 sprintf('%.1f', 100*co2_elec_tcem/co2_tot_tcem), '%'
  'Quota aggredibile (comb+elec)',   sprintf('%.1f', 100*(co2_comb_tcem+co2_elec_tcem)/co2_tot_tcem), '%'
  '=== DINAMICA (Sez.3) ===',        '',                                    ''
  'Capacity factor (giorni)',        sprintf('%.1f', 100*CF_giorni),        '%'
  'Capacity factor (ore)',           sprintf('%.1f', 100*CF_ore),           '%'
  'Ore di marcia totali',            sprintf('%.0f', ore_tot),              'h'
  'N. campagne',                     sprintf('%d',   cicli.n_campagne),         '-'
  'Durata media campagna',           sprintf('%.1f', mean(cicli.dur_campagne)), 'giorni'
  'Durata max campagna',             sprintf('%d',   max(cicli.dur_campagne)),  'giorni'
  'Durata media fermata',            sprintf('%.1f', mean(cicli.dur_fermate)),  'giorni'
  '=== CONFIGURAZIONE H2 (Sez.4-5) ===', '',                                ''
  'Taglia PV',                       sprintf('%.2f', P.B_PV_MWp),           'MWp'
  'Inverter (AC)',                   sprintf('%.2f', B.inv_MW),             'MW_AC'
  'Elettrolizzatore',                sprintf('%.2f', B.ely_MW),             'MW'
  'Producibilita PV',                sprintf('%.0f', B.yield),              'kWh/kWp/anno'
  'Energia PV netta',                sprintf('%.1f', Eref_y/1e6),           'GWh/anno'
  'H2 in combustione blended',       sprintf('%.0f', B.H2_y),               'kg/anno'
  'Sostituzione termica',            sprintf('%.2f', 100*B.subst),          '%'
  'Elettricita autoconsumata',       sprintf('%.2f', B.Eself_y/1e6),        'GWh/anno'
  'PV -> elettrolizzatore',          sprintf('%.2f', E_h2_ele),             'GWh/anno'
  'PV -> H2 utile al forno (PCI)',   sprintf('%.2f', E_h2_pci),             'GWh/anno'
  'Perdita conversione ely',         sprintf('%.2f', E_h2_loss),            'GWh/anno'
  'PV -> autoconsumo',               sprintf('%.2f', E_self_GWh),           'GWh/anno'
  'CO2 evitata (B)',                 sprintf('%.0f', B.CO2),                't/anno'
  'CO2 Scope 1 (B)',                 sprintf('%.0f', B.CO2_s1),             't/anno'
  'CO2 Scope 2 (B)',                 sprintf('%.0f', B.CO2_s2),             't/anno'
  'H2 venduto (taglia reale)',       sprintf('%.0f', B.H2_sale),            'kg/anno'
  'CO2 esportata con H2 venduto',    sprintf('%.0f', B.CO2_exp),            't/anno'
  'Prezzo H2 mercato (rif.)',        sprintf('%.1f', P.B_prezzo_H2),        'EUR/kg'
  'Prezzo export in rete',           sprintf('%.2f', P.prezzo_export),      'EUR/kWh'
  'Export in rete (reale)',          sprintf('%.2f', B.Ecurt_y/1e6),        'GWh/anno'
  'CAPEX (B) totale',                sprintf('%.2f', B.CAPEX/1e6),          'M EUR'
  'CAPEX - campo PV',                sprintf('%.2f', B.capexPV/1e6),        'M EUR'
  'CAPEX - inverter',                sprintf('%.2f', B.capexInv/1e6),       'M EUR'
  'CAPEX - elettrolizzatore',        sprintf('%.2f', B.capexEly/1e6),       'M EUR'
  'CAPEX - retrofit bruciatore',     sprintf('%.2f', B.capexRetr/1e6),      'M EUR'
  'OPEX annuo (B)',                  sprintf('%.2f', B.OPEX/1e6),           'M EUR/anno'
  'Ore equivalenti elettrolizzatore',sprintf('%.0f', B.ore_eq),             'h/anno'
  'Quota PV utile alla cementeria',  sprintf('%.0f', B.fracUtil),           '%'
  'VAN (B)',                         sprintf('%.2f', B.VAN/1e6),            'M EUR'
  'LCOH',                            sprintf('%.2f', B.LCOH),               'EUR/kg'
  'LCOH - CAPEX elettrolizzatore',   sprintf('%.2f', B.LCOH_cap),           'EUR/kg'
  'LCOH - elettricita',              sprintf('%.2f', B.LCOH_ele),           'EUR/kg'
  'LCOH - OPEX',                     sprintf('%.2f', B.LCOH_opx),           'EUR/kg'
  'LCOE PV',                         sprintf('%.0f', 1000*B.LCOE_PV),       'EUR/MWh'
  'CF elettrolizzatore',             sprintf('%.0f', 100*B.CF_ely),         '%'
  'Rif. PV->elettr.: VAN',           sprintf('%.2f', B.VAN_ref/1e6),        'M EUR'
  'Rif. PV->elettr.: CO2',           sprintf('%.0f', B.CO2_ref),            't/anno'
  'Rif. PV->elettr.: CAPEX',         sprintf('%.2f', CAPEX_ref/1e6),        'M EUR'
};

KPI(end+1,:) = {'=== STUDIO PER TAGLIE (Sez.5) ===','',''};
KPI(end+1,:) = {'Tetto sostituzione (no accumulo)', sprintf('%.1f', B.subst_ceiling), '%'};
for k = 1:nT
    t = B.taglie(k);
    KPI(end+1,:) = {sprintf('Taglia %s: PV / superficie', t.nome), ...
                    sprintf('%.1f MWp | %.0f ha (%.1fx sito)', t.PV, t.ha, t.ratio), '-'};
    KPI(end+1,:) = {sprintf('Taglia %s: subst / CO2 / VAN / LCOH / LCOE', t.nome), ...
                    sprintf('%.2f%% | %.0f t/a | %.1f M | %.2f | %.0f EUR/MWh', t.subst, t.CO2, t.VAN, t.LCOH, 1000*t.LCOE), '-'};
    KPI(end+1,:) = {sprintf('Taglia %s: elettrolizz. / CF / CAPEX / OPEX', t.nome), ...
                    sprintf('%.1f MW | %.0f%% | %.1f M | %.2f M/a', t.ely, 100*t.CF_ely, t.CAPEX, t.CAPEX*P.B_opex), '-'};
    KPI(end+1,:) = {sprintf('Taglia %s: ore equiv. elettrolizz. / PV utile cementeria', t.nome), ...
                    sprintf('%.0f h/a | %.0f%%', t.ore_eq, t.fracUtil), '-'};
    KPI(end+1,:) = {sprintf('Taglia %s: H2 forno / H2 venduto / export rete', t.nome), ...
                    sprintf('%.0f t/a | %.0f t/a | %.2f GWh/a', t.H2k/1000, t.H2s/1000, t.Ecurt/1e6), '-'};
    KPI(end+1,:) = {sprintf('Taglia %s: LCOH (CAPEX_ely / elettr. / OPEX)', t.nome), ...
                    sprintf('%.2f + %.2f + %.2f = %.2f EUR/kg', t.LCOH_cap, t.LCOH_ele, t.LCOH_opx, t.LCOH), '-'};
    if isfinite(t.p_be)
        if t.p_be < t.LCOH, rel = 'sotto il'; else, rel = 'sopra il'; end
        be_str = sprintf('%.2f EUR/kg (%s LCOH %.2f)', t.p_be, rel, t.LCOH);
    else
        be_str = 'non vende H2 (VAN insensibile al prezzo)';
    end
    KPI(end+1,:) = {sprintf('Taglia %s: prezzo H2 di pareggio (VAN=0)', t.nome), be_str, '-'};
end

Risultati = cell2table(KPI, 'VariableNames', {'Grandezza','Valore','Unita'});
writetable(Risultati, fullfile(outDir,'risultati_KPI.csv'));

fid = fopen(fullfile(outDir,'risultati_KPI.txt'),'w');
fprintf(fid, 'RIEPILOGO KPI - modello decarbonizzazione Barletta\n');
fprintf(fid, 'Generato: %s\n', datestr(now));
for i = 1:size(KPI,1)
    if isempty(KPI{i,2})
        fprintf(fid, '\n%s\n', KPI{i,1});
    else
        fprintf(fid, '  %-34s %14s  %s\n', KPI{i,1}, KPI{i,2}, KPI{i,3});
    end
end
fclose(fid);

save(fullfile(outDir,'workspace_decarbonizzazione.mat'));

fprintf('\nWorkspace salvato in %s\n', fullfile(outDir,'workspace_decarbonizzazione.mat'));
fprintf('Riepilogo KPI salvato in %s (e .txt)\n', fullfile(outDir,'risultati_KPI.csv'));
fprintf('\nElaborazione completata. Figure in ./%s\n', P.figDir);

%% ===================== FUNZIONI LOCALI ==================================

function VAN = calcola_VAN(cf, r)
% Valore Attuale Netto di una serie di flussi di cassa (cf(1) = anno 0)
    t   = 0:(numel(cf)-1);
    VAN = sum(cf ./ (1+r).^t);
end

function c = capex_scala(P_MW, par)
% CAPEX totale con economia di scala: c = C0*(P/P0)^m  [EUR], P in MW.
% par = [C0 (EUR a P0), P0 (MW), m (esponente di scala, <1)].
    c = par(1) .* (max(P_MW,0)./par(2)).^par(3);
end

function R = cascata_B(PV_MWp, P, C)
% Cascata oraria per una taglia PV generica. Priorita': 1) H2 al forno,
% 2) carico d'impianto, 3) H2 venduto, 4) curtailment. I profili orari per
% MWp sono nel contesto C. Restituisce i KPI annui e le serie orarie.
    P_inv = PV_MWp*1000/P.B_DCAC;            % [kW_AC] inverter
    Ppv   = C.Ppv1 * PV_MWp;                 % [kW] potenza AC oraria
    P_ely = C.pely1 * PV_MWp;                % [kW] elettrolizzatore
    % --- cascata oraria (PRIMA del BESS) -------------------------------------
    % Priorita': 1) PV -> elettrolizzatore -> H2 al forno
    pv_k  = min(Ppv, P_ely);
    h2_k  = min(pv_k/P.B_ely_kWhkg, C.demK); % [kg/h] H2 al forno
    e_k   = h2_k*P.B_ely_kWhkg;              % [kWh] elettricita' per H2 al forno
    pv_r  = Ppv - e_k;                       % [kW] PV residuo dopo H2 al forno
    ely_r = max(P_ely - e_k, 0);             % [kW] capacita' elettrolizzatore residua
    e_s   = min(pv_r, C.load);               % [kWh] PV -> carico d'impianto
    pv_r2 = pv_r - e_s;                      % [kW] PV oltre il carico

    % --- BESS intra-day (FASE 2) --------------------------------------------
    % Il PV oltre il carico (pv_r2), invece di andare subito a vendita/export,
    % puo' caricare la batteria; quando il forno e' acceso ma il PV non satura
    % l'elettrolizzatore (ely_r>0), la batteria scarica e produce H2 aggiuntivo.
    % Con Eb=0 questo blocco e' inattivo e si ricade nel caso senza accumulo.
    Eb = P.B_bess_Eb*1000;                   % [kWh] capacita' batteria
    if Eb > 0
        if P.B_bess_Pb > 0, Pb = P.B_bess_Pb*1000; else, Pb = Eb/4; end  % [kW] C-rate 0,25 di default
        eta1 = sqrt(P.B_bess_eta);           % rendimento per mezzo ciclo (carica e scarica)
        n    = numel(pv_r2);
        soc  = 0;                            % [kWh] stato di carica iniziale
        h2_bess = zeros(n,1);                % [kg/h] H2 extra da batteria
        for t = 1:n
            % SCARICA: forno acceso (demK>0) ed elettrolizzatore non saturo
            need_kW = ely_r(t) - 0;          % [kW] capacita' ely libera dopo il PV diretto
            dem_left = C.demK(t) - h2_k(t);  % [kg/h] domanda H2 ancora aperta
            if dem_left > 1e-9 && need_kW > 1e-9 && soc > 1e-9
                p_dis = min([Pb, soc*eta1, need_kW, dem_left*P.B_ely_kWhkg]);  % [kW] erogati all'ely
                if p_dis > 0
                    h2_bess(t) = p_dis / P.B_ely_kWhkg;     % [kg/h] H2 extra
                    soc = soc - p_dis/eta1;                 % prelievo dalla batteria
                end
            end
            % CARICA: PV oltre il carico disponibile e batteria non piena
            if pv_r2(t) > 1e-9 && soc < Eb
                p_chg = min([Pb, pv_r2(t), (Eb - soc)/eta1]); % [kW] assorbiti dal PV
                if p_chg > 0
                    soc = soc + p_chg*eta1;                 % accumulo
                    pv_r2(t) = pv_r2(t) - p_chg;            % PV residuo ridotto
                end
            end
        end
        h2_k  = h2_k + h2_bess;              % H2 al forno aumentato dal BESS
        e_k   = h2_k*P.B_ely_kWhkg;          % elettricita' per H2 al forno (aggiornata)
        ely_r = max(P_ely - e_k, 0);         % capacita' ely residua (aggiornata)
    end

    % 3) PV oltre il carico (e oltre la carica BESS) -> H2 venduto a terzi
    h2_s  = min(pv_r2/P.B_ely_kWhkg, ely_r/P.B_ely_kWhkg);  % [kg/h] H2 venduto
    e_c   = pv_r2 - h2_s*P.B_ely_kWhkg;      % [kWh] curtailment/export

    % --- STORAGE H2 (FASE A) ------------------------------------------------
    % Serbatoio di idrogeno: invece di vendere subito l'H2 in eccesso (h2_s),
    % lo accumula nelle ore di sole e lo restituisce al forno nelle ore senza
    % sole ma con forno acceso, alzando l'H2 al forno oltre il tetto del
    % dispatch in tempo reale. Con Eb=0 il blocco e' inattivo (non-regressione).
    EbH2 = P.B_h2s_Eb;                       % [kg] capacita' serbatoio H2
    if EbH2 > 0
        etaH = sqrt(P.B_h2s_eta);            % rendimento per mezzo ciclo (carica/scarica)
        n2   = numel(h2_s);
        soc_h2 = 0;                          % [kg] H2 in serbatoio
        h2_from_store = zeros(n2,1);         % [kg/h] H2 prelevato dal serbatoio verso il forno
        for t = 1:n2
            % SCARICA: forno acceso, domanda H2 non saturata dal PV, ely libero
            dem_left = C.demK(t) - h2_k(t);  % [kg/h] domanda H2 ancora aperta
            ely_free = ely_r(t)/P.B_ely_kWhkg;  % [kg/h] H2 ancora producibile/erogabile dall'ely
            if dem_left > 1e-9 && soc_h2 > 1e-9
                q_dis = min([soc_h2*etaH, dem_left, ely_free]);  % [kg/h] H2 al forno dal serbatoio
                if q_dis > 0
                    h2_from_store(t) = q_dis;
                    soc_h2 = soc_h2 - q_dis/etaH;   % prelievo (con perdita di efficienza)
                end
            end
            % CARICA: H2 oggi destinato alla vendita, serbatoio non pieno
            if h2_s(t) > 1e-9 && soc_h2 < EbH2
                q_chg = min([h2_s(t), (EbH2 - soc_h2)/etaH]);  % [kg/h] H2 sottratto alla vendita
                if q_chg > 0
                    soc_h2 = soc_h2 + q_chg*etaH;   % accumulo (con perdita di efficienza)
                    h2_s(t) = h2_s(t) - q_chg;      % meno H2 venduto
                end
            end
        end
        h2_k  = h2_k + h2_from_store;        % H2 al forno aumentato dal serbatoio
        e_k   = h2_k*P.B_ely_kWhkg;          % elettricita' per H2 al forno (aggiornata)
        ely_r = max(P_ely - e_k, 0);         % capacita' ely residua (aggiornata)
        % e_c (curtailment) invariato: lo storage muove H2, non tocca il PV residuo
    end

    % KPI annui
    H2k = sum(h2_k)/C.nAnni;   % [kg/anno]
    H2s = sum(h2_s)/C.nAnni;   % [kg/anno]
    Esf = sum(e_s)/C.nAnni;    % [kWh/anno]
    Epv = sum(Ppv)/C.nAnni;    % [kWh/anno]
    R.PV     = PV_MWp;
    R.subst  = 100*H2k*P.B_LHV_H2/C.th_y;           % [%] sostituzione termica
    R.CO2_s1 = H2k*P.B_LHV_H2*P.EF_fossile/1000;    % [t/anno] Scope 1
    R.CO2_s2 = Esf*P.co2_grid/1000;                 % [t/anno] Scope 2
    R.CO2    = R.CO2_s1 + R.CO2_s2;                 % [t/anno] cementeria
    R.CO2_exp = H2s*P.B_LHV_H2*P.EF_fossile/1000;   % [t/anno] a valle (compratore)
    R.ha     = PV_MWp*C.haMWp;                      % [ha] superficie occupata
    R.ratio  = R.ha/C.siteHa;                       % [-] multipli del sito
    R.ely    = P_ely/1000;                          % [MW]
    R.H2k = H2k;  R.H2s = H2s;  R.Esf = Esf;  R.Epv = Epv;
    R.Ecurt  = sum(e_c)/C.nAnni;                    % [kWh/anno] curtailment
    % serie orarie (per le figure per taglia)
    R.e_k = e_k;  R.e_s = e_s;
    R.e_sale = h2_s*P.B_ely_kWhkg;  R.e_curt = e_c;
    % economia: LCOH (metodo EHO) e VAN con vendita dell'H2 al proprio LCOH
    costPV   = capex_scala(PV_MWp,     P.B_capexPV);   % [EUR] moduli PV
    costInv  = capex_scala(P_inv/1000, P.B_capexInv);  % [EUR] inverter (P in MW)
    costEly  = capex_scala(P_ely/1000, P.B_capexEly);  % [EUR] elettrolizzatore (P in MW)
    costBESS = P.B_bess_Eb*1000 * P.B_bess_capex;      % [EUR] batteria (Eb[MWh]*1000*EUR/kWh)
    costH2S  = P.B_h2s_Eb * P.B_h2s_capex;             % [EUR] serbatoi H2 (Eb[kg]*EUR/kg)
    CAPEX    = costPV + costInv + costEly + P.B_capex_retr + costBESS + costH2S;
    R.capexBESS = costBESS/1e6;                        % [M EUR] quota BESS
    R.capexH2S  = costH2S/1e6;                         % [M EUR] quota serbatoi H2
    H2t      = H2k + H2s;
    CAPEX_pv = costPV + costInv;
    CAPEX_el = costEly;
    EtoH2    = H2t*P.B_ely_kWhkg;                          % [kWh/anno]
    LCOE     = (CAPEX_pv*C.CRF + CAPEX_pv*P.B_opex)/max(Epv,1e-9);   % [EUR/kWh]
    R.LCOH_cap = CAPEX_el*C.CRF    / max(H2t,1e-9);        % [EUR/kg]
    R.LCOH_ele = EtoH2*LCOE        / max(H2t,1e-9);        % [EUR/kg]
    R.LCOH_opx = CAPEX_el*P.B_opex / max(H2t,1e-9);        % [EUR/kg]
    R.LCOH   = R.LCOH_cap + R.LCOH_ele + R.LCOH_opx;
    R.LCOE   = LCOE;                                       % [EUR/kWh] LCOE del PV (varia con la taglia)
    R.CF_ely = EtoH2 / max(P_ely*8760, 1e-9);              % [-]
    R.ore_eq   = R.CF_ely*8760;                                % [h/anno] ore equivalenti elettrolizzatore (no accumulo)
    R.fracUtil = 100*(H2k*P.B_ely_kWhkg + Esf)/max(Epv,1e-9);  % [%] quota PV utile alla cementeria (forno + autoconsumo)
    saving = H2k*P.B_LHV_H2*P.prezzo_fuel + Esf*P.prezzo_el ...
           + R.CO2*P.prezzo_ETS + H2s*R.LCOH + R.Ecurt*P.prezzo_export ...
           - CAPEX*P.B_opex;   % [EUR/anno] (incl. export venduto in rete)
    R.CAPEX = CAPEX/1e6;                                   % [M EUR]
    R.VAN   = calcola_VAN([-CAPEX, repmat(saving,1,P.N)], P.r)/1e6;  % [M EUR]
end

function C = identifica_cicli(inprod)
% Campagne (ON) e fermate (OFF) dal vettore logico giornaliero
    x = double(inprod(:))';
    d = diff([0 x 0]);
    startOn = find(d == 1);
    endOn   = find(d == -1) - 1;
    C.dur_campagne = endOn - startOn + 1;       % [giorni]
    C.n_campagne   = numel(C.dur_campagne);
    if numel(startOn) > 1
        startOff = endOn(1:end-1) + 1;
        endOff   = startOn(2:end) - 1;
        C.dur_fermate = endOff - startOff + 1;  % [giorni]
    else
        C.dur_fermate = [];
    end
end

function s = comma(x)
% Intero con separatore delle migliaia (per le stampe)
    s = regexprep(num2str(round(x)), '\d{1,3}(?=(\d{3})+$)', '$0.');
end

function q = pctl(x, p)
% Percentile p-esimo (0-100) con interpolazione lineare (senza toolbox)
    x = sort(x(:));
    if isempty(x), q = NaN; return; end
    n = numel(x);
    if n == 1, q = x; return; end
    pos = (p/100)*(n-1) + 1;
    lo  = floor(pos);  hi = ceil(pos);
    q   = x(lo) + (pos-lo)*(x(hi)-x(lo));
end

function esporta(fig, nome, P)
% Esporta la figura in PNG e PDF (con fallback per versioni vecchie)
    if ~P.salvaFig, return; end
    try
        exportgraphics(fig, [nome '.png'], 'Resolution', 200);
        exportgraphics(fig, [nome '.pdf'], 'ContentType', 'vector');
    catch
        try, saveas(fig, [nome '.png']); catch, end
    end
end

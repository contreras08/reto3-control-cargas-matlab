%% =====================================================================
%  RETO 3 - ALGORITMO DE CONTROL Y CARGAS (CONTROL HORARIO DEL SIGE)
%  Curso: Software para Ingenieria (203036) - UNAD
%  Grupo: 203036_106
%  Estudiante: Alvaro Daniel Contreras Diaz
%  Archivo: Reto3_ControlCargas_AlvaroContreras.m
%
%  Proposito general del script:
%  Simular durante 24 horas el controlador central de la micro-red.
%  En cada hora se compara la generacion hibrida (solar + eolica) con la
%  demanda de la comunidad. Si hay excedente, la energia sobrante carga
%  la bateria; si hay deficit, el faltante se extrae de la bateria y,
%  segun el Estado de Carga (SOC) resultante, se aplica el protocolo de
%  desconexion de cargas por prioridad:
%     - Escuela Rural      -> prioridad critica (nunca se desconecta)
%     - Bombeo de agua     -> prioridad media
%     - Alumbrado Publico  -> prioridad baja
%  Al final de cada hora se imprime un reporte en la consola.
%
%  Unidades: potencias en kW. Cada paso de simulacion dura 1 hora, por lo
%  que un valor de X kW sostenido durante la hora equivale a X kWh de
%  energia, que es la magnitud que usa la actualizacion del SOC.
%% =====================================================================


%% 1. LIMPIEZA DEL ENTORNO DE TRABAJO -----------------------------------
% Se parte de un estado conocido para que los resultados no dependan de
% ejecuciones anteriores.
clear;      % elimina todas las variables del Workspace
clc;        % limpia la Ventana de Comandos


%% 2. DATOS HEREDADOS DEL RETO 2 [kW] ------------------------------------
% Vectores fila de 24 posiciones: la posicion h corresponde a la hora h.
% Son exactamente los vectores del script del Reto 2 y no se modifican.
solar   = [0 0 0 0 0 2 5 9 14 19 23 25 23 19 14 9 5 2 0 0 0 0 0 0];     % generacion solar
eolica  = [6 7 5 8 6 9 7 10 8 11 9 12 10 15 9 7 11 10 8 12 9 7 8 6];   % generacion eolica
demanda = [3 3 2 2 3 6 8 9 8 7 8 9 8 7 8 9 10 12 15 14 13 4 3 2];      % demanda agregada

% La demanda es el perfil agregado de la comunidad (escuela + bombeo +
% alumbrado). No existe un desglose oficial de potencia por carga, por
% eso la desconexion se modela como un estado logico de cada servicio y
% no se recalcula la demanda despues de desconectar.


%% 3. PARAMETROS DEL CONTROLADOR ----------------------------------------
numHoras         = 24;    % duracion de la simulacion [h]
socInicial       = 50;    % estado de carga inicial de la bateria [%]
capacidadBateria = 100;   % capacidad total del banco de baterias [kWh]
socMaximo        = 100;   % limite maximo de seguridad (evita sobrecarga) [%]
socMinimo        = 0;     % limite minimo absoluto (evita vaciamiento) [%]
umbralAlerta     = 40;    % por debajo o igual a este valor se entra en Alerta [%]
umbralEmergencia = 20;    % por debajo o igual a este valor se entra en Emergencia [%]


%% 4. INICIALIZACION DE VECTORES DE RESULTADOS ---------------------------
% Se reservan vectores de 24 posiciones para registrar cada hora.
generacionTotal = zeros(1, numHoras);   % Egen de cada hora [kW]
balance         = zeros(1, numHoras);   % Egen - Edem de cada hora [kW]
socSinLimite    = zeros(1, numHoras);   % SOC calculado antes de saturar [%]
socHistorico    = zeros(1, numHoras);   % SOC final de cada hora (ya limitado) [%]
estadoControl   = cell(1, numHoras);    % escenario o ruta aplicada
estadoEscuela   = cell(1, numHoras);    % ACTIVA / DESCONECTADA
estadoBombeo    = cell(1, numHoras);    % ACTIVO / DESCONECTADO
estadoAlumbrado = cell(1, numHoras);    % ACTIVO / DESCONECTADO

soc = socInicial;   % variable de estado de la bateria que se actualiza cada hora


%% 5. ENCABEZADO DE CONSOLA ---------------------------------------------
fprintf('==============================================================\n');
fprintf('RETO 3 - CONTROL HORARIO DEL SIGE\n');
fprintf('SOC inicial: %d %% | Capacidad bateria: %d kWh\n', socInicial, capacidadBateria);
fprintf('==============================================================\n');


%% 6. CICLO DE CONTROL HORARIO (24 ITERACIONES) --------------------------
for hora = 1:numHoras

    % 6.1 Lectura de los datos de la hora y calculo del balance
    Egen = solar(hora) + eolica(hora);   % generacion hibrida total [kW]
    Edem = demanda(hora);                % demanda de la comunidad [kW]
    balanceHora = Egen - Edem;           % positivo: sobra; negativo: falta [kW]

    if Egen >= Edem
        % 6.2 RAMA SIN DEFICIT (superavit o equilibrio)
        % El excedente (0 si hay equilibrio) se desvia a cargar la bateria.
        excedente = Egen - Edem;                            % [kWh en 1 h]
        soc = soc + (excedente / capacidadBateria) * 100;   % aumento del SOC [%]
        socSinLimite(hora) = soc;                           % valor antes de saturar

        % Saturacion superior: la bateria no puede superar el 100 %
        if soc > socMaximo
            soc = socMaximo;
        end

        % La comunidad se abastece por completo: todos los servicios activos
        if excedente == 0
            estadoControl{hora} = 'SIN DEFICIT (EQUILIBRIO)';
        else
            estadoControl{hora} = 'SIN DEFICIT (SUPERAVIT)';
        end
        estadoEscuela{hora}   = 'ACTIVA';
        estadoBombeo{hora}    = 'ACTIVO';
        estadoAlumbrado{hora} = 'ACTIVO';

    else
        % 6.3 RAMA DE DEFICIT
        % El faltante se extrae del banco de baterias.
        faltante = Edem - Egen;                             % [kWh en 1 h]
        soc = soc - (faltante / capacidadBateria) * 100;    % descenso del SOC [%]
        socSinLimite(hora) = soc;                           % valor antes de saturar

        % Saturacion inferior: el SOC no puede bajar del 0 %
        if soc < socMinimo
            soc = socMinimo;
        end

        % 6.4 Protocolo de desconexion de cargas segun el SOC ya actualizado
        if soc > umbralAlerta
            % Ruta Segura (SOC > 40 %): energia suficiente, todo activo
            estadoControl{hora}   = 'RUTA SEGURA';
            estadoEscuela{hora}   = 'ACTIVA';
            estadoBombeo{hora}    = 'ACTIVO';
            estadoAlumbrado{hora} = 'ACTIVO';
        elseif soc > umbralEmergencia
            % Ruta de Alerta (20 % < SOC <= 40 %): se apaga el alumbrado
            estadoControl{hora}   = 'RUTA DE ALERTA';
            estadoEscuela{hora}   = 'ACTIVA';
            estadoBombeo{hora}    = 'ACTIVO';
            estadoAlumbrado{hora} = 'DESCONECTADO';
        else
            % Ruta de Emergencia (SOC <= 20 %): solo queda la escuela
            estadoControl{hora}   = 'RUTA DE EMERGENCIA';
            estadoEscuela{hora}   = 'ACTIVA';
            estadoBombeo{hora}    = 'DESCONECTADO';
            estadoAlumbrado{hora} = 'DESCONECTADO';
        end
    end

    % 6.5 Registro de resultados de la hora
    generacionTotal(hora) = Egen;
    balance(hora)         = balanceHora;
    socHistorico(hora)    = soc;

    % 6.6 Reporte horario por consola
    fprintf(['Hora %2d | Egen: %5.2f kW | Edem: %5.2f kW | Balance: %6.2f kW | ' ...
             'SOC: %6.2f %% | %-24s | Escuela: %-6s | Bombeo: %-12s | Alumbrado: %s\n'], ...
            hora, Egen, Edem, balanceHora, soc, estadoControl{hora}, ...
            estadoEscuela{hora}, estadoBombeo{hora}, estadoAlumbrado{hora});
end


%% 7. RESUMEN FINAL ------------------------------------------------------
tol = 1e-9;   % tolerancia para comparar numeros reales

[socMin, horaSocMin] = min(socHistorico);           % minimo tras cada actualizacion
socMax = max(socHistorico);                          % maximo alcanzado
primeraHora100 = find(abs(socHistorico - socMaximo) < tol, 1);   % primera hora al 100 %
horasDeficit = find(balance < 0);                    % horas con Egen < Edem

% Conteo de horas en cada ruta del protocolo de desconexion
horasSegura     = sum(strcmp(estadoControl, 'RUTA SEGURA'));
horasAlerta     = sum(strcmp(estadoControl, 'RUTA DE ALERTA'));
horasEmergencia = sum(strcmp(estadoControl, 'RUTA DE EMERGENCIA'));

fprintf('==============================================================\n');
fprintf('RESUMEN DE LA SIMULACION (24 h)\n');
fprintf('SOC inicial            : %.2f %%\n', socInicial);
fprintf('SOC final              : %.2f %%\n', socHistorico(end));
fprintf('SOC minimo horario actualizado : %.2f %% (hora %d)\n', socMin, horaSocMin);
fprintf('SOC maximo             : %.2f %%\n', socMax);
if isempty(primeraHora100)
    fprintf('Primera hora al 100 %%  : no se alcanzo el 100 %%\n');
else
    fprintf('Primera hora al 100 %%  : hora %d\n', primeraHora100);
end
fprintf('Horas con deficit      : '); fprintf('%d ', horasDeficit); fprintf('\n');
if ~isempty(horasDeficit)
    fprintf('SOC minimo en deficit  : %.2f %%\n', min(socHistorico(horasDeficit)));
end
fprintf('Horas de deficit en Ruta Segura     : %d\n', horasSegura);
fprintf('Horas de deficit en Ruta de Alerta  : %d\n', horasAlerta);
fprintf('Horas de deficit en Emergencia      : %d\n', horasEmergencia);
if horasAlerta == 0 && horasEmergencia == 0
    fprintf('Con los datos del Reto 2 no se activaron las rutas de Alerta ni de Emergencia.\n');
end
fprintf('==============================================================\n');


%% 8. VALIDACIONES TECNICAS ----------------------------------------------
% Comprobaciones automaticas de coherencia. Si alguna falla se muestra una
% ADVERTENCIA; los resultados no se corrigen ni se ocultan.
fprintf('VALIDACIONES TECNICAS\n');
nombres = {};   % descripcion de cada validacion
cumple  = [];   % 1 si se cumple, 0 si falla

nombres{end+1} = 'Vectores de 24 posiciones';
cumple(end+1)  = length(solar) == 24 && length(eolica) == 24 && length(demanda) == 24;
nombres{end+1} = 'SOC siempre dentro de [0, 100] %';
cumple(end+1)  = all(socHistorico >= socMinimo & socHistorico <= socMaximo);
nombres{end+1} = 'generacionTotal = solar + eolica';
cumple(end+1)  = isequal(generacionTotal, solar + eolica);
nombres{end+1} = 'balance = generacionTotal - demanda';
cumple(end+1)  = isequal(balance, generacionTotal - demanda);
nombres{end+1} = 'SOC final = 99 %';
cumple(end+1)  = abs(socHistorico(end) - 99) < tol;
nombres{end+1} = 'Hora 9: saturacion (102 % calculado -> 100 %)';
cumple(end+1)  = abs(socSinLimite(9) - 102) < tol && abs(socHistorico(9) - 100) < tol;
nombres{end+1} = 'Hora 18: equilibrio (balance = 0, SOC 100 %)';
cumple(end+1)  = balance(18) == 0 && abs(socHistorico(18) - 100) < tol ...
                 && strcmp(estadoControl{18}, 'SIN DEFICIT (EQUILIBRIO)');
nombres{end+1} = 'Horas 19 a 21 en deficit';
cumple(end+1)  = all(balance(19:21) < 0);
nombres{end+1} = 'SOC horas 19 a 21 = [93 91 87] %';
cumple(end+1)  = all(abs(socHistorico(19:21) - [93 91 87]) < tol);
nombres{end+1} = 'Conteo Ruta de Alerta = 0';
cumple(end+1)  = horasAlerta == 0;
nombres{end+1} = 'Conteo Ruta de Emergencia = 0';
cumple(end+1)  = horasEmergencia == 0;

for k = 1:length(nombres)
    if cumple(k)
        fprintf('  [OK]          %s\n', nombres{k});
    else
        fprintf('  [ADVERTENCIA] %s\n', nombres{k});
    end
end


%% 9. PRUEBA DE FRONTERAS 40 / 20 (FUERA DE LA SIMULACION OFICIAL) -------
% Esta seccion NO forma parte de las 24 horas: solo evalua valores de SOC
% de prueba con las mismas condiciones del protocolo para comprobar que
% los limites se interpretan correctamente (40 % -> Alerta, 20 % -> Emergencia).
fprintf('PRUEBA DE FRONTERAS (valores de SOC de prueba, no son horas simuladas)\n');
socPrueba = [50 40.01 40 20.01 20 0];   % valores de SOC a evaluar [%]
for k = 1:length(socPrueba)
    if socPrueba(k) > umbralAlerta
        ruta = 'RUTA SEGURA';
    elseif socPrueba(k) > umbralEmergencia
        ruta = 'RUTA DE ALERTA';
    else
        ruta = 'RUTA DE EMERGENCIA';
    end
    fprintf('  SOC = %6.2f %% -> %s\n', socPrueba(k), ruta);
end
fprintf('==============================================================\n');


%% =====================================================================
%  FIN DEL SCRIPT
%% =====================================================================

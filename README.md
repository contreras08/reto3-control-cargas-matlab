# Reto 3 - Algoritmo de control y cargas

Implementación en MATLAB del algoritmo de control horario de un Sistema Inteligente de Gestión Energética (SIGE), desarrollado para el Reto 3 del curso Software para Ingeniería de la UNAD.

## Funcionalidad

El modelo simula un ciclo de 24 horas y:

- calcula la generación híbrida solar + eólica;
- compara la generación con la demanda;
- actualiza el estado de carga de la batería (SOC);
- limita el SOC al intervalo 0 % - 100 %;
- aplica un protocolo de desconexión selectiva de cargas;
- prioriza la Escuela Rural;
- genera un reporte horario en la consola de MATLAB.

## Rutas de control

- SOC > 40 %: Ruta Segura.
- 20 % < SOC <= 40 %: Ruta de Alerta.
- SOC <= 20 %: Ruta de Emergencia.

## Archivo principal

`Reto3_ControlCargas_AlvaroContreras.m`

## Autor

Álvaro Daniel Contreras Díaz  
Software para Ingeniería - UNAD  
Grupo 203036_106

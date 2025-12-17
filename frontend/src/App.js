import React, { useState, useEffect } from 'react';
import axios from 'axios';
import mqtt from 'mqtt';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js';
import { Line, Bar } from 'react-chartjs-2';
import './App.css';

// ============================
// REGISTRO DE COMPONENTES CHART.JS
// ============================
// Chart.js requiere registrar explícitamente los módulos que se utilizarán.
// Esto habilita escalas, elementos de línea/barras, títulos, tooltips y leyendas.

ChartJS.register(
  CategoryScale, LinearScale, PointElement, LineElement, BarElement, Title, Tooltip, Legend
);

// ============================
// CONSTANTES DE CONFIGURACIÓN DEL SISTEMA
// ============================

// Broker MQTT accesible vía WebSocket (puerto 8083) para telemetría y comandos
const MQTT_BROKER = 'ws://broker.emqx.io:8083/mqtt';
// Tópico MQTT donde el dispositivo publica telemetría (estado/lecturas en JSON)
const TOPICO_TELEMETRIA = 'fiusac/grupo_12/telemetria';
// Tópico MQTT donde el dashboard publica comandos (control remoto del sistema)
const TOPICO_COMANDOS = 'fiusac/grupo_12/comandos';
// URL base del backend Flask (API REST)
const API_URL = 'http://127.0.0.1:5000/api';

// ============================
// COMPONENTE PRINCIPAL DE LA APP
// ============================

function App() {

  // ============================
  // ESTADO: LOGIN (CONTROL DE ACCESO)
  // ============================
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [user, setUser] = useState('');
  const [pass, setPass] = useState('');
  const [loginError, setLoginError] = useState('');

  // ============================
  // ESTADO: LOGIN (CONTROL DE ACCESO)
  // ============================

  const [estado, setEstado] = useState({
    temperatura: '--', humedad: '--', movimiento: 0, 
    puerta: 'CERRADA', mantenimiento: false, ventilador: 'OFF', modo_ventilador: 'AUTO'
  });

  const [graficaLineas, setGraficaLineas] = useState({ labels: [], datasets: [] });
  const [graficaBarras, setGraficaBarras] = useState({ labels: [], datasets: [] });
  const [tablaEventos, setTablaEventos] = useState([]);
  const [estadisticas, setEstadisticas] = useState({
    max_temp: 0, min_temp: 0, total_alarmas: 0, total_accesos: 0, promedio_puerta: '0s'
  });

  // ============================
  // ESTADO: FILTROS DE LA TABLA (BUSQUEDA CLIENT-SIDE)
  // ============================

  const [filtroTipo, setFiltroTipo] = useState('');
  const [filtroFecha, setFiltroFecha] = useState('');

  // ============================
  // ESTADO: CLIENTE MQTT
  // ============================

  const [mqttClient, setMqttClient] = useState(null);

   // ============================
  // 1) INICIALIZACIÓN DEL SISTEMA (SOLO CON SESIÓN INICIADA)
  // ============================

  useEffect(() => {
    if (!isLoggedIn) return;

    // ----------------------------
    // A) CONEXIÓN MQTT (TIEMPO REAL)
    // ----------------------------

    // Crear conexión MQTT hacia broker WebSocket
    const client = mqtt.connect(MQTT_BROKER);
    client.on('connect', () => {
      console.log('Conectado a MQTT');
      client.subscribe(TOPICO_TELEMETRIA);
    });
    client.on('message', (topic, msg) => {
      if (topic === TOPICO_TELEMETRIA) {
        try { setEstado(JSON.parse(msg.toString())); } catch (e) {}
      }
    });
    setMqttClient(client);

    // ----------------------------
    // B) CARGA INICIAL + REFRESCO POR API
    // ----------------------------

    cargarDatosCompletos();
    const intervalo = setInterval(cargarDatosCompletos, 5000); // Refrescar cada 5s

    return () => {
      client.end();
      clearInterval(intervalo);
    };
  }, [isLoggedIn]);

  // ============================
  // FUNCIÓN: CARGA COMPLETA DE DATOS DESDE EL BACKEND
  // ============================

  const cargarDatosCompletos = async () => {
    try {

      // ----------------------------
      // 1) GRÁFICA DE LÍNEAS (HISTÓRICO)
      // ----------------------------

      const resHist = await axios.get(`${API_URL}/historico_sensores`);
      setGraficaLineas({
        labels: resHist.data.temperaturas.map(d => d.fecha),
        datasets: [
          { label: 'Temperatura (°C)', data: resHist.data.temperaturas.map(d => d.valor), borderColor: 'red', backgroundColor: 'rgba(255,0,0,0.5)' },
          { label: 'Humedad (%)', data: resHist.data.humedades.map(d => d.valor), borderColor: 'blue', backgroundColor: 'rgba(0,0,255,0.5)' }
        ]
      });

      // ----------------------------
      // 2) TABLA Y GRÁFICA DE BARRAS (EVENTOS)
      // ----------------------------

      const resEv = await axios.get(`${API_URL}/eventos`);
      setTablaEventos(resEv.data.tabla);
      
      const barKeys = Object.keys(resEv.data.grafica_barras);
      const barVals = Object.values(resEv.data.grafica_barras);
      setGraficaBarras({
        labels: barKeys,
        datasets: [{ label: 'Cantidad de Eventos', data: barVals, backgroundColor: 'orange' }]
      });

      // ----------------------------
      // 3) ESTADÍSTICAS DEL DÍA (KPIs)
      // ----------------------------

      const resStats = await axios.get(`${API_URL}/estadisticas`);
      setEstadisticas(resStats.data);

    } catch (error) { console.error("Error API", error); }
  };

  // ============================
  // FUNCIÓN: ENVÍO DE COMANDOS MQTT
  // ============================

  const enviarComando = (cmd) => {
    if (mqttClient) mqttClient.publish(TOPICO_COMANDOS, cmd);
  };

  // ============================
  // FUNCIÓN: MANEJO DEL LOGIN (VALIDACIÓN LOCAL)
  // ============================

  const handleLogin = (e) => {
    e.preventDefault();
    if (user === 'fiusac_datacenter' && pass === 'admin123') { // CONTRASEÑA EJEMPLO
      setIsLoggedIn(true);
    } else {
      setLoginError('Credenciales Incorrectas');
    }
  };

  // ============================
  // FILTRADO DE EVENTOS (CLIENT-SIDE)
  // ============================

  const eventosFiltrados = tablaEventos.filter(ev => {
    return ev.tipo.toLowerCase().includes(filtroTipo.toLowerCase()) &&
           ev.fecha.includes(filtroFecha);
  });

  // ============================
  // VISTA 1: LOGIN (SI NO HAY SESIÓN)
  // ============================

  if (!isLoggedIn) {
    return (
      <div className="login-container">
        <form className="login-form" onSubmit={handleLogin}>
          <h2>🔐 Acceso Seguro FIUSAC</h2>
          <input type="text" placeholder="Usuario" value={user} onChange={e => setUser(e.target.value)} />
          <input type="password" placeholder="Contraseña" value={pass} onChange={e => setPass(e.target.value)} />
          <button type="submit">INGRESAR</button>
          {loginError && <p className="error">{loginError}</p>}
        </form>
      </div>
    );
  }

  // ============================
  // VISTA 2: DASHBOARD (SI HAY SESIÓN)
  // ============================
  
  return (
    <div className="App">
      <header>
        <h1>🏭 FIUSAC DataCenter Monitor</h1>
        <button onClick={() => setIsLoggedIn(false)} className="btn-logout">Salir</button>
      </header>

      <div className="dashboard">
        {/* SECCIÓN 1: ESTADO TIEMPO REAL */}
        <div className="section real-time">
          <h2>📡 Estado Actual</h2>
          <div className="cards-row">
            <div className="card-stat">
              <h3>{estado.temperatura}°C</h3>
              <p>Temperatura</p>
            </div>
            <div className="card-stat">
              <h3>{estado.humedad}%</h3>
              <p>Humedad</p>
            </div>
            <div className={`card-stat ${estado.puerta === 'ABIERTA' ? 'danger' : ''}`}>
              <h3>{estado.puerta}</h3>
              <p>Puerta</p>
            </div>
            <div className="card-stat">
              <h3>{estado.mantenimiento ? 'MANTENIMIENTO' : 'NORMAL'}</h3>
              <p>Sistema</p>
            </div>
          </div>
        </div>

        {/* SECCIÓN 3: ESTADÍSTICAS DEL DÍA */}
        <div className="section stats">
          <h2>📊 Estadísticas del Día</h2>
          <div className="cards-row mini">
            <div className="mini-card">🌡️ Máx: {estadisticas.max_temp}°C</div>
            <div className="mini-card">❄️ Mín: {estadisticas.min_temp}°C</div>
            <div className="mini-card">🚨 Alarmas: {estadisticas.total_alarmas}</div>
            <div className="mini-card">🚪 Accesos: {estadisticas.total_accesos}</div>
            <div className="mini-card">⏱️ Avg Puerta: {estadisticas.promedio_puerta}</div>
          </div>
        </div>

        {/* SECCIÓN 2: GRÁFICAS */}
        <div className="section graphs">
          <div className="graph-box">
            <h3>Histórico (3 Días)</h3>
            <Line data={graficaLineas} />
          </div>
          <div className="graph-box">
            <h3>Eventos por Tipo</h3>
            <Bar data={graficaBarras} />
          </div>
        </div>

        {/* SECCIÓN 2.1: TABLA FILTRABLE */}
        <div className="section table-box">
          <h3>📋 Registro de Eventos (Últimos 50)</h3>
          <div className="filters">
            <input placeholder="Filtrar por Tipo..." value={filtroTipo} onChange={e => setFiltroTipo(e.target.value)} />
            <input placeholder="Filtrar por Fecha (2025-12...)" value={filtroFecha} onChange={e => setFiltroFecha(e.target.value)} />
          </div>
          <table>
            <thead>
              <tr><th>Fecha</th><th>Tipo</th><th>Descripción</th><th>Valor</th></tr>
            </thead>
            <tbody>
              {eventosFiltrados.slice(0, 50).map((ev, i) => (
                <tr key={i}>
                  <td>{ev.fecha}</td>
                  <td>{ev.tipo}</td>
                  <td>{ev.descripcion}</td>
                  <td>{ev.valor}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* PANEL DE CONTROL */}
        <div className="control-panel">
          <button className="btn green" onClick={() => enviarComando('ABRIR')}>Abrir Puerta</button>
          <button className="btn red" onClick={() => enviarComando('CERRAR')}>Cerrar Puerta</button>
          <div className="divider"></div>
          <button className="btn blue" onClick={() => enviarComando('FAN_ON')}>Fan ON</button>
          <button className="btn blue" onClick={() => enviarComando('FAN_OFF')}>Fan OFF</button>
          <div className="divider"></div>
          <button className="btn yellow" onClick={() => enviarComando('MANT_ON')}>Mantenimiento ON</button>
          <button className="btn gray" onClick={() => enviarComando('MANT_OFF')}>Mantenimiento OFF</button>
        </div>
      </div>
    </div>
  );
}

export default App;
const nombresMeses = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"];

// Control del menú desplegable de la ruedita
function toggleMenuConfig(event) {
    event.stopPropagation();
    const menu = document.getElementById('menuConfig');
    menu.classList.toggle('show');
}

window.onclick = function(event) {
    if (!event.target.matches('.config-btn') && !event.target.closest('.config-dropdown')) {
        const menu = document.getElementById('menuConfig');
        if (menu.classList.contains('show')) {
            menu.classList.remove('show');
        }
    }
}

function obtenerMaxDias(ano, mes) {
    return new Date(ano, mes, 0).getDate();
}

function toggleGlobalDias() {
    const modo = document.getElementById('modoGlobal').value;
    const grupoGlobal = document.getElementById('grupoGlobalDias');
    if (modo === 'personalizado') {
        grupoGlobal.classList.remove('oculto');
    } else {
        grupoGlobal.classList.add('oculto');
    }
}

function generarVentanasMeses() {
    const ano = parseInt(document.getElementById('anoReporte').value);
    const inicio = parseInt(document.getElementById('mesInicio').value);
    const fin = parseInt(document.getElementById('mesFin').value);
    const contenedor = document.getElementById('contenedorMeses');

    contenedor.innerHTML = '';

    if (inicio > fin) {
        contenedor.innerHTML = `<div class="placeholder-msg" style="color: #f87171;">El mes inicial no puede ser mayor que el mes final.</div>`;
        document.getElementById('resumenGeneralContainer').classList.add('oculto');
        document.getElementById('searchBarContainer').classList.add('oculto');
        return;
    }

    // Mostrar barra de búsqueda y contenedor KPI
    document.getElementById('resumenGeneralContainer').classList.remove('oculto');
    document.getElementById('searchBarContainer').classList.remove('oculto');
    document.getElementById('kpiPeriodoTexto').innerText = `${nombresMeses[inicio]} - ${nombresMeses[fin]} ${ano}`;

    const modoGlobal = document.getElementById('modoGlobal').value;
    const gInicio = parseInt(document.getElementById('globalDiaInicio').value) || 1;
    const gFin = parseInt(document.getElementById('globalDiaFin').value) || 31;

    for (let m = inicio; m <= fin; m++) {
        const maxDiasMes = obtenerMaxDias(ano, m);

        let modoInicial = "completo";
        let dIniVal = 1;
        let dFinVal = Math.min(15, maxDiasMes);

        if (modoGlobal === 'completo') {
            modoInicial = "completo";
        } else if (modoGlobal === 'personalizado') {
            modoInicial = "personalizado";
            dIniVal = Math.min(gInicio, maxDiasMes);
            dFinVal = Math.min(gFin, maxDiasMes);
        }

        const tarjeta = document.createElement('div');
        tarjeta.className = 'month-card';
        tarjeta.id = `tarjeta-mes-${m}`;
        tarjeta.setAttribute('data-nombre-mes', nombresMeses[m].toLowerCase());

        tarjeta.innerHTML = `
            <h3>${nombresMeses[m]} ${ano}</h3>

            <div class="card-controls">
                <label>Filtro para este mes:</label>
                <select id="modo-${m}" onchange="toggleDiasCard(${m}, ${ano})">
                    <option value="completo" ${modoInicial === 'completo' ? 'selected' : ''}>Mes Entero</option>
                    <option value="personalizado" ${modoInicial === 'personalizado' ? 'selected' : ''}>Días específicos</option>
                </select>

                <div id="grupo-dias-${m}" class="dias-inputs ${modoInicial === 'personalizado' ? '' : 'oculto'}">
                    <input type="number" id="dia-inicio-${m}" min="1" max="${maxDiasMes}" value="${dIniVal}" onchange="validarRangoDias(${m}, ${ano})" title="Máximo ${maxDiasMes} días">
                    <input type="number" id="dia-fin-${m}" min="1" max="${maxDiasMes}" value="${dFinVal}" onchange="validarRangoDias(${m}, ${ano})" title="Máximo ${maxDiasMes} días">
                </div>

                <button onclick="actualizarDatosMes(${m}, ${ano})" style="padding: 6px; font-size: 0.8rem; margin-top: 4px; height: auto;">Actualizar Datos</button>
            </div>

            <div id="resultados-${m}"></div>
        `;
        contenedor.appendChild(tarjeta);

        simularCargaDatos(m, ano);
    }
}

function toggleDiasCard(mes, ano) {
    const modo = document.getElementById(`modo-${mes}`).value;
    const grupoDias = document.getElementById(`grupo-dias-${mes}`);
    const maxDiasMes = obtenerMaxDias(ano, mes);

    if (modo === 'personalizado') {
        grupoDias.classList.remove('oculto');
        document.getElementById(`dia-inicio-${mes}`).max = maxDiasMes;
        document.getElementById(`dia-fin-${mes}`).max = maxDiasMes;
    } else {
        grupoDias.classList.add('oculto');
    }
}

function validarRangoDias(mes, ano) {
    const maxDiasMes = obtenerMaxDias(ano, mes);
    const inputInicio = document.getElementById(`dia-inicio-${mes}`);
    const inputFin = document.getElementById(`dia-fin-${mes}`);

    let valInicio = parseInt(inputInicio.value) || 1;
    let valFin = parseInt(inputFin.value) || 1;

    if (valInicio > maxDiasMes) inputInicio.value = maxDiasMes;
    if (valFin > maxDiasMes) inputFin.value = maxDiasMes;
    if (valInicio > valFin) inputFin.value = inputInicio.value;
}

function simularCargaDatos(mes, ano) {
    const contenedorResultados = document.getElementById(`resultados-${mes}`);
    contenedorResultados.innerHTML = `
        <div class="spinner-container">
            <div class="spinner"></div>
            <span>Calculando impuestos...</span>
        </div>
    `;
    setTimeout(() => {
        actualizarDatosMes(mes, ano, true);
    }, 500);
}

function actualizarDatosMes(mes, ano, omitirSpinner = false) {
    const contenedorResultados = document.getElementById(`resultados-${mes}`);
    const modo = document.getElementById(`modo-${mes}`).value;
    const maxDiasMes = obtenerMaxDias(ano, mes);

    if (!omitirSpinner) {
        contenedorResultados.innerHTML = `
            <div class="spinner-container">
                <div class="spinner"></div>
                <span>Procesando...</span>
            </div>
        `;
        setTimeout(() => {
            renderizarResultadosFinales(mes, modo, maxDiasMes, contenedorResultados);
            calcularResumenGlobal();
        }, 400);
    } else {
        renderizarResultadosFinales(mes, modo, maxDiasMes, contenedorResultados);
        calcularResumenGlobal();
    }
}

function renderizarResultadosFinales(mes, modo, maxDiasMes, contenedorResultados) {
    let textoFiltro = "Mes Completo";
    let ventasSimuladas = Math.floor(Math.random() * 40) + 10;

    if (modo === 'personalizado') {
        const dInicio = Math.min(parseInt(document.getElementById(`dia-inicio-${mes}`).value) || 1, maxDiasMes);
        const dFin = Math.min(parseInt(document.getElementById(`dia-fin-${mes}`).value) || maxDiasMes, maxDiasMes);
        textoFiltro = `Días: ${dInicio} al ${dFin}`;
        ventasSimuladas = Math.floor(Math.random() * 20) + 5;
    }

    const subtotalMonto = ventasSimuladas * 150.00;
    const itbisMonto = subtotalMonto * 0.18;
    const totalGeneralMonto = subtotalMonto + itbisMonto;

    const subtotalFmt = subtotalMonto.toLocaleString('es-DO', { style: 'currency', currency: 'DOP' });
    const itbisFmt = itbisMonto.toLocaleString('es-DO', { style: 'currency', currency: 'DOP' });
    const totalGeneralFmt = totalGeneralMonto.toLocaleString('es-DO', { style: 'currency', currency: 'DOP' });

    contenedorResultados.innerHTML = `
        <div style="font-size: 0.75rem; color: var(--accent); margin-bottom: 8px; font-weight: bold;">Filtro activo: ${textoFiltro}</div>
        <div class="stat-row">
            <span class="stat-label">Transacciones:</span>
            <span class="stat-value" data-raw-transacciones="${ventasSimuladas}">${ventasSimuladas}</span>
        </div>
        <div class="stat-row">
            <span class="stat-label">Subtotal:</span>
            <span class="stat-value" data-raw-subtotal="${subtotalMonto}">${subtotalFmt}</span>
        </div>
        <div class="stat-row">
            <span class="stat-label">ITBIS (18%):</span>
            <span class="stat-value" style="color: #facc15;" data-raw-itbis="${itbisMonto}">${itbisFmt}</span>
        </div>
        <div class="stat-row stat-total">
            <span class="stat-label" style="font-weight: bold; color: var(--text-main);">Total General:</span>
            <span class="stat-value" style="color: #4ade80; font-size: 1rem;" data-raw-total="${totalGeneralMonto}">${totalGeneralFmt}</span>
        </div>
    `;
}

// Calcular KPI Resumen General acumulando todas las tarjetas visibles
function calcularResumenGlobal() {
    const inicio = parseInt(document.getElementById('mesInicio').value);
    const fin = parseInt(document.getElementById('mesFin').value);

    let acumuladoTransacciones = 0;
    let acumuladoSubtotal = 0;
    let acumuladoItbis = 0;
    let acumuladoTotal = 0;

    for (let m = inicio; m <= fin; m++) {
        const tarjeta = document.getElementById(`tarjeta-mes-${m}`);
        if (tarjeta) {
            const elTrans = tarjeta.querySelector('[data-raw-transacciones]');
            const elSub = tarjeta.querySelector('[data-raw-subtotal]');
            const elItbis = tarjeta.querySelector('[data-raw-itbis]');
            const elTotal = tarjeta.querySelector('[data-raw-total]');

            if (elTrans && elSub && elItbis && elTotal) {
                acumuladoTransacciones += parseInt(elTrans.getAttribute('data-raw-transacciones')) || 0;
                acumuladoSubtotal += parseFloat(elSub.getAttribute('data-raw-subtotal')) || 0;
                acumuladoItbis += parseFloat(elItbis.getAttribute('data-raw-itbis')) || 0;
                acumuladoTotal += parseFloat(elTotal.getAttribute('data-raw-total')) || 0;
            }
        }
    }

    document.getElementById('kpiTransacciones').innerText = acumuladoTransacciones;
    document.getElementById('kpiSubtotal').innerText = acumuladoSubtotal.toLocaleString('es-DO', { style: 'currency', currency: 'DOP' });
    document.getElementById('kpiItbis').innerText = acumuladoItbis.toLocaleString('es-DO', { style: 'currency', currency: 'DOP' });
    document.getElementById('kpiTotalGeneral').innerText = acumuladoTotal.toLocaleString('es-DO', { style: 'currency', currency: 'DOP' });
}

// Buscador instantáneo de meses
function filtrarMesesEnPantalla() {
    const query = document.getElementById('inputBuscarMes').value.toLowerCase().trim();
    const inicio = parseInt(document.getElementById('mesInicio').value);
    const fin = parseInt(document.getElementById('mesFin').value);

    for (let m = inicio; m <= fin; m++) {
        const tarjeta = document.getElementById(`tarjeta-mes-${m}`);
        if (tarjeta) {
            const nombreMes = tarjeta.getAttribute('data-nombre-mes');
            if (nombreMes.includes(query)) {
                tarjeta.style.display = 'flex';
            } else {
                tarjeta.style.display = 'none';
            }
        }
    }
}

// Funciones del Menú Desplegable
function exportarPDF() {
    document.getElementById('menuConfig').classList.remove('show');
    window.print();
}

function exportarExcel() {
    document.getElementById('menuConfig').classList.remove('show');
    const ano = document.getElementById('anoReporte').value;
    const inicio = parseInt(document.getElementById('mesInicio').value);
    const fin = parseInt(document.getElementById('mesFin').value);
    let datosReporte = [];

    for (let m = inicio; m <= fin; m++) {
        const tarjeta = document.getElementById(`tarjeta-mes-${m}`);
        if (tarjeta) {
            const modo = document.getElementById(`modo-${m}`).value;
            let filtroTexto = "Mes Completo";
            if (modo === 'personalizado') {
                const dIni = document.getElementById(`dia-inicio-${m}`).value;
                const dFin = document.getElementById(`dia-fin-${m}`).value;
                filtroTexto = `Días ${dIni} al ${dFin}`;
            }

            const rows = tarjeta.querySelectorAll('.stat-row');
            if (rows.length >= 4) {
                const transacciones = rows[0].querySelector('.stat-value').innerText;
                const subtotal = rows[1].querySelector('.stat-value').innerText;
                const itbis = rows[2].querySelector('.stat-value').innerText;
                const totalGeneral = rows[3].querySelector('.stat-value').innerText;

                datosReporte.push({
                    "Mes": nombresMeses[m],
                    "Año": ano,
                    "Tipo de Filtro": filtroTexto,
                    "Transacciones": transacciones,
                    "Subtotal": subtotal,
                    "ITBIS (18%)": itbis,
                    "Total General": totalGeneral
                });
            }
        }
    }

    if (datosReporte.length === 0) {
        alert("No hay datos generados para exportar. Asegúrate de generar el reporte primero.");
        return;
    }

    const worksheet = XLSX.utils.json_to_sheet(datosReporte);
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, "Reporte de Ventas");
    XLSX.writeFile(workbook, `Reporte_Ventas_${ano}.xlsx`);
}

function crearCopiaRespaldo() {
    document.getElementById('menuConfig').classList.remove('show');
    const contenidoHtml = document.documentElement.outerHTML;
    const blob = new Blob([contenidoHtml], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `Copia_Respaldo_BalbuTechApp_${new Date().toISOString().slice(0,10)}.html`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

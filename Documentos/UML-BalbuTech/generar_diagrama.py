#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Genera diagrama-clases.drawio — Diagrama de clases UML de BalbuTechApp.

Uso: python generar_diagrama.py
Salida: diagrama-clases.drawio (abrible en app.diagrams.net)

Para agregar, quitar o mover una clase: edite CLASSES / POS y regenere.
"""
import os
from html import escape

# --- Constantes de layout ---------------------------------------------------
W = 210          # ancho de caja de clase
HDR = 30         # alto del compartimento de titulo
LINE = 17        # alto por linea de texto
PAD = 6          # padding vertical de compartimento
PAGE_W, PAGE_H = 1780, 1780

# --- Paquetes: (clave, titulo, x, y, w, h, fill, stroke) --------------------
PACKAGES = [
    ("seguridad", "Seguridad y sesión", 40, 40, 790, 520, "#dae8fc", "#6c8ebf"),
    ("catalogo", "Catálogo", 870, 40, 790, 530, "#d5e8d4", "#82b366"),
    ("inventario", "Inventario", 40, 610, 540, 270, "#ffe6cc", "#d79b00"),
    ("ventas", "Ventas y postventa", 620, 610, 790, 500, "#e1d5e7", "#9673a6"),
    ("caja", "Caja", 1450, 610, 290, 300, "#fff2cc", "#d6b656"),
    ("compras", "Compras", 40, 930, 540, 462, "#f8cecc", "#b85450"),
    ("rrhh", "RRHH", 620, 1160, 540, 564, "#eeeeee", "#999999"),
]

# --- Clases: clave, nombre, estereotipo, paquete, x, y, atributos, operaciones
CLASSES = [
    # Seguridad y sesión
    ("sesion", "Sesion", "\u00abstruct\u00bb", "seguridad", 80, 100,
     ["idUsuario: int", "username: string", "nombreUsuario: string",
      "idRol: int", "nombreRol: string", "estadoCuenta: string", "activa: bool"],
     ["guardarSesion()", "cerrarSesion()", "mostrarSesionActual()"]),
    ("autenticacion", "Autenticacion", "\u00abcontrol\u00bb", "seguridad", 330, 100,
     ["MAX_INTENTOS: int = 3"],
     ["intentarLogin(user, pass): bool", "verificarPassword(pass): bool",
      "registrarIntento(user, estado)"]),
    ("usuario", "Usuario", None, "seguridad", 580, 100,
     ["idUsuario: int", "username: string", "passwordHash: string", "estado: string"],
     ["verificarPassword(pass): bool", "cambiarClave(nuevaClave)",
      "cambiarEstado(nuevoEstado)"]),
    ("rol", "Rol", None, "seguridad", 80, 352,
     ["idRol: int", "nombre: string"],
     ["tienePermiso(accion): bool", "asignarPermiso(permiso)",
      "quitarPermiso(permiso)"]),
    ("permiso", "Permiso", None, "seguridad", 330, 352,
     ["idPermiso: int", "nombre: string"], []),
    # Catálogo
    ("producto", "Producto", None, "catalogo", 910, 100,
     ["idProducto: int", "codigo: string", "nombre: string",
      "precioVenta: double", "precioCompra: double", "estado: string"],
     ["actualizarPrecio(nuevoPrecio)", "cambiarEstado(nuevoEstado)",
      "obtenerStock(): int"]),
    ("categoria", "Categoria", None, "catalogo", 1160, 100,
     ["idCategoria: int", "nombre: string", "estado: string"],
     ["registrar()", "actualizar()", "cambiarEstado()"]),
    ("marca", "Marca", None, "catalogo", 1410, 100,
     ["idMarca: int", "nombre: string", "estado: string"],
     ["registrar()", "actualizar()", "cambiarEstado()"]),
    ("proveedor", "Proveedor", None, "catalogo", 910, 335,
     ["idProveedor: int", "nombre: string", "telefono: string", "email: string",
      "direccion: string", "estado: string"],
     ["registrar()", "actualizar()", "buscar()"]),
    ("cliente", "Cliente", None, "catalogo", 1160, 335,
     ["idCliente: int", "nombre: string", "telefono: string", "email: string",
      "direccion: string", "estado: string"],
     ["registrar()", "actualizar()", "buscar()"]),
    ("metodoPago", "MetodoPago", None, "catalogo", 1410, 335,
     ["idMetodoPago: int", "nombre: string", "estado: string"],
     ["registrar()", "listar()"]),
    # Inventario
    ("stock", "Stock", None, "inventario", 80, 670,
     ["idProducto: int", "stockActual: int", "stockMinimo: int",
      "ubicacion: string"],
     ["ajustarStock(cantidad, tipo)", "consultarStock(): int",
      "reportarStockCritico(): bool"]),
    ("movimientoInventario", "MovimientoInventario", None, "inventario", 330, 670,
     ["idMovimiento: int", "tipo: TipoMovimiento", "cantidad: int",
      "stockAnterior: int", "stockPosterior: int", "fecha: datetime"],
     ["registrar()"]),
    # Ventas y postventa
    ("venta", "Venta", None, "ventas", 660, 670,
     ["idVenta: int", "fecha: datetime", "subtotal: double", "itbis: double",
      "total: double", "estado: EstadoVenta"],
     ["agregarLinea(producto, cantidad)", "cobrar(metodoPago, monto)",
      "cancelar()", "calcularTotal(): double"]),
    ("detalleVenta", "DetalleVenta", None, "ventas", 910, 670,
     ["idDetalleVenta: int", "cantidad: int", "precioUnitario: double",
      "descuento: double", "subtotal: double"], []),
    ("pago", "Pago", None, "ventas", 1160, 670,
     ["idPago: int", "fecha: datetime", "monto: double", "estado: EstadoPago"],
     ["anular()"]),
    ("garantia", "Garantia", None, "ventas", 660, 922,
     ["idGarantia: int", "fechaEmision: date", "fechaVencimiento: date",
      "estado: string"],
     ["registrar()", "verificarVigencia(): bool"]),
    ("reclamo", "Reclamo", None, "ventas", 910, 922,
     ["idReclamo: int", "fecha: datetime", "descripcion: string",
      "estado: EstadoReclamo"],
     ["registrar()", "finalizar()"]),
    ("devolucion", "Devolucion", None, "ventas", 1160, 922,
     ["idDevolucion: int", "fecha: datetime", "motivo: string",
      "estado: string"], ["registrar()"]),
    # Compras
    ("compra", "Compra", None, "compras", 80, 990,
     ["idCompra: int", "fecha: datetime", "subtotal: double", "itbis: double",
      "total: double", "estado: EstadoCompra"],
     ["agregarLinea(producto, cantidad)", "pagar(monto)", "cancelar()"]),
    ("detalleCompra", "DetalleCompra", None, "compras", 330, 990,
     ["idDetalleCompra: int", "cantidad: int", "costoUnitario: double",
      "subtotal: double"], []),
    ("pagoCompra", "PagoCompra", None, "compras", 80, 1225,
     ["idPagoCompra: int", "fecha: datetime", "monto: double",
      "estado: string"], ["anular()"]),
    # Caja
    ("turnoCaja", "TurnoCaja", None, "caja", 1490, 670,
     ["idTurno: int", "fechaApertura: datetime", "fechaCierre: datetime",
      "saldoInicial: double", "saldoFinal: double", "cuadre: double"],
     ["abrir(saldoInicial)", "cerrar(saldoFinal)", "verificarCuadre(): bool"]),
    # RRHH
    ("empleado", "Empleado", None, "rrhh", 660, 1220,
     ["idEmpleado: int", "cedula: string", "nombre: string", "cargo: string",
      "salario: double", "fechaIngreso: date", "estado: string"],
     ["registrar()", "actualizar()", "despedir()", "reactivar()",
      "marcarAsistencia(fecha)"]),
    ("contrato", "Contrato", None, "rrhh", 910, 1220,
     ["idContrato: int", "tipo: TipoContrato", "fechaInicio: date",
      "fechaFin: date", "archivo: string"],
     ["armarContrato(): string", "escribirContrato(html)", "finalizar()"]),
    ("vacacion", "Vacacion", None, "rrhh", 660, 1506,
     ["idVacacion: int", "fechaInicio: date", "fechaFin: date", "dias: int",
      "estado: EstadoSolicitud"],
     ["solicitar()", "aprobar()", "rechazar()"]),
    ("permisoLaboral", "PermisoLaboral", None, "rrhh", 910, 1506,
     ["idPermiso: int", "fecha: date", "motivo: string",
      "estado: EstadoSolicitud"],
     ["solicitar()", "resolver()"]),
]

# --- Relaciones: id, origen, destino, mult.origen, mult.destino, tipo, etiqueta
# tipo: assoc | comp (diamante en origen = todo) | dep (punteada)
EDGES = [
    ("producto", "categoria", "0..*", "1", "assoc", "categor\u00eda"),
    ("producto", "marca", "0..*", "1", "assoc", "marca"),
    ("producto", "proveedor", "0..*", "0..*", "assoc", "PRODUCTO_PROVEEDOR"),
    ("producto", "stock", "1", "1", "comp", "inventario"),
    ("producto", "movimientoInventario", "1", "0..*", "assoc", "movimientos"),
    ("venta", "cliente", "0..*", "1", "assoc", "cliente"),
    ("venta", "empleado", "0..*", "1", "assoc", "vendedor/cajero"),
    ("venta", "detalleVenta", "1", "0..*", "comp", ""),
    ("detalleVenta", "producto", "0..*", "1", "assoc", "producto"),
    ("venta", "pago", "1", "0..*", "comp", ""),
    ("pago", "metodoPago", "0..*", "1", "assoc", "m\u00e9todo de pago"),
    ("venta", "garantia", "1", "0..*", "comp", ""),
    ("garantia", "reclamo", "1", "0..*", "comp", ""),
    ("venta", "devolucion", "1", "0..*", "assoc", ""),
    ("venta", "turnoCaja", "0..*", "1", "assoc", "turno de caja"),
    ("compra", "proveedor", "0..*", "1", "assoc", "proveedor"),
    ("compra", "empleado", "0..*", "1", "assoc", "registr\u00f3 la compra"),
    ("compra", "detalleCompra", "1", "0..*", "comp", ""),
    ("detalleCompra", "producto", "0..*", "1", "assoc", "producto"),
    ("compra", "pagoCompra", "1", "0..*", "comp", ""),
    ("empleado", "usuario", "1", "0..*", "assoc", ""),
    ("usuario", "rol", "0..*", "1", "assoc", "rol asignado"),
    ("rol", "permiso", "0..*", "0..*", "assoc", "ROL_PERMISO"),
    ("empleado", "contrato", "1", "0..*", "comp", ""),
    ("empleado", "vacacion", "1", "0..*", "assoc", ""),
    ("empleado", "permisoLaboral", "1", "0..*", "assoc", ""),
    ("autenticacion", "usuario", "", "", "dep", "\u00abusa\u00bb"),
    ("autenticacion", "sesion", "", "", "dep", "\u00abcrea\u00bb"),
]

EDGE_STYLES = {
    "assoc": "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;jettySize=auto;"
             "orthogonalLoop=1;",
    "comp": "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;jettySize=auto;"
            "orthogonalLoop=1;startArrow=diamondThin;startFill=1;startSize=17;",
    "dep": "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;dashed=1;"
           "endArrow=open;endFill=0;",
}
MULT_STYLE = ("edgeLabel;html=1;align=center;verticalAlign=middle;resizable=0;"
              "points=[];fontSize=11;")

TITLE_STYLE = ("text;html=1;strokeColor=#000000;fillColor=none;align=center;"
               "verticalAlign=middle;fontSize=13;fontStyle=1;whiteSpace=wrap;")
BODY_STYLE = ("text;html=1;strokeColor=#000000;fillColor=none;align=left;"
              "verticalAlign=top;spacingLeft=6;spacingTop=2;spacingRight=4;"
              "fontSize=12;whiteSpace=wrap;")


def esc(value):
    return escape(str(value), quote=True)


def box_height(attrs, ops):
    attr_h = len(attrs) * LINE + PAD if attrs else LINE + PAD
    op_h = len(ops) * LINE + PAD if ops else LINE + PAD
    return HDR + attr_h + op_h, attr_h, op_h


def build():
    cells = []

    # Fondos de paquete (quedan detras de las cajas)
    for key, title, x, y, w, h, fill, stroke in PACKAGES:
        style = ("rounded=1;whiteSpace=wrap;html=1;fillColor=%s;strokeColor=%s;"
                 "verticalAlign=top;align=left;fontStyle=1;fontSize=16;"
                 "spacingLeft=12;spacingTop=8;" % (fill, stroke))
        cells.append(
            '<mxCell id="pkg_%s" value="%s" style="%s" vertex="1" parent="1">'
            '<mxGeometry x="%d" y="%d" width="%d" height="%d" as="geometry"/>'
            '</mxCell>' % (key, esc(title), style, x, y, w, h))

    # Cajas de clase + compartimentos
    for key, name, stereo, pkg, x, y, attrs, ops in CLASSES:
        h, attr_h, op_h = box_height(attrs, ops)
        cells.append(
            '<mxCell id="c_%s" value="" style="rounded=0;whiteSpace=wrap;'
            'html=1;fillColor=#FFFFFF;strokeColor=#000000;" vertex="1" '
            'parent="1"><mxGeometry x="%d" y="%d" width="%d" height="%d" '
            'as="geometry"/></mxCell>' % (key, x, y, W, h))

        title = ("\u00ab%s\u00bb<br>%s" % (stereo, name)) if stereo else name
        cells.append(
            '<mxCell id="c_%s_t" value="%s" style="%s" vertex="1" '
            'parent="c_%s"><mxGeometry x="0" y="0" width="%d" height="%d" '
            'as="geometry"/></mxCell>'
            % (key, esc(title), TITLE_STYLE, key, W, HDR))
        cells.append(
            '<mxCell id="c_%s_a" value="%s" style="%s" vertex="1" '
            'parent="c_%s"><mxGeometry x="0" y="%d" width="%d" height="%d" '
            'as="geometry"/></mxCell>'
            % (key, esc("<br>".join("- " + a for a in attrs)), BODY_STYLE,
               key, HDR, W, attr_h))
        cells.append(
            '<mxCell id="c_%s_o" value="%s" style="%s" vertex="1" '
            'parent="c_%s"><mxGeometry x="0" y="%d" width="%d" height="%d" '
            'as="geometry"/></mxCell>'
            % (key, esc("<br>".join("+ " + o for o in ops)), BODY_STYLE,
               key, HDR + attr_h, W, op_h))

    # Relaciones + multiplicidades
    for i, (src, tgt, m_src, m_tgt, kind, label) in enumerate(EDGES, 1):
        eid = "e%d" % i
        cells.append(
            '<mxCell id="%s" value="%s" style="%s" edge="1" parent="1" '
            'source="c_%s" target="c_%s"><mxGeometry relative="1" '
            'as="geometry"/></mxCell>'
            % (eid, esc(label), EDGE_STYLES[kind], src, tgt))
        if kind != "dep":
            cells.append(
                '<mxCell id="%s_s" value="%s" style="%s" vertex="1" '
                'connectable="0" parent="%s"><mxGeometry x="-0.5" '
                'relative="1" width="34" height="20" as="geometry"/>'
                '</mxCell>' % (eid, esc(m_src), MULT_STYLE, eid))
            cells.append(
                '<mxCell id="%s_t" value="%s" style="%s" vertex="1" '
                'connectable="0" parent="%s"><mxGeometry x="0.5" '
                'relative="1" width="34" height="20" as="geometry"/>'
                '</mxCell>' % (eid, esc(m_tgt), MULT_STYLE, eid))

    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<mxfile host="app.diagrams.net" type="device">\n'
        '  <diagram id="balbutech-clases" name="Diagrama de clases">\n'
        '    <mxGraphModel dx="100" dy="100" grid="1" gridSize="10" '
        'guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" '
        'pageScale="1" pageWidth="%d" pageHeight="%d" math="0" shadow="0">\n'
        '      <root>\n'
        '        <mxCell id="0"/>\n'
        '        <mxCell id="1" parent="0"/>\n'
        '%s\n'
        '      </root>\n'
        '    </mxGraphModel>\n'
        '  </diagram>\n'
        '</mxfile>\n'
        % (PAGE_W, PAGE_H, "\n".join("        " + c for c in cells))
    )
    return xml


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "diagrama-clases.drawio")
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(build())
    print("OK escrito:", out)
    print("clases=%d paquetes=%d relaciones=%d"
          % (len(CLASSES), len(PACKAGES), len(EDGES)))


if __name__ == "__main__":
    main()

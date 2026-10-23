#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Genera los diagramas complementarios de BalbuTechApp.

Salidas (junto a este script):
  - casos-de-uso.drawio     — Diagrama de casos de uso del sistema
  - secuencia-venta.drawio  — Diagrama de secuencia: venta rápida con cobro

Uso: python generar_diagramas_complementarios.py
"""
import os
from html import escape

PAGE_W, PAGE_H = 1740, 1200

UC_STYLE = ("ellipse;whiteSpace=wrap;html=1;fillColor=#FFFFFF;"
            "strokeColor=#000000;fontSize=12;")
ACTOR_STYLE = ("shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;"
               "html=1;outlineConnect=0;")
BOUNDARY_STYLE = ("rounded=1;whiteSpace=wrap;html=1;fillColor=#F5F5F5;"
                  "strokeColor=#666666;verticalAlign=top;fontStyle=1;"
                  "fontSize=18;spacingTop=8;")
ASSOC_STYLE = "endArrow=none;html=1;rounded=0;"
IO_STYLE = ("endArrow=open;endFill=0;dashed=1;html=1;rounded=0;"
            "fontSize=11;labelBackgroundColor=#FFFFFF;")


def esc(value):
    return escape(str(value), quote=True)


# ===========================================================================
# DIAGRAMA 1 — CASOS DE USO
# ===========================================================================

# clave, etiqueta (con <br> manual), x, y, alto
UC_USECASES = [
    ("sesion", "Iniciar sesión", 790, 100, 66),
    ("cerrar", "Cerrar sesión", 790, 190, 66),
    # columna administrador
    ("roles", "Gestionar roles<br>y permisos", 430, 290, 66),
    ("usuarios", "Gestionar usuarios", 430, 376, 66),
    ("catalogo", "Gestionar catálogo y maestros<br>(productos, marcas, categorías,<br>"
                 "proveedores, métodos de pago)", 430, 462, 88),
    ("compras", "Gestionar compras<br>a proveedores", 430, 580, 66),
    ("pagar", "Pagar a proveedores", 430, 666, 66),
    ("devolverProv", "Devolver mercancía<br>al proveedor", 430, 752, 66),
    ("ajustarInv", "Ajustar inventario", 430, 838, 66),
    ("logs", "Ver logs de accesos", 430, 924, 66),
    ("reportes", "Ver reportes<br>y ganancias", 430, 1010, 66),
    # columna vendedor
    ("venta", "Registrar venta", 790, 290, 66),
    ("cobrar", "Cobrar venta", 790, 376, 66),
    ("descontar", "Descontar stock<br>(automático)", 790, 462, 66),
    ("garantia", "Emitir garantía", 790, 548, 66),
    ("reclamo", "Registrar reclamo<br>de garantía", 790, 634, 66),
    ("devolCliente", "Atender devolución<br>de cliente", 790, 720, 66),
    ("clientes", "Gestionar clientes", 790, 806, 66),
    ("consultarInv", "Consultar inventario<br>y stock crítico", 790, 892, 66),
    ("exportar", "Exportar datos<br>a la página web", 790, 978, 66),
    # columna RRHH
    ("empleados", "Gestionar empleados", 1150, 290, 66),
    ("asistencia", "Registrar y justificar<br>asistencia", 1150, 376, 66),
    ("vacaciones", "Gestionar vacaciones<br>y permisos laborales", 1150, 462, 66),
    ("contratos", "Generar contratos", 1150, 548, 66),
]

# actor, caso
UC_ASSOCS = [
    ("vendedor", "sesion"), ("vendedor", "cerrar"), ("vendedor", "venta"),
    ("vendedor", "devolCliente"), ("vendedor", "reclamo"),
    ("vendedor", "garantia"), ("vendedor", "clientes"),
    ("vendedor", "consultarInv"), ("vendedor", "reportes"),
    ("vendedor", "exportar"),
    ("admin", "sesion"), ("admin", "cerrar"), ("admin", "roles"),
    ("admin", "usuarios"), ("admin", "catalogo"), ("admin", "compras"),
    ("admin", "ajustarInv"), ("admin", "logs"), ("admin", "reportes"),
    ("rrhh", "sesion"), ("rrhh", "cerrar"), ("rrhh", "empleados"),
    ("rrhh", "asistencia"), ("rrhh", "vacaciones"), ("rrhh", "contratos"),
]

UC_ACTORS = [  # clave, nombre, x, y
    ("admin", "Administrador", 150, 290),
    ("vendedor", "Vendedor / Cajero", 150, 700),
    ("rrhh", "RRHH", 1640, 350),
]

# origen, destino, etiqueta (el puntero va de origen a destino)
UC_IO = [
    ("venta", "cobrar", "\u00abinclude\u00bb"),
    ("venta", "descontar", "\u00abinclude\u00bb"),
    ("compras", "pagar", "\u00abinclude\u00bb"),
    ("garantia", "venta", "\u00abextend\u00bb"),
    ("devolverProv", "compras", "\u00abextend\u00bb"),
]


def uc_center(key):
    for k, _label, x, y, h in UC_USECASES:
        if k == key:
            return x + 100, y + h // 2
    for k, _name, x, y in UC_ACTORS:
        if k == key:
            return x + 20, y + 35
    raise KeyError(key)


def build_casos_de_uso():
    cells = []
    cells.append(
        '<mxCell id="sistema" value="BalbuTechApp" style="%s" vertex="1" '
        'parent="1"><mxGeometry x="380" y="60" width="1180" height="1080" '
        'as="geometry"/></mxCell>' % BOUNDARY_STYLE)

    for key, name, x, y in UC_ACTORS:
        cells.append(
            '<mxCell id="a_%s" value="%s" style="%s" vertex="1" parent="1">'
            '<mxGeometry x="%d" y="%d" width="40" height="70" as="geometry"/>'
            '</mxCell>' % (key, esc(name), ACTOR_STYLE, x, y))

    for key, label, x, y, h in UC_USECASES:
        cells.append(
            '<mxCell id="u_%s" value="%s" style="%s" vertex="1" parent="1">'
            '<mxGeometry x="%d" y="%d" width="200" height="%d" as="geometry"/>'
            '</mxCell>' % (key, esc(label), UC_STYLE, x, y, h))

    for actor, uc in UC_ASSOCS:
        ax, ay = uc_center(actor)
        ux, uy = uc_center(uc)
        cells.append(
            '<mxCell id="l_%s_%s" value="" style="%s" edge="1" parent="1" '
            'source="a_%s" target="u_%s"><mxGeometry relative="1" '
            'as="geometry"/></mxCell>' % (actor, uc, ASSOC_STYLE, actor, uc))

    for i, (src, tgt, label) in enumerate(UC_IO, 1):
        cells.append(
            '<mxCell id="io%d" value="%s" style="%s" edge="1" parent="1" '
            'source="u_%s" target="u_%s"><mxGeometry relative="1" '
            'as="geometry"/></mxCell>' % (i, esc(label), IO_STYLE, src, tgt))

    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<mxfile host="app.diagrams.net" type="device">\n'
        '  <diagram id="balbutech-casos-uso" name="Casos de uso">\n'
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


# ===========================================================================
# DIAGRAMA 2 — SECUENCIA: VENTA RÁPIDA CON COBRO
# ===========================================================================

# clave, nombre, estereotipo (o None para actor), centro x
SEQ_LIFELINES = [
    ("vendedor", "Vendedor", None, 140),
    ("interfaz", "InterfazDeVentas", "boundary", 440),
    ("gestor", "GestorDeVentas", "control", 740),
    ("producto", "Producto", "entity", 1040),
    ("venta", "Venta", "entity", 1340),
]

SEQ_TOP = 100          # y del header
SEQ_HDR_H = 48
SEQ_BOTTOM = 1660      # fin de lifelines

# id, y, desde, hacia, texto, tipo (sync|return|self)
SEQ_MESSAGES = [
    ("m1", 240, "vendedor", "interfaz", "Selecciona \u00abVenta r\u00e1pida\u00bb", "sync"),
    ("m2", 310, "interfaz", "gestor", "Solicitar cat\u00e1logo de productos", "sync"),
    ("m3", 380, "gestor", "producto", "Consultar productos activos (SP)", "sync"),
    ("m4", 450, "producto", "gestor", "Lista de productos con stock", "return"),
    ("m5", 520, "gestor", "interfaz", "Productos disponibles", "return"),
    ("m6", 590, "interfaz", "vendedor", "Muestra cat\u00e1logo en consola", "return"),
    ("m7", 660, "vendedor", "interfaz", "Agrega l\u00ednea: producto + cantidad", "sync"),
    ("m8", 730, "interfaz", "gestor", "Validar y agregar l\u00ednea al carrito", "sync"),
    ("m9", 800, "gestor", "producto", "Verificar stock disponible", "sync"),
    ("m10", 870, "producto", "gestor", "Stock OK", "return"),
    ("m11", 940, "gestor", "interfaz", "Carrito actualizado (subtotal)", "return"),
    ("m12", 1010, "vendedor", "interfaz", "Cobrar: m\u00e9todo de pago + monto", "sync"),
    ("m13", 1080, "interfaz", "gestor", "Procesar cobro", "sync"),
    ("m14", 1150, "gestor", "venta", "SP_REGISTRAR_VENTA (cabecera, detalle, pago)", "sync"),
    ("m15", 1220, "venta", "venta", "", "self"),
    ("m16", 1290, "venta", "gestor", "idVenta + total con ITBIS", "return"),
    ("m17", 1360, "gestor", "interfaz", "Venta cobrada exitosamente", "return"),
    ("m18", 1430, "interfaz", "vendedor", "Comprobante + idVenta", "return"),
    ("m19", 1520, "vendedor", "interfaz", "Registrar garant\u00eda (opcional)", "sync"),
    ("m20", 1590, "interfaz", "gestor", "Emitir garant\u00eda vinculada a la venta", "sync"),
]

SEQ_SELF_LABEL = ("Triggers: descontar stock y calcular totales", 1360, 1208)

# nombre, x, y, w, h, etiqueta de esquina
SEQ_FRAGMENTS = [
    ("loop", 360, 630, 760, 340, "loop [por cada l\u00ednea del carrito]"),
    ("opt", 60, 1485, 800, 135,
     "opt [si el cliente solicita garant\u00eda]"),
]

# clave lifeline -> barras de activación (y_ini, y_fin)
SEQ_ACTIVATIONS = {
    "interfaz": [(230, 1600)],
    "gestor": [(300, 1600)],
    "producto": [(370, 460), (790, 880)],
    "venta": [(1140, 1300)],
}

SYNC_STYLE = ("endArrow=block;endFill=1;html=1;rounded=0;fontSize=11;"
              "labelBackgroundColor=#FFFFFF;")
RETURN_STYLE = ("endArrow=open;endFill=0;dashed=1;html=1;rounded=0;fontSize=11;"
                "labelBackgroundColor=#FFFFFF;")
SELF_STYLE = ("edgeStyle=none;endArrow=block;endFill=1;html=1;rounded=0;")
LIFELINE_STYLE = "dashed=1;endArrow=none;startArrow=none;html=1;"
HDR_STYLE = ("rounded=0;whiteSpace=wrap;html=1;fillColor=#FFFFFF;"
             "strokeColor=#000000;fontSize=13;fontStyle=1;")
ACT_BAR_STYLE = "rounded=0;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#000000;"
FRAG_STYLE = "rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#666666;dashed=1;"
FRAG_LABEL_STYLE = ("text;html=1;strokeColor=none;fillColor=#FFFFFF;align=left;"
                    "verticalAlign=middle;fontSize=12;fontStyle=2;spacingLeft=4;")


def seq_x(key):
    for k, _name, _st, cx in SEQ_LIFELINES:
        if k == key:
            return cx
    raise KeyError(key)


def build_secuencia():
    cells = []

    # fragmentos combinados (detrás de todo)
    for name, x, y, w, h, label in SEQ_FRAGMENTS:
        cells.append(
            '<mxCell id="f_%s" value="" style="%s" vertex="1" parent="1">'
            '<mxGeometry x="%d" y="%d" width="%d" height="%d" as="geometry"/>'
            '</mxCell>' % (name, FRAG_STYLE, x, y, w, h))
        cells.append(
            '<mxCell id="f_%s_l" value="%s" style="%s" vertex="1" parent="1">'
            '<mxGeometry x="%d" y="%d" width="290" height="24" as="geometry"/>'
            '</mxCell>' % (name, esc(label), FRAG_LABEL_STYLE, x, y - 12))

    # lifelines (líneas punteadas)
    for key, _name, _st, cx in SEQ_LIFELINES:
        cells.append(
            '<mxCell id="ll_%s" value="" style="%s" edge="1" parent="1">'
            '<mxGeometry relative="1" as="geometry">'
            '<mxPoint x="%d" y="%d" as="sourcePoint"/>'
            '<mxPoint x="%d" y="%d" as="targetPoint"/>'
            '</mxGeometry></mxCell>'
            % (key, LIFELINE_STYLE, cx, SEQ_TOP + SEQ_HDR_H, cx, SEQ_BOTTOM))

    # headers (actor = umlActor; resto = caja con estereotipo)
    for key, name, st, cx in SEQ_LIFELINES:
        if st is None:
            cells.append(
                '<mxCell id="h_%s" value="%s" style="%s" vertex="1" parent="1">'
                '<mxGeometry x="%d" y="%d" width="40" height="70" '
                'as="geometry"/></mxCell>'
                % (key, esc(name), ACTOR_STYLE, cx - 20, SEQ_TOP - 10))
        else:
            label = "\u00ab%s\u00bb<br>%s" % (st, name)
            cells.append(
                '<mxCell id="h_%s" value="%s" style="%s" vertex="1" parent="1">'
                '<mxGeometry x="%d" y="%d" width="170" height="%d" '
                'as="geometry"/></mxCell>'
                % (key, esc(label), HDR_STYLE, cx - 85, SEQ_TOP, SEQ_HDR_H))

    # barras de activación
    for key, bars in SEQ_ACTIVATIONS.items():
        cx = seq_x(key)
        for i, (y0, y1) in enumerate(bars):
            cells.append(
                '<mxCell id="ab_%s_%d" value="" style="%s" vertex="1" '
                'parent="1"><mxGeometry x="%d" y="%d" width="12" height="%d" '
                'as="geometry"/></mxCell>'
                % (key, i, ACT_BAR_STYLE, cx - 6, y0, y1 - y0))

    # mensajes
    for mid, y, src, tgt, text, kind in SEQ_MESSAGES:
        x1, x2 = seq_x(src), seq_x(tgt)
        if kind == "self":
            style = SELF_STYLE
            cells.append(
                '<mxCell id="%s" value="" style="%s" edge="1" parent="1">'
                '<mxGeometry relative="1" as="geometry">'
                '<mxPoint x="%d" y="%d" as="sourcePoint"/>'
                '<mxPoint x="%d" y="%d" as="targetPoint"/>'
                '<Array as="points"><mxPoint x="%d" y="%d"/></Array>'
                '</mxGeometry></mxCell>'
                % (mid, style, x1, y, x1, y + 24, x1 + 70, y + 12))
        else:
            style = SYNC_STYLE if kind == "sync" else RETURN_STYLE
            cells.append(
                '<mxCell id="%s" value="%s" style="%s" edge="1" parent="1">'
                '<mxGeometry relative="1" as="geometry">'
                '<mxPoint x="%d" y="%d" as="sourcePoint"/>'
                '<mxPoint x="%d" y="%d" as="targetPoint"/>'
                '</mxGeometry></mxCell>'
                % (mid, esc(text), style, x1, y, x2, y))

    # etiqueta del mensaje self (a la derecha del bucle)
    text, x, y = SEQ_SELF_LABEL
    cells.append(
        '<mxCell id="self_label" value="%s" style="%s" vertex="1" parent="1">'
        '<mxGeometry x="%d" y="%d" width="300" height="20" as="geometry"/>'
        '</mxCell>'
        % (esc(text), FRAG_LABEL_STYLE.replace("fillColor=#FFFFFF",
                                               "fillColor=none"), x, y))

    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<mxfile host="app.diagrams.net" type="device">\n'
        '  <diagram id="balbutech-secuencia" name="Secuencia venta r\u00e1pida">\n'
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
        % (PAGE_W, SEQ_BOTTOM + 60, "\n".join("        " + c for c in cells))
    )
    return xml


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    outputs = [
        ("casos-de-uso.drawio", build_casos_de_uso(),
         "casos_de_uso=%d actores=%d relaciones=%d include/extend=%d"
         % (len(UC_USECASES), len(UC_ACTORS), len(UC_ASSOCS), len(UC_IO))),
        ("secuencia-venta.drawio", build_secuencia(),
         "lifelines=%d mensajes=%d fragmentos=%d"
         % (len(SEQ_LIFELINES), len(SEQ_MESSAGES), len(SEQ_FRAGMENTS))),
    ]
    for name, content, summary in outputs:
        path = os.path.join(here, name)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(content)
        print("OK escrito:", path)
        print("  ", summary)


if __name__ == "__main__":
    main()

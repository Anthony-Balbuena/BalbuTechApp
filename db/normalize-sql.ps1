# Normaliza los .sql de modulos/ para importacion por CLI (mariadb < archivo).
# Patrones que corrige (los archivos fueron escritos para ejecutar por seleccion en Workbench):
#  1. `END ;` dentro de una region DELIMITER //  ->  `END //`
#     (con delimitador //, el `END ;` nunca termina el bloque y todo cascada en 1064)
#  2. `DELIMITER // <resto>` o `DELIMITER ; <resto>` en la misma linea -> los separa en 2 lineas.
# No toca nada fuera de regiones DELIMITER //, preserva CRLF y UTF-8 sin BOM.
# Uso: powershell -File db/normalize-sql.ps1 [-Apply]
param([switch]$Apply)

$files = Get-ChildItem "modulos/*.sql" | Where-Object {
  $_.Name -ne "todo_modulos.sql" -and $_.Name -ne "Mejoras_extras.sql"
}
$totalChanges = 0
foreach ($f in $files) {
  $raw = [IO.File]::ReadAllText($f.FullName)
  $nl = "`r`n"
  if ($raw -notmatch "`r`n") { $nl = "`n" }
  $lines = $raw -split "`r?`n"
  $inCustom = $false
  $out = New-Object Collections.ArrayList
  $changes = 0
  $sawActive = $false
  $skipNextDelimSemi = $false
  for ($idx = 0; $idx -lt $lines.Count; $idx++) {
    $line = $lines[$idx]
    $t = $line.Trim()
    # T0: el plugin MySQL de VS Code inserta una linea `-- Active: ...` por cada
    # ejecucion; se conserva solo la primera (son comentarios, pero ensucian el diff).
    if ($t -match '^-- Active: ') {
      if ($sawActive) { $changes++; continue }
      $sawActive = $true
      [void]$out.Add($line)
      continue
    }
    if ($t -match '^(?i)DELIMITER\s*(//|;)\s*(.*)$') {
      if ($skipNextDelimSemi -and $Matches[1] -eq ';' -and $Matches[2] -eq '') {
        # T7: este DELIMITER ; ya se adelanto antes del CALL de prueba.
        $skipNextDelimSemi = $false
        $changes++
        continue
      }
      $d = $Matches[1]; $rest = $Matches[2]
      # T9: `DELIMITER //` redundante (ya estamos en regimen //) -> se elimina
      # la linea; si trae resto se conserva (un `//` dentro del buffer partiria
      # el statement y el servidor falla 1064 near 'DELIMITER').
      if ($inCustom -and $d -eq '//') {
        if ($rest -ne '') { [void]$out.Add($rest) }
        $changes++
      }
      else {
      $indent = ($line -match '^(\s*)') | Out-Null; $indent = $Matches[1]
      [void]$out.Add("$indent" + "DELIMITER $d")
      if ($rest -ne "") { [void]$out.Add("$indent$rest"); $changes++ }
      if ($line -ne "$indent" + "DELIMITER $d") { $changes++ }
      $inCustom = ($d -eq '//')
      }
    }
    # T1: `END ;` final de bloque dentro de region DELIMITER // -> `END //`.
    # (Con delimitador //, el `END ;` nunca termina el bloque y todo cascada.)
    # Lookahead: NO se convierte si lo que sigue es continuacion del cuerpo
    # (bloque BEGIN anidado, ej. handler con START TRANSACTION despues) - esos
    # `END;` internos son correctos con `;`.
    elseif ($inCustom -and ($t -match '^(?i)END\s*;\s*$')) {
      $k = $idx + 1
      while ($k -lt $lines.Count -and ($lines[$k].Trim() -eq '' -or $lines[$k].Trim() -match '^--')) { $k++ }
      $nx = if ($k -lt $lines.Count) { $lines[$k].Trim() } else { '' }
      if ($nx -match '^(?i)(START\s+TRANSACTION|COMMIT|ROLLBACK|SAVEPOINT|DECLARE|OPEN|FETCH|CLOSE|LEAVE|ITERATE|RETURN|WHILE|LOOP|REPEAT|IF|ELSEIF|ELSE|CASE|WHEN|UNTIL)\b') {
        [void]$out.Add($line)
      }
      else {
        [void]$out.Add(($line -replace ';\s*$', '//'))
        $changes++
      }
    }
    # T1b: revierte `END//` internos preexistentes (de T1 ciega o del autor)
    # seguidos por continuacion del cuerpo. Doble condicion: indentado (el
    # top-level va a col 0) + keyword de cuerpo. Asi no toca los `END //`
    # finales seguidos de SELECTs scratch a col 0.
    elseif ($inCustom -and ($t -match '^(?i)END\s*//\s*$')) {
      $k = $idx + 1
      while ($k -lt $lines.Count -and ($lines[$k].Trim() -eq '' -or $lines[$k].Trim() -match '^--')) { $k++ }
      $nx = if ($k -lt $lines.Count) { $lines[$k] } else { '' }
      $nxT = $nx.Trim()
      if ($nx -match '^\s+\S' -and $nxT -match '^(?i)(START\s+TRANSACTION|COMMIT|ROLLBACK|SAVEPOINT|DECLARE|OPEN|FETCH|CLOSE|LEAVE|ITERATE|RETURN|WHILE|LOOP|REPEAT|IF|ELSEIF|ELSE|CASE|WHEN|UNTIL|SET|SELECT|INSERT|UPDATE|DELETE)\b') {
        [void]$out.Add(($line -replace '//\s*$', ';'))
        $changes++
      }
      else { [void]$out.Add($line) }
    }
    # T6: `DELIMITER` solo (sin argumento) no hace nada util y el servidor lo
    # rechaza con 1064 -> se restaura el delimitador por defecto.
    elseif ($t -match '^(?i)DELIMITER\s*$') {
      [void]$out.Add("DELIMITER ;")
      $changes++
      $inCustom = $false
    }
    # T7: CALL de prueba entre `END//` y `DELIMITER ;` (patron del autor para
    # verificar en Workbench). Con delimitador // el CALL con `;` nunca termina
    # y se traga las lineas siguientes -> se adelanta el `DELIMITER ;` antes del CALL.
    elseif ($inCustom -and ($t -match '^(?i)CALL\s+.*;\s*$')) {
      $j = $idx + 1
      while ($j -lt $lines.Count -and $lines[$j].Trim() -eq '') { $j++ }
      if ($j -lt $lines.Count -and $lines[$j].Trim() -match '^(?i)DELIMITER\s*;\s*$') {
        [void]$out.Add("DELIMITER ;")
        [void]$out.Add($line)
        $inCustom = $false
        $skipNextDelimSemi = $true
        $changes += 2
      }
      else { [void]$out.Add($line) }
    }
    # (T8 ELIMINADA: ver arriba.)
    # T4: CALL de una sola linea sin `;` final -> se pegaria con la siguiente
    # linea en un solo statement. Solo si termina en `)` para no romper CALLs multilinea.
    elseif ($t -match '^(?i)CALL\s' -and $t -notmatch ';\s*(--.*)?$' -and $t -match '\)\s*(--.*)?$') { 
      [void]$out.Add(($line -replace '\)(\s*(--.*)?)?$', ');$2'))
      $changes++
    }
    # T5: `USE` solo (sin base de datos) nunca es valido -> se comenta.
    elseif ($t -match '^(?i)USE\s*;?\s*$') {
      [void]$out.Add("-- NEUTRALIZADO(normalize-sql): $t")
      $changes++
    }
    else { [void]$out.Add($line) }
  }
  if ($changes -gt 0) {
    Write-Output ("{0,4} cambios  {1}" -f $changes, $f.Name)
    $totalChanges += $changes
    if ($Apply) { [IO.File]::WriteAllText($f.FullName, ($out -join $nl)) }
  }
}
Write-Output ("TOTAL: {0} cambios en archivos. " -f $totalChanges + $(if ($Apply) { "(aplicados)" } else { "(vista previa, usa -Apply)" }))

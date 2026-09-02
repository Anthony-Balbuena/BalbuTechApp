sql::PreparedStatement *pSelect = globalCon->prepareStatement(
            "SELECT U.ID_USUARIO, U.USUARIO, U.CONTRASENA, U.ESTADO, R.NOMBRE_ROL "
            "FROM USUARIOS U LEFT JOIN ROLES R ON U.ID_ROL = R.ID_ROL "
            "WHERE U.USUARIO = ?"
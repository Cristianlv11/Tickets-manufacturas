from sqlalchemy import Column, Integer, String, DateTime, Date, Boolean, BigInteger, Text, Enum, ForeignKey, LargeBinary
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base
import enum

class UserRole(str, enum.Enum):
    CLIENT = "CLIENT"
    ADMIN = "ADMIN"

class TicketStatus(str, enum.Enum):
    PENDING = "Pendiente"
    IN_PROGRESS = "En Progreso"
    COMPLETED = "Completado"

class TicketUrgency(str, enum.Enum):
    LOW = "Bajo"
    MEDIUM = "Medio"
    HIGH = "Alto"
    CRITICAL = "Crítico"

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    password_hash = Column(String)
    role = Column(String, default=UserRole.CLIENT)

class Ticket(Base):
    __tablename__ = "tickets"

    id = Column(Integer, primary_key=True, index=True)
    titulo = Column(String, index=True)
    descripcion = Column(Text)
    nombre_solicitante = Column(String)
    cargo_solicitante = Column(String, nullable=True)
    celular_solicitante = Column(String, nullable=True)
    
    # Nuevos campos solicitados
    tipo_afectacion = Column(String) # Aplicación, Equipo
    subtipo_equipo = Column(String, nullable=True) # Computador, Cámara, Impresora (solo si es Equipo)
    tipo_solicitud = Column(String) # Fallo, Instalación
    responsable = Column(String, default="Soporte") # Soporte, Desarrollo, Administrativo
    
    urgencia = Column(String, default=TicketUrgency.LOW)
    estado = Column(String, default=TicketStatus.PENDING)
    
    fecha_creacion = Column(DateTime, default=func.now())
    fecha_actualizacion = Column(DateTime, default=func.now(), onupdate=func.now())
    fecha_cierre = Column(DateTime, nullable=True)

    gestiones = relationship("TicketGestion", back_populates="ticket", cascade="all, delete-orphan")
    adjuntos = relationship("TicketAdjunto", back_populates="ticket", cascade="all, delete-orphan")

class TicketGestion(Base):
    __tablename__ = "ticket_gestiones"
    
    id = Column(Integer, primary_key=True, index=True)
    ticket_id = Column(Integer, ForeignKey("tickets.id"))
    autor = Column(String)
    nota = Column(Text)
    fecha = Column(DateTime, default=func.now())
    
    ticket = relationship("Ticket", back_populates="gestiones")

class TicketAdjunto(Base):
    __tablename__ = "ticket_adjuntos"
    
    id = Column(Integer, primary_key=True, index=True)
    ticket_id = Column(Integer, ForeignKey("tickets.id"))
    nombre_archivo = Column(String)
    tipo_contenido = Column(String)
    archivo_bytes = Column(LargeBinary)
    tamano = Column(Integer, default=0)
    fecha_subida = Column(DateTime, default=func.now())
    
    ticket = relationship("Ticket", back_populates="adjuntos")

class RedConfig(Base):
    __tablename__ = "red_config"

    id = Column(Integer, primary_key=True, index=True)
    clave = Column(String, unique=True, index=True)
    valor = Column(Text)
    fecha_actualizacion = Column(DateTime, default=func.now(), onupdate=func.now())


# ---------------------------------------------------------------------------
# Gestión TI: respaldos, activos, bóveda de contraseñas y dominios
# ---------------------------------------------------------------------------

class RespaldoEstacion(Base):
    __tablename__ = "respaldo_estaciones"

    id = Column(Integer, primary_key=True, index=True)
    hostname = Column(String, unique=True, index=True)
    equipo_id = Column(String, nullable=True, index=True)  # id del equipo en el inventario (NetMap)
    nombre = Column(String)
    frecuencia_horas = Column(Integer, default=24)
    requiere_fisico = Column(Boolean, default=True)
    requiere_nube = Column(Boolean, default=False)
    activo = Column(Boolean, default=True)
    notas = Column(Text, nullable=True)

    registros = relationship("RespaldoRegistro", back_populates="estacion", cascade="all, delete-orphan",
                             order_by="RespaldoRegistro.fecha.desc()")


class RespaldoRegistro(Base):
    __tablename__ = "respaldo_registros"

    id = Column(Integer, primary_key=True, index=True)
    estacion_id = Column(Integer, ForeignKey("respaldo_estaciones.id"), index=True)
    tipo = Column(String)  # Físico, Nube
    estado = Column(String)  # OK, Error
    fecha = Column(DateTime, default=func.now(), index=True)
    destino = Column(String, nullable=True)
    tamano_bytes = Column(BigInteger, default=0)
    archivos = Column(Integer, default=0)
    duracion_seg = Column(Integer, default=0)
    mensaje = Column(Text, nullable=True)
    origen = Column(String, default="Script")  # Script, Manual
    registrado_por = Column(String, nullable=True)

    estacion = relationship("RespaldoEstacion", back_populates="registros")


class ActivoFicha(Base):
    __tablename__ = "activo_fichas"

    id = Column(Integer, primary_key=True, index=True)
    equipo_id = Column(String, unique=True, index=True)
    placa_inventario = Column(String, nullable=True)
    serial = Column(String, nullable=True)
    estado = Column(String, default="Activo")  # Activo, En reparación, En bodega, De baja
    fecha_compra = Column(Date, nullable=True)
    proveedor = Column(String, nullable=True)
    garantia_hasta = Column(Date, nullable=True)
    valor_compra = Column(Integer, nullable=True)
    observaciones = Column(Text, nullable=True)
    fecha_actualizacion = Column(DateTime, default=func.now(), onupdate=func.now())


class ActivoMantenimiento(Base):
    __tablename__ = "activo_mantenimientos"

    id = Column(Integer, primary_key=True, index=True)
    equipo_id = Column(String, index=True)
    fecha = Column(Date)
    tipo = Column(String)  # Preventivo, Correctivo, Actualización, Revisión
    descripcion = Column(Text)
    tecnico = Column(String, nullable=True)
    ticket_id = Column(Integer, nullable=True)
    costo = Column(Integer, nullable=True)
    registrado_por = Column(String, nullable=True)
    fecha_registro = Column(DateTime, default=func.now())


class ActivoSoftware(Base):
    __tablename__ = "activo_software"

    id = Column(Integer, primary_key=True, index=True)
    equipo_id = Column(String, index=True)
    fecha = Column(Date)
    accion = Column(String)  # Instalado, Actualizado, Desinstalado
    nombre = Column(String)
    version = Column(String, nullable=True)
    licencia = Column(String, nullable=True)  # Licenciado, Gratuito, Suscripción, Sin licencia
    notas = Column(Text, nullable=True)
    registrado_por = Column(String, nullable=True)
    fecha_registro = Column(DateTime, default=func.now())


class Credencial(Base):
    __tablename__ = "credenciales"

    id = Column(Integer, primary_key=True, index=True)
    categoria = Column(String, index=True)  # Correo, Software, Aplicativo, Cámara, Hosting / Dominio, Red, Otro
    servicio = Column(String)
    usuario = Column(String, nullable=True)
    clave_cifrada = Column(Text, nullable=True)
    url = Column(String, nullable=True)
    equipo_id = Column(String, nullable=True)
    notas_cifradas = Column(Text, nullable=True)
    fecha_creacion = Column(DateTime, default=func.now())
    fecha_actualizacion = Column(DateTime, default=func.now(), onupdate=func.now())
    actualizado_por = Column(String, nullable=True)


class CredencialAcceso(Base):
    __tablename__ = "credencial_accesos"

    id = Column(Integer, primary_key=True, index=True)
    credencial_id = Column(Integer, nullable=True, index=True)
    servicio = Column(String, nullable=True)
    usuario_app = Column(String)
    accion = Column(String)  # Ver, Crear, Editar, Eliminar, Importar, Desbloquear, Intento fallido
    ip = Column(String, nullable=True)
    fecha = Column(DateTime, default=func.now(), index=True)


class Dominio(Base):
    __tablename__ = "dominios"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String, unique=True)
    tipo = Column(String, default="Dominio")  # Dominio, Hosting, Certificado SSL, Correo
    proveedor = Column(String, nullable=True)
    fecha_vencimiento = Column(Date)
    renovacion_automatica = Column(Boolean, default=False)
    responsable = Column(String, nullable=True)
    costo_anual = Column(Integer, nullable=True)
    servicios = Column(String, nullable=True)  # p. ej. Correo corporativo, Página web
    notas = Column(Text, nullable=True)
    fecha_actualizacion = Column(DateTime, default=func.now(), onupdate=func.now())

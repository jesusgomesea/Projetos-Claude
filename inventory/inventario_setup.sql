-- ============================================================
--  INVENTÁRIO TI — Script de criação do banco
--  Execute: mysql -u root -p < inventario_setup.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS inventario_ti
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE inventario_ti;

-- ------------------------------------------------------------
-- 1. CATEGORIAS (Cabos, Adaptadores, Periféricos, Peças)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS categorias (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nome        VARCHAR(60)  NOT NULL,
  descricao   VARCHAR(255) DEFAULT NULL,
  criado_em   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

INSERT INTO categorias (nome, descricao) VALUES
  ('Cabos',      'HDMI, USB-A, USB-C, DisplayPort, RJ-45, etc.'),
  ('Adaptadores','Conversores de interface e hubs'),
  ('Periféricos','Mouse, teclado, headset, webcam, etc.'),
  ('Peças internas','RAM, HD, SSD, cooler, placa de rede, etc.');

-- ------------------------------------------------------------
-- 2. FORNECEDORES
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fornecedores (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nome        VARCHAR(100) NOT NULL,
  contato     VARCHAR(120) DEFAULT NULL,
  criado_em   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 3. ITENS (catálogo de produtos)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS itens (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nome             VARCHAR(120) NOT NULL,
  descricao        TEXT         DEFAULT NULL,
  categoria_id     INT UNSIGNED NOT NULL,
  fornecedor_id    INT UNSIGNED DEFAULT NULL,
  modelo           VARCHAR(100) DEFAULT NULL,
  numero_serie     VARCHAR(100) DEFAULT NULL UNIQUE,
  patrimonio       VARCHAR(60)  DEFAULT NULL UNIQUE,
  localizacao      VARCHAR(120) DEFAULT NULL COMMENT 'Sala / armário / prateleira',
  quantidade_total INT UNSIGNED NOT NULL DEFAULT 1,
  quantidade_disp  INT UNSIGNED NOT NULL DEFAULT 1,
  condicao         ENUM('Novo','Bom','Regular','Defeituoso','Descartado') NOT NULL DEFAULT 'Bom',
  observacoes      TEXT         DEFAULT NULL,
  criado_em        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  CONSTRAINT fk_item_categoria  FOREIGN KEY (categoria_id)  REFERENCES categorias(id),
  CONSTRAINT fk_item_fornecedor FOREIGN KEY (fornecedor_id) REFERENCES fornecedores(id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 4. RESPONSÁVEIS (RCAs / técnicos / setores)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS responsaveis (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nome        VARCHAR(120) NOT NULL,
  matricula   VARCHAR(40)  DEFAULT NULL UNIQUE,
  setor       VARCHAR(80)  DEFAULT NULL,
  email       VARCHAR(120) DEFAULT NULL,
  criado_em   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 5. MOVIMENTAÇÕES (empréstimos, devoluções, transferências)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS movimentacoes (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  item_id          INT UNSIGNED NOT NULL,
  responsavel_id   INT UNSIGNED DEFAULT NULL,
  tipo             ENUM('Entrada','Saída','Empréstimo','Devolução','Manutenção','Descarte') NOT NULL,
  quantidade       INT UNSIGNED NOT NULL DEFAULT 1,
  data_mov         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  data_prev_retorno DATETIME    DEFAULT NULL COMMENT 'Previsão de retorno (empréstimos)',
  data_retorno     DATETIME     DEFAULT NULL COMMENT 'Data real de devolução',
  observacao       TEXT         DEFAULT NULL,
  registrado_por   VARCHAR(80)  DEFAULT NULL COMMENT 'Usuário do sistema que fez o registro',

  CONSTRAINT fk_mov_item        FOREIGN KEY (item_id)        REFERENCES itens(id),
  CONSTRAINT fk_mov_responsavel FOREIGN KEY (responsavel_id) REFERENCES responsaveis(id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 6. VIEW — Saldo atual por item
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_saldo_itens AS
SELECT
  i.id,
  i.nome,
  c.nome        AS categoria,
  i.localizacao,
  i.condicao,
  i.quantidade_total,
  i.quantidade_disp                              AS disponivel,
  (i.quantidade_total - i.quantidade_disp)       AS em_uso,
  i.numero_serie,
  i.patrimonio,
  i.atualizado_em
FROM itens i
JOIN categorias c ON c.id = i.categoria_id
WHERE i.condicao != 'Descartado';

-- ------------------------------------------------------------
-- 7. VIEW — Empréstimos em aberto
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_emprestimos_abertos AS
SELECT
  m.id          AS mov_id,
  i.nome        AS item,
  r.nome        AS responsavel,
  r.matricula,
  r.setor,
  m.quantidade,
  m.data_mov    AS saiu_em,
  m.data_prev_retorno,
  m.observacao
FROM movimentacoes m
JOIN itens        i ON i.id = m.item_id
LEFT JOIN responsaveis r ON r.id = m.responsavel_id
WHERE m.tipo = 'Empréstimo'
  AND m.data_retorno IS NULL
ORDER BY m.data_prev_retorno ASC;

-- ------------------------------------------------------------
-- 8. TRIGGER — Atualiza saldo ao registrar movimentação
-- ------------------------------------------------------------
DELIMITER $$

CREATE TRIGGER trg_after_movimentacao
AFTER INSERT ON movimentacoes
FOR EACH ROW
BEGIN
  -- Saída / Empréstimo / Manutenção → diminui disponível
  IF NEW.tipo IN ('Saída', 'Empréstimo', 'Manutenção', 'Descarte') THEN
    UPDATE itens
    SET quantidade_disp = GREATEST(0, quantidade_disp - NEW.quantidade)
    WHERE id = NEW.item_id;
  END IF;

  -- Entrada / Devolução → aumenta disponível
  IF NEW.tipo IN ('Entrada', 'Devolução') THEN
    UPDATE itens
    SET quantidade_disp = LEAST(quantidade_total, quantidade_disp + NEW.quantidade)
    WHERE id = NEW.item_id;
  END IF;

  -- Descarte → marca condição
  IF NEW.tipo = 'Descarte' THEN
    UPDATE itens SET condicao = 'Descartado' WHERE id = NEW.item_id;
  END IF;
END$$

DELIMITER ;

-- ------------------------------------------------------------
-- FIM
-- ------------------------------------------------------------
SELECT 'Banco inventario_ti criado com sucesso!' AS status;

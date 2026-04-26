/**
 * inventario_api.js — Servidor REST local para o Inventário TI
 * ---------------------------------------------------------------
 * Instalação:
 *   npm init -y
 *   npm install express mariadb cors
 *
 * Uso:
 *   node inventario_api.js
 *   Servidor sobe em http://localhost:3000
 */

const express = require("express");
const mariadb  = require("mariadb");
const cors     = require("cors");

const app  = express();
const PORT = 3000;

app.use(cors());
app.use(express.json());

// ── Conexão ────────────────────────────────────────────────────
const pool = mariadb.createPool({
  host:            "localhost",
  user:            "root",       // ← altere se necessário
  password:        "Ehub@1912",  // ← altere para sua senha
  database:        "inventario_ti",
  connectionLimit: 5,
});

// Helper
async function query(sql, params = []) {
  const conn = await pool.getConnection();
  try {
    return await conn.query(sql, params);
  } finally {
    conn.release();
  }
}

// ── CATEGORIAS ─────────────────────────────────────────────────
app.get("/categorias", async (_, res) => {
  try { res.json(await query("SELECT * FROM categorias ORDER BY nome")); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

// ── RESPONSÁVEIS ───────────────────────────────────────────────
app.get("/responsaveis", async (_, res) => {
  try { res.json(await query("SELECT * FROM responsaveis ORDER BY nome")); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

app.post("/responsaveis", async (req, res) => {
  const { nome, matricula, setor, email } = req.body;
  try {
    const r = await query(
      "INSERT INTO responsaveis (nome, matricula, setor, email) VALUES (?,?,?,?)",
      [nome, matricula, setor, email]
    );
    res.json({ id: Number(r.insertId), nome });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── ITENS ──────────────────────────────────────────────────────
app.get("/itens", async (_, res) => {
  try {
    res.json(await query(`
      SELECT i.*, c.nome AS categoria_nome
      FROM itens i
      JOIN categorias c ON c.id = i.categoria_id
      ORDER BY i.nome
    `));
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get("/itens/saldo", async (_, res) => {
  try { res.json(await query("SELECT * FROM vw_saldo_itens")); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

app.get("/itens/:id", async (req, res) => {
  try {
    const rows = await query("SELECT * FROM itens WHERE id = ?", [req.params.id]);
    rows.length ? res.json(rows[0]) : res.status(404).json({ error: "Não encontrado" });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post("/itens", async (req, res) => {
  const { nome, descricao, categoria_id, fornecedor_id, modelo,
          numero_serie, patrimonio, localizacao,
          quantidade_total, condicao, observacoes } = req.body;
  try {
    const r = await query(
      `INSERT INTO itens
         (nome,descricao,categoria_id,fornecedor_id,modelo,numero_serie,
          patrimonio,localizacao,quantidade_total,quantidade_disp,condicao,observacoes)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`,
      [nome, descricao, categoria_id, fornecedor_id || null, modelo,
       numero_serie || null, patrimonio || null, localizacao,
       quantidade_total, quantidade_total, condicao, observacoes]
    );
    res.json({ id: Number(r.insertId) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.put("/itens/:id", async (req, res) => {
  const { nome, descricao, categoria_id, modelo, numero_serie,
          patrimonio, localizacao, quantidade_total, condicao, observacoes } = req.body;
  try {
    await query(
      `UPDATE itens SET nome=?,descricao=?,categoria_id=?,modelo=?,
       numero_serie=?,patrimonio=?,localizacao=?,quantidade_total=?,
       condicao=?,observacoes=? WHERE id=?`,
      [nome, descricao, categoria_id, modelo, numero_serie || null,
       patrimonio || null, localizacao, quantidade_total, condicao,
       observacoes, req.params.id]
    );
    res.json({ ok: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.delete("/itens/:id", async (req, res) => {
  try {
    await query("DELETE FROM itens WHERE id = ?", [req.params.id]);
    res.json({ ok: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── MOVIMENTAÇÕES ──────────────────────────────────────────────
app.get("/movimentacoes", async (_, res) => {
  try {
    res.json(await query(`
      SELECT m.*, i.nome AS item_nome, r.nome AS responsavel_nome
      FROM movimentacoes m
      JOIN itens i ON i.id = m.item_id
      LEFT JOIN responsaveis r ON r.id = m.responsavel_id
      ORDER BY m.data_mov DESC
      LIMIT 200
    `));
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get("/movimentacoes/emprestimos-abertos", async (_, res) => {
  try { res.json(await query("SELECT * FROM vw_emprestimos_abertos")); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

app.post("/movimentacoes", async (req, res) => {
  const { item_id, responsavel_id, tipo, quantidade,
          data_prev_retorno, observacao, registrado_por } = req.body;
  try {
    const r = await query(
      `INSERT INTO movimentacoes
         (item_id,responsavel_id,tipo,quantidade,data_prev_retorno,observacao,registrado_por)
       VALUES (?,?,?,?,?,?,?)`,
      [item_id, responsavel_id || null, tipo, quantidade,
       data_prev_retorno || null, observacao, registrado_por]
    );
    res.json({ id: Number(r.insertId) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// Devolução — fecha empréstimo em aberto
app.patch("/movimentacoes/:id/devolver", async (req, res) => {
  try {
    await query(
      "UPDATE movimentacoes SET data_retorno = NOW(), tipo = 'Devolução' WHERE id = ?",
      [req.params.id]
    );
    // Trigger já atualiza o saldo
    res.json({ ok: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── DASHBOARD ─────────────────────────────────────────────────
app.get("/dashboard", async (_, res) => {
  try {
    const [totais]    = await query("SELECT COUNT(*) AS total, SUM(quantidade_disp) AS disp, SUM(quantidade_total - quantidade_disp) AS em_uso FROM itens WHERE condicao != 'Descartado'");
    const [abertos]   = await query("SELECT COUNT(*) AS total FROM vw_emprestimos_abertos");
    const [defeito]   = await query("SELECT COUNT(*) AS total FROM itens WHERE condicao = 'Defeituoso'");
    const porCateg    = await query("SELECT c.nome, COUNT(i.id) AS qtd FROM itens i JOIN categorias c ON c.id = i.categoria_id GROUP BY c.nome");
    res.json({ totais, emprestimosAbertos: abertos.total, defeituosos: defeito.total, porCategoria: porCateg });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── START ──────────────────────────────────────────────────────
app.listen(PORT, () =>
  console.log(`✅  API Inventário TI rodando em http://localhost:${PORT}`)
);

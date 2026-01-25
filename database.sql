-- ============================================
-- BANCO DE DADOS - CABO PEREIRA
-- Sistema de Controle de Vendas
-- Para uso com Supabase
-- ============================================

-- Habilitar extensão UUID (já vem habilitada no Supabase por padrão)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- TABELA: VENDAS
-- ============================================
CREATE TABLE IF NOT EXISTS vendas (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    nome VARCHAR(255) NOT NULL,
    plano VARCHAR(50) NOT NULL CHECK (plano IN ('Mensal', 'Bimestral', 'Trimestral', 'Quadrimestral', 'Semestral', 'Anual')),
    tipo VARCHAR(20) NOT NULL DEFAULT 'Avulsa' CHECK (tipo IN ('Avulsa', 'Recorrente')),
    valor DECIMAL(10, 2) NOT NULL CHECK (valor > 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('America/Sao_Paulo', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('America/Sao_Paulo', NOW())
);

-- Índices para melhorar performance
CREATE INDEX idx_vendas_created_at ON vendas(created_at DESC);
CREATE INDEX idx_vendas_plano ON vendas(plano);
CREATE INDEX idx_vendas_tipo ON vendas(tipo);

-- Comentários na tabela
COMMENT ON TABLE vendas IS 'Tabela de vendas do sistema Cabo Pereira';
COMMENT ON COLUMN vendas.id IS 'Identificador único da venda';
COMMENT ON COLUMN vendas.nome IS 'Nome do aluno';
COMMENT ON COLUMN vendas.plano IS 'Tipo do plano vendido';
COMMENT ON COLUMN vendas.tipo IS 'Tipo de pagamento: Avulsa (única) ou Recorrente (mensalidade)';
COMMENT ON COLUMN vendas.valor IS 'Valor da venda em reais';
COMMENT ON COLUMN vendas.created_at IS 'Data e hora do registro';

-- ============================================
-- TABELA: TRÁFEGO (Gastos com anúncios)
-- ============================================
CREATE TABLE IF NOT EXISTS trafego (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    descricao VARCHAR(255) NOT NULL,
    valor DECIMAL(10, 2) NOT NULL CHECK (valor > 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('America/Sao_Paulo', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('America/Sao_Paulo', NOW())
);

-- Índices para melhorar performance
CREATE INDEX idx_trafego_created_at ON trafego(created_at DESC);

-- Comentários na tabela
COMMENT ON TABLE trafego IS 'Tabela de gastos com tráfego pago';
COMMENT ON COLUMN trafego.id IS 'Identificador único do gasto';
COMMENT ON COLUMN trafego.descricao IS 'Descrição do gasto (ex: Facebook Ads)';
COMMENT ON COLUMN trafego.valor IS 'Valor gasto em reais';
COMMENT ON COLUMN trafego.created_at IS 'Data e hora do registro';

-- ============================================
-- FUNÇÃO: Atualizar updated_at automaticamente
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('America/Sao_Paulo', NOW());
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers para atualizar updated_at
CREATE TRIGGER update_vendas_updated_at
    BEFORE UPDATE ON vendas
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_trafego_updated_at
    BEFORE UPDATE ON trafego
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- Habilitar para segurança
-- ============================================

-- Habilitar RLS nas tabelas
ALTER TABLE vendas ENABLE ROW LEVEL SECURITY;
ALTER TABLE trafego ENABLE ROW LEVEL SECURITY;

-- Políticas de acesso público (para aplicação sem autenticação)
-- Se você usar autenticação, ajuste essas políticas

-- Política para vendas - permitir todas as operações
CREATE POLICY "Permitir SELECT em vendas" ON vendas
    FOR SELECT USING (true);

CREATE POLICY "Permitir INSERT em vendas" ON vendas
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Permitir UPDATE em vendas" ON vendas
    FOR UPDATE USING (true);

CREATE POLICY "Permitir DELETE em vendas" ON vendas
    FOR DELETE USING (true);

-- Política para trafego - permitir todas as operações
CREATE POLICY "Permitir SELECT em trafego" ON trafego
    FOR SELECT USING (true);

CREATE POLICY "Permitir INSERT em trafego" ON trafego
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Permitir UPDATE em trafego" ON trafego
    FOR UPDATE USING (true);

CREATE POLICY "Permitir DELETE em trafego" ON trafego
    FOR DELETE USING (true);

-- ============================================
-- VIEWS: Estatísticas e Relatórios
-- ============================================

-- View: Resumo geral de vendas
CREATE OR REPLACE VIEW vw_resumo_vendas AS
SELECT
    COUNT(*) as total_vendas,
    COALESCE(SUM(valor), 0) as valor_total,
    COALESCE(AVG(valor), 0) as valor_medio,
    MIN(created_at) as primeira_venda,
    MAX(created_at) as ultima_venda
FROM vendas;

-- View: Vendas por plano
CREATE OR REPLACE VIEW vw_vendas_por_plano AS
SELECT
    plano,
    COUNT(*) as quantidade,
    SUM(valor) as valor_total,
    AVG(valor) as valor_medio
FROM vendas
GROUP BY plano
ORDER BY quantidade DESC;

-- View: Resumo de tráfego
CREATE OR REPLACE VIEW vw_resumo_trafego AS
SELECT
    COUNT(*) as total_registros,
    COALESCE(SUM(valor), 0) as valor_total,
    MIN(created_at) as primeiro_gasto,
    MAX(created_at) as ultimo_gasto
FROM trafego;

-- View: Dashboard completo com ROI
CREATE OR REPLACE VIEW vw_dashboard AS
SELECT
    (SELECT COALESCE(SUM(valor), 0) FROM vendas) as total_vendas,
    (SELECT COUNT(*) FROM vendas) as qtd_vendas,
    (SELECT COALESCE(AVG(valor), 0) FROM vendas) as media_vendas,
    (SELECT COALESCE(SUM(valor), 0) FROM trafego) as total_trafego,
    (SELECT COUNT(*) FROM trafego) as qtd_trafego,
    (SELECT COALESCE(SUM(valor), 0) FROM vendas) - (SELECT COALESCE(SUM(valor), 0) FROM trafego) as lucro_liquido,
    CASE
        WHEN (SELECT COALESCE(SUM(valor), 0) FROM trafego) > 0
        THEN (((SELECT COALESCE(SUM(valor), 0) FROM vendas) - (SELECT COALESCE(SUM(valor), 0) FROM trafego)) / (SELECT SUM(valor) FROM trafego)) * 100
        ELSE 0
    END as roi_percentual;

-- ============================================
-- FUNÇÕES: Para usar na aplicação
-- ============================================

-- Função: Obter estatísticas do dashboard
CREATE OR REPLACE FUNCTION get_dashboard_stats()
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    SELECT json_build_object(
        'total_vendas', COALESCE((SELECT SUM(valor) FROM vendas), 0),
        'qtd_vendas', (SELECT COUNT(*) FROM vendas),
        'media_vendas', COALESCE((SELECT AVG(valor) FROM vendas), 0),
        'total_trafego', COALESCE((SELECT SUM(valor) FROM trafego), 0),
        'qtd_trafego', (SELECT COUNT(*) FROM trafego),
        'lucro_liquido', COALESCE((SELECT SUM(valor) FROM vendas), 0) - COALESCE((SELECT SUM(valor) FROM trafego), 0),
        'roi', CASE
            WHEN COALESCE((SELECT SUM(valor) FROM trafego), 0) > 0
            THEN ((COALESCE((SELECT SUM(valor) FROM vendas), 0) - COALESCE((SELECT SUM(valor) FROM trafego), 0)) / (SELECT SUM(valor) FROM trafego)) * 100
            ELSE 0
        END
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Função: Obter vendas por plano
CREATE OR REPLACE FUNCTION get_vendas_por_plano()
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'plano', plano,
            'quantidade', quantidade,
            'valor_total', valor_total
        )
    ) INTO result
    FROM vw_vendas_por_plano;

    RETURN COALESCE(result, '[]'::json);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- DADOS DE EXEMPLO (opcional - remova se não quiser)
-- ============================================

-- Inserir algumas vendas de exemplo
-- INSERT INTO vendas (nome, plano, valor) VALUES
--     ('João Silva', 'Mensal', 150.00),
--     ('Maria Santos', 'Trimestral', 400.00),
--     ('Pedro Oliveira', 'Anual', 1200.00),
--     ('Ana Costa', 'Semestral', 750.00),
--     ('Carlos Souza', 'Bimestral', 280.00);

-- Inserir alguns gastos de exemplo
-- INSERT INTO trafego (descricao, valor) VALUES
--     ('Facebook Ads - Campanha Janeiro', 500.00),
--     ('Google Ads - Pesquisa', 300.00),
--     ('Instagram Ads - Stories', 200.00);

-- ============================================
-- FIM DO SCRIPT
-- ============================================

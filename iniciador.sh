#!/usr/bin/env bash
# ==============================================================================
# CUDACyclone - Iniciador e Gerenciador de Compilação & Mineração
# Suporte a arquiteturas: RTX 20, RTX 30, RTX 40 e RTX 50
# Script de Mineração: minerar-71-Particular-CUDACyclone-01.py
# ==============================================================================

set -u

# Garante que a execução ocorra no diretório onde o script reside
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Cores e estilos ANSI
BOLD='\033[1m'
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'

PID_FILE="$SCRIPT_DIR/.minerar.pid"
PYTHON_SCRIPT="minerar-71-Particular-CUDACyclone-01.py"
LOG_EXEC="execution.log"
LOG_MINER="minerar_output.log"
PROGRESS_FILE="progress.txt"

# ── Configurar caminhos do CUDA se necessário ────────────────────────────────
setup_cuda_path() {
    if ! command -v nvcc &>/dev/null; then
        for p in /usr/local/cuda/bin /usr/local/cuda-*/bin /opt/cuda/bin /usr/lib/cuda/bin; do
            if [ -x "$p/nvcc" ]; then
                export PATH="$p:$PATH"
                break
            fi
        done
    fi

    if [ -d /usr/local/cuda/lib64 ]; then
        export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
    fi
}
setup_cuda_path

# ── Detecção do Python / Virtualenv ───────────────────────────────────────────
get_python_bin() {
    if [ -x "$SCRIPT_DIR/myenv/bin/python" ]; then
        echo "$SCRIPT_DIR/myenv/bin/python"
    elif [ -x "$SCRIPT_DIR/venv/bin/python" ]; then
        echo "$SCRIPT_DIR/venv/bin/python"
    elif command -v python3 &>/dev/null; then
        echo "python3"
    elif command -v python &>/dev/null; then
        echo "python"
    else
        echo ""
    fi
}

# ── Detecção de GPU ──────────────────────────────────────────────────────────
detect_gpu_info() {
    if command -v nvidia-smi &>/dev/null; then
        local name cap
        name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 | sed 's/^[ \t]*//;s/[ \t]*$//')
        cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | sed 's/^[ \t]*//;s/[ \t]*$//')
        if [ -n "$name" ]; then
            echo "$name (Compute $cap)"
            return 0
        fi
    fi
    echo "Não detectada (nvidia-smi indisponível)"
}

detect_gpu_cc_digits() {
    if command -v nvidia-smi &>/dev/null; then
        local cap
        cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | tr -d '.' | tr -d ' ')
        if [ -n "$cap" ]; then
            echo "$cap"
            return 0
        fi
    fi
    echo "86" # fallback Ampere
}

# ── Verificar se mineração está rodando ───────────────────────────────────────
get_miner_pid() {
    local pid=""
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    # Fallback procurando por processo do script python
    pid=$(pgrep -f "$PYTHON_SCRIPT" 2>/dev/null | head -n1)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
        return 0
    fi

    echo ""
}

# ── Pausa para o usuário ler ─────────────────────────────────────────────────
pause() {
    echo ""
    read -rp "Pressione [ENTER] para voltar ao menu..." dummy
}

# ── Cabeçalho e Painel de Status ─────────────────────────────────────────────
show_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}${BOLD}               CUDACyclone - Central de Operações                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${GRAY}        Compilação Otimizada RTX & Gerenciamento de Mineração           ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}"

    # Status da GPU e CUDA
    local gpu_info cuda_info py_bin miner_pid bin_status
    gpu_info=$(detect_gpu_info)

    if command -v nvcc &>/dev/null; then
        cuda_info=$(nvcc --version | grep "release" | sed -E 's/.*release ([0-9]+\.[0-9]+).*/\1/')
        cuda_info="CUDA $cuda_info ($(which nvcc))"
    else
        cuda_info="${RED}nvcc não encontrado no PATH${NC}"
    fi

    # Status do binário
    if [ -x "$SCRIPT_DIR/CUDACyclone" ]; then
        local b_size b_date
        b_size=$(ls -lh "$SCRIPT_DIR/CUDACyclone" | awk '{print $5}')
        b_date=$(date -r "$SCRIPT_DIR/CUDACyclone" "+%d/%m/%Y %H:%M:%S" 2>/dev/null || echo "OK")
        bin_status="${GREEN}Pronto (${b_size}, modificado em ${b_date})${NC}"
    else
        bin_status="${RED}Não compilado (necessário compilar antes de minerar)${NC}"
    fi

    # Status do Python
    py_bin=$(get_python_bin)
    local py_status
    if [ -n "$py_bin" ]; then
        py_status="${GREEN}${py_bin}${NC}"
    else
        py_status="${RED}Python não encontrado!${NC}"
    fi

    # Status do Minerador
    miner_pid=$(get_miner_pid)
    local miner_status
    if [ -n "$miner_pid" ]; then
        miner_status="${GREEN}${BOLD}EM EXECUÇÃO (PID: ${miner_pid})${NC}"
    else
        miner_status="${YELLOW}Parado${NC}"
    fi

    echo -e " ${BOLD}STATUS DO SISTEMA:${NC}"
    echo -e "   • ${WHITE}GPU Local:${NC}      ${CYAN}${gpu_info}${NC}"
    echo -e "   • ${WHITE}Compilador:${NC}     ${cuda_info}"
    echo -e "   • ${WHITE}CUDACyclone:${NC}    ${bin_status}"
    echo -e "   • ${WHITE}Python:${NC}         ${py_status}"
    echo -e "   • ${WHITE}Mineração:${NC}      ${miner_status}"
    echo -e "${CYAN}╟────────────────────────────────────────────────────────────────────────╢${NC}"
}

# ── Função de Compilação Genérica ─────────────────────────────────────────────
compile_target() {
    local archs="$1"
    local desc="$2"

    echo ""
    echo -e "${BLUE}========================================================================${NC}"
    echo -e "${BOLD}${WHITE}Iniciando compilação: ${YELLOW}${desc}${NC}"
    echo -e "${GRAY}Arquitetura(s) CUDA (-gencode): ${archs}${NC}"
    echo -e "${BLUE}========================================================================${NC}"
    echo ""

    if ! command -v nvcc &>/dev/null; then
        echo -e "${RED}[ERRO] O compilador 'nvcc' (NVIDIA CUDA Toolkit) não foi encontrado!${NC}"
        echo -e "Certifique-se de que o CUDA Toolkit está instalado e no PATH."
        pause
        return 1
    fi

    if ! command -v make &>/dev/null; then
        echo -e "${RED}[ERRO] O utilitário 'make' não foi encontrado!${NC}"
        echo -e "Instale com: sudo apt install build-essential"
        pause
        return 1
    fi

    # Limpeza prévia para garantir que os arquivos objeto (.o) usem a nova arquitetura
    echo -e "${CYAN}[1/2] Limpando compilações anteriores (make clean)...${NC}"
    make clean

    local num_cores
    num_cores=$(nproc 2>/dev/null || echo 2)

    echo -e "${CYAN}[2/2] Compilando com ${num_cores} núcleos paralelos...${NC}"
    echo -e "${GRAY}Comando: make -j${num_cores} SM_ARCHS=\"${archs}\"${NC}"
    echo ""

    if make -j"${num_cores}" SM_ARCHS="${archs}"; then
        echo ""
        if [ -x "$SCRIPT_DIR/CUDACyclone" ]; then
            local b_size
            b_size=$(ls -lh "$SCRIPT_DIR/CUDACyclone" | awk '{print $5}')
            echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║  ✅  COMPILAÇÃO CONCLUÍDA COM SUCESSO!                                ║${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
            echo -e "  Binário gerado: ${BOLD}${CYAN}$SCRIPT_DIR/CUDACyclone${NC} (${b_size})"
            echo -e "  Otimizado para: ${YELLOW}${desc}${NC}"
        else
            echo -e "${RED}[ERRO] Makefile finalizou mas o binário 'CUDACyclone' não foi encontrado.${NC}"
        fi
    else
        echo ""
        echo -e "${RED}╔════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ❌  FALHA NA COMPILAÇÃO! Verifique os erros acima.                   ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    fi

    pause
}

# ── Compilação: RTX 20 Series ─────────────────────────────────────────────────
compile_rtx20() {
    compile_target "75" "RTX 20 Series (Turing: RTX 2060, 2070, 2080, GTX 16xx - sm_75)"
}

# ── Compilação: RTX 30 Series ─────────────────────────────────────────────────
compile_rtx30() {
    compile_target "86" "RTX 30 Series (Ampere: RTX 3050, 3060, 3070, 3080, 3090 - sm_86)"
}

# ── Compilação: RTX 40 Series ─────────────────────────────────────────────────
compile_rtx40() {
    compile_target "89" "RTX 40 Series (Ada Lovelace: RTX 4060, 4070, 4080, 4090 - sm_89)"
}

# ── Compilação: RTX 50 Series ─────────────────────────────────────────────────
compile_rtx50() {
    compile_target "120" "RTX 50 Series (Blackwell: RTX 5070, 5080, 5090 - sm_120)"
}

# ── Compilação: Universal / Todas as RTX ──────────────────────────────────────
compile_universal() {
    compile_target "75 86 89 120" "Universal Fatbinary (RTX 20, 30, 40 e 50 - sm_75, sm_86, sm_89, sm_120)"
}

# ── Compilação: Automática para GPU Local ─────────────────────────────────────
compile_autodetect() {
    local cc
    cc=$(detect_gpu_cc_digits)
    local gpu_info
    gpu_info=$(detect_gpu_info)
    compile_target "$cc" "Auto-detectada: ${gpu_info} (sm_${cc})"
}

# ── Limpar compilação ────────────────────────────────────────────────────────
clean_build() {
    echo ""
    echo -e "${CYAN}Limpando binários e arquivos objeto (.o)...${NC}"
    make clean
    rm -f "$SCRIPT_DIR/CUDACyclone"
    echo -e "${GREEN}Limpeza concluída com sucesso!${NC}"
    pause
}

# ── Verificar se está pronto para minerar ─────────────────────────────────────
check_pre_miner() {
    if [ ! -x "$SCRIPT_DIR/CUDACyclone" ]; then
        echo -e "${RED}[ATENÇÃO] O binário 'CUDACyclone' não foi encontrado ou não está compilado!${NC}"
        echo -e "Deseja compilar agora para a GPU deste computador antes de iniciar? [s/N]: "
        read -r resp
        if [[ "$resp" =~ ^[sSyY]$ ]]; then
            compile_autodetect
            if [ ! -x "$SCRIPT_DIR/CUDACyclone" ]; then
                echo -e "${RED}Falha ao gerar o binário. Não é possível iniciar a mineração.${NC}"
                pause
                return 1
            fi
        else
            echo -e "${YELLOW}Operação cancelada.${NC}"
            pause
            return 1
        fi
    fi

    if [ ! -f "$SCRIPT_DIR/$PYTHON_SCRIPT" ]; then
        echo -e "${RED}[ERRO] O script Python '$PYTHON_SCRIPT' não foi encontrado no diretório!${NC}"
        pause
        return 1
    fi

    local py_bin
    py_bin=$(get_python_bin)
    if [ -z "$py_bin" ]; then
        echo -e "${RED}[ERRO] Nenhum interpretador Python encontrado! Instale python3 e python3-venv.${NC}"
        pause
        return 1
    fi

    # Se não temos ambiente virtual local, tenta criar myenv
    if [ ! -x "$SCRIPT_DIR/myenv/bin/python" ] && [ ! -x "$SCRIPT_DIR/venv/bin/python" ]; then
        echo -e "${CYAN}Criando ambiente virtual isolado (myenv)...${NC}"
        python3 -m venv "$SCRIPT_DIR/myenv" 2>/dev/null || true
        py_bin=$(get_python_bin)
    fi

    # Checar se módulo requests existe
    if ! "$py_bin" -c "import requests" &>/dev/null; then
        echo -e "${YELLOW}[AVISO] O módulo 'requests' não foi detectado no Python (${py_bin}).${NC}"
        echo -e "Instalando dependências..."
        if [ -x "$SCRIPT_DIR/myenv/bin/pip" ]; then
            "$SCRIPT_DIR/myenv/bin/pip" install requests || {
                echo -e "${RED}[ERRO] Falha ao instalar 'requests' no ambiente virtual.${NC}"
                pause
                return 1
            }
        else
            "$py_bin" -m pip install requests --break-system-packages 2>/dev/null || "$py_bin" -m pip install requests || {
                echo -e "${RED}[ERRO] Falha ao instalar dependência 'requests'. Instale com: pip install requests${NC}"
                pause
                return 1
            }
        fi
        echo -e "${GREEN}Dependências instaladas com sucesso!${NC}"
    fi

    return 0
}

# ── Iniciar Mineração em Primeiro Plano (Foreground) ──────────────────────────
start_miner_fg() {
    check_pre_miner || return 1

    local miner_pid
    miner_pid=$(get_miner_pid)
    if [ -n "$miner_pid" ]; then
        echo -e "${YELLOW}[AVISO] A mineração já está rodando em segundo plano (PID: ${miner_pid}).${NC}"
        echo -e "Deseja parar a instância existente para iniciar no terminal? [s/N]: "
        read -r resp
        if [[ "$resp" =~ ^[sSyY]$ ]]; then
            stop_miner_process
        else
            return 1
        fi
    fi

    local py_bin
    py_bin=$(get_python_bin)

    echo ""
    echo -e "${GREEN}========================================================================${NC}"
    echo -e "${BOLD}${WHITE}Iniciando Mineração em Primeiro Plano...${NC}"
    echo -e "${GRAY}Script: ${PYTHON_SCRIPT}${NC}"
    echo -e "${GRAY}Python: ${py_bin}${NC}"
    echo -e "${YELLOW}Pressione Ctrl+C a qualquer momento para interromper.${NC}"
    echo -e "${GREEN}========================================================================${NC}"
    echo ""

    "$py_bin" "$SCRIPT_DIR/$PYTHON_SCRIPT"

    echo ""
    echo -e "${CYAN}Processo de mineração finalizado.${NC}"
    pause
}

# ── Iniciar Mineração em Segundo Plano (Background) ───────────────────────────
start_miner_bg() {
    check_pre_miner || return 1

    local miner_pid
    miner_pid=$(get_miner_pid)
    if [ -n "$miner_pid" ]; then
        echo -e "${YELLOW}[INFO] A mineração já está em execução (PID: ${miner_pid})!${NC}"
        pause
        return 0
    fi

    local py_bin
    py_bin=$(get_python_bin)

    echo ""
    echo -e "${CYAN}Iniciando mineração em segundo plano...${NC}"
    nohup "$py_bin" "$SCRIPT_DIR/$PYTHON_SCRIPT" >> "$SCRIPT_DIR/$LOG_MINER" 2>&1 &
    local new_pid=$!

    echo "$new_pid" > "$PID_FILE"
    sleep 1

    if kill -0 "$new_pid" 2>/dev/null; then
        echo -e "${GREEN}✅ Mineração iniciada com sucesso em segundo plano!${NC}"
        echo -e "   • ${BOLD}PID:${NC} $new_pid"
        echo -e "   • ${BOLD}Log de saída:${NC} $SCRIPT_DIR/$LOG_MINER"
        echo -e "   • ${BOLD}Log de execuções:${NC} $SCRIPT_DIR/$LOG_EXEC"
        echo ""
        echo -e "${GRAY}Você pode acompanhar a execução na opção [10] do menu.${NC}"
    else
        echo -e "${RED}❌ O processo falhou ao iniciar. Verifique o arquivo '$LOG_MINER' para detalhes.${NC}"
    fi

    pause
}

# ── Parar Mineração ───────────────────────────────────────────────────────────
stop_miner_process() {
    local miner_pid
    miner_pid=$(get_miner_pid)

    if [ -z "$miner_pid" ]; then
        echo -e "${YELLOW}Nenhum processo de mineração ativo encontrado.${NC}"
        rm -f "$PID_FILE"
        return 0
    fi

    echo -e "${YELLOW}Encerrando processo de mineração (PID: ${miner_pid})...${NC}"
    kill -TERM "$miner_pid" 2>/dev/null

    # Aguardar até 5 segundos
    local count=0
    while kill -0 "$miner_pid" 2>/dev/null && [ "$count" -lt 5 ]; do
        sleep 1
        count=$((count + 1))
    done

    if kill -0 "$miner_pid" 2>/dev/null; then
        echo -e "${RED}Processo não respondeu a TERM, enviando SIGKILL...${NC}"
        kill -9 "$miner_pid" 2>/dev/null
    fi

    # Também finaliza processo CUDACyclone órfão se houver
    pkill -f "./CUDACyclone" 2>/dev/null || true
    rm -f "$PID_FILE"

    echo -e "${GREEN}Processo de mineração interrompido com sucesso!${NC}"
}

stop_miner_menu() {
    echo ""
    stop_miner_process
    pause
}

# ── Ver Logs e Progresso ──────────────────────────────────────────────────────
view_logs() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}${BOLD}                     LOGS E PROGRESSO DA MINERAÇÃO                     ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ -f "$SCRIPT_DIR/$PROGRESS_FILE" ]; then
        local prog
        prog=$(cat "$SCRIPT_DIR/$PROGRESS_FILE" 2>/dev/null)
        echo -e "${WHITE}${BOLD}Progresso atual ($PROGRESS_FILE):${NC} ${GREEN}${prog}${NC}"
    else
        echo -e "${GRAY}Arquivo $PROGRESS_FILE ainda não criado.${NC}"
    fi
    echo ""

    echo -e "${BOLD}${WHITE}Últimas 10 linhas de execução ($LOG_EXEC):${NC}"
    echo -e "${GRAY}------------------------------------------------------------------------${NC}"
    if [ -f "$SCRIPT_DIR/$LOG_EXEC" ]; then
        tail -n 10 "$SCRIPT_DIR/$LOG_EXEC"
    else
        echo -e "${GRAY}(Nenhum registro ainda)${NC}"
    fi
    echo -e "${GRAY}------------------------------------------------------------------------${NC}"
    echo ""

    echo -e "Opções:"
    echo -e "  [1] Acompanhar execução em tempo real (${CYAN}tail -f $LOG_EXEC${NC})"
    echo -e "  [2] Acompanhar saída do processo (${CYAN}tail -f $LOG_MINER${NC})"
    echo -e "  [0] Voltar ao menu principal"
    echo ""
    read -rp "Escolha uma opção: " opt_log

    case "$opt_log" in
        1)
            if [ -f "$SCRIPT_DIR/$LOG_EXEC" ]; then
                echo -e "${YELLOW}Pressione Ctrl+C para sair do log em tempo real...${NC}"
                sleep 1
                tail -f "$SCRIPT_DIR/$LOG_EXEC"
            else
                echo -e "${RED}Arquivo $LOG_EXEC não existe ainda.${NC}"
                sleep 2
            fi
            ;;
        2)
            if [ -f "$SCRIPT_DIR/$LOG_MINER" ]; then
                echo -e "${YELLOW}Pressione Ctrl+C para sair do log em tempo real...${NC}"
                sleep 1
                tail -f "$SCRIPT_DIR/$LOG_MINER"
            else
                echo -e "${RED}Arquivo $LOG_MINER não existe ainda.${NC}"
                sleep 2
            fi
            ;;
        *)
            ;;
    esac
}

# ── Loop Principal do Menu ────────────────────────────────────────────────────
main_menu() {
    while true; do
        show_header
        echo -e " ${BOLD}COMPILAÇÃO PARA GPUs NVIDIA:${NC}"
        echo -e "   ${CYAN}[1]${NC} Compilar para ${BOLD}RTX 20 Series${NC} ${GRAY}(sm_75 - Turing: 2060, 2070, 2080, 1660)${NC}"
        echo -e "   ${CYAN}[2]${NC} Compilar para ${BOLD}RTX 30 Series${NC} ${GRAY}(sm_86 - Ampere: 3050, 3060, 3070, 3080, 3090)${NC}"
        echo -e "   ${CYAN}[3]${NC} Compilar para ${BOLD}RTX 40 Series${NC} ${GRAY}(sm_89 - Ada Lovelace: 4060, 4070, 4080, 4090)${NC}"
        echo -e "   ${CYAN}[4]${NC} Compilar para ${BOLD}RTX 50 Series${NC} ${GRAY}(sm_120 - Blackwell: 5070, 5080, 5090)${NC}"
        echo -e "   ${CYAN}[5]${NC} Compilar ${BOLD}Universal / Todas${NC} ${GRAY}(RTX 20, 30, 40 e 50 em um único binário)${NC}"
        echo -e "   ${CYAN}[6]${NC} Compilar ${BOLD}Auto-Detect${NC} ${GRAY}(Detecta e compila para a GPU deste computador)${NC}"
        echo -e "   ${CYAN}[7]${NC} Limpar arquivos compilados ${GRAY}(make clean)${NC}"
        echo ""
        echo -e " ${BOLD}EXECUÇÃO DA MINERAÇÃO:${NC}"
        echo -e "   ${GREEN}[8]${NC}  ${BOLD}Iniciar Mineração${NC} ${GRAY}(Primeiro plano no terminal - $PYTHON_SCRIPT)${NC}"
        echo -e "   ${GREEN}[9]${NC}  ${BOLD}Iniciar em Segundo Plano${NC} ${GRAY}(Background com nohup)${NC}"
        echo -e "   ${YELLOW}[10]${NC} Ver Logs e Monitorar Progresso ${GRAY}(Tempo real)${NC}"
        echo -e "   ${RED}[11]${NC} Parar Mineração em Segundo Plano"
        echo ""
        echo -e "   ${WHITE}[0]${NC}  Sair"
        echo -e "${CYAN}────────────────────────────────────────────────────────────────────────${NC}"
        read -rp "Selecione uma opção [0-11]: " choice

        case "$choice" in
            1) compile_rtx20 ;;
            2) compile_rtx30 ;;
            3) compile_rtx40 ;;
            4) compile_rtx50 ;;
            5) compile_universal ;;
            6) compile_autodetect ;;
            7) clean_build ;;
            8) start_miner_fg ;;
            9) start_miner_bg ;;
            10) view_logs ;;
            11) stop_miner_menu ;;
            0|q|Q)
                echo ""
                echo -e "${CYAN}Encerrando o iniciador. Até logo!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Opção inválida! Tente novamente.${NC}"
                sleep 1
                ;;
        esac
    done
}

main_menu

# ── Detectar plataforma ──────────────────────────
ifeq ($(OS),Windows_NT)
  TARGET_EXT := .exe
  OBJ_EXT    := .obj
  RM         := cmd /c del /Q /F
else
  TARGET_EXT :=
  OBJ_EXT    := .o
  RM         := rm -f
endif

TARGET      := CUDACyclone$(TARGET_EXT)
SRC         := CUDACyclone.cu CUDAHash.cu
OBJ         := $(SRC:.cu=$(OBJ_EXT))
CC          := nvcc

# Detecta compute capability da GPU automaticamente
# Windows: usa PowerShell (consegue acessar nvidia-smi no PATH)
# Linux: usa shell normal
ifeq ($(OS),Windows_NT)
  GPU_ARCH ?= $(strip $(shell powershell -NoProfile -Command "try{ (nvidia-smi --query-gpu=compute_cap --format=csv,noheader | Select-Object -First 1).Trim() -replace '\.','' }catch{''}" 2>nul))
else
  GPU_ARCH ?= $(shell nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | tr -d '.')
endif
ifeq ($(GPU_ARCH),)
  GPU_ARCH := 86
  $(warning nvidia-smi nao disponivel. Usando GPU_ARCH=86 como fallback.)
endif

SM_ARCHS   ?= 75 86 89 120 $(GPU_ARCH)
GENCODE    := $(foreach arch,$(sort $(SM_ARCHS)),-gencode arch=compute_$(arch),code=sm_$(arch))

NVCC_FLAGS := -O3 -rdc=true -use_fast_math --ptxas-options=-O3 $(GENCODE)
CXXFLAGS   := -std=c++17

LDFLAGS    := -lcudadevrt -cudart=static

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(NVCC_FLAGS) $(CXXFLAGS) $(OBJ) -o $@ $(LDFLAGS)

%$(OBJ_EXT): %.cu
	$(CC) $(NVCC_FLAGS) $(CXXFLAGS) -c $< -o $@

clean:
	$(RM) $(TARGET) $(OBJ)


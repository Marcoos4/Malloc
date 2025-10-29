# 🧠 Custom `malloc` in Assembly x86-64 / Implementazione personalizzata di `malloc` in Assembly x86-64

---

## 🇬🇧 English Version

### 🎯 Project Overview
This project implements a simplified version of the `malloc` and `free` functions **entirely in x86-64 assembly**, using a **10 MB static memory pool** as the managed heap.  
The goal is to understand how a memory allocator works internally, handling block management, allocation tracking, and memory release — all without relying on standard libraries.

---

### ⚙️ Repository Structure

| File | Description |
|------|--------------|
| `malloc.S` | Core implementation of the memory allocator in assembly |
| `test.c` | C test program to validate correctness and performance |
| `Makefile` | Builds the project and links the assembly with the test code |
| `run.sh` | Runs the test binary multiple times for stress testing |
| `.gitignore`, `classroom.yml` | Configuration files for the GitHub Classroom environment |

---

### 🧩 Allocator Design

#### 📦 Memory Pool
All memory managed by the allocator resides in a global buffer:

```asm
.comm memory_pool, 10485760, 16   # 10 MB
```

This memory is divided into **blocks of 64 bytes** each, for a total of **163,840 blocks**.

---

### 🗺️ Data Structures

The allocator is based on **three main data structures** and one global counter (`last_index`):

1. **Bitmap (`bitmap`)**  
   Tracks which memory blocks are occupied or free.  
   - `0` → free  
   - `1` → allocated  
   (20480 bytes total, 1 bit per block)

2. **Sizemap (`sizemap`)**  
   Tracks whether a block belongs to a multi-block allocation.  
   Each bit indicates if the *next* block is part of the same allocation (`1`) or not (`0`).  
   This allows `free()` to know how many blocks to release.

3. **Bin (Free Address Stack)**  
   A stack of recently freed addresses (size 2042).  
   - `push_bin`: saves a freed address  
   - `pop_bin`: retrieves one for reuse  

4. **`last_index` Counter**  
   Keeps track of the last allocated block in the pool.  
   New allocations are attempted at the end of the pool for efficiency.

---

### 🧮 Allocation & Freeing Logic

#### 🏗️ Allocation (`my_malloc`)
1. Compute the number of blocks using `get_size`:
   ```
   <= 64B  → 1 block
   <= 128B → 2 blocks
   <= 256B → 4 blocks
   ```
2. Try to allocate from the tail of the pool (`tail_malloc`) if space is available.  
3. If not, attempt to reuse freed memory via `bin_find`, or perform a linear search (`linear_find`).  
4. Update `bitmap` and `sizemap` with `update_maps` to mark blocks as allocated.

#### ♻️ Freeing (`my_free`)
1. Push the freed address onto the `bin` stack (`push_bin`).  
2. Compute the block indices using `get_index`.  
3. Use `free_sizemap` to determine how many blocks belong to the allocation.  
4. Clear the corresponding bits in both maps using `free_bitmap`.

---

### ⚡ Optimization Strategies
- **Tail allocation** minimizes search time for consecutive allocations.  
- **Stack reuse (bin)** speeds up reallocations of recently freed blocks.  
- **Compact bitmaps** reduce metadata overhead to a few KB.  
- **RIP-relative addressing** ensures compatibility with position-independent executables (PIE).

---

### 🧪 Testing
The provided `test.c` performs:
1. Full memory fill test  
2. Randomized malloc/free stress test  
3. Data integrity verification (no corruption)  
4. Timing measurement for performance evaluation  

Run locally with:

```bash
make
./test
```

or stress test:

```bash
./run.sh
```

---

### 🧱 Memory Visualization Example

```
Bitmap:   1 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
Sizemap:  0 0 0 1 1 1 0 1 1 1 0 1 0 1 0 0

Legend:
1 = allocated | 0 = free
```

---

### 🔍 Functions Overview

| Function | Description |
|-----------|-------------|
| `my_malloc_init` | Initializes internal structures and registers |
| `my_malloc(size)` | Allocates a memory block of at least `size` bytes |
| `my_free(ptr)` | Frees the previously allocated block |
| `tail_malloc`, `find_block`, `bin_find`, `linear_find` | Search strategies for free blocks |
| `update_maps`, `free_sizemap`, `free_bitmap` | Map management utilities |
| `set_bit`, `reset_bit`, `get_bit` | Bit-level operations |
| `push_bin`, `pop_bin` | Stack management for recently freed addresses |

---

### 🧑‍💻 Authors & Acknowledgements
Developed as part of the **Computer Architecture course** assignment,  
focused on implementing a working `malloc` in pure assembly.

---

**License:** MIT  
**Language:** x86-64 Assembly  
**Memory Pool Size:** 10 MB  
**Block Size:** 64 B  

---

## 🇮🇹 Versione Italiana

### 🎯 Descrizione del Progetto
Questo progetto implementa una versione semplificata delle funzioni `malloc` e `free` **interamente in assembly x86-64**, utilizzando una **memory pool statica da 10 MB**.  
L’obiettivo è comprendere il funzionamento interno di un allocatore di memoria, gestendo manualmente blocchi, bitmap e strategie di rilascio senza l’uso di librerie standard.

---

### ⚙️ Struttura del Repository

| File | Descrizione |
|------|--------------|
| `malloc.S` | Implementazione principale dell’allocatore di memoria |
| `test.c` | Programma di test in C per verificarne correttezza e performance |
| `Makefile` | Compila e collega il codice assembly ai test |
| `run.sh` | Esegue ripetutamente i test di stress |
| `.gitignore`, `classroom.yml` | File di configurazione per GitHub Classroom |

---

### 🧩 Architettura dell’Allocatore

#### 📦 Memory Pool
Tutta la memoria gestita risiede in un buffer globale:

```asm
.comm memory_pool, 10485760, 16   # 10 MB
```

La memoria è divisa in **blocchi da 64 byte**, per un totale di **163.840 blocchi**.

---

### 🗺️ Strutture Dati Utilizzate

L’allocatore utilizza **tre strutture principali** e un contatore globale (`last_index`):

1. **Bitmap (`bitmap`)**  
   Tiene traccia dello stato dei blocchi:  
   - `0` → libero  
   - `1` → occupato  

2. **Sizemap (`sizemap`)**  
   Indica se un blocco appartiene a una stessa allocazione multipla.  
   Consente a `free()` di capire quanti blocchi liberare.

3. **Bin (stack degli indirizzi liberi)**  
   Stack contenente gli indirizzi recentemente liberati.  
   - `push_bin`: inserisce un indirizzo libero  
   - `pop_bin`: recupera un indirizzo da riutilizzare  

4. **`last_index`**  
   Tiene traccia dell’ultimo blocco allocato per velocizzare le operazioni successive.

---

### 🧮 Funzionamento di Allocazione e Deallocazione

#### 🏗️ Allocazione (`my_malloc`)
1. Determina quanti blocchi servono con `get_size` (1, 2 o 4).  
2. Prova ad allocare in coda con `tail_malloc`.  
3. Se non c’è spazio, cerca nel bin (`bin_find`) o esegue una ricerca lineare (`linear_find`).  
4. Aggiorna le mappe (`bitmap` e `sizemap`) con `update_maps`.

#### ♻️ Deallocazione (`my_free`)
1. Inserisce l’indirizzo nello stack `bin`.  
2. Calcola l’indice del blocco con `get_index`.  
3. Usa `free_sizemap` per sapere quanti blocchi liberare.  
4. Libera i bit corrispondenti con `free_bitmap`.

---

### ⚡ Strategie di Ottimizzazione
- **Allocazione in coda** per ridurre i tempi di ricerca.  
- **Riutilizzo tramite stack** per migliorare le prestazioni.  
- **Bitmap compatte** per ridurre l’overhead in memoria.  
- **Indirizzamento RIP-relative** per compatibilità con eseguibili PIE.

---

### 🧪 Test e Validazione
Il file `test.c` esegue:
1. Test di riempimento completo della memoria.  
2. Stress test con allocazioni e deallocazioni casuali.  
3. Controllo dell’integrità dei dati.  
4. Misurazioni di performance.  

Esegui i test con:

```bash
make
./test
```

oppure:

```bash
./run.sh
```

---

### 🧱 Esempio di Stato della Memoria

```
Bitmap:   1 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
Sizemap:  0 0 0 1 1 1 0 1 1 1 0 1 0 1 0 0

Legenda:
1 = blocco occupato | 0 = blocco libero
```

---

### 🧑‍💻 Autori e Riconoscimenti
Progetto sviluppato come parte del corso di **Architettura degli Elaboratori**,  
con l’obiettivo di implementare una `malloc` funzionante in puro Assembly.

---

**Licenza:** MIT  
**Linguaggio:** Assembly x86-64  
**Dimensione Memory Pool:** 10 MB  
**Dimensione Blocco:** 64 B  

# -------------------------------------------------------------------------------------------------------------------------------------
#   DETTAGLI IMPLEMENTAZIONE:
#       
#       Nella nostra implementazione abbiamo usato 3 strutture dati principali e un contatore globale (usato come puntatore, last_index). 
#       Riguardo le 3 strutture dati:  
#       - la prima bitmap tiene conto dello stato attuale della memory pool inserendo uno 0 nelle celle libere e un 1 in quelle   
#         occupate. 
#       - la seconda bitmap (sizemap) permette di controllare se un determinato blocco appartenga ad una parte più grande di memoria  
#         allocata. In corrispondenza ad ogni blocco contiene 1 se il successivo fa parte della stessa allocazione e 0 altrimenti.
#        Entrambe le bitmap sono state implementate come un array di byte di dimensione 20480 (10485760 / 64 "grandezza in byte di un blocco"
#       / 8 "numero di bit in un byte")
#
#       ES:  caso in cui ci siano una allacazione da un blocco, due blocchi vuoti (perchè liberati), due allocazioni da 4 blocchi, due allocazioni 
#            da due blocchi e un ultimo blocco vuoto
#
#       -- Bitmap        
#         1   0   0   4               4               2       2
#       |---+---+---+---+---+---+---+---|---+---+---+---+---+---+---+---|
#       | 1 | 0 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 |
#       |---+---+---+---+---+---+---+---|---+---+---+---+---+---+---+---|
#
#       -- Sizemap 
#         1   0   0   4               4               2       2            
#       |---+---+---+---+---+---+---+---|---+---+---+---+---+---+---+---|
#       | 0 | 0 | 0 | 1 | 1 | 1 | 0 | 1 | 1 | 1 | 0 | 1 | 0 | 1 | 0 | 0 |
#       |---+---+---+---+---+---+---+---|---+---+---+---+---+---+---+---|
#
#        - la terza è uno stack (bin) che tiene conto degli ultimi indirizzi liberati, si effettua un push ogni volta che un blocco viene liberato
#          e un pop quando quest'utlimo viene utilizzato per l'allocazione 
#
#        Per quanto riguarda l'allocazione:
#           Per prima cosa si utilizza last_index che tiene conto dell'ultimo indirizzo allocato; altrimenti si utilizza l'indirizzo in cima al bin e 
#           nel momento in cui questo risulti vuoto si esegue una ricerca lineare sulla bitmap 
#
# -------------------------------------------------------------------------------------------------------------------------------------

.org 0x800

# Queste direttive sono utilizzate dal linker per esporre le funzioni al file test.c e consentire l'esecuzione del programma
.globl  my_malloc_init
.type   my_malloc_init, @function
.globl  my_free
.type   my_free, @function
.globl  my_malloc
.type   my_malloc, @function

# Questa direttiva rende lo stack non eseguibile
.section .note.GNU-stack,"",@progbits

.data
# Se necessario, definire qui nuove variabili necessarie a supportare la malloc
    
    last_index: .quad 0             # indice che tiene conto dell'ultimo indirizzo allocato
    bitmap: .fill 20480, 1, 0       # array di byte che tiene conto dei blocchi occupati in memory pool
    sizemap: .fill 20480, 1, 0      # array fi byte che permette di sapere quanti blocchi contigui fanno parte della stessa allocazione
    bin: .fill 2042, 8, 0           # stack di indirizzi liberi

# Qui sotto viene definito il buffer memory_pool di 10 MB.

.comm   memory_pool, 10485760, 16

# Inizializzo rbx per usarlo in push_bin e pop_bin
.text
my_malloc_init:
    xorq %rbx, %rbx
    retq

# void* MY_MALLOC(int bytes): 
# @param RDI = numero di byte da allocare
# @ret RAX = QUAD indirizzo del primo blocco dell'allocazione
# MEMORIA:
#  -8: block_size (può essere 1,2,4)
# -16: block_address
my_malloc:
    pushq %rbp
    movq %rsp, %rbp
    subq $16, %rsp
    xorq %rax, %rax

    # Chiama get_size per calcolare il numero di blocchi dell'allocazione
    call get_size
    movq %rax, -0x8(%rbp)
    movq %rax, %rdi

    # Controlla se last_index è arrivato alla fine della memory_pool
    mov last_index(%rip), %r13
    addq -0x8(%rbp), %r13
    cmp $163840, %r13
    ja .find_bll
    movq -0x8(%rbp), %rdi
    call tail_malloc
    jmp .update
    
    # Chiama find_block e controlla se la ricerca ha avuto successo
    .find_bll:
    call find_block
    movq %rax, -0x10(%rbp)
    cmpq $0, %rax
    je .end_malloc
    jmp .update

    # Aggiorna le due bitmap dopo aver trovato l'indirizzo
    .update:
        movq %rax, -0x10(%rbp)
        movq %rax, %rdi
        movq -0x8(%rbp), %rsi
        call update_maps
        movq -0x10(%rbp), %rax    
        
    .end_malloc:
        movq %rbp, %rsp
        popq %rbp

        retq

# void MY_FREE(void* address): 
# @param RDI = indirizzo dell'allocazione da liberare
# @ret void
# MEMORIA:
#  -8: indice corrispondente al byte da liberare nelle mappe 
# -16: indice corrispondente al bit da liberare nelle mappe
my_free:
    pushq %rbp
    movq %rsp, %rbp
    subq $16, %rsp

    call push_bin

    # Calcolo gli indici delle celle da liberare
    call get_index
    movq %rax, -0x8(%rbp)       
    movq %rdx, -0x10(%rbp)     
    
    # Libero la sizemap
    movq -0x8(%rbp), %rdi
    movq -0x10(%rbp), %rsi
    call free_sizemap
    movq %rax, %rdx       # RDX per prossima funzione 

    # Libero la bitmap
    movq -0x8(%rbp), %rdi
    movq -0x10(%rbp), %rsi
    call free_bitmap
    
    movq %rbp, %rsp
    popq %rbp

    retq

# §--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++§
# SUBROUTINES

# int GET_SIZE(int bytes): 
# @param RDI = numero di byte da allocare
# @ret int RAX = block_num, numero di blocchi da allocare

# IMPLEMENTAZIONE
# Calcolare il numero di blocchi in base ai bytes richiesti: 
#   bytes <= 64 ----> RAX = 1
#   64 < bytes <= 128 ----> RAX = 2
#   128 < bytes <= 256 ----> RAX = 4
get_size:
    xorq %rax, %rax

    .check_64:
        cmpq $64, %rdi
        ja .check_128
        movq $1, %rax   
        jmp .endif
    .check_128:
        cmpq $128, %rdi
        ja .check_256
        movq $2, %rax   
        jmp .endif
    .check_256:
        movq $4, %rax   
    
    .endif:
        retq


# void* TAIL_MALLOC(void): 
# @ret void* RAX = indirizzo di inizio allocazione

# IMPLEMENTAZIONE
# Considero last_index lo moltiplico per la grandezza del blocco e
# lo sommo all'indirizzo di partenza di memory_pool.
# Ritorno quindi l'indirizzo calcolato
tail_malloc:
    mov last_index(%rip), %rax
    movq $64, %rcx
    mul %rcx
    lea memory_pool(%rip), %rcx
    add %rcx, %rax
    addq %rdi, last_index(%rip)
    retq


# void* FIND_BLOCK(int block_num): 
# @param RDI = numero di blocchi dell'allocazione
# @ret void* RAX = indirizzo di inizio allocazione | 0 se non trova blocchi liberi
# MEMORIA:
#  -8: parametro block_num 

# IMPLEMENTAZIONE
# Chiamo i due metodi di ricerca dell'indirizzo, bin_find e linear_find
find_block:
    pushq %rbp
    movq %rsp, %rbp
    subq $8, %rsp
    
    movq %rdi, -0x8(%rbp)
    xorq %r11, %r11

    # Provo a trovare dei blocchi liberi nel bin 
    call bin_find
    cmpq $0, %rax
    jne .fine_find

    # Se il bin è vuoto faccio la ricerca lineare
    movq -0x8(%rbp), %rdi
    call linear_find
        
    .fine_find:
        movq %rbp, %rsp
        popq %rbp
        retq


# void* BIN_FIND(int block_num): 
# @param RDI = numero di blocchi dell'allocazione
# @ret void* RAX = indirizzo di inizio allocazione | 0 se il bin è vuoto
# MEMORIA:
#  -8: parametro block_num 

# IMPLEMENTAZIONE
# Prende l'elemento in cima al bin (se è vuoto ritorna 0), controlla se sono presenti 
# abbastanza blocchi successivi vuoti. Se li trova ritorna l'indirizzo altrimenti 
# prende il prossimo elemento e riprova finchè il bin non è vuoto.
# Calcola l'indirizzo usando gli indici del bit e del byte relativi alla bitmap.
bin_find:
    pushq %rbp
    movq %rsp, %rbp
    subq $8, %rsp

    movq %rdi, -0x8(%rbp)

    # Prendo l'indirizzo in cima allo stack
    .start_bin:
    call pop_bin
    cmpq $0, %rax
    je .fine_bin 
    
    movq %rax, %rdi
    call get_index
    movq %rax, %rcx
    movq %rdx, %r9

    xorq %r8, %r8
    lea bitmap(%rip), %r15

    .bin_check:
        movb (%r15, %rcx, 1), %r8b

        .address_loop:
            movq %r8, %rdi
            movq %r9, %rsi

            pushq %rcx
            call get_bit
            popq %rcx

             # Se è 0 continuo altrimenti vuol dire che è occupato e cambio elemento
            cmpq $0, %rax  
            je .update_bin
            movq $0, %r11
            jmp .start_bin

            # Controllo se ho trovato gli n blocchi, se non li ho ancora finiti rifaccio il ciclo altrimenti esco
            .update_bin:
                addq $1, %r11
                cmpq -0x8(%rbp), %r11  
                jne .incremento_bin

            # Calcolo l'indirizzo del blocco trovato come ((indice byte)*8 + indice bit +1) - (block_num))
            .bin_found:                 
                movq %rcx, %rax         
                movq $8, %rcx
                mul %rcx
                addq %r9, %rax
                addq $1, %rax
                subq -0x8(%rbp), %rax
                movq $64, %rcx
                mul %rcx
                lea memory_pool(%rip), %rcx
                addq %rcx, %rax
                jmp .fine_bin

            .incremento_bin:
                addq $1, %r9
                cmpq $8, %r9
                jne .address_loop
                addq $1, %rcx
                xorq %r9, %r9
                jmp .bin_check

    .fine_bin:
        movq %rbp, %rsp
        popq %rbp
        retq


# void* LINEAR_FIND(int block_num): 
# @param RDI = numero di blocchi dell'allocazione
# @ret void* RAX = indirizzo di inizio allocazione | 0 se non trova blocchi liberi
# MEMORIA:
#  -8: parametro block_num 

# IMPLEMENTAZIONE
# Ricerca linearmente lungo tutta la bitmap se sono presenti abbastanza blocchi contigui liberi per 
# soddisfare la richiesta. Calcola l'indirizzo usando gli indici del bit e del byte relativi alla bitmap.
linear_find:
    pushq %rbp
    movq %rsp, %rbp
    subq $8, %rsp
    
   
    xorq %rcx, %rcx
    xorq %r8, %r8
    xorq %r11, %r11
    movq %rdi, -0x8(%rbp)
    lea bitmap(%rip), %r14
    
    # Ricerco linearmente in tutti i blocchi, r8 è il byte e r9 è il bit
    .block_loop:    
        movb (%r14, %rcx, 1), %r8b
        xorq %r9, %r9           

        # Eseguo il controllo sui singoli bit fino a trovarne abbastanza vuoti 
        .bit_loop:
            movq %r8, %rdi
            movq %r9, %rsi

            pushq %rcx
            call get_bit
            popq %rcx

            cmpq $0, %rax
            # Se trovo uno 0 incremento il contatore
            je .aggiornamento
            movq $0, %r11
            jmp .incremento

            # Controllo se ho trovato abbastanza blocchi liberi
            .aggiornamento:
                addq $1, %r11
                cmpq -0x8(%rbp), %r11
                jne .incremento
                       
            # Calcolo l'indirizzo del blocco trovato come ((indice byte)*8 + indice bit +1) - (block_num) e salto alla fine
            .linear_found:
                movq %rcx, %rax           
                movq $8, %rcx
                mul %rcx
                addq %r9, %rax
                addq $1, %rax
                subq -0x8(%rbp), %rax
                movq $64, %rcx
                mul %rcx
                lea memory_pool(%rip), %rcx
                addq %rcx, %rax
                jmp .fine_linear

            # Aumento l'indice del bit e controllo se sono a fine byte in caso incremento
            .incremento:
                addq $1, %r9
                cmpq $8, %r9
                jne .bit_loop
                addq $1, %rcx
                cmpq $20480, %rcx
                je .banana
                jmp .block_loop

        .banana:
            movq $0, %rax   
        
        .fine_linear:
        movq %rbp, %rsp
        popq %rbp
        retq


# void UPDATE_MAPS(void* start_address, int block_num): 
# @param RDI = start_address, indirizzo di partenza dell'allocazione
#        RSI = block_num, numero di blocchi dell'allocazione
# @ret void* RAX = indirizzo di inizio allocazione | 0 se non trova blocchi liberi
# MEMORIA:
#  -8: parametro block_num 

# IMPLEMENTAZIONE
# Esegue sulla bitmap e la sizemap le stesse operazioni:
# Partendo dall'indirizzo passato come parametro calcola gli indici del byte e del bit corrispondenti.
# Inizia poi ad aggiornare la cella indicata finchè non esaurisce il block_num.
# In particolare nella sizemap il block_num viene decrementato di 1 
update_maps:
    pushq %rbp
    movq %rsp, %rbp
    subq $8, %rsp
    xorq %r12, %r12
    
    movq %rsi, -0x8(%rbp)
    push %rsi
    call get_index              

    movq %rax, %rcx
    push %rcx
    movq %rdx, %r9              
    push %rdx
    lea bitmap(%rip), %r14

    .update_start:
        xorq %r10, %r10
        
        .map_bit:
            movb (%r14, %rcx, 1), %r10b
            movq %r10, %rdi
            movq %r9, %rsi
            push %rcx
            call set_bit
            pop %rcx
            movb %al, (%r14, %rcx, 1)
            subq $1, -0x8(%rbp)
            cmpq $0, -0x8(%rbp)
            je .end_map
            addq $1, %r9
            cmpq $8, %r9
            jne .map_bit
            xorq %r9, %r9
            addq $1, %rcx
            jmp .update_start

    .end_map:
    cmpq $1, %r12
    je .fine_funzione
    pop %rdx
    pop %rcx
    pop %rsi
    subq $1, %rsi
    movq %rsi, -0x8(%rbp)
    cmpq $0, -0x8(%rbp)
    je .fine_funzione
    addq $1, %r12
    movq %rdx, %r9

    # Passo da Bitmap a Sizemap
    lea sizemap(%rip), %r14
    jmp .update_start
    
    .fine_funzione:
        movq %rbp, %rsp
        popq %rbp

        retq

    

# int FREE_SIZEMAP(int start_byte, int start_index): 
# @param RDI = start_byte, indice del byte da cui effettuare la modifica
#        RSI = start_index, indice del bit da cui effettuare la modifica
# @ret int RAX = 1 se sono stati liberati 0 blocchi, 2 se è stato liberato 1 blocco e 4 se sono stati liberati 3 blocchi

# IMPLEMENTAZIONE
# Partendo dal byte e dal bit forniti come parametri resetta i bit finchè non trova una cella che vale 0
free_sizemap:
    lea sizemap(%rip), %r15
    movq $1, %r13
    movq %rdi, %rcx
    movq %rsi, %r9

    .start_free_sizemap:
        xorq %r10, %r10
    
        .free_size_bit:
            # Considero il byte da aggiornare
            movb (%r15, %rcx, 1), %r10b
            movq %r10, %rdi
            movq %r9, %rsi

            pushq %rcx
            call get_bit
            popq %rcx

            cmpq $0, %rax
            je .ret_free_sizemap

            # Se il bit non è zero lo resetto
            pushq %rcx
            call reset_bit
            popq %rcx
            
            # Aggiorno il byte modificato
            movb %al, (%r15, %rcx, 1)
            addq $1, %r13
            addq $1, %r9
            cmpq $8, %r9
            
            # Se sono giunto alla fine salto al prossimo byte
            jne .free_size_bit
            xorq %r9, %r9
            addq $1, %rcx
            jmp .start_free_sizemap

    .ret_free_sizemap:
        movq %r13, %rax
        retq


# void FREE_BITMAP(int start_byte, int start_index, int block_num): 
# @param RDI = start_byte, indice del byte da cui effettuare la modifica
#        RSI = start_index, indice del bit da cui effettuare la modifica
#        RDX = block_num, numero di blocchi da liberare
# @ret void RAX 

# IMPLEMENTAZIONE
# Partendo dal byte e dal bit forniti come parametri resetta i bit block_num volte
free_bitmap:
    pushq %rbp
    movq %rsp, %rbp
    subq $8, %rsp

    lea bitmap(%rip), %r14
    movq %rdi, %rcx
    movq %rsi, %r9
    movq %rdx, -0x8(%rbp)

    .free_bitmap:
        xorq %r10, %r10
        
        .free_bit_bit:
            # Considero il byte da aggiornare e resetto il bit interessato
            movb (%r14, %rcx, 1), %r10b
            movq %r10, %rdi
            movq %r9, %rsi
            pushq %rcx
            call reset_bit
            popq %rcx

            # Aggiorno il byte modificato e se sono alla fine esco
            movb %al, (%r14, %rcx, 1)
            subq $1, -0x8(%rbp)
            cmpq $0, -0x8(%rbp)
            je .fine_free

            # Se non ho finito passo al prossimo bit
            addq $1, %r9
            cmpq $8, %r9
            jne .free_bit_bit

             # Se non ho finito passo al prossimo byte
            xorq %r9, %r9
            addq $1, %rcx
            jmp .free_bitmap

    .fine_free:
        movq %rbp, %rsp
        popq %rbp
        retq


# (int, int) GET_INDEX(void* addrs): 
# @param RDI = addrs, indirizzo da convertire 
# @ret int RAX = indice byte
#      int RDX = indice bit

# IMPLEMENTAZIONE
# Calcola indici byte e bit della bitmap, dell'indirizzo addrs relativo a memory_pool.
# Divide la differenza tra addrs e memory_pool per la dimensione del singolo blocco(64 byte),
# il quoziente rappresenta l'indice del byte mentre il resto quello del bit
get_index: 
    lea memory_pool(%rip), %rdx
    subq %rdx, %rdi 
    xorq %rdx,%rdx
    movq %rdi, %rax
    movq $64, %rcx
    div %rcx
    movq $8, %rcx
    div %rcx

    retq
    
# int SET_BIT(int start_byte, int i): 
# @param RDI = start_byte, indice del byte da cui effettuare la modifica
#        RSI = i, indice del bit 
# @ret int RAX = byte modificato

# IMPLEMENTAZIONE
# Creo una maschera e setto l'i-esimo bit del byte
set_bit:
    # Carico la maschera 0b00000001
    movb $1, %al             
    movq $7, %rcx
    # Calcola 7 - indice del bit
    subq %rsi, %rcx 
    # Sposto il bit nella posizione corretta         
    shl %cl, %al             
    orb %al, %dil   
    # Ritorno il byte aggiornato        
    movb %dil, %al           
    ret

# int RESET_BIT(int start_byte, int i): 
# @param RDI = start_byte, indice del byte da cui effettuare la modifica
#        RSI = i, indice del bit 
# @ret int RAX = byte modificato

# IMPLEMENTAZIONE
# Creo una maschera e resetto l'i-esimo bit del byte
reset_bit:
    pushq %rbp
    movq %rsp, %rbp
    xorq %rax, %rax
    sub  $0x1, %rsp

    # Creazione maschera di bit per azzerare i-esimo bit
    movb $0b00000001, %al 
    movq $7, %rcx
    # 7 - i per ottenere indice nella parola binaria (numero posizioni da shiftare)
    subl %esi, %ecx 
    shl %cl, %al

    movb %al, -0x1(%rbp)

    movb $0b11111111, %al
    sub -0x1(%rbp), %al    

    # And tra byte e maschera per resettare l'i-esimo
    andb %dil, %al  

    movq %rbp, %rsp
    popq %rbp

    ret

# int GET_BIT(int start_byte, int i): 
# @param RDI = start_byte, indice del byte da cui effettuare la modifica
#        RSI = i, indice del bit 
# @ret int RAX = byte salvato

# IMPLEMENTAZIONE
# Creo una maschera e salvo l'i-esimo bit del byte
get_bit:
    xorq %rax, %rax
    movq $7, %rcx
    subb %sil, %cl # 7 - i per ottenere indice nella parola binaria (numero posizioni da shiftare)
    movb %dil, %al
    shr %cl, %al

    andb $1, %al

    ret


# void* POP_BIN(): 
# @ret void* RAX = indirizzo salvato sulla cima del bin | 0 se vuoto

# IMPLEMENTAZIONE
# Operazione di pop sullo stack bin
pop_bin:
    movq %rbx, %rax
    cmpq $0, %rax
    je .pop_error
    subq $1, %rbx
    lea bin(%rip), %r10
    movq (%r10,%rbx,8), %rax  
    movq $0, (%r10,%rbx,8)
    .end_pop:
    ret

    .pop_error:
    movq $0, %rax
    jmp .end_pop


# void PUSH_BIN(void* addrs): 
# @param void* RDI = indirizzo da salvare sulla cima del bin 
# @ ret void

# IMPLEMENTAZIONE
# Operazione di push sullo stack bin
push_bin:
    movq %rbx, %rcx
    cmpq $2042, %rcx
    je .end_push
    lea bin(%rip), %r10
    movq %rdi, (%r10,%rcx,8)
    addq $1, %rbx
    .end_push:
    ret

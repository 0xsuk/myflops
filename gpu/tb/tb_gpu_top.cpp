#include <cstdio>
#include <cstdlib>
#include "Vgpu_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static vluint64_t sim_time = 0;
static Vgpu_top* dut;
static VerilatedVcdC* tfp;

void tick() {
    dut->clk = 0;
    dut->eval();
    tfp->dump(sim_time++);
    dut->clk = 1;
    dut->eval();
    tfp->dump(sim_time++);
}

void write_imem(int addr, int data) {
    dut->imem_we = 1;
    dut->imem_waddr = addr;
    dut->imem_wdata = data;
    tick();
    dut->imem_we = 0;
}

void write_gmem(int addr, uint32_t data) {
    dut->gmem_ext_we = 1;
    dut->gmem_ext_addr = addr;
    dut->gmem_ext_wdata = data;
    tick();
    dut->gmem_ext_we = 0;
}

uint32_t read_gmem(int addr) {
    dut->gmem_ext_re = 1;
    dut->gmem_ext_we = 0;
    dut->gmem_ext_addr = addr;
    tick();
    tick();
    uint32_t val = dut->gmem_ext_rdata;
    dut->gmem_ext_re = 0;
    return val;
}

void load_and_run(int* prog, int len) {
    dut->rst_n = 0;
    dut->start = 0;
    dut->imem_we = 0;
    dut->gmem_ext_re = 0;
    dut->gmem_ext_we = 0;
    for (int i = 0; i < 3; i++) tick();

    for (int i = 0; i < len; i++)
        write_imem(i, prog[i]);

    dut->rst_n = 1;
    tick();
    tick();

    dut->start = 1;
    tick();
    dut->start = 0;

    for (int i = 0; i < 500; i++) tick();
}

enum { OP_ADD=0, OP_SUB=1, OP_MUL=2, OP_AND=3, OP_OR=4, OP_XOR=5,
       OP_SHL=6, OP_SHR=7, OP_LDR=8, OP_STR=9, OP_LI=0xA,
       OP_BEQ=0xB, OP_BNE=0xC, OP_JMP=0xD, OP_SPC=0xE, OP_FADD=0xF };
enum { SPC_NOP=0, SPC_HALT=1, SPC_TID=2, SPC_LDS=3, SPC_STS=4, SPC_BAR=5 };

int enc_r(int op, int rd, int rs1, int rs2) { return (op<<12)|(rd<<8)|(rs1<<4)|rs2; }
int enc_li(int rd, int imm8) { return (OP_LI<<12)|(rd<<8)|(imm8&0xFF); }
int enc_str(int src, int base, int off) { return (OP_STR<<12)|(src<<8)|(base<<4)|(off&0xF); }
int enc_spc(int sub, int a1, int a2) { return (OP_SPC<<12)|(sub<<8)|(a1<<4)|a2; }
int enc_beq(int rs1, int rs2, int off) { return (OP_BEQ<<12)|(rs1<<8)|(rs2<<4)|(off&0xF); }
int enc_bne(int rs1, int rs2, int off) { return (OP_BNE<<12)|(rs1<<8)|(rs2<<4)|(off&0xF); }
int enc_jmp(int imm12) { return (OP_JMP<<12)|(imm12&0xFFF); }

int test_pass = 0, test_fail = 0;

void check(const char* name, uint32_t got, uint32_t expected) {
    if (got == expected) {
        printf("  PASS: %s = %u\n", name, got);
        test_pass++;
    } else {
        printf("  FAIL: %s = %u (expected %u)\n", name, got, expected);
        test_fail++;
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    dut = new Vgpu_top;
    tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("gpu_test.vcd");

    printf("=== Test 1: LI + ADD + STR ===\n");
    {
        int prog[] = {
            enc_li(1, 10),            // r1 = 10
            enc_li(2, 20),            // r2 = 20
            enc_r(OP_ADD, 3, 1, 2),   // r3 = r1 + r2 = 30
            enc_li(4, 0),             // r4 = 0
            enc_str(3, 4, 0),         // gmem[r4+0] = r3
            enc_spc(SPC_HALT, 0, 0)
        };
        load_and_run(prog, 6);
        check("gmem[0]", read_gmem(0), 30);
    }

    printf("=== Test 2: SUB ===\n");
    {
        int prog[] = {
            enc_li(1, 50),
            enc_li(2, 15),
            enc_r(OP_SUB, 3, 1, 2),
            enc_li(4, 1),
            enc_str(3, 4, 0),
            enc_spc(SPC_HALT, 0, 0)
        };
        load_and_run(prog, 6);
        check("gmem[1]", read_gmem(1), 35);
    }

    printf("=== Test 3: MUL ===\n");
    {
        int prog[] = {
            enc_li(1, 7),
            enc_li(2, 6),
            enc_r(OP_MUL, 3, 1, 2),
            enc_li(4, 2),
            enc_str(3, 4, 0),
            enc_spc(SPC_HALT, 0, 0)
        };
        load_and_run(prog, 6);
        check("gmem[2]", read_gmem(2), 42);
    }

    printf("=== Test 4: AND/OR/XOR ===\n");
    {
        int prog[] = {
            enc_li(1, 0x0F),
            enc_li(2, 0x33),
            enc_r(OP_AND, 3, 1, 2),   enc_li(4, 3), enc_str(3, 4, 0),
            enc_r(OP_OR,  5, 1, 2),   enc_li(6, 4), enc_str(5, 6, 0),
            enc_r(OP_XOR, 7, 1, 2),   enc_li(8, 5), enc_str(7, 8, 0),
            enc_spc(SPC_HALT, 0, 0)
        };
        load_and_run(prog, 12);
        check("AND", read_gmem(3), 0x0F & 0x33);
        check("OR",  read_gmem(4), 0x0F | 0x33);
        check("XOR", read_gmem(5), 0x0F ^ 0x33);
    }

    printf("=== Test 5: TID ===\n");
    {
        int prog[] = {
            enc_spc(SPC_TID, 1, 0),   // r1 = thread_id
            enc_li(2, 10),             // r2 = 10
            enc_str(1, 2, 0),          // gmem[10] = r1
            enc_spc(SPC_HALT, 0, 0)
        };
        load_and_run(prog, 4);
        uint32_t tid = read_gmem(10);
        printf("  TID stored: %u\n", tid);
        if (tid < 4) { printf("  PASS\n"); test_pass++; }
        else         { printf("  FAIL\n"); test_fail++; }
    }

    printf("=== Test 6: LDR/STR ===\n");
    {
        write_gmem(20, 123);

        int prog[] = {
            enc_li(1, 20),                   // r1 = 20 (addr)
            (OP_LDR<<12)|(2<<8)|(1<<4)|0,    // r2 = gmem[r1+0]
            enc_li(3, 1),                    // r3 = 1
            enc_r(OP_ADD, 4, 2, 3),          // r4 = r2 + r3 = 124
            enc_li(5, 21),                   // r5 = 21
            enc_str(4, 5, 0),                // gmem[21] = r4
            enc_spc(SPC_HALT, 0, 0)
        };
        load_and_run(prog, 7);
        check("gmem[21]", read_gmem(21), 124);
    }

    printf("=== Test 7: BEQ (taken) ===\n");
    {
        int prog[] = {
            enc_li(1, 5),             // 0: r1 = 5
            enc_li(2, 5),             // 1: r2 = 5
            enc_li(3, 99),            // 2: r3 = 99 (will be overwritten if branch works)
            enc_beq(1, 2, 2),         // 3: if r1==r2, jump to 3+2=5
            enc_li(3, 77),            // 4: r3 = 77 (should be skipped)
            enc_li(3, 42),            // 5: r3 = 42 (branch target)
            enc_li(4, 30),            // 6: r4 = 30
            enc_str(3, 4, 0),         // 7: gmem[30] = r3
            enc_spc(SPC_HALT, 0, 0)   // 8: halt
        };
        load_and_run(prog, 9);
        check("BEQ taken", read_gmem(30), 42);
    }

    printf("=== Test 8: BEQ (not taken) ===\n");
    {
        int prog[] = {
            enc_li(1, 5),             // 0: r1 = 5
            enc_li(2, 10),            // 1: r2 = 10
            enc_li(3, 99),            // 2: r3 = 99
            enc_beq(1, 2, 2),         // 3: if r1==r2, jump to 5 (NOT taken)
            enc_li(3, 77),            // 4: r3 = 77 (should execute)
            enc_li(3, 42),            // 5: r3 = 42 (also executes, overwrites)
            enc_li(4, 31),            // 6: r4 = 31
            enc_str(3, 4, 0),         // 7: gmem[31] = r3
            enc_spc(SPC_HALT, 0, 0)   // 8: halt
        };
        load_and_run(prog, 9);
        check("BEQ not taken", read_gmem(31), 42);
    }

    printf("=== Test 9: BNE (taken) ===\n");
    {
        int prog[] = {
            enc_li(1, 5),             // 0: r1 = 5
            enc_li(2, 10),            // 1: r2 = 10
            enc_bne(1, 2, 2),         // 2: if r1!=r2, jump to 2+2=4
            enc_li(3, 77),            // 3: should be skipped
            enc_li(3, 42),            // 4: branch target, r3 = 42
            enc_li(4, 32),            // 5: r4 = 32
            enc_str(3, 4, 0),         // 6: gmem[32] = r3
            enc_spc(SPC_HALT, 0, 0)   // 7: halt
        };
        load_and_run(prog, 8);
        check("BNE taken", read_gmem(32), 42);
    }

    printf("=== Test 10: JMP ===\n");
    {
        int prog[] = {
            enc_li(1, 11),            // 0: r1 = 11
            enc_jmp(3),               // 1: jump to addr 3
            enc_li(1, 77),            // 2: should be skipped
            enc_li(2, 33),            // 3: jump target, r2 = 33
            enc_str(1, 2, 0),         // 4: gmem[33] = r1
            enc_spc(SPC_HALT, 0, 0)   // 5: halt
        };
        load_and_run(prog, 6);
        check("JMP", read_gmem(33), 11);
    }

    printf("=== Test 11: SHL/SHR ===\n");
    {
        int prog[] = {
            enc_li(1, 3),             // 0: r1 = 3
            enc_li(2, 4),             // 1: r2 = 4
            enc_r(OP_SHL, 3, 1, 2),   // 2: r3 = 3 << 4 = 48
            enc_li(4, 40),            // 3: r4 = 40
            enc_str(3, 4, 0),         // 4: gmem[40] = 48
            enc_li(5, 64),            // 5: r5 = 64
            enc_li(6, 2),             // 6: r6 = 2
            enc_r(OP_SHR, 7, 5, 6),   // 7: r7 = 64 >> 2 = 16
            enc_li(8, 41),            // 8: r8 = 41
            enc_str(7, 8, 0),         // 9: gmem[41] = 16
            enc_spc(SPC_HALT, 0, 0)   // 10: halt
        };
        load_and_run(prog, 11);
        check("SHL", read_gmem(40), 48);
        check("SHR", read_gmem(41), 16);
    }

    printf("=== Test 12: Shared Memory (LDS/STS) ===\n");
    {
        int prog[] = {
            enc_li(1, 42),                           // 0: r1 = 42 (value)
            enc_li(2, 0),                            // 1: r2 = 0 (smem addr)
            enc_spc(SPC_STS, 1, 2),                  // 2: smem[r2] = r1
            enc_spc(SPC_LDS, 3, 2),                  // 3: r3 = smem[r2]
            enc_li(4, 50),                           // 4: r4 = 50
            enc_str(3, 4, 0),                        // 5: gmem[50] = r3
            enc_spc(SPC_HALT, 0, 0)                  // 6: halt
        };
        load_and_run(prog, 7);
        check("shared mem", read_gmem(50), 42);
    }

    printf("=== Test 13: FADD (1.0 + 2.0 = 3.0) ===\n");
    {
        write_gmem(60, 0x3F800000);  // 1.0f
        write_gmem(61, 0x40000000);  // 2.0f

        int prog[] = {
            enc_li(1, 60),                           // 0: r1 = 60 (addr of 1.0)
            (OP_LDR<<12)|(2<<8)|(1<<4)|0,            // 1: r2 = gmem[60] = 1.0
            enc_li(3, 61),                           // 2: r3 = 61 (addr of 2.0)
            (OP_LDR<<12)|(4<<8)|(3<<4)|0,            // 3: r4 = gmem[61] = 2.0
            enc_r(OP_FADD, 5, 2, 4),                 // 4: r5 = fadd(r2, r4) = 3.0
            enc_li(6, 62),                           // 5: r6 = 62
            enc_str(5, 6, 0),                        // 6: gmem[62] = r5
            enc_spc(SPC_HALT, 0, 0)                  // 7: halt
        };
        load_and_run(prog, 8);
        check("FADD", read_gmem(62), 0x40400000);
    }

    printf("=== Test 14: Loop (sum 1..5 using BNE) ===\n");
    {
        int prog[] = {
            enc_li(1, 5),             // 0: r1 = 5 (counter)
            enc_li(2, 0),             // 1: r2 = 0 (accumulator)
            enc_li(3, 1),             // 2: r3 = 1
            enc_r(OP_ADD, 2, 2, 1),   // 3: r2 = r2 + r1 (loop body)
            enc_r(OP_SUB, 1, 1, 3),   // 4: r1 = r1 - 1
            enc_bne(1, 0, -2),        // 5: if r1!=r0(0), jump to 5+(-2)=3
            enc_li(4, 70),            // 6: r4 = 70
            enc_str(2, 4, 0),         // 7: gmem[70] = r2 (should be 15)
            enc_spc(SPC_HALT, 0, 0)   // 8: halt
        };
        load_and_run(prog, 9);
        check("loop sum 1..5", read_gmem(70), 15);
    }

    printf("=== Test 15: Back-to-back LDR use ===\n");
    {
        write_gmem(80, 100);

        int prog[] = {
            enc_li(1, 80),                           // 0: r1 = 80
            (OP_LDR<<12)|(2<<8)|(1<<4)|0,            // 1: r2 = gmem[80] = 100
            enc_r(OP_ADD, 3, 2, 2),                  // 2: r3 = r2 + r2 = 200 (immediate use)
            enc_li(4, 81),                           // 3: r4 = 81
            enc_str(3, 4, 0),                        // 4: gmem[81] = r3
            enc_spc(SPC_HALT, 0, 0)                  // 5: halt
        };
        load_and_run(prog, 6);
        check("load-use", read_gmem(81), 200);
    }

    printf("=== Test 16: Multi-core TID ===\n");
    {
        int prog[] = {
            enc_spc(SPC_TID, 1, 0),   // 0: r1 = thread_id (core_id)
            enc_li(2, 90),            // 1: r2 = 90 (base addr)
            enc_r(OP_ADD, 3, 2, 1),   // 2: r3 = 90 + core_id
            enc_li(4, 1),             // 3: r4 = 1
            enc_str(4, 3, 0),         // 4: gmem[90+core_id] = 1
            enc_spc(SPC_HALT, 0, 0)   // 5: halt
        };
        load_and_run(prog, 6);
        int multi_ok = 1;
        for (int i = 0; i < 4; i++) {
            uint32_t v = read_gmem(90 + i);
            printf("  core %d: gmem[%d] = %u\n", i, 90+i, v);
            if (v != 1) multi_ok = 0;
        }
        if (multi_ok) { printf("  PASS\n"); test_pass++; }
        else          { printf("  FAIL\n"); test_fail++; }
    }

    printf("=== Test 17: Barrier ===\n");
    {
        // Each core: writes (core_id + 10) to gmem[100 + core_id]
        // Then BAR
        // Then reads gmem[100] (core 0's value = 10) and stores to gmem[110 + core_id]
        int prog[] = {
            enc_spc(SPC_TID, 1, 0),   // 0: r1 = core_id
            enc_li(2, 10),            // 1: r2 = 10
            enc_r(OP_ADD, 3, 1, 2),   // 2: r3 = core_id + 10 (value to write)
            enc_li(4, 100),           // 3: r4 = 100
            enc_r(OP_ADD, 5, 4, 1),   // 4: r5 = 100 + core_id (write addr)
            enc_str(3, 5, 0),         // 5: gmem[100+core_id] = core_id+10
            enc_spc(SPC_BAR, 0, 0),   // 6: barrier
            (OP_LDR<<12)|(6<<8)|(4<<4)|0, // 7: r6 = gmem[100] (core0's value)
            enc_li(7, 110),           // 8: r7 = 110
            enc_r(OP_ADD, 8, 7, 1),   // 9: r8 = 110 + core_id
            enc_str(6, 8, 0),         // 10: gmem[110+core_id] = r6
            enc_spc(SPC_HALT, 0, 0)   // 11: halt
        };
        load_and_run(prog, 12);
        // All cores should have read gmem[100] = 10 (core 0's write)
        int bar_ok = 1;
        for (int i = 0; i < 4; i++) {
            uint32_t v = read_gmem(110 + i);
            printf("  core %d: gmem[%d] = %u (expected 10)\n", i, 110+i, v);
            if (v != 10) bar_ok = 0;
        }
        if (bar_ok) { printf("  PASS\n"); test_pass++; }
        else        { printf("  FAIL\n"); test_fail++; }
    }

    printf("\n=== Results: %d passed, %d failed ===\n", test_pass, test_fail);

    tfp->close();
    delete tfp;
    delete dut;
    return test_fail > 0 ? 1 : 0;
}

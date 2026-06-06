// *********************************************************************
// 单轴双电机防碰撞 + 预等待控制系统 — 功能块
// 版本     : V1.1
// 日期     : 2026-06-06
// 适用 PLC : 信捷 XD/XE 系列
// 新增功能 : 完整手动模式 + 全状态输出 + 多维度报警
// *********************************************************************

FUNCTION_BLOCK FB_SingleAxisDualMotor
VAR_INPUT
    // ====================== 系统模式控制 ======================
    自动模式          : BOOL;   // ON=自动运行，OFF=手动模式
    系统急停          : BOOL;   // 常闭触点，按下=OFF
    报警复位          : BOOL;   // 按下=ON

    // ====================== 手动模式控制输入 ======================
    手动A正向点动     : BOOL;   // A电机向右点动
    手动A反向点动     : BOOL;   // A电机向左点动
    手动B正向点动     : BOOL;   // B电机向右点动
    手动B反向点动     : BOOL;   // B电机向左点动
    手动点动速度      : DINT := 500;

    // ====================== 轴号配置 ======================
    电机A轴号         : UINT := 1;
    电机B轴号         : UINT := 2;

    // ====================== 区域参数配置 ======================
    A专属区右边界     : DINT := 470;
    A等待区右边界     : DINT := 490;
    共享区右边界      : DINT := 510;
    B等待区右边界     : DINT := 530;

    // 目标位置
    A取料位           : DINT := 0;
    A放料位           : DINT := 500;
    B取料位           : DINT := 500;
    B放料位           : DINT := 1000;
    A等待位           : DINT := 470;
    B等待位           : DINT := 530;

    // 运动参数
    自动运动速度      : DINT := 1500;
    加速度            : DINT := 1000;
    减速度            : DINT := 1000;

    // 安全参数
    最小安全距离      : DINT := 30;
    送料优先级高于取料: BOOL := TRUE;  // TRUE=A送料优先

    // ====================== 工艺信号输入 ======================
    A取料完成         : BOOL;
    A放料完成         : BOOL;
    B取料完成         : BOOL;
    B放料完成         : BOOL;
    有料待送          : BOOL;

    // ====================== 伺服反馈输入 ======================
    电机A_当前位置    : DINT;
    电机A_运行中      : BOOL;
    电机A_到位        : BOOL;
    电机A_故障        : BOOL;
    电机B_当前位置    : DINT;
    电机B_运行中      : BOOL;
    电机B_到位        : BOOL;
    电机B_故障        : BOOL;
END_VAR

VAR_OUTPUT
    // ====================== 电机控制输出 ======================
    电机A_目标位置    : DINT;
    电机B_目标位置    : DINT;

    // ====================== 系统状态输出 ======================
    系统就绪          : BOOL;
    自动运行中        : BOOL;
    手动模式中        : BOOL;

    // ====================== 电机 A 状态输出 ======================
    电机A_允许运行    : BOOL;
    电机A_有生产任务  : BOOL;
    电机A_预等待中    : BOOL;
    电机A_在A专属区   : BOOL;
    电机A_在A等待区   : BOOL;
    电机A_在共享区    : BOOL;
    电机A_生产状态    : INT;    // 0=等待取料 1=去取料位 2=取料中 3=去放料位 4=放料中 5=回取料位

    // ====================== 电机 B 状态输出 ======================
    电机B_允许运行    : BOOL;
    电机B_有生产任务  : BOOL;
    电机B_预等待中    : BOOL;
    电机B_在B专属区   : BOOL;
    电机B_在B等待区   : BOOL;
    电机B_在共享区    : BOOL;
    电机B_生产状态    : INT;    // 0=等待取料 1=去取料位 2=取料中 3=去放料位 4=放料中 5=回等待位

    // ====================== 报警输出 ======================
    报警_急停触发     : BOOL;
    报警_防撞触发     : BOOL;
    报警_A越界        : BOOL;
    报警_B越界        : BOOL;
    报警_A伺服故障    : BOOL;
    报警_B伺服故障    : BOOL;
    报警_系统故障     : BOOL;   // 任意报警触发
END_VAR

VAR
    // ====================== 内部状态变量 ======================
    电机A_运动方向    : INT;    // 0=静止 1=向右 -1=向左
    电机B_运动方向    : INT;    // 0=静止 1=向右 -1=向左
    内部急停复位      : BOOL;
END_VAR

// ====================== 最高优先级：急停与报警处理 ======================
报警_急停触发 := NOT 系统急停;
IF 报警_急停触发 THEN
    MC_Stop(Axis:=电机A轴号, Execute:=TRUE);
    MC_Stop(Axis:=电机B轴号, Execute:=TRUE);
    电机A_生产状态   := 0;
    电机B_生产状态   := 0;
    电机A_有生产任务 := FALSE;
    电机B_有生产任务 := FALSE;
    电机A_预等待中   := FALSE;
    电机B_预等待中   := FALSE;
END_IF;

// 伺服故障报警
报警_A伺服故障 := 电机A_故障;
报警_B伺服故障 := 电机B_故障;

// 报警复位
IF 报警复位 THEN
    报警_防撞触发 := FALSE;
    报警_A越界    := FALSE;
    报警_B越界    := FALSE;
    内部急停复位  := TRUE;
ELSE
    内部急停复位  := FALSE;
END_IF;

// 系统故障总输出
报警_系统故障 := 报警_急停触发 OR 报警_防撞触发 OR 报警_A越界
              OR 报警_B越界 OR 报警_A伺服故障 OR 报警_B伺服故障;
系统就绪     := NOT 报警_系统故障;

// 任何报警触发时禁止所有运动
IF 报警_系统故障 THEN
    MC_Stop(Axis:=电机A轴号, Execute:=TRUE);
    MC_Stop(Axis:=电机B轴号, Execute:=TRUE);
    RETURN;
END_IF;

// ====================== 区域状态检测 ======================
电机A_在A专属区 := (电机A_当前位置 < A专属区右边界);
电机A_在A等待区 := (电机A_当前位置 >= A专属区右边界 AND 电机A_当前位置 < A等待区右边界);
电机A_在共享区  := (电机A_当前位置 >= A等待区右边界 AND 电机A_当前位置 <= 共享区右边界);

电机B_在B专属区 := (电机B_当前位置 > B等待区右边界);
电机B_在B等待区 := (电机B_当前位置 > 共享区右边界 AND 电机B_当前位置 <= B等待区右边界);
电机B_在共享区  := (电机B_当前位置 >= A等待区右边界 AND 电机B_当前位置 <= 共享区右边界);

// 越界报警检测
IF 电机A_当前位置 > 共享区右边界 THEN 报警_A越界 := TRUE; END_IF;
IF 电机B_当前位置 < A等待区右边界 THEN 报警_B越界 := TRUE; END_IF;

// ====================== 模式状态输出 ======================
自动运行中 := 自动模式 AND 系统就绪;
手动模式中 := NOT 自动模式 AND 系统就绪;

// ====================== 手动模式（带完整防碰撞保护） ======================
IF 手动模式中 THEN
    // 复位自动状态
    电机A_生产状态   := 0;
    电机B_生产状态   := 0;
    电机A_有生产任务 := FALSE;
    电机B_有生产任务 := FALSE;
    电机A_预等待中   := FALSE;
    电机B_预等待中   := FALSE;

    // --- 手动A正向点动（向右） ---
    IF 手动A正向点动 AND NOT 电机A_运行中 THEN
        IF NOT (电机B_运动方向 = -1 OR 电机B_在共享区 OR 电机A_当前位置 >= 共享区右边界) THEN
            MC_MoveVelocity(Axis:=电机A轴号, Velocity:=手动点动速度,
                Acceleration:=加速度, Deceleration:=减速度, Execute:=TRUE);
            电机A_允许运行 := TRUE;
        ELSE
            电机A_允许运行 := FALSE;
        END_IF;
    ELSIF NOT 手动A正向点动 AND 电机A_运动方向 = 1 THEN
        MC_Stop(Axis:=电机A轴号, Execute:=TRUE);
        电机A_允许运行 := FALSE;
    END_IF;

    // --- 手动A反向点动（向左） ---
    IF 手动A反向点动 AND NOT 电机A_运行中 THEN
        IF 电机A_当前位置 > 0 THEN
            MC_MoveVelocity(Axis:=电机A轴号, Velocity:=-手动点动速度,
                Acceleration:=加速度, Deceleration:=减速度, Execute:=TRUE);
            电机A_允许运行 := TRUE;
        ELSE
            电机A_允许运行 := FALSE;
        END_IF;
    ELSIF NOT 手动A反向点动 AND 电机A_运动方向 = -1 THEN
        MC_Stop(Axis:=电机A轴号, Execute:=TRUE);
        电机A_允许运行 := FALSE;
    END_IF;

    // --- 手动B正向点动（向右） ---
    IF 手动B正向点动 AND NOT 电机B_运行中 THEN
        IF 电机B_当前位置 < B放料位 THEN
            MC_MoveVelocity(Axis:=电机B轴号, Velocity:=手动点动速度,
                Acceleration:=加速度, Deceleration:=减速度, Execute:=TRUE);
            电机B_允许运行 := TRUE;
        ELSE
            电机B_允许运行 := FALSE;
        END_IF;
    ELSIF NOT 手动B正向点动 AND 电机B_运动方向 = 1 THEN
        MC_Stop(Axis:=电机B轴号, Execute:=TRUE);
        电机B_允许运行 := FALSE;
    END_IF;

    // --- 手动B反向点动（向左） ---
    IF 手动B反向点动 AND NOT 电机B_运行中 THEN
        IF NOT (电机A_运动方向 = 1 OR 电机A_在共享区 OR 电机B_当前位置 <= A等待区右边界) THEN
            MC_MoveVelocity(Axis:=电机B轴号, Velocity:=-手动点动速度,
                Acceleration:=加速度, Deceleration:=减速度, Execute:=TRUE);
            电机B_允许运行 := TRUE;
        ELSE
            电机B_允许运行 := FALSE;
        END_IF;
    ELSIF NOT 手动B反向点动 AND 电机B_运动方向 = -1 THEN
        MC_Stop(Axis:=电机B轴号, Execute:=TRUE);
        电机B_允许运行 := FALSE;
    END_IF;

    // 运动方向检测
    IF 电机A_运行中 THEN 电机A_运动方向 := SEL(手动A正向点动, -1, 1); ELSE 电机A_运动方向 := 0; END_IF;
    IF 电机B_运行中 THEN 电机B_运动方向 := SEL(手动B正向点动, -1, 1); ELSE 电机B_运动方向 := 0; END_IF;

    // 最后一道防线：实时距离检测
    IF ABS(电机A_当前位置 - 电机B_当前位置) < 最小安全距离 THEN
        MC_Stop(Axis:=电机A轴号, Execute:=TRUE);
        MC_Stop(Axis:=电机B轴号, Execute:=TRUE);
        报警_防撞触发 := TRUE;
    END_IF;

    RETURN;
END_IF;

// ====================== 自动模式 ======================
IF 自动运行中 THEN

    // ---------- 第一层：防碰撞安全层 ----------
    IF 电机A_运行中 THEN
        电机A_运动方向 := SEL(电机A_目标位置 > 电机A_当前位置, -1, 1);
    ELSE
        电机A_运动方向 := 0;
    END_IF;

    IF 电机B_运行中 THEN
        电机B_运动方向 := SEL(电机B_目标位置 > 电机B_当前位置, -1, 1);
    ELSE
        电机B_运动方向 := 0;
    END_IF;

    // A运动允许条件
    电机A_允许运行 := FALSE;
    IF 电机A_目标位置 <= A等待区右边界 THEN
        电机A_允许运行 := TRUE;
    ELSIF 电机A_目标位置 > A等待区右边界 AND 电机A_目标位置 <= 共享区右边界 THEN
        IF NOT (电机B_运动方向 = -1) THEN
            电机A_允许运行 := TRUE;
        END_IF;
    END_IF;

    // B运动允许条件
    电机B_允许运行 := FALSE;
    IF 电机B_目标位置 > 共享区右边界 THEN
        电机B_允许运行 := TRUE;
    ELSIF 电机B_目标位置 > A等待区右边界 AND 电机B_目标位置 <= 共享区右边界 THEN
        IF NOT (电机A_运动方向 = 1) THEN
            电机B_允许运行 := TRUE;
        END_IF;
    END_IF;

    // 优先级冲突处理
    IF 电机A_运动方向 = 1 AND 电机B_运动方向 = -1 THEN
        IF 送料优先级高于取料 THEN
            电机B_允许运行 := FALSE;
        ELSE
            电机A_允许运行 := FALSE;
        END_IF;
    END_IF;

    // 最后一道防线
    IF ABS(电机A_当前位置 - 电机B_当前位置) < 最小安全距离 THEN
        MC_Stop(Axis:=电机A轴号, Execute:=TRUE);
        MC_Stop(Axis:=电机B轴号, Execute:=TRUE);
        报警_防撞触发 := TRUE;
    END_IF;

    // ---------- 第二层：预等待调度层 ----------
    电机A_预等待中 := FALSE;
    IF NOT 电机A_运行中 AND NOT 电机A_有生产任务 THEN
        IF 电机B_在共享区 THEN
            电机A_预等待中   := TRUE;
            电机A_目标位置   := A等待位;
        END_IF;
    END_IF;

    电机B_预等待中 := FALSE;
    IF NOT 电机B_运行中 AND NOT 电机B_有生产任务 THEN
        IF 电机A_在共享区 THEN
            电机B_预等待中   := TRUE;
            电机B_目标位置   := B等待位;
        END_IF;
    END_IF;

    // ---------- 第三层：生产任务层 ----------
    // A电机生产任务
    IF NOT 电机A_预等待中 THEN
        CASE 电机A_生产状态 OF
            0:  IF 有料待送 THEN
                    电机A_目标位置   := A取料位;
                    电机A_有生产任务 := TRUE;
                    电机A_生产状态   := 1;
                END_IF;

            1:  IF 电机A_到位 AND 电机A_当前位置 = A取料位 THEN
                    电机A_生产状态 := 2;
                END_IF;

            2:  IF A取料完成 THEN
                    电机A_目标位置 := A放料位;
                    电机A_生产状态 := 3;
                END_IF;

            3:  IF 电机A_到位 AND 电机A_当前位置 = A放料位 THEN
                    电机A_生产状态 := 4;
                END_IF;

            4:  IF A放料完成 THEN
                    电机A_目标位置 := A取料位;
                    电机A_生产状态 := 5;
                END_IF;

            5:  IF 电机A_到位 AND 电机A_当前位置 = A取料位 THEN
                    电机A_有生产任务 := FALSE;
                    电机A_生产状态   := 0;
                END_IF;
        END_CASE;
    END_IF;

    // B电机生产任务
    IF NOT 电机B_预等待中 THEN
        CASE 电机B_生产状态 OF
            0:  IF A放料完成 THEN
                    电机B_目标位置   := B取料位;
                    电机B_有生产任务 := TRUE;
                    电机B_生产状态   := 1;
                END_IF;

            1:  IF 电机B_到位 AND 电机B_当前位置 = B取料位 THEN
                    电机B_生产状态 := 2;
                END_IF;

            2:  IF B取料完成 THEN
                    电机B_目标位置 := B放料位;
                    电机B_生产状态 := 3;
                END_IF;

            3:  IF 电机B_到位 AND 电机B_当前位置 = B放料位 THEN
                    电机B_生产状态 := 4;
                END_IF;

            4:  IF B放料完成 THEN
                    电机B_目标位置 := B等待位;
                    电机B_生产状态 := 5;
                END_IF;

            5:  IF 电机B_到位 AND 电机B_当前位置 = B等待位 THEN
                    电机B_有生产任务 := FALSE;
                    电机B_生产状态   := 0;
                END_IF;
        END_CASE;
    END_IF;

    // ---------- 执行电机运动 ----------
    IF 电机A_允许运行 AND NOT 电机A_运行中 AND (电机A_目标位置 <> 电机A_当前位置) THEN
        MC_MoveAbsolute(Axis:=电机A轴号, Position:=电机A_目标位置,
            Velocity:=自动运动速度, Acceleration:=加速度, Deceleration:=减速度,
            Execute:=TRUE);
    END_IF;

    IF 电机B_允许运行 AND NOT 电机B_运行中 AND (电机B_目标位置 <> 电机B_当前位置) THEN
        MC_MoveAbsolute(Axis:=电机B轴号, Position:=电机B_目标位置,
            Velocity:=自动运动速度, Acceleration:=加速度, Deceleration:=减速度,
            Execute:=TRUE);
    END_IF;

END_IF

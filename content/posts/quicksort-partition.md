---
title: "手撕快排卡在哪？拆解 partition 的 i、lo、hi 与递归出口"
date: 2026-10-25
draft: false
tags: ["算法", "数据结构", "手撕"]
categories: ["算法"]
summary: "拆解 Lomuto 快速排序中 i、lo、hi 的职责，说明 i + 1 如何切分递归区间，并梳理 lo >= hi 的三种触发场景和随机基准的作用。"
source_note: "03-Resources/study/算法/手撕/Sort/手撕快排卡在哪-拆解partition的i-lo-hi与递归出口.md"
---

## 0. 引子

快排是手撕高频题，代码只有十几行，但每一行都值得问一句"为什么"。本文基于我读自己代码时连问的四个问题展开：

1. `partition` 里的 `i` 是判断每次快排边界的吗？
2. `if lo >= hi: return` 这个返回条件是什么？
3. `lo` 和 `hi` 到底判断的是什么？
4. 什么情况下会出现 `lo >= hi`？

先把完整代码贴在这里，后面所有讨论都基于它：

```python
import random

def quick_sort(arr: list, lo=0, hi=None):
    if hi is None:
        hi = len(arr) - 1
    if lo >= hi:                              # 0 或 1 个元素，直接返回
        return
    p = partition(arr, lo, hi)                # 分区，返回基准最终位置
    quick_sort(arr, lo, p - 1)
    quick_sort(arr, p + 1, hi)

def partition(arr, lo, hi):
    r = random.randint(lo, hi)                # 随机选基准，避免最坏情况
    arr[r], arr[hi] = arr[hi], arr[r]         # 把基准换到末尾
    pivot = arr[hi]
    i = lo - 1                                # i 指向"小于基准区域"的最后一个位置
    for j in range(lo, hi):
        if arr[j] < pivot:
            i += 1
            arr[i], arr[j] = arr[j], arr[i]
    arr[i + 1], arr[hi] = arr[hi], arr[i + 1] # 基准放到正确位置
    return i + 1
```

这是典型的 **Lomuto 分区方案** + **随机化基准**。注意它是**原地排序**，没有返回值——调用后要打印原始数组，而不是打印函数返回值。

---

## 1. `lo` 和 `hi`：当前这轮排哪一段

`lo`（lower）和 `hi`（upper）是**当前递归要处理的区间端点下标**，含义是"只排 `arr[lo ... hi]` 这一段，包括两端"。

- 窗口外的元素：要么已排好，要么还没轮到，**这轮绝不碰**
- 初始调用 `quick_sort(arr)` 时 `lo=0, hi=len(arr)-1`，窗口就是整个数组

`partition` 同样只在窗口内工作：

```python
for j in range(lo, hi):   # 只扫描窗口内 lo ~ hi-1 的元素
```

传什么窗口，它就只负责排什么窗口。

整个快排的分治过程，本质就是**窗口不断被切小**：

```
初始:  lo=0                          hi=7      整个数组
                    ↓ partition 后 p=3
左半:  lo=0              hi=2
右半:                  lo=4          hi=7
      ↓ 继续切分……
直到窗口只剩 0 或 1 个元素 → lo >= hi → 停
```

所以 `lo` 和 `hi` 回答的问题是：**这一次递归排哪一段。**

---

## 2. `partition` 里的 `i`：不是分区边界，是"小元素区域"的右沿

先给结论：**`i` 是扫描过程中"值 < pivot 区域"的临时边界，而真正的分区边界是返回值 `i + 1`**——也就是基准最终落位的位置。

两个指针分工不同：

| 指针 | 角色 | 行为 |
|------|------|------|
| `j` | 扫描指针 | 从 `lo` 走到 `hi-1`，逐个检查元素 |
| `i` | 分界指针 | 标记"已处理区域中，值 < pivot 那部分"的右端；初始 `lo-1` 表示左边还没有小元素 |

循环里每遇到比 pivot 小的元素，`i` 先右移一格再交换，把小元素挤到左边，始终维持这个结构：

```
[lo .... i]   (i+1) .... (hi-1)      hi
  < pivot      ≥ pivot       pivot
```

### 走一遍例子

`arr = [3, 1, 4, 2]`，pivot = 2（已换到末尾）：

| 步骤 | j | arr[j] | < pivot? | i | 数组状态 |
|------|---|--------|----------|---|----------|
| 开始 | - | - | - | -1 | `[3, 1, 4, 2]` |
| 1 | 0 | 3 | 否 | -1 | `[3, 1, 4, 2]` |
| 2 | 1 | 1 | 是 | 0 | `[1, 3, 4, 2]`（`i+1=0` 与 `j=1` 交换） |
| 3 | 2 | 4 | 否 | 0 | `[1, 3, 4, 2]` |

循环结束，`i + 1 = 1` 就是 pivot 该去的位置，把它换过去：

```
[1, 2, 4, 3]
    ↑
  返回 1
```

### 和 `quick_sort` 的衔接

```python
p = partition(arr, lo, hi)    # p = i + 1，pivot 的最终下标
quick_sort(arr, lo, p - 1)    # 左半区：比 pivot 小的
quick_sort(arr, p + 1, hi)    # 右半区：≥ pivot 的
```

`p` 位置上的元素已就位，左右两半永远不会再包含它。所以准确说法是：

> `i` 是分区过程中的**临时分界线**，`i + 1` 才是每轮快排用来切分左右子数组的**分区边界**。

---

## 3. `if lo >= hi: return`：递归的出口

这是递归**必须有的 base case**：当前区间里没元素了、或只剩 1 个元素，不用再排，直接返回。注释里那句"0 或 1 个元素，直接返回"就是它的全部含义。

- `lo == hi`：区间只剩 1 个元素，单元素天然有序
- `lo > hi`：区间为空，没有东西可排

没有这个判断会发生什么？空区间会被拿去 `partition`，`random.randint(lo, hi)` 直接抛错：

```
ValueError: Empty range for randrange() ...
```

它是整个递归能停下来的保证——没有它，递归会无限下钻直到爆栈或报错。

---

## 4. 什么情况下触发 `lo >= hi`

三种时机，前两种是 `lo == hi`，最后一种是 `lo > hi`。

### 情形一：初始数组本身就 ≤ 1 个元素

```python
quick_sort(arr)   # hi = len(arr) - 1
```

- 空数组：`lo=0, hi=-1` → `0 >= -1` ✅
- 1 个元素：`lo=0, hi=0` → `0 >= 0` ✅

还没开始就直接退出。

### 情形二：递归到的子区间只剩 1 个元素

```python
quick_sort(arr, 3, 3)   # 只剩 arr[3]，lo == hi → 返回
```

### 情形三：基准落在区间端点，某一侧切空了（最关键的一种）

```python
p = partition(arr, lo, hi)
quick_sort(arr, lo, p - 1)      # 左半区
quick_sort(arr, p + 1, hi)      # 右半区
```

- **`p == lo`**（基准是最小元素，落到区间最左边）→ 左半区 `[lo, lo-1]`，即 `lo > hi`
- **`p == hi`**（基准是最大元素，落到区间最右边）→ 右半区 `[hi+1, hi]`，即 `lo > hi`

### 完整递归轨迹

`arr = [3, 1, 2]`，某轮 partition 后 `p = 2`（最大元素 3 落到末尾）：

```
quick_sort(arr, 0, 2)          # 3 个元素，继续
├── p = 2
├── quick_sort(arr, 0, 1)      # 左半区，lo < hi，继续
│   ├── partition → p = 0
│   ├── quick_sort(arr, 0, -1) # lo=0 > hi=-1，空区间，返回 ✅
│   └── quick_sort(arr, 1, 1)  # lo=hi=1，单元素，返回 ✅
└── quick_sort(arr, 3, 2)      # lo=3 > hi=2，空区间，返回 ✅
```

每一次 `lo >= hi` 都是递归的自然收敛，不是异常路径。

---

## 5. 小抄总结

| 疑问 | 答案 |
|------|------|
| `lo` / `hi` 是什么 | 当前这轮要排的区间端点，`partition` 也只在这个窗口内操作 |
| `i` 是分区边界吗 | 不是。`i` 是"< pivot 区域"的临时右沿，`i + 1`（返回值 `p`）才是分区边界 |
| `lo >= hi` 是什么 | 递归出口：区间只剩 0 或 1 个元素 |
| 什么时候触发 | ① 数组初始就 ≤1 元素；② 子区间剩 1 个元素（`lo==hi`）；③ 基准落在端点切出空区间（`lo>hi`） |

再补两个手撕时容易踩的点：

1. **原地排序没有返回值**。`quick_sorts = quick_sort(list)` 拿到的是 `None`，正确姿势是调用后直接 `print(list)`。
2. **随机基准不是可有可无的**。固定取 `arr[lo]` 或 `arr[hi]`，在有序/近有序数组上会退化到 O(n²)；`random.randint` 选基准把最坏情况变成概率事件，平均仍是 O(n log n)。

---

## 相关笔记

- `sort.py`：本文全部代码来源，含冒泡、选择、快排三种实现。

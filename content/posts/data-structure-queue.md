---
title: "手撕队列：环形数组与链表两种实现"
date: 2026-10-19T21:15:00+08:00
draft: false
tags: ["算法", "数据结构", "手撕"]
categories: ["算法"]
summary: "从零手写队列：只用 front 和 size 两个变量实现 O(1) 入队出队的环形数组队列，以及基于（双向）链表的链式队列。"
---

队列（Queue）是一种**先进先出（FIFO）**的线性结构：只能从队尾入队、从队首出队，就像排队买票。
手撕队列最常见的坑是"数组首部删除元素是 O(n)"，而解法就是**环形数组**。本文给出两种完整实现，并配一个可交互的动画演示。

<!--more-->

## 核心设计：只维护 front 和 size

如果每次出队都把数组元素整体前移，时间复杂度是 O(n)。优化思路：

- 用变量 `front` 指向队首元素的索引；
- 用变量 `size` 记录队列长度；
- 定义 **`rear = front + size`**，它指向队尾元素之后的下一个位置；
- 有效区间为 `[front, rear - 1]`。

于是：

| 操作 | 做法 | 复杂度 |
|------|------|--------|
| 入队 | 写入 `rear` 处，`size += 1` | O(1) |
| 出队 | `front += 1`，`size -= 1` | O(1) |
| 访问队首 | 直接读 `nums[front]` | O(1) |

注意此时**没有 rear 变量**，rear 是现算的。最后一个细节：当 `front` 或 `rear` 越过数组尾部时，用**取余**回到数组头部继续遍历——这就是"环形"。

```text
rear = (front + size) % capacity
```

## 交互演示

下面这个 demo 可以直接点"入队 / 出队"观察指针怎么走，也可以取消勾选"环形"，看看不取余时 rear 走到末尾后整个数组就再也用不上的窘境：

{{< rawhtml >}}
<iframe src="../demo/circular-queue.html" title="环形数组队列动画" loading="lazy" style="width:100%;height:980px;border:1px solid #d3d9e0;border-radius:10px;background:#fff;" ></iframe>
{{< /rawhtml >}}

> 如果在手机上阅读，动画可能需要横屏或放大查看。

## 实现一：环形数组队列

```python
class ArrayQueue:
    """基于环形数组实现的队列"""

    def __init__(self, size: int):
        """构造方法"""
        self._nums: list[int] = [0] * size  # 用于存储队列元素的数组
        self._front: int = 0                # 队首指针，指向队首元素
        self._size: int = 0                 # 队列长度

    def capacity(self) -> int:
        """获取队列的容量"""
        return len(self._nums)

    def size(self) -> int:
        """获取队列的长度"""
        return self._size

    def is_empty(self) -> bool:
        """判断队列是否为空"""
        return self._size == 0

    def push(self, num: int):
        """入队"""
        if self._size == self.capacity():
            raise IndexError("队列已满")
        # 计算队尾指针 rear = front + size，指向队尾元素的下一个位置
        # 通过取余操作实现 rear 越过数组尾部后回到头部
        rear: int = (self._front + self._size) % self.capacity()
        # 将 num 添加至队尾
        self._nums[rear] = num
        self._size += 1

    def pop(self) -> int:
        """出队"""
        num: int = self.peek()
        # 队首指针向后移动一位，若越过尾部，则返回到数组头部
        self._front = (self._front + 1) % self.capacity()
        self._size -= 1
        return num

    def peek(self) -> int:
        """访问队首元素"""
        if self.is_empty():
            raise IndexError("队列为空")
        return self._nums[self._front]

    def to_list(self) -> list[int]:
        """返回列表用于打印"""
        res = [0] * self._size
        j: int = self._front
        for i in range(self._size):
            res[i] = self._nums[j % self.capacity()]
            j += 1
        return res
```

验证一下"环形"确实发生了——出队腾出的头部空位被复用：

```python
if __name__ == "__main__":
    queue = ArrayQueue(5)

    # 入队
    for i in [1, 2, 3, 4, 5]:
        queue.push(i)
    print("入队后:", queue.to_list())         # [1, 2, 3, 4, 5]

    # 出队两个元素，front 后移，前面腾出空位
    print("出队:", queue.pop(), queue.pop())  # 1 2
    print("出队后:", queue.to_list())         # [3, 4, 5]

    # 再入队，rear 越过数组尾部，回到数组头部
    queue.push(6)
    queue.push(7)
    print("环形入队后:", queue.to_list())     # [3, 4, 5, 6, 7]
    print("队首元素:", queue.peek())          # 3
    print("长度:", queue.size())              # 5
```

## 实现二：链表队列

链表天然是"头出尾入"，不需要环形技巧。最简版本用单链表 + 头尾指针：

```python
class ListNodeI:
    def __init__(self, val):
        self.val = val
        self.next = None


class LinkedListQueueI:
    def __init__(self):
        self._front = None
        self._rear = None
        self._size = 0

    def push(self, num):
        node = ListNodeI(num)
        if self._front is None:
            self._front = self._rear = node
        else:
            self._rear.next = node
            self._rear = node
        self._size += 1

    def pop(self):
        if self._size == 0:
            raise IndexError("队列为空")
        num = self._front.val
        self._front = self._front.next
        if self._front is None:   # 删的是最后一个节点，尾指针也要清空
            self._rear = None
        self._size -= 1
        return num
```

> **经典 bug**：出队把最后一个节点删掉时，`_rear` 会悬空指向已释放/已出队的节点，必须显式置 `None`，否则下次入队会写进脏节点。

升级为双向链表后，节点还带 `prev`，便于回溯；出队时把新头节点的 `prev` 置空即可：

```python
class ListNodeII:
    def __init__(self, val: int):
        self.val = val
        self.next: ListNodeII | None = None
        self.prev: ListNodeII | None = None


class LinkedListQueue:
    def __init__(self):
        self._front: ListNodeII | None = None  # 头节点 = 队首
        self._rear: ListNodeII | None = None   # 尾节点 = 队尾
        self._size = 0

    def is_empty(self) -> bool:
        return self._size == 0

    def push(self, num: int):
        node = ListNodeII(num)
        if self._front is None:        # 空队列：头尾都是新节点
            self._front = self._rear = node
        else:
            self._rear.next = node     # 旧尾节点指向新节点
            node.prev = self._rear     # 新节点回指旧尾节点
            self._rear = node          # 尾指针后移
        self._size += 1

    def pop(self) -> int:
        if self.is_empty():
            raise IndexError("队列为空")
        num = self._front.val
        self._front = self._front.next
        if self._front is None:        # 删的是最后一个节点
            self._rear = None
        else:
            self._front.prev = None
        self._size -= 1
        return num
```

## 两种实现对比

| | 环形数组 | 链表 |
|---|---|---|
| 入队 / 出队 | O(1) | O(1) |
| 空间 | 预分配，可能浪费或需扩容 | 按需分配，有指针开销 |
| 缓存友好 | ✅ 连续内存 | ❌ 节点分散 |
| 扩容 | 容量固定（可另写扩容版） | 无限制 |

实际工程里，如果容量可预估（如滑动窗口、BFS），**环形数组是首选**；容量不可预估时用链表或动态数组 + 取模。

## 小结

1. 队列 FIFO，只允许队尾入、队首出；
2. 数组实现的关键是 `front + size` 现算 rear，**取余**让它首尾相接成环；
3. 出队不搬元素，只动 `front` 和 `size`，所以是 O(1)；
4. 链表实现要注意"删最后一个节点时同步清空 `_rear`"。

手写完这两种实现，LeetCode 上的滑动窗口最大值、用栈实现队列、设计循环队列一类题目基本就是套路复用了。

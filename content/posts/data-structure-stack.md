---
title: "手撕栈：数组与链表两种实现"
date: 2026-10-20T20:00:00+08:00
draft: false
tags: ["算法", "数据结构", "手撕"]
categories: ["算法"]
summary: "从零实现栈的数组版与链表版，梳理后进先出、栈顶操作、复杂度和常见边界问题。"
---

栈（Stack）是一种**后进先出（LIFO）**的线性结构：最后放进去的元素最先取出来，像一摞盘子，只能从最上面放、从最上面拿。

本文沿用手撕队列的思路，分别用动态数组和单链表实现栈，并重点看清楚一件事：所有操作都围绕**栈顶**进行。

<!--more-->

## 核心设计：只在栈顶操作

栈只需要支持几种基本操作：

| 操作 | 含义 | 复杂度 |
|------|------|--------|
| `push` | 把元素压入栈顶 | O(1) 均摊 |
| `pop` | 移除并返回栈顶元素 | O(1) |
| `peek` | 查看栈顶元素，不移除 | O(1) |
| `is_empty` | 判断栈是否为空 | O(1) |

例如依次压入 `A`、`B`、`C`，栈顶是 `C`，弹出顺序就是 `C → B → A`。

如果栈为空时调用 `pop` 或 `peek`，就发生了**栈下溢**。实现时应明确报错，而不是返回一个容易与正常数据混淆的值。

## 实现一：动态数组栈

Python 的 `list` 在尾部追加和删除元素很方便。把列表末尾作为栈顶，就不需要移动其他元素：

```python
class ArrayStack:
    """基于动态数组实现的栈，列表末尾作为栈顶"""

    def __init__(self):
        self._items: list[int] = []

    def is_empty(self) -> bool:
        return len(self._items) == 0

    def size(self) -> int:
        return len(self._items)

    def push(self, num: int) -> None:
        self._items.append(num)

    def pop(self) -> int:
        if self.is_empty():
            raise IndexError("栈为空")
        return self._items.pop()

    def peek(self) -> int:
        if self.is_empty():
            raise IndexError("栈为空")
        return self._items[-1]

    def to_list(self) -> list[int]:
        """按栈底到栈顶的顺序返回元素，用于打印"""
        return self._items.copy()
```

简单验证一下后进先出：

```python
stack = ArrayStack()
for num in [1, 2, 3]:
    stack.push(num)

print("栈（底到顶）:", stack.to_list())  # [1, 2, 3]
print("查看栈顶:", stack.peek())        # 3，元素仍在栈中
print("弹出:", stack.pop())             # 3
print("弹出后:", stack.to_list())       # [1, 2]
print("当前长度:", stack.size())        # 2
```

注意，动态数组扩容时，某一次 `append` 可能需要搬移元素，因此更准确地说，压栈是 **O(1) 均摊**；弹出和访问末尾元素是 O(1)。

## 实现二：链表栈

链表栈用一个指针 `top` 指向栈顶节点。压栈时，新节点接到旧栈顶前面；弹栈时，`top` 移到下一个节点。

```python
class ListNode:
    def __init__(self, val: int):
        self.val = val
        self.next: ListNode | None = None


class LinkedStack:
    """基于单链表实现的栈，链表头部作为栈顶"""

    def __init__(self):
        self._top: ListNode | None = None
        self._size = 0

    def is_empty(self) -> bool:
        return self._top is None

    def size(self) -> int:
        return self._size

    def push(self, num: int) -> None:
        node = ListNode(num)
        node.next = self._top
        self._top = node
        self._size += 1

    def pop(self) -> int:
        if self.is_empty():
            raise IndexError("栈为空")

        node = self._top
        self._top = node.next
        node.next = None  # 断开已弹出的节点与剩余链表
        self._size -= 1
        return node.val

    def peek(self) -> int:
        if self.is_empty():
            raise IndexError("栈为空")
        return self._top.val
```

链表版的 `push` 和 `pop` 只改动头指针，因此都是 O(1)。每个节点还要额外保存一个 `next` 引用，会带来指针空间开销。

原始练习里用 `Student` 对象作为元素。栈本身不关心元素的类型，只负责按 LIFO 顺序存取；上面的 `int` 换成 `Student` 一样可以使用。这里让栈内部创建节点，调用者只传入数据，可以避免把已经连着其他节点的节点重复压入后意外改坏链表。

## 两种实现对比

| | 动态数组栈 | 链表栈 |
|---|---|---|
| 压栈 / 弹栈 | O(1) 均摊 / O(1) | O(1) / O(1) |
| 空间 | 连续存储，可能预留额外容量 | 每个元素都需要节点和指针 |
| 缓存局部性 | 较好 | 节点分散，较差 |
| 容量 | 自动扩容 | 按需分配 |

通常直接用动态数组实现栈更简单，也更节省空间；只有在节点本身已经存在，或有其他链表结构方面的需求时，链表栈才更合适。

## 小结

1. 栈遵循 LIFO，压入和弹出都发生在栈顶；
2. 数组栈把动态数组末尾作为栈顶，`append` 和 `pop()` 不需要移动元素；
3. 链表栈把头节点作为栈顶，通过更新 `top` 指针完成操作；
4. 空栈调用 `pop` 或 `peek` 时要明确报错；
5. Python 中数组栈通常是首选，链表实现适合练习指针操作与节点关系。

括号匹配、深度优先搜索、表达式求值和撤销操作，都是栈的典型应用。把“只操作栈顶”这条原则抓住，实现起来就很直接。

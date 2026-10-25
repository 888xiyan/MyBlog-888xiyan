---
title: "手撕线程池：C 语言实现多线程任务队列"
date: 2026-10-25
draft: false
tags: ["算法", "计算机基础", "操作系统", "手撕"]
categories: ["计算机基础"]
summary: "使用 POSIX 线程实现一个最小线程池：固定工作线程从共享任务队列取任务，以互斥锁和条件变量完成并发协调，并明确创建、提交和销毁阶段的边界。"
source_note: "03-Resources/study/算法/手撕/ThreadPool/"
---

线程池解决的是**重复创建线程与任务调度**的问题：线程通常比协程更重，每来一个任务就创建一个线程，会持续付出线程创建、调度和回收的开销。线程池预先创建一组工作线程，把任务放进队列，由空闲线程取出执行。

线程池本质上是“**固定线程集合 + 共享任务队列 + 同步机制**”。其中最核心的问题只有三个：

1. 多个工作线程如何安全地共享同一个任务队列；
2. 没有任务时线程如何等待，有新任务时如何被唤醒；
3. 停止线程池时，如何唤醒并回收所有线程。

线程与进程、协程在资源、调度和切换方式上的差异，可以先看[进程、线程与协程的区别]({{< relref "process-thread-coroutine-difference.md" >}})。本文继续往下看：线程创建出来以后，怎样被稳定地复用。

## 核心设计

### 任务结构

任务只需要两部分信息：要执行的函数，以及传给函数的数据。

```c
typedef void (*task_fn)(void *);

typedef struct task {
    task_fn function;
    void *arg;
    struct task *next;
} task_t;
```

`task_fn` 的类型是 `void (*)(void *)`：接收一个 `void *` 参数，没有返回值。`next` 把任务连接成单链表，形成先进先出的任务队列。

### 线程池结构

```c
typedef struct threadpool {
    pthread_t *threads;
    size_t thread_count;

    task_t *head;
    task_t *tail;

    pthread_mutex_t mutex;
    pthread_cond_t condition;

    bool stopping;
} threadpool_t;
```

各个字段的职责如下：

| 字段 | 作用 |
|------|------|
| `threads` | 保存工作线程的标识，销毁时用于 `pthread_join()` |
| `thread_count` | 固定的工作线程数量 |
| `head` / `tail` | 任务队列的出队端和入队端 |
| `mutex` | 保护任务队列和 `stopping` |
| `condition` | 让没有任务的工作线程等待，并在新任务或停止时唤醒 |
| `stopping` | 标记线程池是否进入停止阶段 |

因此，线程池的运行过程可以概括为：

```text
submit：任务追加到队尾 -> signal 唤醒一个等待线程
worker：等待任务 -> 从队首取任务 -> 解锁 -> 执行任务
destroy：标记停止 -> broadcast 唤醒全部线程 -> join 回收
```

## 实现：公共接口

实现拆成头文件、线程池接口、工作线程和示例四个部分。公共定义统一放在 `threadpool.h`：

```c
#ifndef THREADPOOL_H
#define THREADPOOL_H

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>

typedef void (*task_fn)(void *);

typedef struct task {
    task_fn function;
    void *arg;
    struct task *next;
} task_t;

typedef struct threadpool {
    pthread_t *threads;
    size_t thread_count;

    task_t *head;
    task_t *tail;

    pthread_mutex_t mutex;
    pthread_cond_t condition;

    bool stopping;
} threadpool_t;

threadpool_t *threadpool_create(size_t thread_count);
int threadpool_submit(threadpool_t *pool, task_fn function, void *arg);
int threadpool_destroy(threadpool_t *pool);

void *worker(void *arg);

#endif /* THREADPOOL_H */
```

使用 include guard 可以避免头文件被重复包含后重复定义结构体。各个 `.c` 文件只包含 `threadpool.h`，不要直接包含其他 `.c` 文件。

## 实现：创建线程池

```c
#include "threadpool.h"
#include <stdlib.h>

threadpool_t *threadpool_create(size_t thread_count)
{
    if (thread_count == 0) {
        return NULL;
    }

    threadpool_t *pool = calloc(1, sizeof(*pool));
    if (pool == NULL) {
        return NULL;
    }

    pool->threads = calloc(thread_count, sizeof(*pool->threads));
    if (pool->threads == NULL) {
        free(pool);
        return NULL;
    }

    pool->thread_count = thread_count;
    pool->head = NULL;
    pool->tail = NULL;
    pool->stopping = false;

    if (pthread_mutex_init(&pool->mutex, NULL) != 0) {
        free(pool->threads);
        free(pool);
        return NULL;
    }

    if (pthread_cond_init(&pool->condition, NULL) != 0) {
        pthread_mutex_destroy(&pool->mutex);
        free(pool->threads);
        free(pool);
        return NULL;
    }

    size_t created = 0;
    for (; created < thread_count; created++) {
        if (pthread_create(&pool->threads[created],
                           NULL,
                           worker,
                           pool) != 0) {
            break;
        }
    }

    if (created != thread_count) {
        pthread_mutex_lock(&pool->mutex);
        pool->stopping = true;
        pthread_cond_broadcast(&pool->condition);
        pthread_mutex_unlock(&pool->mutex);

        for (size_t i = 0; i < created; i++) {
            pthread_join(pool->threads[i], NULL);
        }

        pthread_cond_destroy(&pool->condition);
        pthread_mutex_destroy(&pool->mutex);
        free(pool->threads);
        free(pool);
        return NULL;
    }

    return pool;
}
```

创建阶段的关键不是“建多少线程”，而是**任意一步失败后如何清理已经取得的资源**：

- 线程数为 0，直接拒绝；
- 分配线程池或线程数组失败，释放已经分配的内存；
- 初始化锁或条件变量失败，逆序清理；
- 只创建成功部分线程时，唤醒并 `join` 这些线程，再释放资源，最终返回 `NULL`。

## 实现：提交任务

```c
int threadpool_submit(threadpool_t *pool, task_fn function, void *arg)
{
    if (pool == NULL || function == NULL) {
        return -1;
    }

    task_t *task = malloc(sizeof(*task));
    if (task == NULL) {
        return -1;
    }

    task->function = function;
    task->arg = arg;
    task->next = NULL;

    pthread_mutex_lock(&pool->mutex);

    if (pool->stopping) {
        pthread_mutex_unlock(&pool->mutex);
        free(task);
        return -1;
    }

    if (pool->tail == NULL) {
        pool->head = task;
        pool->tail = task;
    } else {
        pool->tail->next = task;
        pool->tail = task;
    }

    pthread_cond_signal(&pool->condition);
    pthread_mutex_unlock(&pool->mutex);

    return 0;
}
```

队列采用单链表，所以入队是 O(1)：

| 队列状态 | 入队动作 |
|----------|----------|
| 空队列 | `head` 和 `tail` 都指向新任务 |
| 非空队列 | `tail->next` 指向新任务，再移动 `tail` |

新任务放好后使用 `pthread_cond_signal()`，只唤醒一个等待中的工作线程。写队列、检查 `stopping` 和修改 `head`、`tail` 都必须在同一个临界区内完成。

## 实现：工作线程

```c
#include "threadpool.h"
#include <stdlib.h>

void *worker(void *arg)
{
    threadpool_t *pool = arg;

    for (;;) {
        pthread_mutex_lock(&pool->mutex);

        while (pool->head == NULL && !pool->stopping) {
            pthread_cond_wait(&pool->condition, &pool->mutex);
        }

        if (pool->head == NULL && pool->stopping) {
            pthread_mutex_unlock(&pool->mutex);
            return NULL;
        }

        task_t *task = pool->head;
        pool->head = task->next;

        if (pool->head == NULL) {
            pool->tail = NULL;
        }

        pthread_mutex_unlock(&pool->mutex);

        task->function(task->arg);
        free(task);
    }
}
```

这里有三个并发设计要点：

1. **条件等待必须放在 `while` 中**。线程被唤醒后要重新检查队列和停止状态，处理虚假唤醒以及多个线程争抢同一个任务的情况。
2. **取任务和改队列要在锁内完成**。一个任务节点只能被一个工作线程取走。
3. **任务函数在锁外执行**。如果拿着 `mutex` 执行耗时任务，其他线程连取任务都会被阻塞，多线程会退化成串行执行。

`head` 移走最后一个任务时，还要同步把 `tail` 置为 `NULL`，维持“队列为空时头尾都为空”的不变量。

## 实现：销毁线程池

```c
int threadpool_destroy(threadpool_t *pool)
{
    if (pool == NULL) {
        return -1;
    }

    pthread_mutex_lock(&pool->mutex);
    pool->stopping = true;
    pthread_cond_broadcast(&pool->condition);
    pthread_mutex_unlock(&pool->mutex);

    for (size_t i = 0; i < pool->thread_count; i++) {
        pthread_join(pool->threads[i], NULL);
    }

    while (pool->head) {
        task_t *tmp = pool->head;
        pool->head = pool->head->next;
        free(tmp);
    }

    pthread_cond_destroy(&pool->condition);
    pthread_mutex_destroy(&pool->mutex);
    free(pool->threads);
    free(pool);

    return 0;
}
```

这个版本采用“**排空任务后再停止**”的语义：

```text
stopping = true
    -> 唤醒所有等待线程
    -> 工作线程继续消费已有任务
    -> 队列为空且 stopping 为 true
    -> 工作线程退出
    -> 主线程 join 全部线程
```

销毁阶段必须使用 `pthread_cond_broadcast()`。如果只用 `signal()`，一次只能唤醒一个线程，其他线程可能继续永久等待，`pthread_join()` 就无法返回。

## 使用示例

```c
#include <stdio.h>
#include <stdlib.h>
#include "threadpool.h"

void print_number(void *arg)
{
    int number = *(int *)arg;
    printf("任务执行：number = %d\n", number);
    free(arg);
}

int main(void)
{
    threadpool_t *pool = threadpool_create(4);
    if (pool == NULL) {
        printf("线程池创建失败\n");
        return 1;
    }

    for (int i = 0; i < 10; i++) {
        int *n = malloc(sizeof(int));
        *n = i;
        threadpool_submit(pool, print_number, n);
    }

    threadpool_destroy(pool);
    printf("线程池已销毁\n");
    return 0;
}
```

使用 POSIX 线程编译：

```bash
gcc -std=c11 -Wall -Wextra -Wpedantic -pthread \
    main.c threadpool.c worker.c -o threadpool_test
./threadpool_test
```

线程池创建了 4 个工作线程，但提交了 10 个任务。任务按提交顺序进入队列，具体由哪个线程执行、打印顺序如何交错则不确定。`threadpool_destroy()` 会等待任务排空并回收全部线程，所以函数正常返回后，程序可以安全退出。

## 复杂度

| 操作 | 时间复杂度 | 额外空间 |
|------|------------|----------|
| 创建线程池 | O(n)，n 为线程数 | O(n) |
| 提交任务 | O(1) | 每个任务 O(1) |
| 取出并执行任务 | 出队 O(1)，任务本身另计 | O(1) |
| 销毁线程池 | O(n + m)，m 为剩余任务数 | O(1) |

## 易错点

- **忘记检查条件变量的等待条件**：必须使用循环，不能假定一次 `signal()` 对应一次有效唤醒。
- **在锁内执行任务**：会阻塞其他工作线程，失去线程池的并发效果。
- **只删除 `head` 不清理 `tail`**：取出最后一个任务后若不把 `tail` 置空，下次入队会写入已经出队的节点。
- **销毁时使用 `signal`**：只能唤醒一个线程，应该使用 `broadcast`。
- **先释放锁对象再等待线程退出**：必须先 `join`，确保没有线程仍会访问 `mutex` 或 `condition`。
- **忽略任务参数的所有权**：示例约定 `arg` 的内存由任务函数释放；如果提交失败，任务函数不会执行，调用方需要自行处理这块内存。
- **把任务顺序当成执行顺序**：任务队列是 FIFO，但多个工作线程并发执行，完成顺序并不固定。

## 与“每任务一线程”对比

| | 线程池 | 每个任务创建线程 |
|---|---|---|
| 线程创建成本 | 创建一次，长期复用 | 每个任务一次 |
| 并发规模 | 固定线程数，容易控制 | 任务越多线程越多 |
| 任务积压 | 暂存在队列中 | 通常直接创建更多线程 |
| 关闭方式 | 统一停止并 `join` | 分别等待各个线程 |
| 适合场景 | 大量、频繁的短任务 | 少量、独立且生命周期清楚的任务 |

这个实现是理解线程池同步模型的最小版本。它没有任务返回值、优先级、超时、取消、动态扩容和有界队列背压策略；这些能力可以在确认需求后继续加入，但不应绕开当前最基本的队列一致性、条件等待和线程回收规则。

## 小结

1. 线程池由固定工作线程、共享任务队列和同步机制组成；
2. `mutex` 保护 `head`、`tail` 和 `stopping`，`condition` 负责等待与唤醒；
3. 任务函数必须在锁外运行，否则并发执行无法成立；
4. 本实现的销毁语义是先排空已有任务，再退出并回收全部线程；
5. 提交任务是 O(1)，代价主要来自线程并发执行任务本身。

相关阅读：[进程、线程与协程的区别]({{< relref "process-thread-coroutine-difference.md" >}})。

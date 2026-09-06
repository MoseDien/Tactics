# 在 iOS Simulator 中查看 SwiftData SQLite 数据库

本文说明如何定位并查看 DailyTactics 在 iOS Simulator 中生成的 SwiftData SQLite 数据库。

DailyTactics 的 Bundle ID 是：

```text
com.dienbell.tactics
```

项目使用 SwiftData 默认的磁盘 `ModelConfiguration`。数据库通常位于 App 数据容器的 `Library/Application Support/default.store`。

> 建议只查询数据库，不要直接修改 SwiftData 的内部表。直接写入可能破坏对象关系、元数据或后续的数据迁移。

## 前置条件

1. 启动一个 iOS Simulator。
2. 在该 Simulator 中安装并至少运行一次 DailyTactics。
3. 打开 macOS 的 Terminal，并进入项目目录（可选）。

查看当前已启动的 Simulator：

```bash
xcrun simctl list devices booted
```

## 获取 App 数据容器

获取当前已启动 Simulator 中 DailyTactics 的数据目录：

```bash
APP_DATA=$(xcrun simctl get_app_container booted com.dienbell.tactics data)
echo "$APP_DATA"
```

输出类似：

```text
~/Library/Developer/CoreSimulator/Devices/<DEVICE-UUID>/data/Containers/Data/Application/<APP-UUID>
```

如果系统中同时启动了多个 Simulator，`booted` 可能无法唯一确定设备。先取得目标设备的 UDID：

```bash
xcrun simctl list devices booted
```

然后用具体 UDID 替换 `booted`：

```bash
APP_DATA=$(xcrun simctl get_app_container <DEVICE-UDID> com.dienbell.tactics data)
```

## 定位数据库文件

列出 Application Support 目录：

```bash
ls -la "$APP_DATA/Library/Application Support"
```

自动搜索常见 SQLite 和 SwiftData 存储文件：

```bash
find "$APP_DATA/Library/Application Support" \
  -type f \( -name "*.store" -o -name "*.sqlite" -o -name "*.db" \) \
  -print
```

本项目通常会生成：

```text
default.store
default.store-wal
default.store-shm
```

其中：

- `default.store` 是主数据库文件。
- `default.store-wal` 是 SQLite Write-Ahead Log，可能包含最新事务。
- `default.store-shm` 是 WAL 模式使用的共享内存索引。

## 使用 sqlite3 查看数据库

为了减少 App 同时写数据库造成的干扰，先终止 App：

```bash
xcrun simctl terminate booted com.dienbell.tactics
```

进入 SQLite 命令行：

```bash
sqlite3 "$APP_DATA/Library/Application Support/default.store"
```

建议进入后立即启用只读保护和易读的输出格式：

```sql
.bail on
.headers on
.mode column
PRAGMA query_only = ON;
```

### 常用查询

列出所有表：

```sql
.tables
```

查看所有建表定义：

```sql
.schema
```

查看某一张表的定义：

```sql
.schema ZPUZZLEPROGRESS
```

通过 SQLite 元数据列出表名：

```sql
SELECT name
FROM sqlite_master
WHERE type = 'table'
ORDER BY name;
```

查看一张表的字段：

```sql
PRAGMA table_info('ZPUZZLEPROGRESS');
```

查看前 10 行：

```sql
SELECT * FROM ZPUZZLEPROGRESS LIMIT 10;
```

统计行数：

```sql
SELECT COUNT(*) FROM ZPUZZLEPROGRESS;
```

退出 SQLite：

```sql
.quit
```

SwiftData 生成的物理表名和字段名属于实现细节，通常会带有 `Z` 前缀。实际名称可能随模型、系统版本或迁移而变化，应先用 `.tables` 和 `.schema` 确认，不要假定表名永远固定。

## 一次性执行查询

不进入交互界面，直接列出数据库中的表：

```bash
sqlite3 -readonly "$APP_DATA/Library/Application Support/default.store" ".tables"
```

执行一条只读 SQL：

```bash
sqlite3 -readonly -header -column \
  "$APP_DATA/Library/Application Support/default.store" \
  "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;"
```

## 使用图形化工具

如果已经安装 DB Browser for SQLite，可以这样打开：

```bash
open -a "DB Browser for SQLite" \
  "$APP_DATA/Library/Application Support/default.store"
```

也可以使用其他支持 SQLite 的工具。打开前最好先终止 App，避免工具和 App 同时访问数据库。

## 安全复制数据库

SQLite 的最新数据可能仍在 WAL 文件里，因此不要在 App 运行时只复制 `default.store`。推荐先终止 App，再使用 SQLite 自带的备份命令生成一致的单文件副本：

```bash
xcrun simctl terminate booted com.dienbell.tactics
sqlite3 "$APP_DATA/Library/Application Support/default.store" \
  ".backup '/tmp/DailyTactics-debug.sqlite'"
```

然后以只读方式查看副本：

```bash
sqlite3 -readonly /tmp/DailyTactics-debug.sqlite
```

该副本仅用于本地调试，不应提交到 Git。

## 常见问题

### 找不到 App 容器

如果出现类似 `No such file or directory` 的错误，检查：

- Simulator 是否已启动。
- DailyTactics 是否已安装到当前 Simulator。
- Bundle ID 是否为 `com.dienbell.tactics`。
- 是否在错误的 Simulator 中运行了 App。

可以查询安装信息：

```bash
xcrun simctl get_app_container booted com.dienbell.tactics app
```

### 找不到 default.store

可能的原因包括：

- App 尚未首次创建 SwiftData 容器。
- 当前打开的不是运行 DailyTactics 的 Simulator。
- SwiftData 的默认文件名或位置发生变化。

重新运行一次 App，然后使用前面的 `find` 命令搜索，不要只依赖固定路径。

### 查询结果不是最新数据

数据可能仍在 `default.store-wal` 中，或者 App 尚未保存当前 `ModelContext`。先在 App 中完成触发保存的操作，再终止 App 后重新查询。

### 数据库被锁定

先终止 App：

```bash
xcrun simctl terminate booted com.dienbell.tactics
```

如果图形化数据库工具仍占用文件，也先关闭该工具，再重新打开数据库。

## 快速操作清单

```bash
APP_DATA=$(xcrun simctl get_app_container booted com.dienbell.tactics data)
xcrun simctl terminate booted com.dienbell.tactics
find "$APP_DATA/Library/Application Support" -type f -print
sqlite3 -readonly "$APP_DATA/Library/Application Support/default.store"
```

进入 SQLite 后：

```sql
.headers on
.mode column
.tables
.schema
PRAGMA query_only = ON;
.quit
```

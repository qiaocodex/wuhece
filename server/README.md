# BoxBook Cloud 自托管服务端

「物盒册」的自托管同步服务：多用户、多物品册、共享（可编辑/只读角色）、内置 Web 管理页。
数据以 JSON 备份形式存放在你自己的服务器上，应用不经手任何第三方服务。

> 运行目录：本文件位于物盒册仓库的 `server/` 子目录，是一个独立的 Dart 项目。

## 功能

- 多用户：开放注册（可用环境变量关闭），token 认证
- 物品册：每本物品册 = 一份完整的物盒册数据快照（JSON 备份）
- 共享：创建者可将物品册共享给其他用户，角色分「可编辑」与「只读」
- Web 管理页：登录、创建/删除物品册、共享成员管理、备份下载
- 数据落盘：JSON 文件 + 原子写入（临时文件 + 重命名）

## API 一览

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | /api/register | 注册 `{username, password}` → `{token}` |
| POST | /api/login | 登录 → `{token}` |
| GET | /api/books | 我的 + 共享的物品册列表 |
| POST | /api/books | 创建物品册 `{name}` |
| PUT | /api/books/:id | 重命名（owner） |
| DELETE | /api/books/:id | 删除（owner，级联删除数据） |
| POST | /api/books/:id/share | 共享给用户 `{username, role: editor\|viewer}`（owner） |
| GET | /api/books/:id/members | 成员列表（owner） |
| GET | /api/books/:id/data | 读取备份内容（viewer 可读） |
| PUT | /api/books/:id/data | 写入备份内容（editor/owner） |

认证方式：`Authorization: Bearer <token>`。

## 本地运行

```bash
cd server
dart pub get
dart run bin/server.dart                    # 默认 8800 端口
dart run bin/server.dart --port 9000 --db ./data/boxbook.db
dart test                                   # 端到端测试
```

环境变量：`PORT`、`DB_PATH`、`OPEN_REGISTRATION`（设为 0 关闭注册）。

## Docker 一键部署

```bash
docker compose up -d --build
# 浏览器访问 http://服务器IP:8800 → 注册账号 → 在物盒册 App 中配置
```

compose 文件已将 `./data` 挂载为数据卷，备份持久化在宿主机。

## 物盒册 App 端配置

1. 设置 → 云同步 → 服务商选择「BoxBook Cloud」
2. 填服务器地址（如 `http://192.168.1.10:8800`）、用户名、密码 → 登录
3. 选择要同步的物品册（自己的或共享给你的）→ 立即同步
4. 多台设备选择同一本物品册，即可实现多设备共享同步

## 安全说明

- 密码加盐 SHA-256 存储；token 长期有效（泄露请在服务器删除对应 token 记录）
- 服务面向局域网 / 可信网络设计；如需公网暴露，建议放在反代 + HTTPS 之后，并关闭注册

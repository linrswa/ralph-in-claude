# TypeScript for MCP Servers -- Quick Reference

For programmers who know Python/C++/Swift. Only what you need to build an MCP server with file I/O.

## 1. TS vs Python/C++/Swift Comparison

| Concept | Python | C++/Swift | TypeScript |
|---|---|---|---|
| Type annotation | `x: int = 5` | `int x = 5` / `let x: Int = 5` | `let x: number = 5` |
| Type inference | duck typing | `auto` / `let x = 5` | `let x = 5` (inferred `number`) |
| String | `str` | `std::string` / `String` | `string` (lowercase!) |
| Dict/Map | `dict[str, int]` | `map<string,int>` / `[String:Int]` | `Record<string, number>` |
| Optional/null | `Optional[int]` | `optional<int>` / `Int?` | `number \| null` or `number \| undefined` |
| Array | `list[int]` | `vector<int>` / `[Int]` | `number[]` |
| Async | `async def f():` | coroutines / `async func` | `async function f(): Promise<T>` |
| Import | `from x import y` | `#include` / `import X` | `import { y } from "x"` |
| Interface | `Protocol` / ABC | pure virtual / `protocol` | `interface Foo { bar: string }` |
| Union type | `int \| str` | `variant` / enum | `number \| string` |
| Null-safe access | `x.get("k")` | `.value_or()` / `x?.prop` | `x?.prop` |
| Error handling | `try/except` | `try/catch` / `do/catch` | `try/catch` (no typed catches) |

## 2. Key TS Concepts for MCP

**Interfaces** define object shapes (like Python `TypedDict` or Swift `struct`):
```typescript
interface Task { id: string; priority: number; tags?: string[] }  // ? = optional
```

**Generics** -- like C++ templates. You will see `Promise<T>` everywhere:
```typescript
async function readJson<T>(path: string): Promise<T> {
  return JSON.parse(await readFile(path, "utf-8")) as T;  // 'as T' = type assertion
}
const data = await readJson<Task>("task.json");
```

**async/await** -- same as Python. Every `async` function returns `Promise<T>`:
```typescript
async function load(): Promise<string> { return await readFile("f.json", "utf-8"); }
```

**Union types + narrowing** -- TS narrows types after null checks:
```typescript
const task = tasks.find((t) => t.id === id);  // returns Task | undefined
if (!task) return;                             // after this, TS knows task is Task
```

**Destructuring** -- used in every MCP tool handler:
```typescript
const { name, priority } = config;   // object destructuring
```

**`const` vs `let`** -- `const` = immutable binding (Swift `let`), `let` = mutable (Swift `var`).

**`as const`** -- narrows a string literal from type `string` to its exact value. Needed in MCP responses:
```typescript
{ type: "text" as const, text: "hello" }  // type is "text", not string
```

**Error catches are untyped** -- must cast: `catch (err) { (err as Error).message }`

## 3. MCP TypeScript SDK Patterns

**Install:** `npm install @modelcontextprotocol/sdk zod`  (SDK v1.x + Zod v3)

**Server + transport:**
```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
const server = new McpServer({ name: "my-server", version: "1.0.0" });
await server.connect(new StdioServerTransport());
```

**Register a tool** (Zod = Pydantic for TS -- runtime validation + type generation):
```typescript
import { z } from "zod";
server.registerTool("read-file", {
    description: "Read a JSON file",
    inputSchema: { filePath: z.string().describe("Path to file") },
  },
  async ({ filePath }) => ({  // args auto-typed from Zod schema
    content: [{ type: "text" as const, text: await readFile(filePath, "utf-8") }],
  }),
);
```

**Tool return format:** `{ content: [{ type: "text", text: string }] }`. Add `isError: true` for errors.

**File I/O:**
```typescript
import { readFile, writeFile, mkdir } from "node:fs/promises";
const raw = await readFile("config.json", "utf-8");       // read -> string
const obj = JSON.parse(raw) as MyType;                     // parse + type assert
await writeFile("out.json", JSON.stringify(obj, null, 2)); // write with 2-space indent
await mkdir("dir", { recursive: true });                   // mkdir -p
```

**Logging:** Never `console.log()` in stdio servers (corrupts JSON-RPC). Use `console.error()`.

## 4. Complete MCP Server Example

```typescript
// src/index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname } from "node:path";

interface Task { id: string; title: string; done: boolean }

const server = new McpServer({ name: "task-server", version: "1.0.0" });

server.registerTool("read-tasks", {
    description: "Read tasks from a JSON file",
    inputSchema: { filePath: z.string().describe("Path to tasks JSON") },
  },
  async ({ filePath }) => {
    try {
      const tasks: Task[] = JSON.parse(await readFile(filePath, "utf-8"));
      return { content: [{ type: "text" as const, text: JSON.stringify(tasks, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text" as const, text: `Error: ${(err as Error).message}` }], isError: true };
    }
  },
);

server.registerTool("update-task", {
    description: "Mark a task done",
    inputSchema: {
      filePath: z.string().describe("Path to tasks JSON"),
      taskId: z.string().describe("Task ID to mark done"),
    },
  },
  async ({ filePath, taskId }) => {
    try {
      const tasks: Task[] = JSON.parse(await readFile(filePath, "utf-8"));
      const task = tasks.find((t) => t.id === taskId);   // returns Task | undefined
      if (!task) {
        return { content: [{ type: "text" as const, text: `Task ${taskId} not found` }], isError: true };
      }
      task.done = true;
      await mkdir(dirname(filePath), { recursive: true });
      await writeFile(filePath, JSON.stringify(tasks, null, 2), "utf-8");
      return { content: [{ type: "text" as const, text: `Task ${taskId} marked done` }] };
    } catch (err) {
      return { content: [{ type: "text" as const, text: `Error: ${(err as Error).message}` }], isError: true };
    }
  },
);

async function main(): Promise<void> {
  await server.connect(new StdioServerTransport());
  console.error("Task MCP server running on stdio");
}
main().catch((err) => { console.error("Fatal:", err); process.exit(1); });
```

### Project Config

```jsonc
// package.json essentials
{ "type": "module", "scripts": { "build": "tsc" },
  "dependencies": { "@modelcontextprotocol/sdk": "^1.12.0", "zod": "^3.24.0" },
  "devDependencies": { "@types/node": "^22.0.0", "typescript": "^5.8.0" } }
```
```jsonc
// tsconfig.json
{ "compilerOptions": {
    "target": "ES2022", "module": "Node16", "moduleResolution": "Node16",
    "outDir": "./build", "rootDir": "./src", "strict": true,
    "esModuleInterop": true, "skipLibCheck": true
  }, "include": ["src/**/*"] }
```

Build and run: `npx tsc && node build/index.js`

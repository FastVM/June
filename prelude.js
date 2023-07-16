
if (globalThis.Bun != null) {
  var write = (s) => {
    Bun.stdout.write(s);
  };
  var argv = Bun.argv;
  var readFile = (s) => {
    return Bun.readFile(s);
  };
  var writeFile = async (p,s) => {
    return await Bun.write(p,s);
  };
  var readline = Object.create(null);
  readline.read = () => Bun.stdin.read();
  readline.prompt = () => prompt("");
  readline.questionFloat = () => Number(prompt(""));
} else {
  const fs = import('fs/promises');
  var write = (s) => {
    process.stdout.write(s);
  };
  var argv = process.argv;
  var readFile = async(p) => {
    return (await fs).readFile(p);
  };
  var writeFile = async(p,s) => {
    await (await fs).writeFile(p,s);
  };
  var readline = import('readline');
}

const internal = Symbol.for('internal');

const lua_first = (a) => Array.isArray(a) ? a[0] : a;
const lua_index = (a, b) => a[b];
const lua_set = (a, b, c) => a[b] = c;

const lua_add = (a, b) => a + b;
const lua_sub = (a, b) => a - b;
const lua_mul = (a, b) => a * b;
const lua_div = (a, b) => a / b;
const lua_mod = (a, b) => a % b;
const lua_pow = (a, b) => Math.pow(a, b);

const lua_unm = (n) => -n;

const lua_eq = (a, b) => a === b;
const lua_ne = (a, b) => a !== b;
const lua_lt = (a, b) => a < b;
const lua_gt = (a, b) => a > b;
const lua_le = (a, b) => a <= b;
const lua_ge = (a, b) => a >= b;

const lua_concat = (a, b) => `${a}${b}`;

const lua_toboolean = (a) => a != null && a !== false;

const lua_and = async (a, b) => (lua_toboolean(a) ? await b() : a);
const lua_or = async (a, b) => (lua_toboolean(a) ? a : await b());

const lua_array_of = (v) => Array.isArray(v) ? v : [v];

const lua_apply = async (obj, func, ...args) => {
  return lua_array_of(await lua_index(obj, func).apply(obj, args));
};
const lua_call = async (func, ...args) => lua_array_of(await func.apply(null, args));

const lua_length = (a) => {
  if (typeof a === "string") {
    return a.length;
  } else if (typeof a === "object") {
    let i = 1;
    while (a[i] != null) {
      i += 1;
    }
    return i-1;
  } else {
    throw new Error(`cannot get length (jstype: ${typeof a})`)
  }
};

const local__ENV = Object.create(null);

local__ENV.js = Object.create(null);
local__ENV.js.global = globalThis;
local__ENV.js.new = (o, ...a) => {
  return new o(...a);
};
local__ENV.js.import = (x) => import(x);
  
local__ENV._G = local__ENV;
local__ENV.arg = Object.create(null);
for (let i = 0; i < argv.length; i++) {
    local__ENV.arg[i-1] = argv[i];
}

const typemap = {
  "undefined": "nil",
  "null": "nil",
  "boolean": "boolean",
  "string": "string",
  "number": "number",
  "object": "table",
};
local__ENV.error = (v) => {
  throw new Error(v);
}
local__ENV.type = (v) => v instanceof Function ? ['function'] : [typemap[typeof v]];
local__ENV.tonumber = (n) => [Number(n)];
local__ENV.tostring = (s) => [String(s)];
local__ENV.print = console.log;

local__ENV.table = Object.create(null);
local__ENV.table.concat = (t, j='') => {
  const parts = [];
  for (var i = 1; t[i] != null; i++) {
    parts.push(t[i]);
  }
  return [parts.join(j)];
}

local__ENV.io = Object.create(null);
local__ENV.io.write = (s) => {
  processwrite(s);
  return [null];
};
local__ENV.io.read = async(s) => {
  switch (s) {
    case "*all":
      return (await readline).read();
    case "*line":
      return (await readline).prompt();
    case "*number":
      return (await readline).questionFloat();
    default:
      return (await readline).read(Number(s));
  }
};
local__ENV.io.open = async(path, mode="r") => {
  if (typeof path !== 'string') {
    throw new Error('cannot open non-string path');
  }
  if (mode.indexOf('r') !== -1) {
    const file = Object.create(null);
    file[internal] = Object.create(null);
    file[internal].str = await readFile(path);
    file[internal].head = 0;
    file.close = () => {
    };
    file.read = (file, txt) => {
      const data = file[internal];
      switch (txt) {
        case '*all':
          return [data.str];
        case '*line':
          var l = [];
          while (data.head < data.str.length && !/[\n\r]/.test(data.str[data.head])) {
            l.push(data.str[data.head++]);
          }
          return [l.join('')];
        case '*number':
          var n = 0;
          while (data.head < data.str.length) {
            var c = data.str.charCodeAt(data.head) - 48;
            if (0 <= c && c <= 9) {
              n *= 10;
              n += c;
              data.head += 1;
            } else if (n == 0) {
              throw new Error('file:read(\'*number\') not a number');
            } else {
              return [n];
            }
          } 
        default:
          var l = [];
          for (var i = Number(txt); i > 0; i-=1) {
            l.push(data.str[data.head++]);
          }
          return [l.join('')];
      }
    };
    return [file];
  } else if (mode.indexOf('w') !== -1) {
    const file = Object.create(null);
    file[internal] = Object.create(null);
    file[internal].path = path;
    file[internal].parts = [];
    file.close = (file) => {
      const data = file[internal];
      writeFile(data.path, data.parts.join(''));
      return [null];
    };
    file.write = (file, txt) => {
      file[internal].parts.push(txt);
      return [null];
    };
    return [file];
  } else {
    throw new Error(`file mode: ${mode}`);
  }
};

local__ENV.string = Object.create(null);
local__ENV.string.format = (fmt, ...args) => {
  let i = 0;
  const format = (match, dot, pad, fmt) => {
    switch (fmt) {
      case "d":
        return Math.floor(Number(args[i])).toString();
      case "s":
        return String(args[i]);
      case "f":
        return Number(args[i]);
      case "F":
        return Number(args[i]).toString().toUpperCase();
      case "b":
        return Number(args[i]).toString(2).toLowerCase();
      case "o":
        return Number(args[i]).toString(8).toLowerCase();
      case "x":
        return Number(args[i]).toString(16).toLowerCase();
      case "X":
        return Number(args[i]).toString(16).toUpperCase();
      case "c":
        return String.fromCodePoint(Number(args[i]));
      case "g":
        var f = format(match, dot, pad, "f");
        var e = format(match, dot, pad, "e");
        if (f.length < e.length) {
          return f;
        } else {
          return e;
        }
      case "G":
        var f = format(match, dot, pad, "F");
        var e = format(match, dot, pad, "E");
        if (f.length < e.length) {
          return f;
        } else {
          return e;
        }
    }
  };
  const ret = fmt.replace(/%(\.?)(\d*)([dsfFboxXcgG])/g, (...match) => {
    const ret = format(...match);
    i += 1;
    return ret;
  });
  return [ret];
};
local__ENV.string.len = (x) => {
  return [String(x).length];
};
local__ENV.string.sub = (x, l, h) => {
  return [String(x).substring(l - 1, h)];
};
local__ENV.string.byte = (s, i=1) => {
  return [s.charCodeAt(i-1)];
};

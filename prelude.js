// import { readFile, writeFile } from "fs/promises";

const readFile = () => '';
const writeFile = () => {};

const internal = Symbol("internal");
const metatable = Symbol("metatable");

const meta =
  (name, func) =>
  (obj, ...args) => {
    if (obj != null && typeof obj === "object" && obj[metatable] != null) {
      const method = obj[metatable][name];
      if (method != null) {
        return call(obj[method], ...args)[0];
      }
    }
    return func(obj, ...args);
  };

export const first = (a) => (Array.isArray(a) ? a[0] : a);
export const index = (a, b) => {
  const res = a[b];
  if (res == null && typeof obj === "object" && obj[metatable] != null) {
    return call(obj[metatable]["__index"], a, b);
  }
  return res;
};
export const set = (a, b, c) => (a[b] = c);

export const add = meta("__add", (a, b) => a + b);
export const sub = meta("__sub", (a, b) => a - b);
export const mul = meta("__mul", (a, b) => a * b);
export const div = meta("__div", (a, b) => a / b);
export const mod = meta("__mod", (a, b) => a % b);
export const pow = meta("__pow", (a, b) => Math.pow(a, b));

export const unm = meta("__unm", (n) => -n);

export const eq = meta("__eq", (a, b) => (a, b) => {
  if (a == null && b == null) {
    return true;
  }
  return a === b;
});
export const lt = meta("__lt", (a, b) => a < b);
export const le = meta("__le", (a, b) => a <= b);
export const ne = (a, b) => !eq(a, b);
export const gt = (a, b) => lt(b, a);
export const ge = (a, b) => le(b, a);

export const concat = meta("concat", (a, b) => `${a}${b}`);

export const toboolean = (a) => a != null && a !== false;

export const and = async (a, b) => (toboolean(a) ? await b() : a);
export const or = async (a, b) => (toboolean(a) ? a : await b());

const array_of = (v) => (Array.isArray(v) ? v : [v]);

export const apply = async (obj, func, ...args) => {
  return array_of(await index(obj, func).apply(obj, args));
};
export const call = async (func, ...args) => {
  if (typeof func === "object") {
    return call();
  }
  return array_of(await func.apply(null, args));
};

export const length = meta("__len", (a) => {
  if (typeof a === "string") {
    return a.length;
  } else if (typeof a === "object") {
    let i = 1;
    while (a[i] != null) {
      i += 1;
    }
    return i - 1;
  } else {
    throw new Error(`cannot get length (jstype: ${typeof a})`);
  }
});

export const env = (dataArg) => {
  const data = dataArg != null ? dataArg : {};
  const argv = data.argv != null ? data.argv : [];
  let buf = '';
  const write =
    data.write != null
    ? data.write
    : ((s) => {
      for (const c in s) {
        if (c === '\n') {
          console.log(buf);
          buf = '';
        } else if (c !== '\r') {
          buf += c;
        }
      }
    });
  const env = Object.create(null);

  env.eval = async (s) => {
    return await eval(s);
  };
  env.js = Object.create(null);
  // env.js.global = this;
  env.js.new = (o, ...a) => {
    return new o(...a);
  };
  // env.js.import = (x) => this.import(x);

  env._G = env;
  env.arg = Object.create(null);
  for (let i = 0; i < argv.length; i++) {
    env.arg[i - 1] = argv[i];
  }

  const typemap = {
    undefined: "nil",
    null: "nil",
    boolean: "boolean",
    string: "string",
    number: "number",
    object: "table",
    function: "function",
  };
  env.error = (v) => {
    throw new Error(v);
  };
  env.assert = (v, m) => {
    if (!v) {
      throw new Error(m);
    }
    return [v];
  };
  env.type = (v) => [typemap[typeof v]];
  env.tonumber = (n) => [Number(n)];
  env.tostring = (s) => [String(s)];
  env.print = console.log;

  env.table = Object.create(null);
  env.table.concat = (t, j = "") => {
    const parts = [];
    for (let i = 1; t[i] != null; i++) {
      parts.push(t[i]);
    }
    return [parts.join(j)];
  };

  env.io = Object.create(null);
  env.io.write = (s) => {
    write(s);
    return [null];
  };
  env.io.read = async (s) => {
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
  env.io.open = async (path, mode = "r") => {
    if (typeof path !== "string") {
      throw new Error("cannot open non-string path");
    }
    if (mode.indexOf("r") !== -1) {
      const file = Object.create(null);
      file[internal] = Object.create(null);
      file[internal].str = await readFile(path);
      file[internal].head = 0;
      file.close = () => {};
      file.read = (file, txt) => {
        const data = file[internal];
        switch (txt) {
          case "*all": {
            return [data.str];
          }
          case "*line": {
            const l = [];
            while (
              data.head < data.str.length &&
              !/[\n\r]/.test(data.str[data.head])
            ) {
              l.push(data.str[data.head++]);
            }
            return [l.join("")];
          }
          case "*number": {
            let n = 0;
            while (data.head < data.str.length) {
              let c = data.str.charCodeAt(data.head) - 48;
              if (0 <= c && c <= 9) {
                n *= 10;
                n += c;
                data.head += 1;
              } else if (n == 0) {
                throw new Error("file:read('*number') not a number");
              } else {
                return [n];
              }
            }
          }
          default: {
            let l = [];
            for (let i = Number(txt); i > 0; i -= 1) {
              l.push(data.str[data.head++]);
            }
            return [l.join("")];
          }
        }
      };
      return [file];
    } else if (mode.indexOf("w") !== -1) {
      const file = Object.create(null);
      file[internal] = Object.create(null);
      file[internal].path = path;
      file[internal].parts = [];
      file.close = (file) => {
        const data = file[internal];
        writeFile(data.path, data.parts.join(""));
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

  env.math = Object.create(null);
  env.math.abs = (n) => [Math.abs(n)];
  env.math.acos = (n) => [Math.acos(n)];
  env.math.asin = (n) => [Math.asan(n)];
  env.math.atan = (n) => [Math.atan(n)];
  env.math.atan2 = (n, m) => [Math.atan2(n, m)];
  env.math.ceil = (n) => [Math.ceil(n)];
  env.math.cos = (n) => [Math.cos(n)];
  env.math.cosh = (n) => [Math.cosh(n)];
  env.math.floor = (n) => [Math.floor(n)];
  env.math.fmod = (n, m) => [m % n];
  // env.math.frexp = (n) => [Math.frexp(n)]
  env.math.huge = Infinity;
  env.math.ldexp = (n, m) => [Math.ldexp(n, m)];
  env.math.log = (n) => [Math.log(n)];
  env.math.log10 = (n) => [Math.log(n)];
  env.math.max = (...n) => [Math.max(...n)];
  env.math.min = (...n) => [Math.min(...n)];
  const trunc = (n) => (n < 0 ? Math.ceil(x) : Math.floor(x));
  env.math.modf = (n) => [n - trunc(n)];
  env.math.pi = Math.PI;
  env.math.pow = (n, m) => [Math.pow(n, m)];
  env.math.rad = (n) => [(n * Math.PI) / 180];
  env.math.random = (...args) => {
    if (args.length == 0) {
      return [Math.random()];
    } else if (args.length == 1) {
      return [Math.random() * args[0] - 1 + 1];
    } else {
      return [Math.random() * (args[1] - args[0]) + args[0]];
    }
  };
  // env.math.randomseed = ()
  env.math.sin = (n) => [Math.sin(n)];
  env.math.sinh = (n) => [Math.sinh(n)];
  env.math.sqrt = (n) => [Math.sqrt(n)];
  env.math.tan = (n) => [Math.tan(n)];
  env.math.tanh = (n) => [Math.tanh(n)];

  env.string = Object.create(null);
  env.string.format = (fmt, ...args) => {
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
        case "g": {
          const f = format(match, dot, pad, "f");
          const e = format(match, dot, pad, "e");
          if (f.length < e.length) {
            return f;
          } else {
            return e;
          }
        }
        case "G": {
          const f = format(match, dot, pad, "F");
          const e = format(match, dot, pad, "E");
          if (f.length < e.length) {
            return f;
          } else {
            return e;
          }
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
  env.string.len = (x) => {
    return [String(x).length];
  };
  env.string.sub = (x, l, h) => {
    return [String(x).substring(l - 1, h)];
  };
  env.string.byte = (s, i = 1) => {
    return [s.charCodeAt(i - 1)];
  };
  return env;
};

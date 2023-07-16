const process = require("process");
const readline = require("readline-sync");

const lua = new Map();

lua.first = (a) => a[0];
lua.index = (a, b) => a[b];
lua.set = (a, b, c) => a[b] = c;

lua.add = (a, b) => a + b;
lua.sub = (a, b) => a - b;
lua.mul = (a, b) => a * b;
lua.div = (a, b) => a / b;
lua.mod = (a, b) => a % b;
lua.pow = (a, b) => Math.pow(a, b);

lua.unm = (n) => -n;

lua.eq = (a, b) => a === b;
lua.ne = (a, b) => a !== b;
lua.lt = (a, b) => a < b;
lua.gt = (a, b) => a > b;
lua.le = (a, b) => a <= b;
lua.ge = (a, b) => a >= b;

lua.concat = (a, b) => `${a}${b}`;

lua.toboolean = (a) => a != null && a !== false;

lua.and = (a, b) => (lua.toboolean(a) ? b() : a);
lua.or = (a, b) => (lua.toboolean(a) ? a : b());

lua.length = (a) => {
  if (typeof a === "string") {
    return a.length;
  } else if (typeof a === "object") {
    let i = 1;
    while (a[i] != null) {
      i += 1;
    }
    return i-1;
  } else {
    throw new Error("cannot get length")
  }
};

const local__ENV = new Map();

local__ENV._G = local__ENV;
local__ENV.arg = new Map();
for (let i = 0; i < process.argv.length; i++) {
  local__ENV.arg[i-1] = process.argv[i];
}

local__ENV.tonumber = (n) => [Number(n)];
local__ENV.tostring = (s) => [String(s)];

local__ENV.print = console.log;
local__ENV.io = new Map();
local__ENV.io.write = (s) => {
  process.stdout.write(s);
  return [null];
};
local__ENV.io.read = (s) => {
  switch (s) {
    case "*all":
      return readline.read();
    case "*line":
      return readline.prompt();
    case "*number":
      return readline.questionFloat();
    default:
      return readline.read(Number(s));
  }
};

local__ENV.string = new Map();
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
  const ret = fmt.replace(/%(\.?)(\d*)([dsfFboxXcgG])/g, (...args) => {
    const ret = format(...args);
    i += 1;
    return ret;
  });
  return [ret];
};
local__ENV.string.len = (x) => {
  return [String(x).length];
};
local__ENV.string.sub = (x, l, h) => {
  return [String(x).substring(l, h + 1)];
};

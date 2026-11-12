// acorn 精确定位：正确处理正则/字符串，报告首个语法错误的位置与上下文
const fs = require('fs');
const acorn = require('C:/Nbeetok/dy-tvos/_tmp/node_modules/acorn');
const file = process.argv[2] || 'C:/Nbeetok/dy-tvos/_tmp/hook_extracted.js';
const code = fs.readFileSync(file, 'utf8');
try {
  acorn.parse(code, { ecmaVersion: 2022 });
  console.log('PARSE_OK length=' + code.length);
} catch (e) {
  console.log('ERROR: ' + e.message);
  const pos = typeof e.pos === 'number' ? e.pos : -1;
  if (pos >= 0) {
    console.log('pos=' + pos);
    const line = code; // 单行文件
    const a = Math.max(0, pos - 100), b = Math.min(line.length, pos + 100);
    console.log('CTX: ' + JSON.stringify(line.slice(a, b)));
    console.log('CHAR: ' + JSON.stringify(line[pos]));
  }
}

// 精确定位语法错误：编译 hook_from_binary.js，解析 caret 列号，打印上下文
const fs = require('fs');
const vm = require('vm');
const file = 'C:/Nbeetok/dy-tvos/_tmp/hook_from_binary.js';
const code = fs.readFileSync(file, 'utf8');
try {
  new vm.Script(code, { filename: 'hook.js' });
  console.log('SYNTAX_OK');
} catch (e) {
  console.log('ERROR: ' + e.message);
  const st = e.stack.split('\n');
  // 找 caret 行（全空格+^）
  let line = null, col = 0;
  for (let i = 0; i < st.length; i++) {
    const m = st[i].match(/^\s*\^/);
    if (m) { col = st[i].indexOf('^'); line = st[i - 1]; break; }
  }
  if (line !== null) {
    console.log('column=' + col);
    const a = Math.max(0, col - 80), b = Math.min(line.length, col + 80);
    console.log('CONTEXT: ' + line.slice(a, b));
    console.log('CHAR AT COL: ' + JSON.stringify(line[col]));
  } else {
    console.log('no caret line in stack');
    console.log(st.slice(0, 8).join('\n'));
  }
}

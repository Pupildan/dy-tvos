// 前缀扫描（只打印 C 级异常跳变点，写文件避免 cmd 截断）
const fs = require('fs');
const vm = require('vm');
const code = fs.readFileSync('C:/Nbeetok/dy-tvos/_tmp/hook_extracted.js', 'utf8');
const out = [];
let prev = '';
for (let n = 100; n <= code.length; n++) {
  let msg;
  try { new vm.Script(code.slice(0, n)); msg = 'OK'; }
  catch (e) { msg = e.message; }
  if (msg !== prev) {
    // 只关心“非未完成态”的跳变（真正的语法破坏点）
    if (msg !== 'Unexpected end of input' && prev !== 'Unexpected end of input' && msg !== 'OK') {
      out.push('len=' + n + ' msg="' + msg + '"');
      out.push('CTX: ' + JSON.stringify(code.slice(Math.max(0, n - 150), Math.min(code.length, n + 80))));
    }
    if (msg === 'OK') { out.push('FIRST_OK_AT=' + n); break; }
    prev = msg;
  }
}
fs.writeFileSync('C:/Nbeetok/dy-tvos/_tmp/scan_result.txt', out.join('\n') || 'no transitions');
console.log('scan done, see _tmp/scan_result.txt');

// 前缀扫描：第一个错误信息变化的位置 = 坏 construct 所在
const fs = require('fs');
const vm = require('vm');
const code = fs.readFileSync('C:/Nbeetok/dy-tvos/_tmp/hook_from_binary.js', 'utf8');
let prev = 'Unexpected end of input';
let found = -1;
for (let n = 50; n <= code.length; n++) {
  let msg;
  try { new vm.Script(code.slice(0, n)); msg = 'OK'; }
  catch (e) { msg = e.message; }
  if (msg !== prev) {
    console.log('len=' + n + '  msg="' + msg + '"  (prev="' + prev + '")');
    const a = Math.max(0, n - 90), b = Math.min(code.length, n + 90);
    console.log('CONTEXT: ' + JSON.stringify(code.slice(a, b)));
    found = n;
    prev = msg;
    if (msg === 'OK') break;
  }
}
if (found < 0) console.log('no transition found');
console.log('total=' + code.length);
